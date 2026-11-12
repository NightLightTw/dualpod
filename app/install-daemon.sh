#!/bin/zsh
# 安裝或更新背景服務（之後 App 切換不用密碼）。App 用 macOS 的管理員密碼視窗執行它（INSTALL_USER＝登入的帳號）；
# 開發時也可以直接：sudo zsh app/install-daemon.sh。移除：加參數 remove
# 要裝的檔案：從 App 執行時在 App 裡的 Contents/Resources/runtime，開發時在專案資料夾。
# 執行檔裝到 root 擁有、一般使用者改不了的資料夾；App 只寫 want 等設定檔，服務照著做。
# 更新是「先備好新版、再換上、起不來就換回舊版」：中途失敗不會留下半新半舊。
set -eu
setopt extended_glob
umask 022  # 安裝資料夾要讓一般使用者讀得到（App 查狀態、降權後的 audiotee 要執行）
[[ $(id -u) == 0 ]] || { echo "請用 sudo 執行：sudo zsh $0"; exit 1; }
# 出錯時告訴 App 是哪一行（App 只看得到 stderr）；還沒換上新版前出錯，就把準備到一半的東西清掉
trap 'echo "install-daemon.sh 第 $LINENO 行失敗" >&2' ZERR
STAGED=""
trap '[[ -n $STAGED ]] && rm -rf "$DEST.new" ${TMPPLIST:-}' EXIT
LABEL=local.airplay-stereo
PLIST=/Library/LaunchDaemons/$LABEL.plist
DEST="/Library/Application Support/AirPlayStereo"

stop_service() {  # 卸載並確認真的停了；停不了就失敗，不往下刪檔或換檔
  launchctl bootout system/$LABEL 2>/dev/null || true
  # bootout 不等服務收尾（它收到 TERM 會先關掉串流），還沒退完就 bootstrap 會報 5: Input/output error
  for i in {1..40}; do launchctl print system/$LABEL >/dev/null 2>&1 || break; sleep 0.5; done
  launchctl print system/$LABEL >/dev/null 2>&1 && { echo "背景服務停不下來"; exit 1; }
  # 舊版（管理員對話框啟動、狀態在 /tmp）的 supervisor 收到 TERM 會自己清掉串流
  pkill -TERM -f '^zsh .*/stereo\.sh supervise' 2>/dev/null && sleep 3 || true
  for p in cliairplay-macos-arm64 audiotee localplay; do pkill -9 -x $p 2>/dev/null || true; done
}

