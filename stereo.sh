#!/bin/zsh
# AirPlay stereo switch: sudo zsh stereo.sh on [<speaker id>… Mac]|off|status|discover, or `serve <want file>` as the background service
# Speakers are found on the network (discover) and named by their 12-hex-digit AirPlay device id.
# on starts a background watchdog (supervise) that keeps run_pair.sh live running and restarts both speakers
# together when one re-anchors, starves, or a process disappears.
set -u
umask 022
setopt no_bg_nice extended_glob  # zsh 預設讓每層背景工作 nice +5，疊到 cliairplay／audiotee 變 nice 15，起播會慢上百 ms
DIR=${DIR:-${0:A:h}}  # 跟著腳本所在位置走：開發在 Documents，安裝後在 /Library/Application Support/AirPlayStereo
# 狀態放在腳本旁（安裝後是 root 擁有）。放 /tmp 時一般使用者能換掉 pidfile，讓 root 殺錯行程或寫穿 symlink
STATE=${STATE:-$DIR/state}
RUN_PAIR=${RUN_PAIR:-$DIR/run_pair.sh}
LOGDIR=${LOGDIR:-$DIR/logs}
LOG=$LOGDIR/stereo.log
PIDFILE=$STATE/supervisor.pid
DEVFILE=$STATE/devices  # supervisor 正在播的裝置組合
VOLFILE=$STATE/volumes   # 各台 HomePod 音量，serve 從使用者的音量檔整理後寫入
RUNDIR_FILE=$STATE/rundir  # 目前 run_pair 的暫存資料夾（裡面有每台的 cmd 管道）
SPEAKERS=$STATE/speakers  # 找到的喇叭：「ID<tab>IP<tab>名稱」，App 也讀這份
DEVICES=${DEVICES:-}
LATENCY=200 TARGET=200  # 實測最低又穩定的組合；再低會單台 REANCHOR、左右錯開
# 任何一行出現就代表兩台可能不再對齊（單台平移時間軸、斷流、結束）
BAD='REANCHOR|anchor_corrected|content_cut|\[STATUS\] (error|eof|stopped)|PCM input starved|Splice-padded'
MAX_RESTARTS=5 WINDOW_S=300 POLL_S=${POLL_S:-2}

HEARTBEAT=$STATE/heartbeat
mkdir -p $STATE $LOGDIR 2>/dev/null  # App 以一般使用者跑 status 時建不了，也不需要
say() { print -r -- "$(date '+%F %T') $*" >> $LOG; }
# 一般使用者對 root 行程 kill -0 會被拒，改用 ps；同時確認那個 PID 真的是 supervisor，避免 PID 重用時誤判或誤殺
running() {
  [[ -f $PIDFILE && ! -L $PIDFILE ]] || return 1
  local pid=$(head -c 12 $PIDFILE | tr -cd 0-9)
  [[ -n $pid ]] && ps -p $pid -o command= 2>/dev/null | grep -q 'stereo.sh supervise'
}

stop_all() {
  [[ -n ${TEST:-} ]] && return  # 自測時不碰真的 cliairplay
  # 比對任何位置的 run_pair.sh：Documents 裡手動跑的舊 session 結束時會清掉所有 cliairplay，包括新開的。
  # 用行程名稱（-x）或錨定開頭的樣式，不用裸字串 -f：命令列只是「提到」這些字的行程（編輯器、測試腳本）也會被 root 殺掉
  pkill -TERM -f '^zsh .*/run_pair\.sh' 2>/dev/null; sleep 2
  pkill -9 -f '^zsh .*/run_pair\.sh' 2>/dev/null
  pkill -9 -x cliairplay-macos-arm64 2>/dev/null
  pkill -9 -x audiotee 2>/dev/null
  pkill -9 -x localplay 2>/dev/null
  pkill -9 -x stereotool 2>/dev/null
  true
}

