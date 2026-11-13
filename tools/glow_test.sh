#!/bin/zsh
# 用法：zsh tools/glow_test.sh <暫存資料夾>
# 自測 stereo.sh 的 glow_tick（Sound Glow）：載入函式（GLOW_LIB=1），暫存資料夾裡的 FIFO 配背景讀端，不碰真的背景服務
set -u
S=${1:?暫存資料夾}; HERE=${0:A:h}
rm -rf $S/gl; mkdir -p $S/gl/state/run $S/gl/logs $S/gl/set; S=$S/gl
export TEST=1 STATE=$S/state LOGDIR=$S/logs GLOW_LIB=1
A=AAAAAAAAAAAA B=BBBBBBBBBBBB J=CCCCCCCCCCCC
pids=(); trap 'kill $pids 2>/dev/null' EXIT
fail() { print -u2 "FAIL: $*"; exit 1 }
eq() { [[ $1 == $2 ]] || fail "$3：要 [$2]，實際 [$1]" }
source $HERE/../stereo.sh
dir=$S/set rd=$STATE/run
mkdir -p $rd; touch $rd/ready
print -r -- "$A $B Mac" > $DEVFILE
reader() { mkfifo $1; cat <> $1 >> $2 & pids+=($!) }  # 管道 輸出檔
for d in $A $B; do reader $rd/cmd-$d $S/got-$d; done
sleep 0.3
got() { sleep 0.25; cat $S/got-$1 2>/dev/null }
clear() { : > $S/got-$A; : > $S/got-$B }
META=$'TITLE=DualPod\nARTIST=Mac\nITEMID=airplay-stereo\nACTION=SENDMETA'
WARM=$STATE/glow.jpg

# 沒有 glow 檔、關、亂寫的內容：什麼都不送、也不產圖
for v in "" off "preset:nope" "preset:" "preset:../x" "custom:../../x" "custom:#GGGGGG" "custom:#FF0000,#00FF00,#0000FF,#FFFFFF" "custom:#FF000" "custom:FF0000" "preset:warm;x" "garbage"; do
  print -rn -- $v > $dir/glow; glow_tick
  eq "$(got $A)$(got $B)" "" "[$v] 當作關"
done
rm -f $dir/glow; glow_tick; eq "$(got $A)" "" "沒有 glow 檔"
[[ -z "$(print -l $STATE/glow*(N))" ]] || fail "關閉或無效時不該產圖"
ln -s /etc/hosts $dir/glow; glow_tick; eq "$(got $A)" "" "glow 檔是 symlink 不跟隨"; rm $dir/glow

# 開：先 SENDMETA（沒有 ARTWORKFILE），GLOW_DELAY 秒之後才送 ARTWORK=
print "preset:warm" > $dir/glow
t0=$SECONDS; glow_tick
eq "$(got $A)" $META "A 先收到 SENDMETA"; eq "$(got $B)" $META "B 先收到 SENDMETA"
[[ -f $WARM ]] || fail "沒有產圖 $WARM"
sleep 0.6; glow_tick
eq "$(got $A)" $META "不到 $GLOW_DELAY 秒不送 ARTWORK"
while (( SECONDS - t0 < GLOW_DELAY )); do sleep 0.1; done; glow_tick
(( SECONDS - t0 >= GLOW_DELAY )) || fail "測試時間不對"
eq "$(got $A)" "$META"$'\n'"ARTWORK=$WARM" "兩秒後 A 收到 ARTWORK"; eq "$(got $B)" "$META"$'\n'"ARTWORK=$WARM" "兩秒後 B 收到 ARTWORK"
grep -c ARTWORKFILE $S/got-$A | grep -qx 0 || fail "SENDMETA 不能帶 ARTWORKFILE"

# 同一個顏色再評估多次：不重送
clear; glow_tick; glow_tick; eq "$(got $A)$(got $B)" "" "同色不重送"

# 換顏色（自訂單色）：只送新的 ARTWORK=
print "custom:#12ab34" > $dir/glow; glow_tick
eq "$(got $A)" "ARTWORK=$STATE/glow.jpg" "換色只送 ARTWORK"; eq "$(got $B)" "ARTWORK=$STATE/glow.jpg" "B 也是"
clear; glow_tick; eq "$(got $A)" "" "換色後同色不重送"

