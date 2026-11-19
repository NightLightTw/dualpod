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
nowms() { print ${$(( EPOCHREALTIME * 1000 ))%.*} }
mkrun() { mkdir -p $1; touch $1/ready; $TOOL offset > $1/clock_offset; print $(( $(nowms) - 5000 )) > $1/start_ms }  # 起播時刻已過很久
mkrun $rd
print -r -- "$A $B Mac" > $DEVFILE
reader() { mkfifo $1; cat <> $1 >> $2 & pids+=($!) }  # 管道 輸出檔
for d in $A $B; do reader $rd/cmd-$d $S/got-$d; done
sleep 0.3
got() { sleep 0.25; cat $S/got-$1 2>/dev/null }
clear() { : > $S/got-$A; : > $S/got-$B }
META=$'TITLE=DualPod\nARTIST=Mac\nITEMID=airplay-stereo\nACTION=SENDMETA'
MUSIC=MEDIATYPE=music VIDEO=MEDIATYPE=video
WARM=$STATE/glow.jpg

# 沒有 glow 檔、關、亂寫的內容：每個管道只送一次 MEDIATYPE=video（燈不亮），不送封面、也不產圖
print -rn -- "" > $dir/glow; glow_tick; eq "$(got $A)" $VIDEO "關：A 標成影片"; eq "$(got $B)" $VIDEO "關：B 標成影片"
clear
for v in off "preset:nope" "preset:" "preset:../x" "custom:../../x" "custom:#GGGGGG" "custom:#FF0000,#00FF00,#0000FF,#FFFFFF" "custom:#FF000" "custom:FF0000" "preset:warm;x" "garbage"; do
  print -rn -- $v > $dir/glow; glow_tick
  eq "$(got $A)$(got $B)" "" "[$v] 當作關"
done
rm -f $dir/glow; glow_tick; eq "$(got $A)" "" "沒有 glow 檔"
[[ -z "$(print -l $STATE/glow*(N))" ]] || fail "關閉或無效時不該產圖"
ln -s /etc/hosts $dir/glow; glow_tick; eq "$(got $A)" "" "glow 檔是 symlink 不跟隨"; rm $dir/glow

eq "$(glow_mt_now)" video "關時起播標影片"; print "preset:warm" > $dir/glow; eq "$(glow_mt_now)" music "開時起播標音樂"; print off > $dir/glow
clear

# 開：先標回音樂、SENDMETA（沒有ARTWORKFILE），GLOW_DELAY 秒之後才送 ARTWORK=
print "preset:warm" > $dir/glow
GLOW_DELAY=100  # SECONDS 是整數，「還沒到」的斷言要用遠大於測試耗時的值才不會跨過邊界
glow_tick
eq "$(got $A)" "$MUSIC"$'\n'$META "A 先標音樂再收到 SENDMETA"; eq "$(got $B)" "$MUSIC"$'\n'$META "B 先標音樂再收到 SENDMETA"
[[ -f $WARM ]] || fail "沒有產圖 $WARM"
clear; sleep 0.6; glow_tick
eq "$(got $A)" "" "還沒到 GLOW_DELAY 不送 ARTWORK"
for k in ${(k)glow_sent}; do glow_sent[$k]=meta@0; done; glow_tick  # 把到期時刻拉到現在，不必真的等
eq "$(got $A)" "ARTWORK=$WARM" "到期後 A 收到 ARTWORK"; eq "$(got $B)" "ARTWORK=$WARM" "到期後 B 收到 ARTWORK"
grep -c ARTWORKFILE $S/got-$A | grep -qx 0 || fail "SENDMETA 不能帶 ARTWORKFILE"

# 同一個顏色再評估多次：不重送
clear; glow_tick; glow_tick; eq "$(got $A)$(got $B)" "" "同色不重送"

# 換顏色（自訂單色）：只送新的 ARTWORK=
print "custom:#12ab34" > $dir/glow; glow_tick
eq "$(got $A)" "ARTWORK=$STATE/glow.jpg" "換色只送 ARTWORK"; eq "$(got $B)" "ARTWORK=$STATE/glow.jpg" "B 也是"
clear; glow_tick; eq "$(got $A)" "" "換色後同色不重送"

