# Fisch Musical-Rod Macro — Design

**Date:** 2026-06-19
**Branch:** `feat/musical-rod-macro`
**Status:** Approved design → implementation plan next

## Goal

Auto-catch fish in the Roblox game **Fisch** when using a **musical rod**, whose
catch minigame is a 4-lane rhythm game (Guitar-Hero style) on keys **D / F / J / K**.
The macro runs a full AFK loop: cast → wait for bite → play the rhythm game → fish
caught → re-cast, repeating indefinitely so a rare fish can be ground out unattended.

A secondary goal is a tight **Mac → Windows** development loop: the author works on a
Mac and cannot run the game or AutoHotkey locally, so the design must allow validating
the screen-detection logic on the Mac (against screenshots) before shipping to the
Windows gaming PC.

## Background

This repository already contains a working macro, `Stable Releases/Than's Fisch Macro
v2.2.ahk`, but it automates a **different** minigame — Fisch's classic *reel bar*
(a white control bar chasing a fish marker), driven by `PixelSearch` over horizontal
scan-lines. The musical rod **replaces that entire minigame** with the rhythm game, so
the catch logic is net-new. The reel-bar macro is left untouched; the musical macro is a
separate file.

What we reuse from the existing macro (proven patterns):

- Roblox window detection (`GetRobloxHWND`, `WinGetClientPos` via `GetClientRect`).
- `CoordMode, Pixel/Mouse, Client` and 16:9 fraction-based coordinate math
  (e.g. `x := width * (575/1920)`), so it works at any 16:9 fullscreen resolution.
- The 100%-Display-Scale (DPI) guard.
- The `Settings.ini` create-and-read pattern with sane defaults.
- The on-screen tooltip HUD and the `P` (start) / `O` (reload) / `M` (exit) hotkeys.

## Confirmed requirements & assumptions

Confirmed with the user:

1. **Full AFK auto-loop** (not rhythm-only assist).
2. Musical-rod flow is **cast → bite → rhythm game**, with **no separate "shake" step**.
3. Notes are **taps** (press once), never hold-and-release.
4. Lanes are always **D / F / J / K**, left-to-right.
5. **Notes accelerate and get very fast at the end** of the minigame, so the detect →
   press → re-arm cycle must be as fast as possible.
6. We want the note centered on (or slightly past the center of) the target ring at the
   moment of the press for a cleaner/"quicker" catch, so the detection point should sit
   a little **below** the ring center by default — tunable later.

Target environment: Windows 10, Roblox fullscreen at a 16:9 resolution (recommend
2560×1440 to match the reference screenshots; any 16:9 works), Windows Display Scale 100%.

## Architecture

Two pieces:

### A. Mac-side validation tool — `tools/analyze_rhythm.py`

A Python script (run in a local venv with Pillow) that loads the reference screenshots
and:

- Auto-detects the 4 lane x-centers and the target-ring row (y).
- Samples each lane's **ring color** (hollow) and **note color** (filled), plus the dark
  background inside an empty ring, and reports the separation between them.
- Emits the **normalized 16:9 fractions** (lane x-centers, ring y) and **note colors +
  suggested tolerance** that become the AHK defaults.
- Writes **annotated PNGs**: the source screenshot with the 4 scan boxes drawn at their
  computed positions, so the author can visually confirm on the Mac that every box lands
  on the right ring — including the empty/lit/MISS variations across the three
  screenshots.

This is the "test without the game" harness and the regression suite for the detection
geometry. Reference screenshots live under `tools/fixtures/` (the three provided
2560×1440 captures: different lit lanes, MISS overlays, and varying chat-log text — a
useful spread of conditions).

### B. AHK v1.1 macro — `Musical Rod/Fisch Musical Macro v1.0.ahk`

A new, self-contained script (separate from the reel-bar macro). Sections:

- **Boot:** DPI guard, `Settings.ini` create/read, Roblox window lookup.
- **Geometry:** compute the 4 lane scan boxes and the rhythm-active probe points from
  16:9 fractions × client size.
- **Detection (per lane):** a tiny `PixelSearch` box at the hit point; **edge-triggered**.
- **Main loop:** cast ↔ rhythm state machine.
- **HUD/hotkeys:** tooltip status + `P`/`O`/`M`.

## Detection model

Each target ring is **hollow**; a falling note is the **filled** circle of the same lane
color. The scan box sits at the ring center (offset down by `HitOffsetPixels`). When the
box is empty it reads dark background; when a note covers it, it flashes bright lane color.

**Edge-triggered, no timers.** Each lane stores its previous state (`armed`/`fired`). The
key is `Send` only on the **rising edge** (empty → filled). The lane re-arms automatically
the instant the box reads empty again (filled → empty). This is the fastest correct scheme
for discrete taps with gaps between them: one small `PixelSearch` per lane per iteration,
no debounce timer to tune, and re-arm happens as soon as the note leaves the box.

