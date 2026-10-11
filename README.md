# FPS Boost

Windows tweaks for Fortnite that **actually do something**, in a clean app where every tweak is one switch. Flip it on to apply it, flip it off to undo it.

## Download

Grab **FPSBoost.exe** from the [Releases](../../releases) page and run it. It asks for admin because most of these are system settings.

> Windows SmartScreen or your antivirus may warn about it because the exe isn't code-signed. The full source is `FPSBoost.ps1` in this repo, so you can read exactly what it does, or run `Run_FPS_Boost.bat` instead of the exe.

## What's in it

**FPS + smoothness**
- Max performance power plan: fewer random FPS dips
- Kill Xbox background recording (Game DVR)
- Make sure Game Mode is on
- Hardware GPU scheduling (needs a restart)
- Optimizations for windowed games (Windows 11)
- Turn off mouse acceleration
- High CPU priority for Fortnite
- Force Fortnite onto your dedicated GPU (big on gaming laptops)

**Network + input delay**
- Stop network adapter power saving (random lag spikes)
- Stop Windows uploading updates to other PCs (ping spikes)
- Remove network throttling
- Kill the Sticky Keys popup

**Server Ping**
- Live ping to **every Fortnite datacenter**, not just the region: NA East (Virginia, Ohio), NA Central (Dallas), NA West (Oregon, San Jose), Europe (Frankfurt, London, Paris), Brazil (Sao Paulo), Oceania (Sydney), Asia (Tokyo), Middle East (Bahrain)
- Uses Epic's own matchmaking ping servers, then maps every server IP to its real city using Amazon's published IP ranges. New datacenters show up automatically
- Shows ping, jitter, packet loss and a live graph for each datacenter, plus the best server and which Matchmaking Region to pick

**Tools**
- **Make restore point** before changing anything
- **Clean temp files** (leaves your shader cache alone so you don't get stutters)

## Honest notes
- No app can lower your *base* ping. That comes down to how far you are from the server. These tweaks fix lag spikes and jitter. An Ethernet cable is the biggest fix there is.
- The biggest FPS gains are in Fortnite's own settings: **Performance** rendering mode, **NVIDIA Reflex On + Boost**, Fullscreen, and V-Sync off.

## Building the exe yourself
GitHub Actions builds `FPSBoost.exe` with [ps2exe](https://github.com/MScholtes/PS2EXE) and publishes a new release every time something is pushed to `main`.
