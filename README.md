# vzc1's optimizations

A Windows app for getting more FPS and less lag in Fortnite. Every change can be switched back off from inside the app.

## Download

Get **vzc1-optimizations.exe** from the [latest release](../../releases/latest) and run it. It asks for admin because most of these are system settings.

If Windows shows "Windows protected your PC", click **More info**, then **Run anyway**. That screen appears for any new app that isn't code-signed. You can also download `vzc1-optimizations-script.zip` instead and double-click `Run-vzc1-optimizations.bat`. It's the same app as a script you can read.

## What it does

**Dashboard** shows live CPU and memory use and checks your PC before you play:
- Monitor stuck at 60 Hz when it supports more. Switches it with one click.
- Laptop running on battery
- Power plan not on max performance
- Fortnite settings that cost you FPS or add delay
- Wi-Fi instead of a cable
- Background apps using a lot of memory

**Tweaks** (Performance, Network, Mouse and keyboard, Low-end PC)
- Max performance power plan, Game DVR off, Game Mode, hardware GPU scheduling, windowed game optimizations
- High CPU priority for Fortnite, run Fortnite on the dedicated GPU
- Network card power saving off, update sharing off, network throttling off
- Mouse acceleration off, Sticky Keys shortcut off
- Low-end PC: Windows visual effects set to best performance, transparency off, background Store apps off

**Fortnite settings** edits Fortnite's own settings file: Performance mode, DirectX 11 or 12, frame rate limit, window mode, NVIDIA Reflex, V-Sync, motion blur, shadows, grass, Nanite, ray tracing and the FPS counter. It has a **Pro preset**, three **potato graphics** levels (Potato Lite 75%, Potato 50%, Ultra Potato 35% at 1280 x 720) with an option to lock the settings file, **your own saved presets**, 3D resolution and game resolution controls, and for NVIDIA cards one-click **potato textures** in the NVIDIA driver (texture LOD bias +3, the NVIDIA Profile Inspector trick) with an Undo button. The Pro preset is with what most top-earning pros run (Performance mode, low settings, Reflex On + Boost, FPS capped at your monitor). Your original file is backed up the first time, with a one-click restore.

**Pro player presets**: Martoz, Clix, Peterbot, Mongraal and Bugha's video settings from prosettings.net, one click each.

**Server ping** shows live ping, jitter and packet loss to every Fortnite datacenter: Virginia, Ohio, Dallas, Oregon, San Jose, Frankfurt, London, Paris, Sao Paulo, Sydney, Tokyo and Bahrain. It uses Epic's own matchmaking ping servers and tells you which Matchmaking Region to pick.

**Startup apps** turns off apps that open with Windows, the same way Task Manager does.

**Background apps** lists what's using your memory right now and closes it with one click.

**Tools**: free up memory (trims RAM background apps aren't using and clears the standby cache), developer mode with a live activity log (locked behind a code), restore point, undo all tweaks, temp file cleanup, bufferbloat test.

## Honest notes
- No app can lower your base ping. That depends on how far you are from the server. What you can fix is lag spikes, and an Ethernet cable fixes most of them.
- The biggest FPS gain on low and mid-range PCs is Fortnite's Performance rendering mode. The Fortnite settings page sets it for you.

## Credits
NVIDIA driver function and setting IDs come from [NVIDIA Profile Inspector](https://github.com/Orbmu2k/nvidiaProfileInspector) by Orbmu2k (MIT license).

## How the exe is built
GitHub Actions compiles a small C# launcher (`build/Launcher.cs`) that runs `vzc1-optimizations.ps1` inside the exe. Nothing is dropped to disk or downloaded. A new release is published on every push to `main`.

## Terms of use

You have to accept these the first time you open the app. You can read them again from the Tools page.

- This app changes Windows settings, Fortnite's settings file, which apps start with Windows, and can close running programs. You choose every change.
- It is provided "as is", without any warranty. **You use it at your own risk.**
- vzc1 and anyone who works on this app are **not responsible** for any damage to your PC, lost data, crashes, lost settings, account problems or bans, or any other problem that comes from using it.
- Make a restore point before you change anything. The app can do it for you.
- Not made by, affiliated with or endorsed by Epic Games. It does not change Fortnite's game files.

See [LICENSE](LICENSE) for the full license.