**Signed hit offset.** `HitOffsetPixels` is a signed offset from the ring center
(positive = below center, negative = above). Because notes accelerate, the note moves
`speed × latency` pixels between our scan and the game registering the press — fast notes
favor scanning slightly *above* center (fire early), slow notes favor *below*. A single
offset is therefore a compromise across the speed ramp; we default slightly below center
(per requirement 6) and dial it in on Windows. This is one knob, easy to tweak.

**Performance rules for the hot loop:**

- No `tooltip`/HUD calls and no `Sleep` inside the per-note detection loop. HUD updates
  happen only between casts (or throttled, e.g. once every N ms), never per scan.
- Smallest viable scan boxes and `FastRGB` mode.
- Target loop period of a few milliseconds — far shorter than the gap between consecutive
  taps even at end-game speed.

## Main loop (pseudocode)

```
loop:
    if not rhythmActive():                 # rings not present at the bottom
        cast()                             # MouseMove center; click; brief wait
        waitForRhythm(timeout)             # poll rhythmActive(); re-cast on timeout
        continue
    # rhythm is active — run the burst until it ends
    for each lane in [D, F, J, K]:
        filled := pixelInHitBox(lane)
        if filled and lane.armed:
            Send lane.key                  # edge: empty -> filled
            lane.armed := false
        else if not filled:
            lane.armed := true             # re-arm as soon as box clears
    if rhythm ended (rings gone for a short grace period):
        update HUD (caught++); break inner, go cast again
```

`rhythmActive()` checks for the presence of the 4 ring colors at their fixed bottom-row
positions (a couple of probe points), distinguishing "minigame on screen" from normal
gameplay.

## Configuration (`Settings.ini`)

`[Common]` (defaults seeded from the validation tool, all overridable):

- `KeyD`, `KeyF`, `KeyJ`, `KeyK` — lane → keyboard key bindings (default `d f j k`).
- `NoteColorD/F/J/K` — filled-note color per lane, or `Auto` to use built-in defaults.
- `NoteTolerance` — `PixelSearch` color tolerance (default ~30; bright glow varies).
- `HitOffsetPixels` — signed offset of the scan box from ring center (default small +,
  i.e. slightly below center).
- `HitBoxSize` — scan box half-size in pixels (small).
- `CastHoldMs`, `PostCastWaitMs`, `RhythmAppearTimeoutMs` — cast timing / safety.

`[No Touch]` — internal timing constants, matching the existing macro's convention.

All positional values are stored/derived as 16:9 fractions so the macro is
resolution-independent at any 16:9 fullscreen size.

## Error handling

- **Roblox not open** → message box and exit (reused pattern).
- **DPI ≠ 100%** → warn and exit, with instructions (reused pattern).
- **Rhythm UI never appears after a cast** (within `RhythmAppearTimeoutMs`) → re-cast
  rather than block forever. The repo's history already includes a "dead safety timeout"
  fix on the reel-bar macro; this loop is written to avoid the same soft-lock class.
- **Lane color not found** → do nothing for that lane. The safe default everywhere is:
  *when unsure, don't press.* A missed note is harmless; a wrong or spammed key is not.

## Testing strategy

- **Mac (no game required):** `analyze_rhythm.py` must produce correct annotated overlays
  on all three reference screenshots — scan boxes centered on the right rings, note colors
  cleanly separable from empty-ring background, across the lit/empty/MISS variations. This
  validates all detection geometry and colors before anything ships.
- **Windows (live tuning):** son downloads the `.ahk` from GitHub and runs it. Tune
  `HitOffsetPixels` (and `NoteTolerance` if needed) over a few quick GitHub re-downloads.
  The HUD shows a live hit/catch count so accuracy is visible at a glance.

## Delivery (Mac → Windows)

GitHub download (no git required on the Windows PC), matching the existing README flow:
the author commits and pushes from the Mac; the son opens the file on GitHub and saves it
(Ctrl+Shift+S), then runs it. AutoHotkey v1.1 must be installed (already documented in the
README).

## File layout

```
Musical Rod/
  Fisch Musical Macro v1.0.ahk      # the macro
tools/
  analyze_rhythm.py                 # Mac-side validation/regression harness
  fixtures/                         # reference screenshots (2560x1440)
docs/superpowers/specs/
  2026-06-19-musical-rod-macro-design.md
```

README gets a short new section documenting the musical-rod macro and its settings.

## Out of scope (YAGNI)

- No GUI/launcher — `Settings.ini` only, like the existing macro.
- No support for hold/sustained notes (assumption: taps only).
- No multi-rod auto-switching or integration with the reel-bar macro.
- No machine learning / template matching — plain color `PixelSearch` is sufficient.

## Open items to tune on Windows (not blockers)

- Final `HitOffsetPixels` and `NoteTolerance` values for the fastest end-game notes.
- Exact cast timing (`CastHoldMs`, `PostCastWaitMs`) for the musical rod.
- Confirm `rhythmActive()` probe points are robust against the dimmed gameplay behind the
  minigame overlay.
