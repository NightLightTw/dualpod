AirPlay Stereo 安裝說明

這個 App 能把 Mac 的所有聲音用 AirPlay 送到一台或兩台喇叭（例如 HomePod mini），兩台時一台當左聲道、一台當右聲道，也可以同時保留 Mac 本機喇叭。

需要
- Apple 晶片的 Mac（M1 以後），macOS 14.4 以上
- Mac 和喇叭在同一個 Wi‑Fi
- Mac 的管理員密碼（安裝、更新、移除背景服務時要輸入，平常切換喇叭不用）

安裝
1. 解壓縮後會有一個資料夾，把裡面的「AirPlay Stereo.app」拖到「應用程式」資料夾。
2. 打開它。這個 App 沒有經過 Apple 公證，第一次會被擋下：
   到「系統設定 → 原始碼與授權
- GNU GPL 第 3 版（GPLv3），條款見同資料夾的 LICENSE 與 THIRD_PARTY_NOTICES.md。
- 原始碼：https://github.com/NightLightTw/airplay-stereo（下載的版本對應同名的 Release tag）

隱私權與安全性」，往下找到 AirPlay Stereo，按「強制打開」，輸入密碼後在跳出的視窗再按「打開」。
3. App 會問「要安裝背景服務嗎？」，按「安裝」並輸入密碼。
4. 第一次播放時，macOS 可能會詢問錄製系統聲音的權限，請允許，否則喇叭會沒有聲音。
   如果不小心拒絕了：到「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」（各版 macOS 名稱略有不同），
   打開 audiotee 或 AirPlay Stereo 的開關，再到選單列取消、重新勾選一次喇叭。
5. 點選單列的喇叭圖示，勾選要出聲的喇叭。大約一分鐘內會列出同一個網路上的喇叭。

使用
- 勾兩台喇叭：左右聲道。左右相反時，到「設定 → 左右聲道」按「播放測試音」確認，再按「交換左右」。
- 同時勾「這台 Mac」：Mac 喇叭一起播。有回音時，到「設定 → 這台 Mac 的喇叭」按「自動對齊」（會用麥克風約一分鐘，請保持安靜）。
- 結束 App：串流停止，聲音回到 Mac。（App 當掉時串流可能還在，重開 App 取消勾選喇叭即可。）

移除
「設定 → 一般 → 背景服務 → 移除」，再把 App 丟到垃圾桶。

隱私
- App 只會串流到你勾選的喇叭。找喇叭時會用 Bonjour 查詢同一個網路上的 AirPlay 裝置，但不會連到沒勾選的裝置。
  其他 Mac（螢幕鏡像接收）會被濾掉，不列在選單裡。
- 記錄只存在這台 Mac 上。「複製診斷資訊」會把 IP、裝置 ID、喇叭名稱換成代號，送出前請自己再看一次。


AirPlay Stereo — install guide (English)

Sends all of your Mac's sound over AirPlay to one or two speakers (two = left and right), optionally keeping the Mac's own speakers.

Needs: an Apple silicon Mac on macOS 14.4 or later, speakers on the same Wi‑Fi, and your admin password to install, update, or remove the background helper (not to switch speakers).

1. Unzip, open the folder, and drag "AirPlay Stereo.app" to Applications.
2. Open it. The app isn't notarized by Apple, so macOS blocks it the first time: go to System Settings → Privacy & Security, find AirPlay Stereo, click "Open Anyway", enter your password, then click "Open".
3. When asked "Install the background helper?", click Install and enter your password.
4. On first playback macOS may ask for permission to record system audio. Allow it, or the speakers stay silent.
   If you declined: System Settings → Privacy & Security → Screen & System Audio Recording (the name varies by macOS version),
   turn on audiotee or AirPlay Stereo, then deselect and reselect the speakers in the menu bar.
5. Click the speaker icon in the menu bar and select your speakers (they appear within about a minute).

To remove: Settings → General → Background helper → Remove, then move the app to the Trash.
