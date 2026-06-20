This Macro is capable of auto fishing on the ROBLOX game "Fisch". You can leave the macro running whilst AFK and it will continue to shake and catch for you.
This Macro has a 98% catch rate. That is 2 fish lost per 100 fish caught.

Discord For Support: https://discord.gg/bpEGPyH55Q

====================================================

DOWNLOADS:

You can download either the stable or experimental releases. Click into the folders.
Stable releases are confirmed to work properly.
Experimental releases can be either better or worse than the stable versions, adding new features.



To download the file, click the .ahk file you want to download and press ctrl + shift + S.

Alternatively, you can copy the entire content of the file and create your own .ahk file and paste it there.

====================================================

How to use: (.ahk file)

Ensure that you have AutoHotKey v1.1 installed.

1. Download the most recent version ahk file.
2. Put the ahk file into its own folder.
3. Double click and run the ahk file.
4. It will create a Settings.ini file for you.
5. Change the "control" setting to your rod's control number. (ex. 0.15)
7. Press O to reload program to update the settings
8. Press P to run
9. You may need to press O to reload if the tooltips arent correctly positioned to the right of the roblox screen.

====================================================

Screen resolution:

The macro works at any 16:9 resolution (e.g. 1280x720, 1920x1080, 2560x1440, 3840x2160) in fullscreen.
You no longer have to switch your display down to 1920x1080. Non-16:9 ratios still work but may need
the bars re-checked, so you will get a one-time warning. Keep your Windows Display Scale at 100%.

====================================================

Custom rod / fish colors (Settings.ini, [Common] section):

Most rods use the default colors and need no changes. Some rods (e.g. event/sword rods) draw the fish
marker in a non-standard color, so the macro can't "see" it. To fix those:

- CatchBarColor   - color of the white control bar. Leave as "Auto" for the default.
- FishBarColor    - color of the fish marker. Leave as "Auto" for the default, or set a hex value
                    like 0x7d8aa6 to match an unusual rod.
- FishBarTolerance- how loosely to match FishBarColor (default 5). Multi-colored markers may need a
                    higher value (e.g. 25-40).

How to find a rod's color: install AutoHotkey v1.1, right-click its tray icon -> "Window Spy", then
hover the fish marker on the reel bar and read the hex color shown. Put that value in FishBarColor,
press O to reload, then P to run.

[Virustotal scan of the .ahk program](https://www.virustotal.com/gui/file/c041cb7ad42291cd0d8082690c206fe3486f5b7854edecfd8ac8f39016d17fde?nocache=1)

====================================================

MUSICAL ROD MACRO (rhythm minigame):

For rods whose catch minigame is the 4-lane D/F/J/K rhythm game, use
"Musical Rod/Fisch Musical Macro v1.0.ahk". It runs a full AFK loop:
cast -> wait for the bite -> hit the notes -> re-cast.

It only presses keys while Roblox is the focused window, so it will not type
into other apps if you alt-tab away (it pauses and resumes on refocus).

Setup:
1. Install AutoHotkey v1.1. Put the .ahk in its own folder and run it
   (creates Settings.ini). Run Roblox in BORDERLESS fullscreen at a 16:9
   resolution, Windows Display Scale 100%. (Exclusive fullscreen can make the
   screen-reader return black; if so see CaptureMode below.)
2. First, calibrate: set TestMode=1 in Settings.ini, press O to reload, open
   the minigame and press P. A diagnostic overlay shows, per lane, the live and
   min/max brightness, plus focus/active state and a flicker counter. No keys
   are pressed in this mode. You want each lane low (~20-40) when empty and high
   (~240+) when a note crosses the ring, and flicker staying near 0. Tune
   BrightnessThreshold to sit between empty-max and note-min, then press O.
3. Run: set TestMode=0, press O, equip the rod, press P. P = start,
   O = reload settings, M = exit.

Key settings (Settings.ini):
- HitOffsetPixels - scan point offset below ring center. Lower it (toward 0 or
  negative) to fire earlier on the very fast end-game notes; raise it to fire
  later. Tune this first.
- BrightnessThreshold - dark/bright cutoff for "a note is on the ring" (default
  110; empty ring ~30, note ~250).
- CaptureMode - how the screen is read (default RGB). If calibration shows the
  lanes stuck near 0 while the game is visible, set this to "Alt RGB" or
  "Slow RGB" and press O.
- InactiveConfirm - how many consecutive "minigame gone" reads end the song
  (default 6). Raise it if a song ends early or a catch is miscounted.
- CastHoldMs / PostCatchWaitMs / RhythmAppearTimeoutMs - cast charge time, pause
  after a catch, and how long to wait for a bite before re-casting.
- Geometry section - lane fractions / ring position; only change for non-16:9
  layouts. Regenerate with tools/analyze_rhythm.py from a screenshot. The
  screenshot MUST show all four target rings EMPTY (no notes covering any
  ring), otherwise the emitted lane fractions will be wrong or incomplete (the
  tool only emits lane fractions when it detects exactly 4 clean rings).

Dev note (Mac): tools/analyze_rhythm.py validates lane geometry and note
detection against screenshots without the game, and prints the Settings values
above. Run: python3 -m venv .venv && .venv/bin/pip install -r tools/requirements.txt
then .venv/bin/python tools/analyze_rhythm.py your_shot.png --out /tmp