if [[ ${1:-} == remove ]]; then  # 全機的服務不靠帳號查詢也能移除；帳號的設定檔有查到才順便清
  stop_service
  rm -f $PLIST; rm -rf "$DEST"
  u=${SUDO_USER:-${INSTALL_USER:-}}
  if [[ $u == [A-Za-z0-9._-]## ]] && id -u $u >/dev/null 2>&1; then
    h=$(dscl . -read /Users/$u NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory: //')
    [[ -n $h ]] && rm -f "$h/Library/Application Support/AirPlayStereo/want"
  fi
  echo "removed"; exit 0
fi

USER_NAME=${SUDO_USER:-${INSTALL_USER:-}}
[[ $USER_NAME == [A-Za-z0-9._-]## && $USER_NAME != root ]] && id -u $USER_NAME >/dev/null 2>&1 ||
  { echo "需要一般使用者帳號：sudo zsh $0，或由 App 安裝"; exit 1; }
USER_HOME=$(dscl . -read /Users/$USER_NAME NFSHomeDirectory | sed 's/^NFSHomeDirectory: //')
[[ -d $USER_HOME ]] || { echo "找不到 $USER_NAME 的家目錄"; exit 1; }
WANT_DIR="$USER_HOME/Library/Application Support/AirPlayStereo"
SRC=${0:A:h}
[[ -f $SRC/stereo.sh ]] || SRC=${SRC:h}

# 1. 先把新版完整備好（還沒動到正在跑的服務）
NEW="$DEST.new" OLD="$DEST.old"
STAGED=1
rm -rf "$NEW" "$OLD"
mkdir -p "$NEW/airplay-cli/bin" "$NEW/audiotee/.build/release" "$NEW/tools"
install -m 755 "$SRC/run_pair.sh" "$SRC/stereo.sh" "$NEW/"
install -m 755 "$SRC/airplay-cli/bin/cliairplay-macos-arm64" "$NEW/airplay-cli/bin/"
install -m 755 "$SRC/audiotee/.build/release/audiotee" "$NEW/audiotee/.build/release/"
install -m 755 "$SRC/tools/stereotool" "$NEW/tools/"
install -m 755 "$SRC/tools/localplay" "$NEW/tools/"
# App 比對這個，知道背景服務和自己帶的是不是同一版（開發時沒有就記 dev）
if [[ -f $SRC/VERSION ]]; then install -m 644 "$SRC/VERSION" "$NEW/"; else print dev > "$NEW/VERSION"; fi
chown -R root:wheel "$NEW"; chmod -R go-w,a+rX "$NEW"
# 從網路下載的 App，裡面的檔案帶著「隔離」標記；背景服務由 launchd 執行時不會跳出詢問，只會被擋。
# 使用者已在密碼視窗同意安裝，所以只清掉我們自己這份安裝目錄的標記
xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true

# plist 用 plutil 產生：家目錄有 & < 這類字元也不會壞
TMPPLIST=$(mktemp /tmp/airplay-stereo-plist.XXXXXX)
plutil -create xml1 $TMPPLIST
plutil -insert Label -string $LABEL $TMPPLIST
plutil -insert ProgramArguments -array $TMPPLIST
i=0; for a in /bin/zsh "$DEST/stereo.sh" serve "$WANT_DIR/want"; do plutil -insert ProgramArguments.$i -string "$a" $TMPPLIST; i=$(( i + 1 )); done  # 不用 (( i++ ))：i 是 0 時它回傳失敗，set -e 會中止
plutil -insert EnvironmentVariables -dictionary $TMPPLIST
plutil -insert EnvironmentVariables.AS_USER -string $USER_NAME $TMPPLIST
# 只放 root 擁有的路徑：/opt/homebrew 屬於一般使用者，放進來等於讓它替換 root 執行的程式
plutil -insert EnvironmentVariables.PATH -string /usr/bin:/bin:/usr/sbin:/sbin $TMPPLIST
plutil -insert ProcessType -string Interactive $TMPPLIST  # 即時音訊：不讓 launchd 把背景服務節流
plutil -insert RunAtLoad -bool true $TMPPLIST
plutil -insert KeepAlive -bool true $TMPPLIST
plutil -insert StandardErrorPath -string "$DEST/logs/serve.err" $TMPPLIST
plutil -lint -s $TMPPLIST
chown root:wheel $TMPPLIST; chmod 644 $TMPPLIST
sudo -u $USER_NAME mkdir -p "$WANT_DIR"

# 2. 停舊的、換上新的（找到的喇叭、log 搬過去），起不來就整個換回舊版
STAGED=""
stop_service
if [[ -d $DEST ]]; then
  for keep in state logs; do [[ -d $DEST/$keep ]] && mv "$DEST/$keep" "$NEW/"; done
  mv "$DEST" "$OLD"
fi
mkdir -p "$NEW/logs"
mv "$NEW" "$DEST"
[[ -f $PLIST ]] && cp -p $PLIST $TMPPLIST.old
mv -f $TMPPLIST $PLIST
if ! launchctl bootstrap system $PLIST; then
  echo "新版起不來，換回舊版"
  rm -f $PLIST
  if [[ -d $OLD ]]; then
    for keep in state logs; do [[ -d $DEST/$keep ]] && mv "$DEST/$keep" "$OLD/"; done
    rm -rf "$DEST"; mv "$OLD" "$DEST"
    [[ -f $TMPPLIST.old ]] && mv -f $TMPPLIST.old $PLIST && launchctl bootstrap system $PLIST || true
  fi
  exit 1
fi
rm -rf "$OLD" $TMPPLIST.old
echo "installed: $DEST"
