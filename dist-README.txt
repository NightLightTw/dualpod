DualPod 安裝說明
English version below (後半是英文版)

DualPod 把 Mac 的聲音送到兩台 HomePod mini，一台當左聲道、一台當右聲道。一代配二代這種不能配成立體聲的組合也可以。Mac 本機喇叭也可以一起播。

需要
- Apple 晶片的 Mac（M1 以後），macOS 14.4 以上
- 一到兩台 HomePod，和 Mac 在同一個網路。測過 HomePod mini 第一代與第二代。大尺寸 HomePod 會出現在喇叭清單，但沒測過。其他 AirPlay 裝置不會出現。
- Mac 的管理員密碼（安裝、更新、移除背景服務時要輸入，平常切換喇叭不用）。背景服務是 DualPod 負責串流的部分。

安裝
1. 解壓縮，把資料夾裡的「DualPod.app」拖到「應用程式」資料夾。
2. 打開它。DualPod 是免費軟體，沒有經過 Apple 付費的公證，第一次會跳出「Apple 無法驗證」的訊息。這代表沒有公證，不是偵測到惡意程式。
   - macOS 15 以上：按「完成」，到「系統設定 → 隱私權與安全性」往下捲，在 DualPod 旁按「強制打開」，輸入密碼。
   - macOS 14：在 Finder 按住 Control 點 App，選「打開」，再按「打開」。
3. App 會問「要安裝背景服務嗎？」，按「安裝」並輸入密碼。
4. 勾選喇叭前，先照下面「『家庭』App 設定」那一節，讓喇叭不用密碼就能存取，否則 HomePod 會沒有聲音。
5. 點選單列的 DualPod 圖示（兩個交疊的圓環）。大約一分鐘內會列出同一個網路上的 HomePod，勾選要出聲的喇叭。
6. 第一次播放時，macOS 會詢問錄製系統聲音的權限，請允許，否則喇叭會沒有聲音。

權限
- 管理員密碼：安裝負責串流的背景服務。裝好之後切換喇叭不用密碼。
- 錄製系統聲音：錄下 Mac 正在播的聲音送到喇叭。不錄麥克風，只送到你勾選的喇叭。
  不小心拒絕了：到「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」打開 DualPod 或 audiotee（DualPod 內附的錄音元件）。
  再到選單列取消、重新勾選一次喇叭。
- 麥克風（可不給）：只有「自動對齊」會用。它讓 Mac 喇叭和 HomePod 同步，會聽喇叭最多約一分鐘。
  之後想用：到「系統設定 → 隱私權與安全性 → 麥克風」打開 DualPod。

安裝後，「系統設定 → 一般 → 登入項目與延伸功能」會多一個叫「zsh」的背景項目，那就是 DualPod 的背景服務。關掉它 DualPod 就不能播。

「家庭」App 設定
DualPod 不支援 HomeKit 配對與喇叭密碼。請在「家庭」App 的「家庭設定 → 揚聲器與電視」選「連接相同網路的人」（或「所有人」），並關閉「需要輸入密碼」。選了「只限共享此家庭的成員」或設了密碼，HomePod 會沒有聲音，DualPod 也不會提示原因。

使用
下面的「設定…」在選單列 DualPod 圖示的選單裡，不是 macOS 的「系統設定」。App 介面跟隨系統語言，也可以在「設定… → 一般 → 語言」切換。
- 勾一台 HomePod：播完整的立體聲。
- 勾兩台 HomePod：一台左聲道、一台右聲道。到「設定… → 音訊 → 左右聲道」點喇叭，它會從那一邊響一聲。左右相反就按「交換左右」。
- 同時勾「這台 Mac」：Mac 喇叭一起播完整的聲音。有回音時，到「設定… → 音訊 → 這台 Mac 的喇叭」按「自動對齊…」，請在安靜的地方用。
- 選單裡每台喇叭都有自己的音量。
- 「設定… → 光暈」會在串流時讓 HomePod 頂端亮出顏色（聲波光暈）。需要 HomePod 軟體 27.2，並在「家庭」App 開啟聲波光暈。
- 「結束 DualPod」：串流停止，聲音回到 Mac。

