#!/bin/zsh
# 一般使用者身分執行，背景服務要在播、房間要安靜：zsh tools/sweep.sh <每檔分鐘> <緩衝 ms>…（由大到小）
# 每檔寫 buffer-ms 讓背景服務重新起播，播完後記下斷流與重啟次數、split lead，再跑一次 hourcheck 量端到端與左右偏差。
# 一檔斷流 2 次以上或自癒放棄就停：再小只會更糟。結束時把 buffer-ms 還原。
set -u
DIR=${0:A:h:h}
CFG=~/Library/Application\ Support/AirPlayStereo
export LOGS=${LOGS:-/Library/Application Support/AirPlayStereo/logs}
SLOG=$LOGS/stereo.log
MIN=$1; shift
OUT=$DIR/checks/sweep-$(date +%H%M%S).txt
orig=$(cat $CFG/buffer-ms 2>/dev/null)
restore() { if [[ -n $orig ]]; then print -r -- $orig > $CFG/buffer-ms; else rm -f $CFG/buffer-ms; fi }
trap 'restore; exit 1' INT TERM
echo "緩衝掃描 $*，每檔 $MIN 分鐘，結果寫到 $OUT" | tee $OUT
for b in "$@"; do
  n0=$(wc -l < $SLOG)
  print -r -- $b > $CFG/buffer-ms
  stamp=""
  for i in {1..60}; do
    stamp=$(tail -n +$(( n0 + 1 )) $SLOG | sed -n "s/.* start .*buffer_ms=$b (log tag \([0-9-]*\)).*/\1/p" | head -1)
    [[ -n $stamp ]] && break; sleep 1
  done
  [[ -n $stamp ]] || { echo "=== $b ms：60 秒內沒有以這個緩衝起播，停止" | tee -a $OUT; break; }
  gave=""
  for i in $(seq 1 $(( MIN * 2 ))); do
    sleep 30
    tail -n +$(( n0 + 1 )) $SLOG | grep -q 'gave up' && { gave=1; break; }
  done
  new=$(tail -n +$(( n0 + 1 )) $SLOG)
  stamps=(${(f)"$(print -r -- $new | sed -n 's/.*(log tag \([0-9-]*\)).*/\1/p')"})
  bad=0; for s in $stamps; do for f in $LOGS/pair-$s-[0-9A-F]*.log(N); do (( bad += $(grep -cE 'REANCHOR|starved|Splice-padded' $f) )); done; done
  { echo "=== $b ms（$(date +%H:%M)）起播 $stamp"
    echo "斷流／REANCHOR $bad 次，看門狗重啟 $(print -r -- $new | grep -c 'restart:') 次${gave:+，自癒放棄}"
    grep 'lead_ms' $LOGS/pair-$stamps[-1]-split.log | tail -1
  } | tee -a $OUT
  [[ -n $gave ]] && break
  zsh $DIR/tools/hourcheck.sh 1 1 2>&1 | grep -E '右減左|端到端|峰值' | tee -a $OUT
  (( bad >= 2 )) && { echo "斷流 2 次以上，不再往下" | tee -a $OUT; break; }
done
restore
echo "已還原 buffer-ms" | tee -a $OUT
