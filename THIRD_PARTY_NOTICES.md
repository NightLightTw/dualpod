# Third-party notices

DualPod is licensed under the GNU General Public License, version 3 (see [LICENSE](LICENSE)).
Its release bundles two programs built from other projects. Both are fetched from upstream and patched by
[scripts/fetch-deps.sh](scripts/fetch-deps.sh); the patches are in [patches/](patches).

## cliairplay (airplay-cli)

- Source: https://github.com/music-assistant/airplay-cli, commit `0a58c239d5fb3cf8927b9707a71c6fe897266b6a`
- License: GNU General Public License, version 3. Its own third-party components (libraop, mdnssd,
  OpenSSL, ALAC, and others) are listed in [third_party/cliairplay-THIRD_PARTY_NOTICES.md](third_party/cliairplay-THIRD_PARTY_NOTICES.md),
  copied from upstream unchanged. Where that file says to `git clone --recursive` its repository, the equivalent here
  is to clone this repository at the release tag and run `scripts/fetch-deps.sh`.
- OpenSSL: the build uses `STATIC=1`, which links the prebuilt static library that libraop ships for macOS arm64.
  That library is **OpenSSL 3.5.4** (Apache License 2.0, compatible with GPLv3), not the 1.1.1u listed in the upstream
  notices. Its source: https://github.com/openssl/openssl/releases/tag/openssl-3.5.4
- Known upstream ambiguity: libraop's `pairing.cpp` and `bplist.cpp` carry no explicit license grant (see "Note on
  libraop's license" in the upstream notices). The upstream project distributes binaries containing them under GPLv3,
  and this project follows it.
- Patches:
  - `patches/airplay-cli/0001-upstream-pr100-homepod-mini-2-ptp.diff` is the change proposed upstream in
    music-assistant/airplay-cli pull request #100 by Jonathan Delgado (HomePod mini 2 silent over PTP; SETPEERSX to every Apple receiver).
  - `patches/airplay-cli/0002-bind-ptp-to-interface-on-macos.diff` binds PTP ports 319/320 to the chosen interface address,
    because macOS's own gPTP holds the wildcard sockets.

## audiotee

- Source: https://github.com/makeusabrew/audiotee, commit `56ac954369a09318e46b88a6eec33c2d2b0d32a3`
- Patch: `patches/audiotee/0001-converter-supply-input-once.diff` hands each input chunk to the sample-rate converter once.
  The unpatched converter replayed the chunk when asked for more input, which added an audible hiss to music.
- License: MIT

```
The MIT License

Copyright (C) 2025 Nick Payne.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