已知限制
- 聲音大約晚 0.3 秒才從 HomePod 出來。聽音樂感覺不到，看影片時聲音可能比畫面晚一點點。
- 串流一直失敗（例如 Wi-Fi 斷線）時，5 分鐘內重新連線超過 5 次，DualPod 會放棄。網路恢復後取消、重新勾選一次喇叭。
- 其他裝置（iPhone、別台 Mac）播到同一台 HomePod 時，兩邊會互相搶。請停掉其中一邊。
- 開著 VPN 或同時有多個網路時，可能用錯網路，喇叭會沒有聲音。請關掉 VPN，再取消、重新勾選一次喇叭。

疑難排解
1. 選單顯示背景服務停止，或出現「更新背景服務…」（App 內附的背景服務和已安裝的不同，通常是換了版本之後）：點那一項重新安裝或更新。
2. 顯示播放中卻沒有聲音：檢查上面的「錄製系統聲音」權限與「家庭」App 設定，有開 VPN 先關掉。
3. 找不到 HomePod：確認它開著、和 Mac 在同一個網路。清單大約每分鐘更新一次。
4. 還是不行：「設定… → 一般 → 疑難排解」可以按「打開 log 資料夾」，或按「複製診斷資訊」回報問題。

移除
「設定… → 一般 → 背景服務 → 管理 → 移除…」，再把 App 丟到垃圾桶。背景服務停止或需要更新時，那一頁沒有「管理」，改成「移除背景服務 → 移除…」。
App 已經刪掉的話，在「終端機」執行下面四行（名稱是 DualPod 的舊名 AirPlay Stereo）。終端機在「應用程式 → 工具程式」裡。一次貼一行，按 Return。第一個 sudo 會要 Mac 密碼，輸入時畫面不會顯示字元。
  sudo launchctl bootout system/local.airplay-stereo
  sudo rm -f /Library/LaunchDaemons/local.airplay-stereo.plist
  sudo rm -rf "/Library/Application Support/AirPlayStereo"
  rm -rf ~/Library/Application\ Support/AirPlayStereo

回報問題
到 https://github.com/NightLightTw/dualpod/issues 開 issue，附上：
- Mac 型號與 macOS 版本
- HomePod 型號與軟體版本
- DualPod 版本（下載檔名裡的數字）
- 出問題前做了什麼
可以的話也貼上「複製診斷資訊」的內容。它會把 IP、裝置 ID、喇叭名稱換成代號，送出前請自己再看一次。

隱私
- DualPod 不連網際網路、不收集任何資料。找喇叭用的是同一個網路上的 Bonjour，聲音只送到你勾選的喇叭。
- 記錄只存在這台 Mac 的 /Library/Application Support/AirPlayStereo/logs，每段播放的記錄 7 天後刪除。

原始碼與授權
- GNU GPL 第 3 版（GPLv3），條款見同資料夾的 LICENSE 與 THIRD_PARTY_NOTICES.md。
- 原始碼：https://github.com/NightLightTw/dualpod（GitHub Releases 上和下載檔名同版本號的那一版）
- DualPod 是獨立專案，與 Apple Inc. 無關，也未經 Apple 認可或贊助。Apple、AirPlay、HomePod、HomePod mini、Mac 是 Apple Inc. 在美國及其他國家和地區註冊的商標。


DualPod: install guide (English)

DualPod plays your Mac's sound on two HomePod minis as left and right, even when they can't be paired as a stereo pair. The Mac's own speakers can play along.

Needs
- An Apple silicon Mac on macOS 14.4 or later.
- One or two HomePods on the same network. Tested with HomePod mini, 1st and 2nd generation.
- Your admin password to install, update, or remove the background helper (the part that does the streaming).

Install
1. Unzip and drag "DualPod.app" to Applications.
2. Open it. DualPod is free and isn't notarized by Apple, so macOS says Apple could not verify it. That means it hasn't been notarized, not that malware was found.
   - macOS 15 or later: click Done, open System Settings → Privacy & Security, scroll down, click Open Anyway next to DualPod, and enter your password.
   - macOS 14: Control-click the app in Finder, choose Open, then click Open.