# 回傳要重啟的原因「代碼: 細節」；空字串＝正常。代碼固定（學 AirFlash 的 channel/code），方便統計
check() {  # stamp elapsed_s
  local d hit n=0 code
  local -a logs=()
  for d in ${=DEVICES}; do [[ $d != Mac ]] && logs+=$LOGDIR/pair-$1-$d.log; done
  hit=$(grep -hE "$BAD" $logs 2>/dev/null | head -1)
  if [[ -n $hit ]]; then
    case $hit in
      *REANCHOR*|*anchor_corrected*) code=reanchor ;;
      *starved*) code=input_starved ;;
      *Splice-padded*) code=delivery_stall ;;
      *content_cut*) code=content_cut ;;
      *) code=client_status ;;
    esac
    print -r -- "$code: $hit"; return
  fi
  [[ -n ${TEST:-} ]] && return
  # 每台喇叭都起播之後，各自的 client、PTP daemon、本機播放器都要還在
  for d in $logs; do grep -q 'STATUS\] started' $d 2>/dev/null && (( n++ )); done
  if (( n < $#logs )); then
    (( $2 > 35 )) && print "not_started: not all speakers started within 35 s"  # run_pair 自己的等待加總最多約 26 秒
    return
  fi
  (( $(pgrep -x cliairplay-macos-arm64 | wc -l) < $#logs + 1 )) && { print "client_exited: a cliairplay process exited"; return; }
  [[ " $DEVICES " == *" Mac "* ]] && ! pgrep -x localplay >/dev/null && print "local_player_exited: local player exited"
}

# 一段播放一列摘要（學 AirFlash 的 session-summary.csv）。只記 ID 與數字，不記 IP、名稱
SESSIONS=$LOGDIR/sessions.csv
count() { local c=$(grep -cE "$1" $2 2>/dev/null); print ${c:-0}; }  # 檔案不存在也回 0
summarize() {  # stamp end_code began_epoch
  local d l re=0 st=0 sp=0 cc=0 fill=0 drop=0
  [[ -f $SESSIONS ]] || print "session_id,start,duration_s,devices,left,mac_sync_ms,end_code,reanchors,input_starved,delivery_stalls,content_cuts,split_fill_ms,split_drop_ms" > $SESSIONS
  for d in ${=DEVICES}; do
    [[ $d == Mac ]] && continue
    l=$LOGDIR/pair-$1-$d.log
    (( re += $(count 'REANCHOR|anchor_corrected' $l), st += $(count 'PCM input starved' $l) ))
    (( sp += $(count 'Splice-padded' $l), cc += $(count 'content_cut' $l) ))
  done
  # split 每 10 秒印一次「補靜音 X ms，丟棄 Y ms」，加總起來
  for l in ${(f)"$(sed -n 's/.*補靜音 \([0-9]*\) ms，丟棄 \([0-9]*\) ms.*/\1 \2/p' $LOGDIR/pair-$1-split.log 2>/dev/null)"}; do
    (( fill += ${l%% *}, drop += ${l##* } ))
  done
  print -r -- "$1,$(date -r $3 '+%F %T'),$(( $(date +%s) - $3 )),${DEVICES// /;},${LEFT:-},${LOCAL_ADJ_MS:-0},$2,$re,$st,$sp,$cc,$fill,$drop" >> $SESSIONS
}

# 保留 7 天：每段播放的 log 超過就刪；總事件記錄超過 1 MB 換檔；摘要只留最近 2000 列
prune_logs() {
  find $LOGDIR -maxdepth 1 -type f -name 'pair-*' -mtime +7 -delete 2>/dev/null
  [[ -f $LOG && $(stat -f %z $LOG) -gt 1048576 ]] && mv -f $LOG $LOG.1
  # 摘要由 supervisor 追加：播放中不裁切，免得裁切中間追加的那列被蓋掉
  running || { [[ -f $SESSIONS ]] && (( $(wc -l < $SESSIONS) > 2001 )) && { head -1 $SESSIONS; tail -2000 $SESSIONS; } > $SESSIONS.$$ && mv -f $SESSIONS.$$ $SESSIONS }
  true
}

supervise() {
  trap '' HUP
  say "supervisor pid $$ as $(whoami)"
  echo $$ > $PIDFILE
  print -r -- $DEVICES > $DEVFILE
  local -a restarts
  local stamp="" reason now recent t began_at=0 summarized=""
  # 收到停止時，這段還沒寫摘要才補一列（重啟等待中收到的不重複記）
  trap 'say "stop requested"; [[ -n ${child:-} ]] && kill -TERM $child 2>/dev/null; stop_all; [[ -n $stamp && $stamp != $summarized ]] && summarize $stamp user_stop $began_at; rm -f $PIDFILE; exit 0' TERM INT
  while true; do
    stamp=$(date +%y%m%d-%H%M%S) began_at=$(date +%s)  # 含日期：跨日同一秒不會覆寫還在保留期的 log
    say "start $DEVICES left=${LEFT:-} mac_sync_ms=${LOCAL_ADJ_MS:-0} (log tag $stamp)"
    SPEAKERS=$SPEAKERS VOLFILE=$VOLFILE RUNDIR_FILE=$RUNDIR_FILE DEVICES=$DEVICES STAMP=$stamp DEBUG=3 zsh $RUN_PAIR live $LATENCY $TARGET >> $LOG 2>&1 &
    child=$!
    reason="" began=$SECONDS
    while ps -p $child >/dev/null 2>&1; do
      sleep $POLL_S
      reason=$(check $stamp $(( SECONDS - began )))
      [[ -n $reason ]] && break
    done
    [[ -z $reason ]] && reason="run_pair_exited: run_pair exited"
    say "restart: $reason"
    kill -TERM $child 2>/dev/null; wait $child 2>/dev/null; stop_all
    summarize $stamp ${reason%%:*} $began_at
    summarized=$stamp
    now=$(date +%s); restarts+=($now); recent=0
    for t in $restarts; do (( now - t < WINDOW_S )) && (( recent++ )); done
    if (( recent > MAX_RESTARTS )); then
      say "gave up: more than $MAX_RESTARTS restarts in $((WINDOW_S / 60)) min"
      rm -f $PIDFILE; exit 1
    fi
    sleep 3
  done
}

zmodload zsh/system
# 讀一般使用者可寫的小檔：不跟隨 symlink、非阻塞開啟（換成 FIFO 也不會讓 root 卡住），最多 64 bytes
read_user() {
  local fd s=""
  sysopen -r -o nofollow,nonblock -u fd $1 2>/dev/null || return 0
  sysread -i $fd -s 64 s 2>/dev/null
  exec {fd}<&-
  print -r -- $s
}
# 音量檔可能有好幾台喇叭，讀長一點（同樣不跟隨 symlink、非阻塞）
read_volume() {
  local fd s=""
  sysopen -r -o nofollow,nonblock -u fd $1 2>/dev/null || return 0
  sysread -i $fd -s 1024 s 2>/dev/null
  exec {fd}<&-
  print -r -- $s
}
# 非阻塞寫 cmd 管道：run_pair 剛結束、沒有讀端時直接失敗，不會卡住
send_cmd() {
  local fd
  sysopen -w -o nonblock -u fd $1 2>/dev/null || return 1
  syswrite -o $fd -- "$2"$'\n' 2>/dev/null
  exec {fd}>&-
}

my_ip() { ipconfig getifaddr $(route -n get default 2>/dev/null | awk '/interface:/ {print $2}') 2>/dev/null; }

# 找區網裡的 AirPlay 接收器（不含這台 Mac），寫成 SPEAKERS 與每台的 TXT 紀錄。
# 名稱與 TXT 都是網路上別人廣播的內容：只當資料存，ID 必須是 12 位十六進位、IP 必須是 IPv4 才收
discover() {
  # 一次只跑一個（mkdir 是原子的）；暫存檔帶 PID，不會互相覆蓋。當機留下的鎖超過 5 分鐘就當作失效
  [[ -n $(find $STATE/discover.lock -maxdepth 0 -mmin +5 2>/dev/null) ]] && rmdir $STATE/discover.lock
  mkdir $STATE/discover.lock 2>/dev/null || return 0
  trap 'rmdir $STATE/discover.lock 2>/dev/null' EXIT
  local me=$(my_ip) tmp=$SPEAKERS.$$ name out host txt key ip
  local -a names
  names=("${(@f)$( (dns-sd -B _airplay._tcp local & p=$!; sleep 3; kill $p) 2>/dev/null |
    awk '$2 == "Add" { sub(/.*_airplay\._tcp\.[ ]+/, ""); print }' | sort -u)}")
  : > $tmp
  for name in $names; do
    [[ -n $name ]] || continue
    out=$( (dns-sd -L "$name" _airplay._tcp local & p=$!; sleep 2; kill $p) 2>/dev/null )
    host=$(print -r -- $out | sed -n 's/.* can be reached at \([^ :]*\)\.:[0-9]* .*/\1/p' | head -1)
    txt=$(print -r -- $out | grep -m1 'deviceid=' | sed 's/^ *//')
    key=$(print -r -- $txt | sed -n 's/.*deviceid=\([0-9A-Fa-f:]*\).*/\1/p' | tr -d ':' | tr a-f A-F)
    [[ $key == [0-9A-F](#c12) && -n $host ]] || continue
    # 其他 Mac 也會廣播 AirPlay（螢幕鏡像接收），在別人的網路上就是別人的電腦，不列出來免得誤送
    [[ $txt == *model=Mac* ]] && continue
    ip=$( (dns-sd -G v4 "$host" & p=$!; sleep 1.5; kill $p) 2>/dev/null | awk '$2 == "Add" { print $6; exit }')
    [[ $ip == <0-255>.<0-255>.<0-255>.<0-255> && $ip != $me && $ip != 127.* ]] || continue  # 這台 Mac 自己會解析成 127.0.0.1
    grep -q "^$key"$'\t' $tmp && continue  # 同一台改名時新舊名稱會同時廣播：同一個 ID 只留一筆
    print -r -- $txt > $STATE/txt-$key.$$ && mv -f $STATE/txt-$key.$$ $STATE/txt-$key  # 起播時不會讀到寫一半的
    print -r -- "$key"$'\t'"$ip"$'\t'"${name//[[:cntrl:]]/}"$'\t'"$(date +%s)" >> $tmp  # 第 4 欄：最後看到的時間
  done
  # 這次沒回應的保留 10 分鐘，免得一時沒回應就從選單消失；更久沒看到（換了網路、關機、別人帶走）就拿掉
  if [[ -f $SPEAKERS ]]; then  # 用檔名分辨兩個輸入（NR == FNR 遇到空的第一個檔會判錯）
    awk -F'\t' -v cutoff=$(( $(date +%s) - 600 )) 'FILENAME == ARGV[1] { seen[$1] = 1; next }
      !($1 in seen) && $4 + 0 >= cutoff && $3 !~ /^$/ { seen[$1] = 1; print }' $tmp $SPEAKERS > $tmp.old 2>/dev/null
    cat $tmp.old >> $tmp; rm -f $tmp.old
  fi
  sort -t$'\t' -k3 $tmp > $tmp.sorted && mv -f $tmp.sorted $SPEAKERS; rm -f $tmp
}
# 找過的喇叭 ID 才算數
known() { [[ $1 == [0-9A-F](#c12) ]] && grep -q "^$1"$'\t' $SPEAKERS 2>/dev/null; }

case ${1:-status} in
  on)
    shift; DEVICES=$*
    running && { echo "already on"; exit 0; }
    stop_all  # 清掉上次手動測試留下的 daemon，否則會搶 319/320
    # 不用 nohup：以 root 從管理員對話框跑時，macOS 的 nohup 會失敗（can't detach from console）
    DEVICES=$DEVICES zsh $0 supervise < /dev/null >> $LOGDIR/supervise.err 2>&1 &!
    for i in {1..20}; do running && break; sleep 0.25; done
    running && echo "on" || { echo "failed to start: $(tail -3 $LOGDIR/supervise.err 2>/dev/null) (whoami=$(whoami))"; exit 1; }
    ;;
  off)
    running && kill -TERM $(head -c 12 $PIDFILE | tr -cd 0-9)
    for i in {1..40}; do running || break; sleep 0.25; done
    stop_all; rm -f $PIDFILE
    echo "off"
    ;;
  status)
    # 背景服務每次迴圈更新 heartbeat；開關本身最多卡十幾秒，超過 20 秒沒更新、或從沒跑過，就是服務沒在跑
    if [[ -z ${TEST:-} ]] && { [[ ! -f $HEARTBEAT ]] || (( $(date +%s) - $(stat -f %m $HEARTBEAT) > 20 )) }; then echo "noservice"
    elif running; then echo "on $(head -c 64 $DEVFILE 2>/dev/null)"; else echo "off"; fi
    tail -1 $LOG 2>/dev/null || true
    ;;
  supervise) supervise ;;
  discover) discover ;;
  serve)  # 背景服務（root）：App 改寫 want 檔時才照內容開或關。只在檔案變動時動作，自癒放棄後不會被立刻拉起來
    want_file=$2 dir=${2:h} last="" vlast="" vdone="" found_at=-999 pruned_at=-9999
    trap 'zsh $0 off >/dev/null; exit 0' TERM INT
    while true; do
      touch $HEARTBEAT
      # 每分鐘重新找一次喇叭（背景跑，約 3 秒＋每台 3.5 秒，不擋住這個迴圈）
      if (( SECONDS - found_at > 60 )); then found_at=$SECONDS; zsh $0 discover < /dev/null > /dev/null 2>&1 &!; fi
      if (( SECONDS - pruned_at > 3600 )); then pruned_at=$SECONDS; prune_logs; fi
      # want：要出聲的裝置，喇叭 ID 加上「Mac」。只收找過的 ID、最多兩台、照排序；沒有喇叭就是關（聲音回到 Mac 本身）
      seen=$(stat -f '%Fm %i' $want_file 2>/dev/null)  # 奈秒 mtime 加 inode，同一秒內的兩次寫入也分得出來
      want="" n=0 mac=""
      for w in ${(ou)=$(read_user $want_file | tr -c 'A-Za-z0-9' ' ')}; do  # 排序並去掉重複
        if [[ $w == Mac ]]; then mac=" Mac"
        elif (( n < 2 )) && known $w; then want+="$w "; (( n++ ))
        fi
      done
      want=${want% }
      [[ -z $want ]] && want=off || want+=$mac
      # 設定視窗改的值（Mac 對齊、哪台當左聲道）只在起播時讀；改了而且正在播，就重新起播套用
      cfg=$(stat -f '%Fm %i' $dir/mac-sync-ms $dir/left 2>/dev/null | tr '\n' ' ')
      cfg_changed=""
      [[ -n ${clast+x} && $cfg != $clast ]] && cfg_changed=1
      clast=$cfg
      want_changed=""
      [[ "$seen $want" != $last ]] && want_changed=1
      if [[ -n $want_changed || -n $cfg_changed ]]; then
        last="$seen $want"
        if [[ $want == off ]]; then running && zsh $0 off
        # 改裝置組合：不是已經在播這組就起播。只改設定：正在播才重新起播（自癒放棄後不會被設定拉起來）
        elif [[ -n $want_changed ]] && [[ $(zsh $0 status | head -1) != "on $want" ]] || { [[ -n $cfg_changed ]] && running }; then
          running && zsh $0 off
          # Mac 喇叭的對齊微調（ms）：只接受 -300 到 300 的整數，其他當 0。左聲道：這次要播的其中一台，其他當第一台
          adj=$(read_user $dir/mac-sync-ms | tr -d ' \n')  # 原樣驗證，不先濾字元（1e2 不能變成 12）
          [[ $adj == (|-)<0-300> ]] || adj=0
          left=$(read_user $dir/left | tr -cd 'A-Z0-9')
          [[ " $want " == *" $left "* && $left != Mac ]] || left=${want%% *}
          LEFT=$left LOCAL_ADJ_MS=$adj zsh $0 on ${=want}
        fi
      fi
      # 音量（如「<喇叭 ID>=40 …」）：只認喇叭 ID、0–100 的整數，整理後原子寫到 root 的 VOLFILE 給起播用
      vseen=$(stat -f '%Fm %i' $dir/volume 2>/dev/null)
      if [[ $vseen != $vlast ]]; then
        vlast=$vseen vols=""
        for kv in $(read_volume $dir/volume | tr -c 'A-Za-z0-9=' ' '); do
          [[ ${kv%%=*} == [0-9A-F](#c12) && ${kv#*=} == <0-100> ]] && vols+="$kv "
        done
        print -r -- ${vols% } > $VOLFILE.tmp && mv -f $VOLFILE.tmp $VOLFILE
        vdone=""  # 新音量要重送
      fi
      # 播放中：等這一輪的 client 都連上（run_pair 建 ready），把 VOLFILE 送給每台。每輪 run_pair 都重送一次，
      # 起播途中改的音量、或存成 0 的音量（cliairplay 起播時不送 0）才不會漏掉
      rd=$(head -c 64 $RUNDIR_FILE 2>/dev/null)
      if [[ $rd != $vdone ]] && running && [[ $rd == /tmp/cliairplay-pair.* && -O $rd && -f $rd/ready ]]; then
        for kv in $(<$VOLFILE); do
          [[ -p $rd/cmd-${kv%%=*} ]] && send_cmd $rd/cmd-${kv%%=*} "VOLUME=${kv#*=}"
        done
        vdone=$rd
      fi
      sleep 0.3  # 拉音量滑桿要跟手
    done
    ;;
  *) echo "usage: sudo zsh stereo.sh on|off|status"; exit 2 ;;
esac
