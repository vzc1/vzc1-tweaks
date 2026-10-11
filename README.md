# vzc1's optimizations

A Windows app for getting more FPS and less lag in Fortnite. Every change can be switched back off from inside the app.

## Download

Get **vzc1-optimizations.exe** from the [latest release](../../releases/latest) and run it. It asks for admin because most of these are system settings.

If Windows shows "Windows protected your PC", click **More info**, then **Run anyway**. That screen appears for any new app that isn't code-signed. You can also download `vzc1-optimizations-script.zip` instead and double-click `Run-vzc1-optimizations.bat`. It's the same app as a script you can read.

## What it does

**Home** checks your PC before you play:
- Monitor stuck at 60 Hz when it supports more. Switches it with one click.
- Laptop running on battery
- Power plan not on max performance
- Fortnite settings that cost you FPS or add delay
- Wi-Fi instead of a cable
- Background apps using a lot of memory

**Tweaks**
- Max performance power plan, Game DVR off, Game Mode, hardware GPU scheduling, windowed game optimizations
- High CPU priority for Fortnite, run Fortnite on the dedicated GPU
- Network card power saving off, update sharing off, network throttling off
- Mouse acceleration off, Sticky Keys shortcut off

**Fortnite settings** edits Fortnite's own settings file: Performance mode, DirectX 11 or 12, frame rate limit, window mode, NVIDIA Reflex, V-Sync, motion blur, shadows, grass, Nanite, ray tracing and the FPS counter. Your original file is backed up the first time, with a one-click restore.

**Server ping** shows live ping, jitter and packet loss to every Fortnite datacenter: Virginia, Ohio, Dallas, Oregon, San Jose, Frankfurt, London, Paris, Sao Paulo, Sydney, Tokyo and Bahrain. It uses Epic's own matchmaking ping servers and tells you which Matchmaking Region to pick.

**Startup apps** turns off apps that open with Windows, the same way Task Manager does.

**Background apps** lists what's using your memory right now and closes it with one click.

**Tools**: restore point, undo all tweaks, temp file cleanup, bufferbloat test.

## Honest notes
- No app can lower your base ping. That depends on how far you are from the server. What you can fix is lag spikes, and an Ethernet cable fixes most of them.
- The biggest FPS gain on low and mid-range PCs is Fortnite's Performance rendering mode. The Fortnite settings page sets it for you.

## How the exe is built
GitHub Actions compiles a small C# launcher (`build/Launcher.cs`) that runs `vzc1-optimizations.ps1` inside the exe. Nothing is dropped to disk or downloaded. A new release is published on every push to `main`.