3. When asked "Install the background helper?", click Install and enter your password.
4. Before selecting speakers, set up the Home app as described in "Home app setting" below, or the HomePods stay silent.
5. Click the DualPod icon (two overlapping rings) in the menu bar. HomePods appear within a minute. Select the ones to play on.
6. The first time it plays, macOS asks to let it record system audio. Allow it, or the speakers stay silent.
   If you declined: System Settings → Privacy & Security → Screen & System Audio Recording, turn on DualPod or audiotee (the audio capture tool inside DualPod), then deselect and reselect a speaker.

Permissions
- Admin password: installs the background helper that does the streaming. After that, switching speakers needs no password.
- Record system audio: captures what the Mac plays and sends it only to the speakers you select. It doesn't record the microphone.
- Microphone (optional): only for Align Automatically, which lines up the Mac's speakers with the HomePods. To allow it later: System Settings → Privacy & Security → Microphone.

After installing, System Settings → General → Login Items & Extensions lists a background item named "zsh". That is DualPod's helper. Turning it off stops DualPod from playing.

Home app setting
DualPod doesn't support HomeKit pairing or speaker passwords. In the Home app, open Home Settings → Speakers & TV, choose Anyone On the Same Network (or Everyone), and turn off Require Password. Otherwise the HomePods stay silent, and DualPod doesn't say why.

Use
Settings… is in the DualPod menu in the menu bar, not in System Settings. The app follows the system language. Change it in Settings… → General → Language.
- One HomePod plays the full stereo mix.
- Two HomePods play left and right. Settings… → Audio → Stereo Pair: click a speaker to hear a chime from that side, and click Swap Left and Right if needed.
- Select This Mac too to play along on the Mac's speakers. If you hear an echo, use Settings… → Audio → This Mac's Speakers → Align Automatically… in a quiet room.
- Settings… → Glow lights up the HomePods while streaming (needs HomePod software 27.2 and Sound Glow on in the Home app).
- Quit DualPod stops streaming and returns sound to the Mac.

Known limitations
- The sound reaches the HomePods about 0.3 seconds after the Mac plays it. With music you won't notice. With video, the sound can trail the picture slightly.
- If the stream keeps failing (for example, Wi-Fi is down), DualPod gives up after more than 5 restarts in 5 minutes. Deselect and reselect a speaker when the network is back.
- If another device plays to one of the HomePods, the two take turns grabbing it. Stop one of them.
- With a VPN or several active network interfaces, DualPod may stream from the wrong one and the speakers stay silent. Turn off the VPN, then deselect and reselect a speaker.

Troubleshooting
- The menu says the background helper stopped, or offers to update it (this DualPod carries a different helper than the installed one, usually after you install another version): click that item.
- Playing but no sound: check the recording permission and the Home app setting above, and turn off any VPN.
- A HomePod doesn't appear: make sure it's on and on the same network. The list refreshes about once a minute.
- Still stuck: Settings… → General → Troubleshooting has Open Log Folder and Copy Diagnostics.

Uninstall: Settings… → General → Background helper → Manage → Remove…, then move the app to the Trash. When the helper is stopped or needs an update, that page shows Remove the helper → Remove… instead of Manage.
If the app is already gone, run these in Terminal (AirPlay Stereo is DualPod's earlier name). Terminal is in Applications → Utilities. Paste one line at a time and press Return. The first sudo asks for your Mac password, and nothing appears on screen while you type it.
  sudo launchctl bootout system/local.airplay-stereo
  sudo rm -f /Library/LaunchDaemons/local.airplay-stereo.plist
  sudo rm -rf "/Library/Application Support/AirPlayStereo"
  rm -rf ~/Library/Application\ Support/AirPlayStereo

Report a problem: https://github.com/NightLightTw/dualpod/issues, with your Mac model, macOS version, HomePod models and software version, the DualPod version (the number in the download's file name), and the Copy Diagnostics output. It replaces IP addresses, device IDs, and speaker names with placeholders, but read it before posting.

Privacy: DualPod doesn't connect to the internet and collects nothing. Logs stay on this Mac.

License: GNU GPL version 3, see LICENSE and THIRD_PARTY_NOTICES.md in this folder.
Source: https://github.com/NightLightTw/dualpod (the release with the same version number as this download).
DualPod is an independent project and is not affiliated with, endorsed by, or sponsored by Apple Inc. Apple, AirPlay, HomePod, HomePod mini, and Mac are trademarks of Apple Inc., registered in the U.S. and other countries and regions.