# 播放中改成 off：只標成影片（燈立刻暗）；再開成同色只標回音樂（cliairplay 帶著留著的封面重送），換色才送 ARTWORK
print off > $dir/glow; glow_tick; eq "$(got $A)" $VIDEO "改成 off 標影片"; eq "$(got $B)" $VIDEO "B 也標影片"
clear; glow_tick; eq "$(got $A)$(got $B)" "" "off 不重送"
print "custom:#12ab34" > $dir/glow; glow_tick; eq "$(got $A)" $MUSIC "off 再開同色只標回音樂"
clear; print "custom:#ff0000,#00ff00" > $dir/glow; glow_tick; eq "$(got $A)" "ARTWORK=$STATE/glow.jpg" "兩色"

# 新加入的喇叭（.1 管道）：先 SENDMETA 再 ARTWORK，原本的不動
clear; GLOW_DELAY=0
print "$A $B $J Mac" > $DEVFILE; print .1 > $rd/cur-$J; reader $rd/cmd-$J.1 $S/got-$J; sleep 0.3
glow_tick; eq "$(got $J)" "$MUSIC"$'\n'$META "新加入的先標音樂、SENDMETA"; eq "$(got $A)$(got $B)" "" "原本的不動"
glow_tick; eq "$(got $J)" "$MUSIC"$'\n'"$META"$'\n'"ARTWORK=$STATE/glow.jpg" "新加入的再收到 ARTWORK"
eq "$(got $A)$(got $B)" "" "原本的仍然不動"
# 那台離開（不在 DEVFILE）後換色：不送給它
print "$A $B Mac" > $DEVFILE; : > $S/got-$J; print "preset:cool" > $dir/glow; glow_tick; eq "$(got $J)" "" "不在組合內的不送"
eq "$(got $A)" "ARTWORK=$STATE/glow.jpg" "換成預設色"

