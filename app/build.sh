#!/bin/zsh
# 編出選單列 app：zsh app/build.sh → app/DualPod.app（自己用）
# 給別人：zsh app/build.sh dist → dist/DualPod.zip（在 iCloud 外建置、整包簽名、附安裝說明）
set -eu
cd ${0:A:h}
TARGET=arm64-apple-macos14.4  # 系統錄音（process tap）從 14.4 才有；不指定會變成只能在編譯這台的版本上跑
if [[ ${1:-} == dist ]]; then
  # iCloud 同步的資料夾會一直加回 FinderInfo，整包簽不了，所以到快取資料夾建置
  OUT="$HOME/Library/Caches/airplay-stereo-dist"
  rm -rf "$OUT"; mkdir -p "$OUT"
  APP="$OUT/DualPod.app"
else
  APP="DualPod.app"
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target $TARGET StereoMenu.swift Settings.swift Align.swift -o "$APP/Contents/MacOS/StereoMenu"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>StereoMenu</string>
  <key>CFBundleIdentifier</key><string>local.airplay-stereo.menu</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>DualPod</string>
  <key>CFBundleDisplayName</key><string>DualPod</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSUIElement</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>DualPod records the Mac's sound to send it to your speakers. DualPod 會錄下 Mac 的聲音，送到喇叭。</string>
  <key>NSMicrophoneUsageDescription</key><string>Auto-align listens to the speakers to line the Mac up with the HomePods. 自動對齊會用麥克風聽喇叭，把 Mac 和 HomePod 對齊。</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
</dict></plist>
EOF
mkdir -p "$APP/Contents/Resources"; cp AppIcon.icns "$APP/Contents/Resources/"  # 由 ../tools/make-icon.swift 從 icon.svg 產生
swiftc -O -target $TARGET ../tools/localplay.swift -o ../tools/localplay  # 本機喇叭同步播放器
swiftc -O -target $TARGET ../tools/stereotool.swift -o ../tools/stereotool  # 時鐘與拆聲道（取代 Python）
# 背景服務要裝的檔案打包進 App，App 用管理員密碼視窗安裝或更新；VERSION 是這些檔案的雜湊
RT="$APP/Contents/Resources/runtime"
mkdir -p "$RT/airplay-cli/bin" "$RT/audiotee/.build/release" "$RT/tools"
cp ../run_pair.sh ../stereo.sh install-daemon.sh "$RT/"
cp ../airplay-cli/bin/cliairplay-macos-arm64 "$RT/airplay-cli/bin/"
cp ../audiotee/.build/release/audiotee "$RT/audiotee/.build/release/"
cp ../tools/stereotool ../tools/localplay "$RT/tools/"
(cd "$RT" && find . -type f ! -name VERSION | sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16) > "$RT/VERSION"
HELPERS=("$RT/airplay-cli/bin/cliairplay-macos-arm64" "$RT/audiotee/.build/release/audiotee" "$RT/tools/localplay" "$RT/tools/stereotool")
for f in $HELPERS; do
  lipo -archs "$f" | grep -q arm64 || { echo "$f 不是 arm64"; exit 1; }
done
xattr -cr "$APP"  # 帶著延伸屬性 codesign 會失敗
if [[ ${1:-} == dist ]]; then
  # 臨時簽名（ad-hoc）：沒有 Developer ID 憑證就無法公證，對方第一次開要在「隱私權與安全性」按「強制打開」。
  # 用 ad-hoc 不用 Apple Development 憑證：那張憑證會把你的 email 簽進 App，而且別台 Mac 一樣不認
  for f in $HELPERS; do codesign -s - --force "$f"; done
  codesign -s - --force "$APP"
  codesign --verify --strict --deep --verbose=1 "$APP"
  for f in $HELPERS; do codesign --verify --strict "$f"; done  # 放在 Resources 裡的不算 App 的巢狀程式碼，要各自驗
  # 一個資料夾裝 App 和說明，用 ditto 壓（中文檔名用 UTF-8，zip 指令會變亂碼）
  PKG="$OUT/DualPod"
  mkdir -p "$PKG"; mv "$APP" "$PKG/"; cp ../dist-README.txt "$PKG/安裝說明.txt"
  # GPLv3 與上游授權條款要跟著執行檔一起給；原始碼在 GitHub repo
  cp ../LICENSE ../THIRD_PARTY_NOTICES.md "$PKG/"; cp ../third_party/cliairplay-THIRD_PARTY_NOTICES.md "$PKG/"
  mkdir -p ../dist; rm -f ../dist/DualPod.zip
  ditto -c -k --norsrc --keepParent "$PKG" ../dist/DualPod.zip
  echo "dist: $(cd ..; pwd)/dist/DualPod.zip"
else
  # shortcut: 專案在 iCloud 同步的 Documents，FinderInfo 會被加回、整包簽不了；執行檔已由 linker 簽好，本機可用
  codesign -s - --force "$APP" 2>/dev/null || echo "(bundle signing skipped: iCloud-synced folder; executable is linker-signed)"
  echo "built: $PWD/$APP"
fi
