#!/bin/zsh
# 用法：zsh tools/reroute_test.sh <暫存資料夾>
# 自測 stereo.sh reroute：TEST=1、狀態與記錄都放暫存資料夾，不碰真的背景服務
set -u
S=${1:?暫存資料夾}; HERE=${0:A:h}
rm -rf $S/rr; mkdir -p $S/rr/state/run $S/rr/logs; S=$S/rr
export TEST=1 STATE=$S/state LOGDIR=$S/logs
A=AAAAAAAAAAAA B=BBBBBBBBBBBB
RD=$STATE/run
pids=()
# sleep 是 zsh 的子行程，要一起收；join 還留著的話收掉它（假 client 的父行程，先確認那個 pid 真的是假 client）
trap 'pkill -P $pids[1] 2>/dev/null; kill $pids 2>/dev/null
  fp=$(cat $S/fake.pid 2>/dev/null); [[ -n $fp && "$(ps -o command= -p $fp)" == *$S/fakeclient* ]] && kill $(ps -o ppid= -p $fp)' EXIT
fail() { print -u2 "FAIL: $*"; exit 1 }
eq() { [[ $1 == $2 ]] || fail "$3：要 [$2]，實際 [$1]" }
rr() { zsh $HERE/../stereo.sh reroute "$@" }