# 新 session（run dir 換掉）：全部當沒見過
rd2=$STATE/run2; mkrun $rd2
for d in $A $B; do reader $rd2/cmd-$d $S/got-$d; done; sleep 0.3; clear
rd=$rd2; glow_tick; eq "$(got $A)" "$MUSIC"$'\n'$META "新 session 重新標音樂、送 SENDMETA"; glow_tick; eq "$(got $B)" "$MUSIC"$'\n'"$META"$'\n'"ARTWORK=$STATE/glow.jpg" "新 session 再送 ARTWORK"
# run dir 失效（不是 ready、不在 STATE 下）：不送、狀態清空
clear; rd=/tmp/elsewhere; glow_tick; eq "$(got $A)" "" "run dir 不合格不送"; eq "${#glow_sent}${#glow_mt}" 00 "狀態清空"
# 沒有讀端的管道：送不出去就不記，讀端回來後補送
rm -rf $rd2; mkrun $rd2; mkfifo $rd2/cmd-$A; rd=$rd2; print "$A Mac" > $DEVFILE
glow_tick; eq "${#glow_sent}${#glow_mt}" 00 "沒讀端不記為已送"
cat <> $rd2/cmd-$A >> $S/late & pids+=($!); sleep 0.3; glow_tick; sleep 0.25
eq "$(cat $S/late)" "$MUSIC"$'\n'$META "讀端回來後補送 MEDIATYPE、SENDMETA"
# 管道滿了（讀端不收）寫會失敗：不記為已送，讀端開始收之後補送；全程有上限不會卡住
rd3=$STATE/run3; mkrun $rd3; mkfifo $rd3/cmd-$A; rd=$rd3; print "$A Mac" > $DEVFILE
sleep 20 <> $rd3/cmd-$A & hold=$!; pids+=($hold)  # 有讀端但不讀
sleep 0.3; sysopen -w -o nonblock -u ffd $rd3/cmd-$A || fail "開不了管道"
chunk=$(printf "x%.0s" {1..4000}); n=0
while (( n++ < 100 )) && syswrite -o $ffd -- $chunk 2>/dev/null; do :; done
n=0; while (( n++ < 5000 )) && syswrite -o $ffd -- x 2>/dev/null; do :; done  # 補滿零碎空間，小寫入才一定失敗
exec {ffd}>&-; (( n <= 5000 )) || fail "管道填不滿"
glow_tick; eq "${#glow_sent}${#glow_mt}" 00 "寫失敗不記為已送"
kill $hold; wait $hold 2>/dev/null
cat <> $rd3/cmd-$A > $S/drain & pids+=($!); sleep 0.5; glow_tick; sleep 0.25
grep -q SENDMETA $S/drain || fail "管道收走後沒有補送 SENDMETA"
# 起播時刻之前不送：有 ready 但沒有 start_ms、start_ms 在未來、剛過但不到 1 秒，都不能碰管道（會排在 START 前面）
rd4=$STATE/run4; mkdir -p $rd4; touch $rd4/ready; $TOOL offset > $rd4/clock_offset; mkfifo $rd4/cmd-$A; rd=$rd4; print "$A Mac" > $DEVFILE; GLOW_DELAY=0
cat <> $rd4/cmd-$A >> $S/gate & pids+=($!); sleep 0.3
glow_tick; sleep 0.25; eq "$(cat $S/gate)" "" "沒有 start_ms 不送"
print $(( $(nowms) + 5000 )) > $rd4/start_ms; glow_tick; sleep 0.25; eq "$(cat $S/gate)" "" "start_ms 在未來不送"
print $(( $(nowms) - 500 )) > $rd4/start_ms; glow_tick; sleep 0.25; eq "$(cat $S/gate)" "" "start_ms 後不到 1 秒不送"
print $(( $(nowms) - 1100 )) > $rd4/start_ms; glow_tick; sleep 0.25; eq "$(cat $S/gate)" "$MUSIC"$'\n'$META "start_ms 後 1 秒才送 MEDIATYPE、SENDMETA"
# 牆上時鐘和 session 時鐘分開比：session 時鐘落後牆鐘 10 秒時，就算牆鐘已過起播 2 秒也還不能送
rd5=$STATE/run5; mkdir -p $rd5; touch $rd5/ready; mkfifo $rd5/cmd-$A; rd=$rd5; : > $S/gate5
print $(( $($TOOL offset) - 10000000000 )) > $rd5/clock_offset; print $(( $(nowms) - 2000 )) > $rd5/start_ms
cat <> $rd5/cmd-$A >> $S/gate5 & pids+=($!); sleep 0.3
glow_tick; sleep 0.25; eq "$(cat $S/gate5)" "" "用 session 時鐘判斷起播，不用牆鐘"
# 起播時的內容類型：serve 用 GLOW_DIR 傳設定目錄給 on／reroute；沒傳（手動跑 on）就是音樂
( unset GLOW_DIR; eq "$(start_mt)" music "沒有 GLOW_DIR 用音樂" )
print off > $dir/glow; eq "$(GLOW_DIR=$dir dir=/nonexistent start_mt)" video "GLOW_DIR 指向關的設定"
print "preset:cool" > $dir/glow; eq "$(GLOW_DIR=$dir dir=/nonexistent start_mt)" music "GLOW_DIR 指向開的設定"
# 產圖失敗：照樣標回音樂，不送封面；工具好了下一輪補送
rd6=$STATE/run6; mkrun $rd6; rd=$rd6; print "$A Mac" > $DEVFILE; : > $S/got6; GLOW_DELAY=0
reader $rd6/cmd-$A $S/got6; sleep 0.3
print off > $dir/glow; glow_tick; sleep 0.25; eq "$(cat $S/got6)" $VIDEO "新 session 關：標影片"
: > $S/got6; print "custom:#0000ff" > $dir/glow; realtool=$TOOL; TOOL=false; glow_tick; TOOL=$realtool; sleep 0.25
eq "$(cat $S/got6)" $MUSIC "產圖失敗仍標回音樂、不送封面"
: > $S/got6; glow_tick; glow_tick; sleep 0.25; eq "$(cat $S/got6)" "$META"$'\n'"ARTWORK=$STATE/glow.jpg" "工具好了補送封面"
# 舊版每組顏色一個檔：prune_logs 清掉
touch $STATE/glow-AAAAAA.jpg; prune_logs; [[ -z "$(print -l $STATE/glow-*(N))" ]] || fail "舊的 glow-*.jpg 沒清掉"
print "glow self-test ok"
