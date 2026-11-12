# AirPlay Stereo

A macOS menu bar app that sends all of your Mac's sound over AirPlay 2 to one or two speakers. With two speakers,
one plays the left channel and the other the right, so two HomePod minis that can't be paired as a stereo pair
(for example, different generations) still work as left and right. The Mac's own speakers can play along, aligned in time.

中文安裝說明：[dist-README.txt](dist-README.txt)

## Why this exists

I happily bought a HomePod mini (2nd generation) to go with the first-generation one I already had, got it home,
and found out the two can't be set up as a stereo pair. That was annoying enough to start this project.

起因：開開心心買了一台 HomePod mini 第二代回家，才發現它沒辦法跟之前那台第一代配成立體聲，很生氣，所以有了這個專案。

## Requirements

- Apple silicon Mac, macOS 14.4 or later (system audio capture needs 14.4)
- Speakers on the same network. Tested with HomePod mini (1st and 2nd generation). It streams native AirPlay 2
  with PTP timing, so other AirPlay 2 receivers may or may not work
- An administrator password to install, update, or remove the background helper

## Install

Download `AirPlay-Stereo.zip` from Releases and follow `安裝說明.txt` inside (Chinese and English).
The app is ad-hoc signed and not notarized, so macOS blocks it the first time: open it from
System Settings → Privacy & Security → Open Anyway.

## What it does

- Lists AirPlay receivers found on the network. Other Macs are left out.
- Plays to any mix of up to two speakers and This Mac. Two speakers play left and right.
- Volume for each speaker, a test chime to tell left from right, and a swap button.
- Auto-align: shifts the Mac's speakers until they line up with the HomePods, using the microphone.
- A watchdog restarts both speakers together when one of them falls out of step.
- Quitting the app stops streaming and returns sound to the Mac.

Measured on one setup (two HomePod minis, three runs each against Apple Music, same microphone position):
end-to-end latency about 0.27 to 0.30 s (Apple Music to the same speakers: 0.63 to 0.73 s),
left/right offset 0.7 to 3.3 ms (Apple Music: 0.5 to 2.2 ms). Your numbers will differ with the room and the network.

## How it works

```
system audio ──audiotee (Core Audio process tap)──▶ stereotool split ──L──▶ cliairplay ──AirPlay 2──▶ speaker 1
                                                                     ├─R──▶ cliairplay ──AirPlay 2──▶ speaker 2
                                                                     └─LR─▶ localplay (This Mac)
                        one PTP clock (cliairplay --ptp-daemon), one shared start time
```

- `stereo.sh` is the root background helper (a LaunchDaemon). It finds speakers, starts and watches the stream,
  and reads the app's choices from files in `~/Library/Application Support/AirPlayStereo/`.
- `run_pair.sh` starts one streaming session.
- `app/` is the menu bar app (Swift, AppKit and SwiftUI). It installs the helper through macOS's own password dialog.
- `tools/stereotool` keeps the clock and splits the channels; `tools/localplay` plays the Mac's share in time.

## Build from source

```bash
zsh scripts/fetch-deps.sh      # clone airplay-cli and audiotee, apply patches/, build them
zsh app/build.sh               # app/AirPlay Stereo.app for yourself
zsh app/build.sh dist          # dist/AirPlay-Stereo.zip for others (signed, with install notes)
```

Requires Xcode or the Command Line Tools. The measurement tools are for development only: they need Python with
numpy and scipy, `swiftc tools/rec.swift -o tools/rec`, `mkdir signals checks && python measure.py gen signals`,
and Homebrew ffmpeg for the test and measure modes of `run_pair.sh`.

## Privacy

- Streams only to the speakers you select. Finding speakers uses Bonjour queries on the local network.
- Logs stay on the Mac, under `/Library/Application Support/AirPlayStereo/logs`. Per-session logs are deleted after
  7 days, the event log rolls over at 1 MB, and the session summary keeps the last 2000 rows.
- "Copy Diagnostics" in Settings replaces IP addresses, device IDs, host names, and the names of speakers it found
  with placeholders. Read it before you send it: it can't catch everything.

## License

GNU General Public License, version 3. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