zsh -c 'sleep 600; :' stereo.sh supervise > /dev/null 2>&1 & pids+=($!)  # running 看的是命令列有「stereo.sh supervise」
print $! > $STATE/supervisor.pid; print -r -- $RD > $STATE/rundir
touch $RD/ready; mkfifo $RD/pcm-Mac $RD/pcm-$A $RD/pcm-$B $RD/cmd-$A $RD/cmd-$B
for d in $A $B; do cat <> $RD/cmd-$d > $S/got-$d & pids+=($!); done
sleep 0.3
zmodload zsh/datetime
# 假的 split：routes 一出現就（延遲 ackdelay 秒後）原樣複製成 routes.applied；有 noack 檔就不回報。
# 排程（@T）到了 T 才寫 routes.active，沒有 @ 的馬上寫；有 noactive 檔就不寫（tool、off 檔在加入測試前才有，沒 @ 的用不到）
zsh -c 'cd $0; while :; do
  if [[ ! -e noack && -f $1/routes ]] && ! cmp -s $1/routes $1/routes.applied; then
    sleep $(cat ackdelay 2>/dev/null || echo 0); cp $1/routes $1/routes.ack.tmp && mv -f $1/routes.ack.tmp $1/routes.applied
    t=${${(M)${(z)$(cat $1/routes)}:#*@<->}[1]##*@}
    [[ -n $t ]] && $(cat $0/tool) sleepuntil $t $(cat $0/off)
    [[ -e noactive ]] || { cp $1/routes $1/routes.act.tmp && mv -f $1/routes.act.tmp $1/routes.active; }
  fi; sleep 0.01; done' $S $RD > /dev/null 2>&1 & pids+=($!)
print 0.4 > $S/ackdelay
setdev() { print -r -- $1 > $STATE/devices; rm -f $RD/routes }
snap() { print -r -- "$(cat $STATE/devices) | $(cat $RD/routes 2>/dev/null)" }
unchanged() {  # 名稱 參數…：以非 0 結束，且 devices、routes、cmd 都沒動
  local before=$(snap) name=$1; shift
  rr "$@" && fail "$name 應該失敗"
  eq "$(snap)" $before "$name 沒有改任何東西"
}

setdev "$A $B"
rr $A $B Mac || fail "開 Mac"
eq "$(snap)" "$A $B Mac | $RD/pcm-$A:L $RD/pcm-$B:R $RD/pcm-Mac:LR" "兩台加 Mac"
LEFT=$B rr $A $B || fail "關 Mac、左右對調"
eq "$(snap)" "$A $B | $RD/pcm-$B:L $RD/pcm-$A:R $RD/pcm-Mac:0" "LEFT=B 時 B 是左"
sleep 0.3; eq "$(cat $S/got-$A $S/got-$B)" "" "只改 Mac 或左右時沒人收到 DISCONNECT"

rr $A & rrpid=$!
sleep 0.2
[[ ! -e $RD/routes.applied ]] && eq "$(cat $S/got-$B)" "" "ack 還沒到，B 不能先收到 DISCONNECT"
wait $rrpid || fail "移除 B"
eq "$(cat $RD/routes.applied)" "$(cat $RD/routes)" "reroute 結束時 ack 已存在"
eq "$(snap)" "$A | $RD/pcm-$A:LR $RD/pcm-$B:X $RD/pcm-Mac:0" "剩一台 LR、B 是 X"
sleep 0.3
eq "$(cat $S/got-$B)" "ACTION=DISCONNECT" "B 收到 DISCONNECT"
eq "$(cat $S/got-$A)" "" "A 沒收到任何指令"
grep -q "reroute: $A $B -> $A" $LOGDIR/stereo.log || fail "沒有 log 一行"

rr $A Mac || fail "剩一台再開 Mac"
eq "$(snap)" "$A Mac | $RD/pcm-$A:LR $RD/pcm-$B:X $RD/pcm-Mac:LR" "移除 B 後再開 Mac，B:X 仍在（表完整）"
sleep 0.3; eq "$(cat $S/got-$B)" "ACTION=DISCONNECT" "B 沒有被重送 DISCONNECT"
unchanged "加沒找過的喇叭" $A $B

# 播放中加入一台：真的跑 run_pair.sh join，cliairplay 換成假的（印 clock_ready、收到 START 就回 started）
TOOL=$HERE/stereotool
print -r -- "$A"$'\t'"127.0.0.1"$'\t'"a"$'\n'"$B"$'\t'"127.0.0.1"$'\t'"b" > $STATE/speakers
print "model=fake" > $STATE/txt-$B
OFF=$($TOOL offset); nowms() { $TOOL now $OFF }
print $TOOL > $S/tool; print $OFF > $S/off; print $OFF > $RD/clock_offset; print 200 > $RD/latency; print teststamp > $RD/stamp; print $(( $(nowms) - 5000 )) > $RD/start_ms
cat > $S/fakeclient <<'FAKE'
#!/bin/zsh
while (( $# )); do case $1 in --clock-offset-ns) off=$2 ;; --cmdpipe) cp=$2 ;; esac; shift; done
cd $FAKE_DIR; print $$ > fake.pid
print "[STATUS] connected"
[[ -e noready ]] || print "[STATUS] clock_ready mode=ptp state=ready streak_ms=753 exchanges=6 ready_in_ms=0 ready_at_unix_ms=$(( $($FAKE_TOOL now $off) + $(<readyin) ))"
while read -r line; do
  print -r -- $line >> fake.got
  case $line in
    START_UNIX_MS=*) t=${line#*=} ;;
    ACTION=START) print "[STATUS] started requested_unix_ms=$t at_unix_ms=$(( t + $(<skew) ))" ;;
    ACTION=DISCONNECT) print "[STATUS] stopped"; exit ;;
  esac
done < $cp
FAKE
chmod +x $S/fakeclient
export FAKE_BIN=$S/fakeclient FAKE_DIR=$S FAKE_TOOL=$TOOL MY_IP=127.0.0.1
JLOG=$LOGDIR/pair-teststamp-$B.log
alive() { kill -0 $(cat $S/fake.pid) 2>/dev/null }
ready_at() { sed -n 's/.*ready_at_unix_ms=\([0-9]*\).*/\1/p' $JLOG }
print -r -- "$B=0" > $STATE/volumes
print 0 > $S/ackdelay; print 0 > $S/skew; print 300 > $S/readyin; : > $S/got-$B

setdev "$A"
unchanged "A 起播時刻沒核對到就不加入" $A $B
print "[STATUS] started requested_unix_ms=$(cat $RD/start_ms) at_unix_ms=$(cat $RD/start_ms)" > $LOGDIR/pair-teststamp-$A.log
t0=$(nowms)
rr $A $B || fail "加入 B"
t1=$(nowms)
T2=$(sed -n 's/.*:L@\([0-9]*\) .*/\1/p' $RD/routes)
eq "$(snap)" "$A $B | $RD/pcm-$A:L@$T2 $RD/pcm-$B.1:R@$T2 $RD/pcm-$B:X $RD/pcm-Mac:0@$T2" "加入：每個留下的輸出都在 T2 切換，B 用新的一代"
(( T2 >= t0 + 600 && T2 >= $(ready_at) && T2 <= t1 )) || fail "T2=$T2 要不早於 ready_at、比決定時晚 600 ms，且 reroute 等到 T2 才回來（$t0..$t1）"
eq "$(cat $S/fake.got)" "VOLUME=0"$'\n'"START_UNIX_MS=$T2"$'\n'"START_JOIN=1"$'\n'"ACTION=START" "B 先收到存成 0 的 VOLUME，再收到 START 三行"
eq "$(cat $RD/routes.active)" "$(cat $RD/routes)" "reroute 回來時 .active 已在"
eq "$(cat $RD/cur-$B)" ".1" "記下 B 目前這一代"
alive || fail "加入成功後 B 的 client 要留著"
eq "$(cat $S/got-$A)" "" "加入時 A 沒收到任何指令"
grep -q "reroute: $A -> $A $B" $LOGDIR/stereo.log || fail "沒有 log 加入一行"

rm $S/fake.got
rr $A || fail "移除加入的 B"
eq "$(snap)" "$A | $RD/pcm-$A:LR $RD/pcm-$B:X $RD/pcm-$B.1:X $RD/pcm-Mac:0" "移除後 B 的兩代都是 X"
sleep 1.5
eq "$(cat $S/fake.got)" "ACTION=DISCONNECT" "DISCONNECT 送到 B 這一代的 cmd"
eq "$(cat $S/got-$B)" "" "起播那一代的 cmd-B 沒收到"
alive && fail "B 斷開後 client 要結束"
[[ ! -e $RD/pcm-$B.1 && ! -e $RD/cmd-$B.1 ]] || fail "B 這一代的 FIFO 要收掉"

# 再加一次：又是新的一代、上一代的 log（有 stopped）移開、左右照 LEFT；ready_at 比 now+600 晚時 T2 就是 ready_at
rm $S/fake.got; print 2000 > $S/readyin
LEFT=$B rr $A $B || fail "再加入 B"
T2=$(ready_at)
eq "$(snap)" "$A $B | $RD/pcm-$B.2:L@$T2 $RD/pcm-$A:R@$T2 $RD/pcm-$B:X $RD/pcm-Mac:0@$T2" "再加入：新的一代 .2，T2 就是 ready_at"
grep -q stopped $JLOG && fail "這一代的 log 不能有上一代的 stopped"
grep -q stopped $JLOG.*(N) || fail "上一代的 log 要留著（移開）"

prep() { rr $A || fail "回到只有 A"; sleep 1.5; rm -f $S/fake.got $S/fake.pid }
joinfails() {  # 名稱：以非 0 結束、devices 不變、新加的 client 被收掉、A 沒收到指令
  rr $A $B && fail "$1 應該失敗"
  eq "$(cat $STATE/devices)" $A "$1：devices 不變"
  sleep 1.5; alive && fail "$1：新加的 client 要被收掉"
  [[ -z "$(print -l $RD/*-$B.<->(N))" ]] || fail "$1：新加那一代的 FIFO 要收掉"
  eq "$(cat $S/got-$A)" "" "$1：A 沒收到任何指令"
  grep -q "加入 $B 失敗" $LOGDIR/stereo.log || fail "$1：沒有 log 失敗一行"
}
prep; print 300 > $S/readyin; print 7 > $S/skew
joinfails "started 的時刻被修正"
grep -q "ACTION=START" $S/fake.got || fail "時刻被修正那次有送 START"
prep; print 0 > $S/skew; touch $S/noack
joinfails "split 沒有 ack"
grep -q START $S/fake.got && fail "split 沒 ack 就不能送 START"
rm $S/noack; prep; touch $S/noactive
before=$(cat $STATE/devices)
joinfails "split 收下排程但沒執行（.active 沒來）"
grep -q "沒回報排程已執行" $LOGDIR/stereo.log || fail "沒有 log .active 逾時一行"
rm $S/noactive; prep; touch $S/noready
before=$(cat $RD/routes)
joinfails "時鐘一直沒就緒"
eq "$(cat $RD/routes)" $before "時鐘沒就緒不寫路由"
rm $S/noready
unchanged "只有 Mac（空集合）" Mac
unchanged "沒有裝置" 
unchanged "不認得的喇叭" CCCCCCCCCCCC
touch $S/noack; setdev "$A $B"; rm -f $RD/routes.applied
t0=$EPOCHREALTIME
before=$(cat $STATE/devices)
rr $B && fail "沒有 ack 時要以非 0 結束"
(( EPOCHREALTIME - t0 > 0.9 && EPOCHREALTIME - t0 < 2 )) || fail "沒有 ack 應等約 1 秒，實際 $((EPOCHREALTIME - t0))"
sleep 0.3; eq "$(cat $S/got-$A)" "" "沒有 ack 不送 DISCONNECT"
eq "$(cat $STATE/devices)" $before "沒有 ack 不改 devices"
grep -q "沒收到 split 的 ack" $LOGDIR/stereo.log || fail "沒有 log timeout 一行"
rm -f $S/noack
# ack 的同時把 rundir 換成別的 session：reroute 要放棄、devices 維持原樣、不送 DISCONNECT
setdev "$A $B"; rm -f $RD/routes.applied; print 0.4 > $S/ackdelay
{ sleep 0.2; print -r -- $STATE/other > $STATE/rundir } & swp=$!
rr $B && fail "session 被換掉時要以非 0 結束"
wait $swp; sleep 0.3
eq "$(cat $STATE/devices)" "$A $B" "session 被換掉，devices 維持原樣"
eq "$(cat $S/got-$A)" "" "session 被換掉不送 DISCONNECT"
print -r -- $RD > $STATE/rundir
rm -f $STATE/supervisor.pid
unchanged "沒在播" $A
print $pids[1] > $STATE/supervisor.pid; rm $RD/ready
unchanged "run dir 還沒 ready" $A
touch $RD/ready; print -r -- /tmp/elsewhere > $STATE/rundir
unchanged "run dir 不是 /tmp/cliairplay-pair.*" $A
print "reroute self-test ok"