# 播放中改成 off：什麼都不送；再開成同色也不重送，換色才送
print off > $dir/glow; glow_tick; eq "$(got $A)$(got $B)" "" "改成 off 不送"
print "custom:#12ab34" > $dir/glow; glow_tick; eq "$(got $A)" "" "off 再開同色不重送"
print "custom:#ff0000,#00ff00" > $dir/glow; glow_tick; eq "$(got $A)" "ARTWORK=$STATE/glow.jpg" "兩色"

# 新加入的喇叭（.1 管道）：先 SENDMETA 再 ARTWORK，原本的不動
clear; GLOW_DELAY=0
print "$A $B $J Mac" > $DEVFILE; print .1 > $rd/cur-$J; reader $rd/cmd-$J.1 $S/got-$J; sleep 0.3
glow_tick; eq "$(got $J)" $META "新加入的先收到 SENDMETA"; eq "$(got $A)$(got $B)" "" "原本的不動"
glow_tick; eq "$(got $J)" "$META"$'\n'"ARTWORK=$STATE/glow.jpg" "新加入的再收到 ARTWORK"
eq "$(got $A)$(got $B)" "" "原本的仍然不動"
# 那台離開（不在 DEVFILE）後換色：不送給它
print "$A $B Mac" > $DEVFILE; : > $S/got-$J; print "preset:cool" > $dir/glow; glow_tick; eq "$(got $J)" "" "不在組合內的不送"
eq "$(got $A)" "ARTWORK=$STATE/glow.jpg" "換成預設色"

# 新 session（run dir 換掉）：全部當沒見過
rd2=$STATE/run2; mkdir -p $rd2; touch $rd2/ready
for d in $A $B; do reader $rd2/cmd-$d $S/got-$d; done; sleep 0.3; clear
rd=$rd2; glow_tick; eq "$(got $A)" $META "新 session 重新送 SENDMETA"; glow_tick; eq "$(got $B)" "$META"$'\n'"ARTWORK=$STATE/glow.jpg" "新 session 再送 ARTWORK"
# run dir 失效（不是 ready、不在 STATE 下）：不送、狀態清空
clear; rd=/tmp/elsewhere; glow_tick; eq "$(got $A)" "" "run dir 不合格不送"; eq "${#glow_sent}" 0 "狀態清空"
# 沒有讀端的管道：送不出去就不記，讀端回來後補送
rm -rf $rd2; mkdir -p $rd2; touch $rd2/ready; mkfifo $rd2/cmd-$A; rd=$rd2; print "$A Mac" > $DEVFILE
glow_tick; eq "${#glow_sent}" 0 "沒讀端不記為已送"
cat <> $rd2/cmd-$A >> $S/late & pids+=($!); sleep 0.3; glow_tick; sleep 0.25
eq "$(cat $S/late)" $META "讀端回來後補送 SENDMETA"
# 管道滿了（讀端不收）寫會失敗：不記為已送，讀端開始收之後補送；全程有上限不會卡住
rd3=$STATE/run3; mkdir -p $rd3; touch $rd3/ready; mkfifo $rd3/cmd-$A; rd=$rd3; print "$A Mac" > $DEVFILE
sleep 20 <> $rd3/cmd-$A & hold=$!; pids+=($hold)  # 有讀端但不讀
sleep 0.3; sysopen -w -o nonblock -u ffd $rd3/cmd-$A || fail "開不了管道"
chunk=$(printf "x%.0s" {1..4000}); n=0
while (( n++ < 100 )) && syswrite -o $ffd -- $chunk 2>/dev/null; do :; done
n=0; while (( n++ < 5000 )) && syswrite -o $ffd -- x 2>/dev/null; do :; done  # 補滿零碎空間，小寫入才一定失敗
exec {ffd}>&-; (( n <= 5000 )) || fail "管道填不滿"
glow_tick; eq "${#glow_sent}" 0 "寫失敗不記為已送"
kill $hold; wait $hold 2>/dev/null
cat <> $rd3/cmd-$A > $S/drain & pids+=($!); sleep 0.5; glow_tick; sleep 0.25
grep -q SENDMETA $S/drain || fail "管道收走後沒有補送 SENDMETA"
# 舊版每組顏色一個檔：prune_logs 清掉
touch $STATE/glow-AAAAAA.jpg; prune_logs; [[ -z "$(print -l $STATE/glow-*(N))" ]] || fail "舊的 glow-*.jpg 沒清掉"
print "glow self-test ok"
