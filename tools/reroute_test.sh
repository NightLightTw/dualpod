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
trap 'pkill -P $pids[1] 2>/dev/null; kill $pids 2>/dev/null' EXIT  # sleep 是 zsh 的子行程，要一起收
fail() { print -u2 "FAIL: $*"; exit 1 }
eq() { [[ $1 == $2 ]] || fail "$3：要 [$2]，實際 [$1]" }
rr() { zsh $HERE/../stereo.sh reroute "$@" }

zsh -c 'sleep 600; :' stereo.sh supervise > /dev/null 2>&1 & pids+=($!)  # running 看的是命令列有「stereo.sh supervise」
print $! > $STATE/supervisor.pid; print -r -- $RD > $STATE/rundir
touch $RD/ready; mkfifo $RD/pcm-Mac $RD/pcm-$A $RD/pcm-$B $RD/cmd-$A $RD/cmd-$B
for d in $A $B; do cat <> $RD/cmd-$d > $S/got-$d & pids+=($!); done
sleep 0.3
zmodload zsh/datetime
# 假的 split：routes 一出現就（延遲 ackdelay 秒後）原樣複製成 routes.applied；有 noack 檔就不回報
zsh -c 'cd $0; while :; do
  if [[ ! -e noack && -f $1/routes ]] && ! cmp -s $1/routes $1/routes.applied; then
    sleep $(cat ackdelay 2>/dev/null || echo 0); cp $1/routes $1/routes.ack.tmp && mv -f $1/routes.ack.tmp $1/routes.applied
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
unchanged "加喇叭" $A $B
unchanged "只有 Mac（空集合）" Mac
unchanged "沒有裝置" 
unchanged "不認得的喇叭" CCCCCCCCCCCC
touch $S/noack; setdev "$A $B"; rm -f $RD/routes.applied
t0=$EPOCHREALTIME
rr $B || fail "沒有 ack 時仍要成功"
(( EPOCHREALTIME - t0 > 0.9 && EPOCHREALTIME - t0 < 2 )) || fail "沒有 ack 應等約 1 秒，實際 $((EPOCHREALTIME - t0))"
sleep 0.3; eq "$(cat $S/got-$A)" "ACTION=DISCONNECT" "沒有 ack 仍送出 DISCONNECT"
grep -q "沒收到 split 的 ack" $LOGDIR/stereo.log || fail "沒有 log timeout 一行"
rm -f $S/noack
rm -f $STATE/supervisor.pid
unchanged "沒在播" $A
print $pids[1] > $STATE/supervisor.pid; rm $RD/ready
unchanged "run dir 還沒 ready" $A
touch $RD/ready; print -r -- /tmp/elsewhere > $STATE/rundir
unchanged "run dir 不是 /tmp/cliairplay-pair.*" $A
print "reroute self-test ok"
