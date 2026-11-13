#!/bin/zsh
# 用法：zsh tools/glow_read_test.sh <暫存資料夾>
# 同一批 glow 檔內容，App 的 readGlowFile+parseGlow 和 helper 的 glow_colors 必須判斷一致
set -u
S=${1:?暫存資料夾}; HERE=${0:A:h}
mkdir -p $S; S=$(mktemp -d $S/gr.XXXXXX)
export TEST=1 STATE=$S/state LOGDIR=$S/logs GLOW_LIB=1; mkdir -p $STATE $LOGDIR
source $HERE/../stereo.sh
dir=$S/set; mkdir -p $dir
mkdir $S/swift  # 只抽出 Settings.swift 裡讀檔與驗證的函式來編（整檔要整個 App 才編得起來）
{
  print 'import Foundation'; print 'let glowFile = URL(fileURLWithPath: "/dev/null")'
  sed -n '/^func readGlowFile/,/^}/p;/^let glowPresets/,/^]/p;/^func parseGlow/,/^}/p' $HERE/../app/Settings.swift
  print 'print(parseGlow(readGlowFile(URL(fileURLWithPath: CommandLine.arguments[1]))))'
} > $S/swift/main.swift
swiftc -O $S/swift/main.swift -o $S/swift/app || { print -u2 "編不起來"; exit 1; }
fail=0
check() {  # 名稱 內容（printf 格式）
  rm -f $dir/glow; printf -- "$2" > $dir/glow
  [[ -n ${3:-} ]] && { rm -f $dir/glow; ln -s $3 $dir/glow; }
  local app=$($S/swift/app $dir/glow) h=$(glow_colors | tr -d '\n') want
  case $app in
    off) want="" ;;
    preset:*) want=$GLOW_PRESETS[${app#preset:}] ;;
    custom:*) app=${(U)app#custom:}; want=${${(j: :)${(s:,:)app}}//\#/} ;;
  esac
  if [[ $h == $want ]]; then print "ok   $1 -> [${want:-off}]"; else print "DIFF $1：app [$want] helper [$h]"; fail=1; fi
}
check "tab + preset:warm" '\tpreset:warm\n'
check "preset:warm + 53 空白 + X" 'preset:warm%53sX' 
check "preset:warm + LF" 'preset:warm\n'
check "空白穿插" ' preset: warm \n'
check "CRLF" 'preset:warm\r\n'
check "custom 小寫" 'custom:#12ab34,#ff0000\n'
check "亂寫" 'garbage'
check "空檔" ''
check "symlink" 'preset:warm\n' /etc/hosts
printf 'preset:warm\n' > $S/real; check "symlink 指向有效檔" '' $S/real
exit $fail
