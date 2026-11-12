#!/bin/zsh
# 一般使用者身分執行，live 模式要已經在跑：zsh tools/hourcheck.sh [分鐘間隔] [次數]
# 每隔一段時間播 21 秒 chirp、錄音、算延遲與左右偏差，並回報 cliairplay 有沒有 REANCHOR／斷流。
set -u
DIR=${0:A:h:h}
PY=${PYTHON:-python3}  # 要有 numpy、scipy
EVERY=${1:-30}
COUNT=${2:-3}
LOGS=${LOGS:-$DIR/logs}  # 背景服務的 log 在 /Library/Application Support/AirPlayStereo/logs
LIVE=$(ls -t $LOGS/pair-*-split.log | head -1); LIVE=${LIVE%-split.log}  # 這一輪的 log 前綴
OUT=$DIR/checks/hourcheck-$(date +%H%M%S).txt
echo "監看 $LIVE，每 $EVERY 分鐘一次，共 $COUNT 次，結果寫到 $OUT" | tee $OUT
for i in $(seq 1 $COUNT); do
  REC=$DIR/checks/hourcheck-$(date +%H%M%S)-mic.wav
  $DIR/tools/rec $REC 26 > /tmp/hourcheck-rec.out &
  sleep 2
  # 和 run_pair.sh livemeasure 同一種量法：印出時間後立刻 exec afplay
  PLAY=$(python3 -I -c 'import os, sys, time
print("%.6f" % time.time(), flush=True)
if os.fork() == 0:
    os.dup2(os.open(os.devnull, os.O_WRONLY), 1)
    os.execv("/usr/bin/afplay", ["afplay", "-t", "21", sys.argv[1]])
os.wait()' $DIR/signals/chirps.wav)
  wait
  FIRST=$(sed -n 's/.*first_sample_unix=\([0-9.]*\).*/\1/p' /tmp/hourcheck-rec.out)
  { echo "=== 第 $i 次 $(date +%H:%M:%S)"
    $PY -I -W ignore $DIR/measure.py analyze $REC $FIRST $PLAY
    for f in $LIVE-[0-9A-F]*.log(N); do echo "${${f##*-}%.log} REANCHOR/斷流累計: $(grep -cE 'REANCHOR|starved|Splice-padded' $f)"; done
    tail -1 $LIVE-split.log 2>/dev/null
  } 2>&1 | tee -a $OUT
  [[ $i -lt $COUNT ]] && sleep $(( EVERY * 60 - 30 ))
done
