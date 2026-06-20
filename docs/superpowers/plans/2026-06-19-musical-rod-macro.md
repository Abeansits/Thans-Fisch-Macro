# Fisch Musical-Rod Macro — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-catch fish in Roblox *Fisch* with a musical rod by playing its 4-lane (D/F/J/K) rhythm minigame, in a full AFK cast→play→re-cast loop.

**Architecture:** Two pieces. (1) A Mac-side Python tool that measures lane/ring geometry and note/empty brightness from screenshots, validates the detection against fixtures, and emits the constants the macro uses — this is how we test without the game. (2) An AutoHotkey v1.1 macro that, at runtime, casts, detects when a note fills each ring's dark center (brightness jumps dark→bright), and presses that lane's key edge-triggered.

**Tech Stack:** Python 3 + Pillow + pytest (Mac dev/validation only); AutoHotkey v1.1 (Windows runtime). Detection is plain `PixelGetColor` brightness comparison — no color matching, no ML.

## Global Constraints

- **AutoHotkey v1.1** only (matches existing repo macro and the Windows target). Not v2.
- **Windows Display Scale = 100%**; Roblox **fullscreen at a 16:9 resolution**. All on-screen positions derived from 16:9 fractions of the client rect, so 1080p/1440p/4K all work.
- **Detection is rod-color agnostic:** trigger on brightness (empty ring interior ≈ 21–35; filled note / ring stroke ≈ 243–255). Default `BrightnessThreshold=110`.
- **Measured geometry (from 2560×1440 fixtures), as client-fractions:** lane x = D `0.3512`, F `0.4502`, J `0.5492`, K `0.6480`; ring center y = `0.7653`; ring radius y = `0.0486`.
- **Safe default everywhere:** when unsure, do **not** press. A missed note is harmless; a wrong/spammed key is not.
- **Hot scan loop must stay HUD-free and sleepless** (notes get very fast at the end); tooltips/HUD update only between casts or throttled.
- The existing reel-bar macro (`Stable Releases/Than's Fisch Macro v2.2.ahk`) is **not modified**.
- Commits use the repo author's email: `git config user.email sebastian.nystorm@spotter.la` (set once in Task 1).
- **Platform note for Phase 2:** AutoHotkey cannot run on the macOS dev machine, so AHK tasks cannot be unit-tested locally. Their correctness rests on (a) the constants/geometry already validated by the Phase 1 Python tool and (b) a built-in **TestMode** calibration overlay the user runs on Windows (draws scan boxes + live brightness, presses nothing). Each AHK task's verification is a concrete manual procedure on Windows, by design — not an omission.

### Safety/robustness hardening (from Codex review — applies to all AHK tasks)

These are mandatory in the macro; they are why the auto-player is safe to leave running:

1. **No re-entry:** `#MaxThreadsPerHotkey 1` and a global `running` flag; `$p::` returns immediately if already running.
2. **Focus guard:** every main-loop iteration checks `WinActive("ahk_exe RobloxPlayerBeta.exe")`. If Roblox is not the foreground window, release all keys, show a paused HUD, and press nothing — never type D/F/J/K into another app.
3. **Arm-from-dark:** at song start every lane's `armed` flag is `false`; a lane only becomes armed after it has been observed **dark** at least once. A lane that never reads dark (bad threshold/geometry, or stuck bright) is never pressed — it self-disables. This is how "do nothing when unsure" is actually enforced.
4. **Edge down/up, zero sleep:** press `{key down}` on the dark→bright rising edge and `{key up}` on the bright→dark falling edge. No `Sleep` in the hot loop (natural hold = the note's dwell time); independent per lane, so chords work with no skew. `SetKeyDelay, -1, -1`.
5. **Multi-point sampling:** lane brightness is the **max of a 3-point vertical cross** (center, center±`HitBoxRadius`), never a single pixel.
6. **Active-state hysteresis:** the song is only declared over after `InactiveConfirm` (default 6) consecutive `RhythmActive()=false` reads; a single transient flash/miss cannot end the song, miscount a catch, or trigger a mid-song re-cast.
7. **Configurable capture mode:** `PixelGetColor` uses a `CaptureMode` setting (default `RGB`; fallbacks `Alt RGB` / `Slow RGB`) because some fullscreen/D3D modes return black under the default. README recommends borderless-fullscreen.
8. **Clean key release:** `ReleaseAllKeys()` runs on focus loss, song end, `O` (reload), and `M` (exit) so no key is ever left stuck down. No bare `global` in `RunAuto()` — declare only the specific globals used.

---

## Phase 1 — Mac-side validation tool (Python, TDD)

### Task 1: Project setup + pixel helpers

**Files:**
- Create: `tools/analyze_rhythm.py`
- Create: `tools/test_analyze_rhythm.py`
- Create: `tools/requirements.txt`
- Create: `tools/fixtures/cave.png`, `tools/fixtures/swamp.png`, `tools/fixtures/stop.png`
- Create: `.gitignore`

**Interfaces:**
- Produces: `brightness(rgb:tuple)->int` (max channel), `colorfulness(rgb:tuple)->int` (max−min). These are used by every later Task.

- [ ] **Step 1: Copy fixtures and write requirements/gitignore**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git config user.email sebastian.nystorm@spotter.la
mkdir -p tools/fixtures
cp ~/Downloads/RobloxScreenShot20260619_195407112.png tools/fixtures/swamp.png
cp ~/Downloads/RobloxScreenShot20260619_195537925.png tools/fixtures/cave.png
cp ~/Downloads/RobloxScreenShot20260619_200112465.png tools/fixtures/stop.png
printf 'Pillow>=10\npytest>=7\n' > tools/requirements.txt
printf '.venv/\n__pycache__/\ntools/overlay_*.png\nStable Releases/Settings.ini\nMusical Rod/Settings.ini\n' > .gitignore
```

Expected: three files in `tools/fixtures/`, each 2560×1440 (`sips -g pixelWidth tools/fixtures/cave.png`).

- [ ] **Step 2: Create the venv and install deps**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
python3 -m venv .venv
.venv/bin/pip install -q -r tools/requirements.txt
.venv/bin/python -c "import PIL, pytest; print('ok')"
```

Expected: prints `ok`.

- [ ] **Step 3: Write the failing test for the helpers**

In `tools/test_analyze_rhythm.py`:

```python
import os
import sys
import pytest
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import analyze_rhythm as ar

FX = os.path.join(os.path.dirname(__file__), "fixtures")
CAVE = os.path.join(FX, "cave.png")
SWAMP = os.path.join(FX, "swamp.png")
STOP = os.path.join(FX, "stop.png")


def test_brightness_is_max_channel():
    assert ar.brightness((10, 20, 30)) == 30


def test_colorfulness_is_range():
    assert ar.colorfulness((10, 20, 35)) == 25
```

- [ ] **Step 4: Run it to confirm it fails**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q
```

Expected: FAIL — `ModuleNotFoundError: No module named 'analyze_rhythm'`.

- [ ] **Step 5: Write the minimal module**

In `tools/analyze_rhythm.py`:

```python
"""Measure Fisch musical-rod rhythm-game geometry from screenshots.

Mac-side dev/validation tool. Emits the lane/ring constants the AHK macro
uses and renders annotated overlays so detection can be verified without
running the game. Detection is brightness-based and rod-color agnostic:
an empty ring interior is dark (~21-35); a filled note or ring stroke is
bright (~243-255).
"""
from collections import deque, namedtuple
from PIL import Image, ImageDraw

Ring = namedtuple("Ring", "cx cy r color")


def brightness(rgb):
    return max(rgb[0], rgb[1], rgb[2])


def colorfulness(rgb):
    return max(rgb[0], rgb[1], rgb[2]) - min(rgb[0], rgb[1], rgb[2])
```

- [ ] **Step 6: Run it to confirm it passes**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q
```

Expected: PASS (2 passed).

- [ ] **Step 7: Commit**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git add tools .gitignore
git commit -m "Add rhythm-analysis tool scaffold, fixtures, pixel helpers"
```

---

### Task 2: Detect the hollow target rings

**Files:**
- Modify: `tools/analyze_rhythm.py`
- Modify: `tools/test_analyze_rhythm.py`

**Interfaces:**
- Consumes: `brightness`, `colorfulness` (Task 1).
- Produces:
  - `interior_brightness(pix, cx:int, cy:int, box:int=12)->float` — mean brightness of a small square centred at `(cx,cy)`.
  - `find_rings(img:Image)->list[Ring]` — hollow rings only (dark interior), sorted left→right by `cx`. A `Ring` is `(cx, cy, r, color)` in pixels.

- [ ] **Step 1: Write the failing tests**

Append to `tools/test_analyze_rhythm.py`:

```python
def test_find_four_rings_in_cave():
    rings = ar.find_rings(Image.open(CAVE).convert("RGB"))
    assert len(rings) == 4


def test_find_four_rings_in_swamp():
    rings = ar.find_rings(Image.open(SWAMP).convert("RGB"))
    assert len(rings) == 4


def test_stop_tolerates_note_occluding_a_ring():
    # In stop.png a note sits on the F ring, so its interior is filled and
    # that ring is not a hollow ring -> at least the other three are found.
    rings = ar.find_rings(Image.open(STOP).convert("RGB"))
    assert len(rings) >= 3


def test_rings_sorted_left_to_right():
    rings = ar.find_rings(Image.open(CAVE).convert("RGB"))
    xs = [r.cx for r in rings]
    assert xs == sorted(xs)


def test_empty_ring_interior_is_dark():
    img = Image.open(CAVE).convert("RGB")
    pix = img.load()
    for r in ar.find_rings(img):
        assert ar.interior_brightness(pix, r.cx, r.cy) < 50
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q
```

Expected: FAIL — `AttributeError: module 'analyze_rhythm' has no attribute 'find_rings'`.

- [ ] **Step 3: Implement `interior_brightness` and `find_rings`**

Append to `tools/analyze_rhythm.py`:

```python
def _colorful_bright(p, cf=55, br=90):
    return colorfulness(p) > cf and brightness(p) > br


def interior_brightness(pix, cx, cy, box=12):
    total = 0
    n = 0
    for y in range(cy - box, cy + box + 1):
        for x in range(cx - box, cx + box + 1):
            total += brightness(pix[x, y])
            n += 1
    return total / n


def find_rings(img, region_top=0.55, dark_interior_max=50):
    """Connected-component scan of the bottom region for ring-sized blobs of
    bright, colorful pixels; keep only those with a DARK interior (hollow
    target rings). Filled notes have bright interiors and are rejected."""
    W, H = img.size
    pix = img.load()
    y_start = int(H * region_top)
    step = 2
    seen = set()
    rings = []
    for sy in range(y_start, H, step):
        for sx in range(0, W, step):
            if (sx, sy) in seen or not _colorful_bright(pix[sx, sy]):
                continue
            q = deque([(sx, sy)])
            seen.add((sx, sy))
            xs, ys = [], []
            while q:
                x, y = q.popleft()
                xs.append(x)
                ys.append(y)
                for dx, dy in ((step, 0), (-step, 0), (0, step), (0, -step)):
                    nx, ny = x + dx, y + dy
                    if (0 <= nx < W and y_start <= ny < H
                            and (nx, ny) not in seen
                            and _colorful_bright(pix[nx, ny])):
                        seen.add((nx, ny))
                        q.append((nx, ny))
            w = max(xs) - min(xs)
            h = max(ys) - min(ys)
            if not (90 <= w <= 200 and 90 <= h <= 200):
                continue  # wrong size: clipped note, merged notes, speck
            cx = (min(xs) + max(xs)) // 2
            cy = (min(ys) + max(ys)) // 2
            if interior_brightness(pix, cx, cy) > dark_interior_max:
                continue  # filled note, not a hollow ring
            color = pix[cx, max(0, cy - h // 2)]  # bright stroke at ring top
            rings.append(Ring(cx, cy, max(w, h) // 2, color))
    rings.sort(key=lambda r: r.cx)
    return rings
```

- [ ] **Step 4: Run to confirm pass**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q
```

Expected: PASS (7 passed).

- [ ] **Step 5: Commit**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git add tools/analyze_rhythm.py tools/test_analyze_rhythm.py
git commit -m "Detect hollow target rings via dark-interior connected components"
```

---

### Task 3: Lane geometry + AHK constants

**Files:**
- Modify: `tools/analyze_rhythm.py`
- Modify: `tools/test_analyze_rhythm.py`

**Interfaces:**
- Consumes: `find_rings` (Task 2).
- Produces:
  - `lane_geometry(img:Image)->dict` with keys `width,height,n_rings,lane_fx(list[float]),ring_fy(float|None),radius_fy(float|None),ring_colors(list[tuple])`.
  - `emit_constants(geo:dict)->str` — newline-joined `Key=Value` lines for the AHK `Settings.ini` (`LaneDFrac`, `LaneFFrac`, `LaneJFrac`, `LaneKFrac`, `RingFracY`, `RadiusFracY`, `BrightnessThreshold`, `HitOffsetPixels`).

- [ ] **Step 1: Write the failing tests**

Append to `tools/test_analyze_rhythm.py`:

```python
def test_lane_fractions_match_measured():
    geo = ar.lane_geometry(Image.open(CAVE).convert("RGB"))
    assert geo["n_rings"] == 4
    for got, exp in zip(geo["lane_fx"], [0.3512, 0.4502, 0.5492, 0.6480]):
        assert abs(got - exp) < 0.01
    assert abs(geo["ring_fy"] - 0.7653) < 0.01
    assert abs(geo["radius_fy"] - 0.0486) < 0.01


def test_emit_constants_has_required_keys():
    geo = ar.lane_geometry(Image.open(CAVE).convert("RGB"))
    out = ar.emit_constants(geo)
    for key in ("LaneDFrac=", "LaneFFrac=", "LaneJFrac=", "LaneKFrac=",
                "RingFracY=", "RadiusFracY=", "BrightnessThreshold=110",
                "HitOffsetPixels=15"):
        assert key in out
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q -k "lane_fractions or emit_constants"
```

Expected: FAIL — `AttributeError: ... 'lane_geometry'`.

- [ ] **Step 3: Implement `lane_geometry` and `emit_constants`**

Append to `tools/analyze_rhythm.py`:

```python
def lane_geometry(img):
    W, H = img.size
    rings = find_rings(img)
    geo = {
        "width": W,
        "height": H,
        "n_rings": len(rings),
        "lane_fx": [round(r.cx / W, 4) for r in rings],
        "ring_fy": round(sum(r.cy for r in rings) / len(rings) / H, 4) if rings else None,
        "radius_fy": round(sum(r.r for r in rings) / len(rings) / H, 4) if rings else None,
        "ring_colors": [r.color for r in rings],
    }
    return geo


def emit_constants(geo):
    keys = ["D", "F", "J", "K"]
    lines = []
    for k, fx in zip(keys, geo["lane_fx"]):
        lines.append("Lane%sFrac=%s" % (k, fx))
    lines.append("RingFracY=%s" % geo["ring_fy"])
    lines.append("RadiusFracY=%s" % geo["radius_fy"])
    lines.append("BrightnessThreshold=110")
    lines.append("HitOffsetPixels=15")
    return "\n".join(lines)
```

- [ ] **Step 4: Run to confirm pass**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q
```

Expected: PASS (9 passed).

- [ ] **Step 5: Commit**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git add tools/analyze_rhythm.py tools/test_analyze_rhythm.py
git commit -m "Derive lane geometry and emit AHK constants from rings"
```

---

### Task 4: Note-present detection

**Files:**
- Modify: `tools/analyze_rhythm.py`
- Modify: `tools/test_analyze_rhythm.py`

**Interfaces:**
- Consumes: `interior_brightness`, `find_rings` (Task 2); `Ring`.
- Produces: `note_present(img:Image, ring:Ring, hit_offset_px:int=15, box:int=12, threshold:int=110)->bool` — True when the scan box (ring center shifted down by `hit_offset_px`) is bright, i.e. a note is over the ring.

- [ ] **Step 1: Write the failing tests**

Append to `tools/test_analyze_rhythm.py`:

```python
def test_no_note_on_empty_rings():
    img = Image.open(CAVE).convert("RGB")
    for r in ar.find_rings(img):
        assert ar.note_present(img, r) is False


def test_note_detected_when_interior_filled():
    img = Image.open(CAVE).convert("RGB")
    rings = ar.find_rings(img)
    r = rings[0]
    d = ImageDraw.Draw(img)
    sy = r.cy + 15
    d.ellipse([r.cx - 45, sy - 45, r.cx + 45, sy + 45], fill=(120, 240, 245))
    assert ar.note_present(img, r) is True
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q -k note
```

Expected: FAIL — `AttributeError: ... 'note_present'`.

- [ ] **Step 3: Implement `note_present`**

Append to `tools/analyze_rhythm.py`:

```python
def note_present(img, ring, hit_offset_px=15, box=12, threshold=110):
    pix = img.load()
    return interior_brightness(pix, ring.cx, ring.cy + hit_offset_px, box) > threshold
```

- [ ] **Step 4: Run to confirm pass**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q
```

Expected: PASS (11 passed).

- [ ] **Step 5: Commit**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git add tools/analyze_rhythm.py tools/test_analyze_rhythm.py
git commit -m "Add brightness-based note-present detection"
```

---

### Task 5: Annotated overlays + CLI

**Files:**
- Modify: `tools/analyze_rhythm.py`
- Modify: `tools/test_analyze_rhythm.py`

**Interfaces:**
- Consumes: `find_rings`, `lane_geometry`, `emit_constants` (Tasks 2–3).
- Produces:
  - `annotate(img:Image, hit_offset_px:int=15, box:int=12)->Image` — copy of `img` with each scan box (yellow) and ring-top probe dot (red) drawn.
  - `main(argv=None)->int` — CLI: `analyze_rhythm.py SHOT [SHOT...] [--out DIR]`, prints constants per shot and writes `overlay_<name>` PNGs.

- [ ] **Step 1: Write the failing tests**

Append to `tools/test_analyze_rhythm.py`:

```python
def test_annotate_preserves_size():
    img = Image.open(CAVE).convert("RGB")
    out = ar.annotate(img)
    assert out.size == img.size


def test_main_writes_overlays(tmp_path):
    rc = ar.main([CAVE, SWAMP, "--out", str(tmp_path)])
    assert rc == 0
    assert (tmp_path / "overlay_cave.png").exists()
    assert (tmp_path / "overlay_swamp.png").exists()
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q -k "annotate or main"
```

Expected: FAIL — `AttributeError: ... 'annotate'`.

- [ ] **Step 3: Implement `annotate` and `main`**

Append to `tools/analyze_rhythm.py`:

```python
def annotate(img, hit_offset_px=15, box=12):
    out = img.copy()
    d = ImageDraw.Draw(out)
    for r in find_rings(out):
        sy = r.cy + hit_offset_px
        d.rectangle([r.cx - box, sy - box, r.cx + box, sy + box],
                    outline=(255, 255, 0), width=3)
        d.ellipse([r.cx - 5, r.cy - r.r - 5, r.cx + 5, r.cy - r.r + 5],
                  fill=(255, 0, 0))
    return out


def main(argv=None):
    import argparse
    import os
    ap = argparse.ArgumentParser(description="Analyze Fisch rhythm screenshots")
    ap.add_argument("shots", nargs="+", help="screenshot paths")
    ap.add_argument("--out", default=".", help="output dir for overlays")
    args = ap.parse_args(argv)
    for shot in args.shots:
        img = Image.open(shot).convert("RGB")
        geo = lane_geometry(img)
        name = os.path.basename(shot)
        print("\n# %s  (rings found: %d)" % (name, geo["n_rings"]))
        if geo["n_rings"] != 4:
            print("# WARNING: expected 4 rings, found %d "
                  "(a note may be covering a ring; use a clean shot)"
                  % geo["n_rings"])
        print(emit_constants(geo))
        op = os.path.join(args.out, "overlay_" + name)
        annotate(img).save(op)
        print("# wrote %s" % op)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run to confirm pass + eyeball a real overlay**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro/tools
../.venv/bin/python -m pytest test_analyze_rhythm.py -q
../.venv/bin/python analyze_rhythm.py fixtures/cave.png --out /tmp
echo "open /tmp/overlay_cave.png and confirm yellow boxes sit inside each ring's dark center"
```

Expected: PASS (13 passed); printed constants match the measured values (LaneDFrac≈0.3512 …); `/tmp/overlay_cave.png` shows 4 yellow boxes centered in the ring interiors.

- [ ] **Step 5: Commit**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git add tools/analyze_rhythm.py tools/test_analyze_rhythm.py
git commit -m "Add overlay rendering and CLI to rhythm-analysis tool"
```

---

## Phase 2 — AutoHotkey macro (Windows runtime)

> Reminder (see Global Constraints): these tasks cannot run on macOS. Verify by reading the code against this plan, then by the stated Windows procedure. The geometry/threshold constants are already validated by Phase 1.

### Task 6: Scaffolding, settings, geometry, and TestMode diagnostic

**Files:**
- Create: `Musical Rod/Fisch Musical Macro v1.0.ahk`

**Interfaces:**
- Produces (relied on by Task 7): directives (`#MaxThreadsPerHotkey 1`, `SetBatchLines -1`, `SetKeyDelay -1,-1`); globals `running`, `hits`, `caught`, `downD/F/J/K`; functions `GetRobloxHWND()`, `WinGetClientPos(hwnd)`, `ComputeGeometry()` (sets `WindowWidth/Height`, `laneX1..4`, `ringY`, `radius`, `scanY`, `probeY`, `centerX`, `centerY`, `gapX`), `PixelBright(x,y)`, `LaneBright(cx,cy)`, `RhythmActive()`, `ReleaseAllKeys()`, `RunCalibration()`. Settings globals: `CastHoldMs`, `PostCatchWaitMs`, `RhythmAppearTimeoutMs`, `BrightnessThreshold`, `HitOffsetPixels`, `HitBoxRadius`, `InactiveConfirm`, `CaptureMode`, `KeyD/F/J/K`, `TestMode`, `LaneDFrac/FFrac/JFrac/KFrac`, `RingFracY`, `RadiusFracY`.

This task implements all eight hardening rules from the Global Constraints
"Safety/robustness hardening" block except the auto-play loop itself (Task 7).

- [ ] **Step 1: Write the full scaffolding file**

Create `Musical Rod/Fisch Musical Macro v1.0.ahk`:

```ahk
#SingleInstance, force
#MaxThreadsPerHotkey 1
SetBatchLines, -1
SetKeyDelay, -1, -1
CoordMode, Pixel, Client
CoordMode, Mouse, Client
CoordMode, ToolTip, Client

; ===== Defaults (overridden by Settings.ini) =====
CastHoldMs := 900
PostCatchWaitMs := 2000
RhythmAppearTimeoutMs := 12000
BrightnessThreshold := 110
HitOffsetPixels := 15
HitBoxRadius := 12
InactiveConfirm := 6
CaptureMode := "RGB"
KeyD := "d"
KeyF := "f"
KeyJ := "j"
KeyK := "k"
TestMode := 0
LaneDFrac := 0.3512
LaneFFrac := 0.4502
LaneJFrac := 0.5492
LaneKFrac := 0.6480
RingFracY := 0.7653
RadiusFracY := 0.0486

global running := false
global hits := 0
global caught := 0
global downD := false
global downF := false
global downJ := false
global downK := false

; ===== Display-scale guard (must be 100%) =====
if (A_ScreenDPI * 100 // 96 != 100) {
    Run, ms-settings:display
    MsgBox, 0x1030, WARNING, % "Windows Display Scale must be 100`%, or the macro will misread the screen.`n`nDesktop -> Display Settings -> Scale = 100`%, restart Roblox, then run again."
    ExitApp
}

; ===== Settings.ini: create defaults if missing, then read (with fallback) =====
if !FileExist("Settings.ini") {
    IniWrite, %CastHoldMs%, Settings.ini, Common, CastHoldMs
    IniWrite, %PostCatchWaitMs%, Settings.ini, Common, PostCatchWaitMs
    IniWrite, %RhythmAppearTimeoutMs%, Settings.ini, Common, RhythmAppearTimeoutMs
    IniWrite, %BrightnessThreshold%, Settings.ini, Common, BrightnessThreshold
    IniWrite, %HitOffsetPixels%, Settings.ini, Common, HitOffsetPixels
    IniWrite, %HitBoxRadius%, Settings.ini, Common, HitBoxRadius
    IniWrite, %InactiveConfirm%, Settings.ini, Common, InactiveConfirm
    IniWrite, %CaptureMode%, Settings.ini, Common, CaptureMode
    IniWrite, %KeyD%, Settings.ini, Common, KeyD
    IniWrite, %KeyF%, Settings.ini, Common, KeyF
    IniWrite, %KeyJ%, Settings.ini, Common, KeyJ
    IniWrite, %KeyK%, Settings.ini, Common, KeyK
    IniWrite, %TestMode%, Settings.ini, Common, TestMode
    IniWrite, %LaneDFrac%, Settings.ini, Geometry, LaneDFrac
    IniWrite, %LaneFFrac%, Settings.ini, Geometry, LaneFFrac
    IniWrite, %LaneJFrac%, Settings.ini, Geometry, LaneJFrac
    IniWrite, %LaneKFrac%, Settings.ini, Geometry, LaneKFrac
    IniWrite, %RingFracY%, Settings.ini, Geometry, RingFracY
    IniWrite, %RadiusFracY%, Settings.ini, Geometry, RadiusFracY
}
IniRead, CastHoldMs, Settings.ini, Common, CastHoldMs, %CastHoldMs%
IniRead, PostCatchWaitMs, Settings.ini, Common, PostCatchWaitMs, %PostCatchWaitMs%
IniRead, RhythmAppearTimeoutMs, Settings.ini, Common, RhythmAppearTimeoutMs, %RhythmAppearTimeoutMs%
IniRead, BrightnessThreshold, Settings.ini, Common, BrightnessThreshold, %BrightnessThreshold%
IniRead, HitOffsetPixels, Settings.ini, Common, HitOffsetPixels, %HitOffsetPixels%
IniRead, HitBoxRadius, Settings.ini, Common, HitBoxRadius, %HitBoxRadius%
IniRead, InactiveConfirm, Settings.ini, Common, InactiveConfirm, %InactiveConfirm%
IniRead, CaptureMode, Settings.ini, Common, CaptureMode, %CaptureMode%
IniRead, KeyD, Settings.ini, Common, KeyD, %KeyD%
IniRead, KeyF, Settings.ini, Common, KeyF, %KeyF%
IniRead, KeyJ, Settings.ini, Common, KeyJ, %KeyJ%
IniRead, KeyK, Settings.ini, Common, KeyK, %KeyK%
IniRead, TestMode, Settings.ini, Common, TestMode, %TestMode%
IniRead, LaneDFrac, Settings.ini, Geometry, LaneDFrac, %LaneDFrac%
IniRead, LaneFFrac, Settings.ini, Geometry, LaneFFrac, %LaneFFrac%
IniRead, LaneJFrac, Settings.ini, Geometry, LaneJFrac, %LaneJFrac%
IniRead, LaneKFrac, Settings.ini, Geometry, LaneKFrac, %LaneKFrac%
IniRead, RingFracY, Settings.ini, Geometry, RingFracY, %RingFracY%
IniRead, RadiusFracY, Settings.ini, Geometry, RadiusFracY, %RadiusFracY%

; ===== Hotkeys =====
$o::
    running := false
    ReleaseAllKeys()
    Reload
return

$m::
    running := false
    ReleaseAllKeys()
    ExitApp
return

$p::
    if (running)
        return
    currentWindow := GetRobloxHWND()
    if (!currentWindow) {
        MsgBox, Roblox needs to be open first.
        return
    }
    WinActivate, ahk_exe RobloxPlayerBeta.exe
    Sleep, 250
    ComputeGeometry()
    running := true
    if (TestMode = 1 or TestMode = "1")
        RunCalibration()
    else
        RunAuto()
    running := false
return

; ===== Geometry (all coords floored to ints) =====
ComputeGeometry() {
    global
    client := WinGetClientPos(currentWindow)
    WindowWidth := client.W
    WindowHeight := client.H
    laneX1 := Floor(WindowWidth * LaneDFrac)
    laneX2 := Floor(WindowWidth * LaneFFrac)
    laneX3 := Floor(WindowWidth * LaneJFrac)
    laneX4 := Floor(WindowWidth * LaneKFrac)
    ringY := Floor(WindowHeight * RingFracY)
    radius := Floor(WindowHeight * RadiusFracY)
    scanY := ringY + HitOffsetPixels
    probeY := ringY - radius
    centerX := Floor(WindowWidth / 2)
    centerY := Floor(WindowHeight / 2)
    gapX := Floor((laneX1 + laneX2) / 2)
}

; ===== Pixel brightness (max channel), capture-mode aware =====
PixelBright(x, y) {
    global CaptureMode
    PixelGetColor, c, x, y, %CaptureMode%
    R := (c >> 16) & 0xFF
    G := (c >> 8) & 0xFF
    B := c & 0xFF
    return Max(R, G, B)
}

; ===== Lane brightness: max of a 3-point vertical cross (never one pixel) =====
LaneBright(cx, cy) {
    global HitBoxRadius
    b := PixelBright(cx, cy)
    b := Max(b, PixelBright(cx, cy - HitBoxRadius))
    b := Max(b, PixelBright(cx, cy + HitBoxRadius))
    return b
}

; ===== Is the rhythm minigame on screen? =====
; All four ring-top probes bright AND the gap between lanes D and F dark.
RhythmActive() {
    global laneX1, laneX2, laneX3, laneX4, probeY, ringY, gapX, BrightnessThreshold
    if (PixelBright(laneX1, probeY) < BrightnessThreshold)
        return false
    if (PixelBright(laneX2, probeY) < BrightnessThreshold)
        return false
    if (PixelBright(laneX3, probeY) < BrightnessThreshold)
        return false
    if (PixelBright(laneX4, probeY) < BrightnessThreshold)
        return false
    if (PixelBright(gapX, ringY) > BrightnessThreshold)
        return false
    return true
}

; ===== Release any keys we are holding (safety) =====
ReleaseAllKeys() {
    global downD, downF, downJ, downK, KeyD, KeyF, KeyJ, KeyK
    if (downD) {
        Send, % "{" KeyD " up}"
        downD := false
    }
    if (downF) {
        Send, % "{" KeyF " up}"
        downF := false
    }
    if (downJ) {
        Send, % "{" KeyJ " up}"
        downJ := false
    }
    if (downK) {
        Send, % "{" KeyK " up}"
        downK := false
    }
}

; ===== Calibration / diagnostic overlay: presses NOTHING =====
; Shows live + min/max brightness per lane, focus state, and how many times
; RhythmActive() flipped (flicker) so thresholds/capture mode can be tuned.
RunCalibration() {
    global
    minD := 999, minF := 999, minJ := 999, minK := 999
    maxD := 0, maxF := 0, maxJ := 0, maxK := 0
    flicker := 0
    prevActive := RhythmActive()
    Loop {
        if (!running)
            break
        focused := WinActive("ahk_exe RobloxPlayerBeta.exe") ? 1 : 0
        active := RhythmActive()
        if (active != prevActive)
            flicker += 1
        prevActive := active
        b1 := LaneBright(laneX1, scanY)
        b2 := LaneBright(laneX2, scanY)
        b3 := LaneBright(laneX3, scanY)
        b4 := LaneBright(laneX4, scanY)
        minD := Min(minD, b1), maxD := Max(maxD, b1)
        minF := Min(minF, b2), maxF := Max(maxF, b2)
        minJ := Min(minJ, b3), maxJ := Max(maxJ, b3)
        minK := Min(minK, b4), maxK := Max(maxK, b4)
        info := "CALIBRATION - no keys pressed`n"
        info .= "focused:" focused "  active:" active "  flicker:" flicker "  thr:" BrightnessThreshold "`n"
        info .= "D now:" b1 " min:" minD " max:" maxD "`n"
        info .= "F now:" b2 " min:" minF " max:" maxF "`n"
        info .= "J now:" b3 " min:" minJ " max:" maxJ "`n"
        info .= "K now:" b4 " min:" minK " max:" maxK
        ToolTip, %info%, centerX - 150, probeY - 130, 1
        ToolTip, % "D " (b1 > BrightnessThreshold ? "HIT" : "-"), laneX1 - 10, scanY, 2
        ToolTip, % "F " (b2 > BrightnessThreshold ? "HIT" : "-"), laneX2 - 10, scanY, 3
        ToolTip, % "J " (b3 > BrightnessThreshold ? "HIT" : "-"), laneX3 - 10, scanY, 4
        ToolTip, % "K " (b4 > BrightnessThreshold ? "HIT" : "-"), laneX4 - 10, scanY, 5
        Sleep, 30
    }
}

; ===== Reused Roblox window helpers (from v2.2) =====
GetRobloxHWND() {
    if (hwnd := WinExist("Roblox ahk_exe RobloxPlayerBeta.exe"))
        return hwnd
}

WinGetClientPos(Hwnd) {
    VarSetCapacity(size, 16, 0)
    DllCall("GetClientRect", UInt, Hwnd, Ptr, &size)
    DllCall("ClientToScreen", UInt, Hwnd, Ptr, &size)
    x := NumGet(size, 0, "Int")
    y := NumGet(size, 4, "Int")
    w := NumGet(size, 8, "Int")
    h := NumGet(size, 12, "Int")
    return { X: x, Y: y, W: w, H: h }
}

; RunAuto() and helpers (DoCast, ShowHud) are added in Task 7.
RunAuto() {
    MsgBox, RunAuto not implemented yet. Set TestMode=1 to calibrate.
}
```

- [ ] **Step 2: Static self-review against this plan**

Confirm, reading the file: AHK v1.1 syntax only; `#MaxThreadsPerHotkey 1` present; `$p::` returns early when `running`; `$o::`/`$m::` both call `ReleaseAllKeys()` before reload/exit; every Settings key has an `IniWrite` default and an `IniRead` with fallback; `ComputeGeometry` floors every coordinate (incl. `gapX`); `LaneBright` samples three points; `PixelBright` honors `CaptureMode`; `RunCalibration` sends **no** keys/clicks and tracks min/max + flicker. AHK can't run on macOS, so this static review is the Mac-side gate.

- [ ] **Step 3: Commit**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git add "Musical Rod/Fisch Musical Macro v1.0.ahk"
git commit -m "Add musical-rod macro scaffolding with hardened TestMode diagnostic"
```

- [ ] **Step 4: Windows verification procedure (manual, by the user)**

1. Install AutoHotkey v1.1; download the `.ahk`; double-click to run (creates `Settings.ini`). Run Roblox in **borderless** fullscreen at a 16:9 resolution.
2. Set `TestMode=1` in `Settings.ini`, press `O` to reload.
3. Open the musical-rod minigame, press `P`.
4. Confirm: the diagnostic tooltip shows `focused:1`; `active` reads `1` only while the minigame is up; each lane's `now` brightness sits low (~20-40) when empty and jumps high (~240+) when a note crosses the ring; `flicker` stays low. If `now` is stuck near 0 even with the game visible, set `CaptureMode=Alt RGB` (or `Slow RGB`), press `O`, retry — this is the D3D capture-mode fix. Tune `BrightnessThreshold` between the observed empty-`max` and note-`min`. No keys are pressed in this mode.

---

### Task 7: Auto-play loop (detection, cast, hysteresis, safety)

**Files:**
- Modify: `Musical Rod/Fisch Musical Macro v1.0.ahk`

**Interfaces:**
- Consumes: all globals/functions from Task 6 (`LaneBright`, `RhythmActive`, `ReleaseAllKeys`, geometry globals, `running`, `hits`, `caught`, `downD/F/J/K`, settings).
- Produces: `RunAuto()` (replaces the stub), `DoCast()`, `ShowHud(status)`.

- [ ] **Step 1: Replace the `RunAuto()` stub and add helpers**

In `Musical Rod/Fisch Musical Macro v1.0.ahk`, replace:

```ahk
; RunAuto() and helpers (DoCast, ShowHud) are added in Task 7.
RunAuto() {
    MsgBox, RunAuto not implemented yet. Set TestMode=1 to calibrate.
}
```

with:

```ahk
DoCast() {
    global centerX, centerY, CastHoldMs
    MouseMove, centerX, centerY
    Click, Down
    Sleep, %CastHoldMs%
    Click, Up
}

ShowHud(status) {
    global centerX, probeY, hits, caught
    ToolTip, % "Musical Macro | " status " | hits:" hits " caught:" caught "  (O reload, M exit)", centerX - 170, probeY - 70, 1
}

; Full AFK loop. Safety rules (see plan Global Constraints):
;  - focus guard: never press unless Roblox is foreground
;  - arm-from-dark: a lane fires only after it has been seen dark this song
;  - edge down/up, zero sleep in the hot loop; Sleep,-1 only pumps messages so
;    O/M stay responsive without slowing the scan
;  - InactiveConfirm consecutive inactive reads required before "song over"
RunAuto() {
    global running, hits, caught
    global laneX1, laneX2, laneX3, laneX4, scanY
    global BrightnessThreshold, InactiveConfirm
    global KeyD, KeyF, KeyJ, KeyK
    global downD, downF, downJ, downK
    global CastHoldMs, PostCatchWaitMs, RhythmAppearTimeoutMs
    armedD := false, armedF := false, armedJ := false, armedK := false
    prevActive := false
    inactiveCount := 0
    hudTimer := A_TickCount
    Loop {
        if (!running)
            break
        ; --- focus guard: never type into another app ---
        if (!WinActive("ahk_exe RobloxPlayerBeta.exe")) {
            ReleaseAllKeys()
            armedD := false, armedF := false, armedJ := false, armedK := false
            ShowHud("Paused - Roblox not focused")
            Sleep, 250
            continue
        }
        if (RhythmActive()) {
            inactiveCount := 0
            if (!prevActive) {
                ; song just started: require a dark baseline before pressing
                armedD := false, armedF := false, armedJ := false, armedK := false
                prevActive := true
                ShowHud("Playing")
            }
            ; ---- HOT SCAN LOOP: no real sleep, edge down/up per lane ----
            if (LaneBright(laneX1, scanY) > BrightnessThreshold) {
                if (armedD and !downD) {
                    Send, % "{" KeyD " down}"
                    downD := true
                    hits += 1
                }
            } else {
                armedD := true
                if (downD) {
                    Send, % "{" KeyD " up}"
                    downD := false
                }
            }
            if (LaneBright(laneX2, scanY) > BrightnessThreshold) {
                if (armedF and !downF) {
                    Send, % "{" KeyF " down}"
                    downF := true
                    hits += 1
                }
            } else {
                armedF := true
                if (downF) {
                    Send, % "{" KeyF " up}"
                    downF := false
                }
            }
            if (LaneBright(laneX3, scanY) > BrightnessThreshold) {
                if (armedJ and !downJ) {
                    Send, % "{" KeyJ " down}"
                    downJ := true
                    hits += 1
                }
            } else {
                armedJ := true
                if (downJ) {
                    Send, % "{" KeyJ " up}"
                    downJ := false
                }
            }
            if (LaneBright(laneX4, scanY) > BrightnessThreshold) {
                if (armedK and !downK) {
                    Send, % "{" KeyK " down}"
                    downK := true
                    hits += 1
                }
            } else {
                armedK := true
                if (downK) {
                    Send, % "{" KeyK " up}"
                    downK := false
                }
            }
            Sleep, -1   ; pump messages (keeps O/M responsive); no real delay
        } else {
            inactiveCount += 1
            if (inactiveCount >= InactiveConfirm) {
                ReleaseAllKeys()
                armedD := false, armedF := false, armedJ := false, armedK := false
                if (prevActive) {
                    caught += 1
                    prevActive := false
                    ShowHud("Caught")
                    Sleep, %PostCatchWaitMs%
                }
                ShowHud("Casting")
                DoCast()
                ShowHud("Waiting for bite")
                waitStart := A_TickCount
                Loop {
                    if (!running)
                        break
                    if (WinActive("ahk_exe RobloxPlayerBeta.exe") and RhythmActive())
                        break
                    if (A_TickCount - waitStart > RhythmAppearTimeoutMs)
                        break
                    Sleep, 50
                }
                inactiveCount := 0
            } else {
                Sleep, -1
            }
        }
        if (A_TickCount - hudTimer > 300) {
            ShowHud(prevActive ? "Playing" : "Idle")
            hudTimer := A_TickCount
        }
    }
    ReleaseAllKeys()
}
```

- [ ] **Step 2: Static self-review against this plan**

Confirm: the hot scan loop has no blocking `Sleep` (only `Sleep, -1`, the message-pump) and no `ToolTip` except the 300 ms-throttled `ShowHud`; each lane presses `{key down}` only when `armed and !down` and releases `{key up}` on the dark edge; `armed*` start `false` and are set true only on a dark read (arm-from-dark); the focus guard releases keys and skips pressing when Roblox isn't foreground; the song is declared over only after `InactiveConfirm` inactive reads; the wait-for-bite loop has the `RhythmAppearTimeoutMs` safety break and respects `running`; `ReleaseAllKeys()` runs on song end, focus loss, and loop exit. AHK v1.1 syntax throughout.

- [ ] **Step 3: Commit**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git add "Musical Rod/Fisch Musical Macro v1.0.ahk"
git commit -m "Implement hardened musical-rod auto-play loop"
```

- [ ] **Step 4: Windows verification procedure (manual, by the user)**

1. Calibrate first via Task 6 (get clean dark/bright separation and `flicker` near 0). Then set `TestMode=0`, press `O`.
2. Equip the musical rod, press `P`. The macro casts, waits for the bite, and hits notes as they reach the rings; the HUD shows rising `hits`/`caught`. Alt-tab away and confirm it pauses (no stray key presses); refocus Roblox and confirm it resumes.
3. Tune the fast end-game notes with `HitOffsetPixels`: if hits land late, lower it (toward 0 / negative = scan higher = fire earlier); if early, raise it. If the song ever ends early or miscounts, raise `InactiveConfirm`. Press `O` after each change.

---

## Phase 3 — Documentation & delivery

### Task 8: README section and publish

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append a musical-rod section to `README.md`**

Add at the end of `README.md`:

```markdown

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
  layouts. Regenerate with tools/analyze_rhythm.py from a screenshot.

Dev note (Mac): tools/analyze_rhythm.py validates lane geometry and note
detection against screenshots without the game, and prints the Settings values
above. Run: python3 -m venv .venv && .venv/bin/pip install -r tools/requirements.txt
then .venv/bin/python tools/analyze_rhythm.py your_shot.png --out /tmp
```

- [ ] **Step 2: Commit**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git add README.md
git commit -m "Document the musical-rod macro and calibration workflow"
```

- [ ] **Step 3: Push the branch for GitHub download**

```bash
cd /Users/sebastian.nystorm/Developer/thans-fisch-macro
git push -u origin feat/musical-rod-macro
```

Expected: branch on GitHub; the user/son can open `Musical Rod/Fisch Musical Macro v1.0.ahk` and download it (Ctrl+Shift+S), per the README. (Open a PR to `main` only if/when the user wants it merged.)

---

## Self-Review (against the spec)

**Spec coverage:** Full AFK loop → Task 7 (`RunAuto`). Edge-triggered detection + signed hit offset → Tasks 4, 6, 7. Rhythm-active detection → Task 6 (`RhythmActive`). Mac screenshot harness → Tasks 1–5. Resolution-independent 16:9 fractions → Task 6 (`ComputeGeometry`). Settings.ini + reused scaffolding (DPI guard, window helpers, HUD, P/O/M) → Task 6. Error handling (Roblox-not-open, DPI, re-cast timeout, do-nothing-when-unsure) → Tasks 6–7. Testing on Mac + tuning on Windows → Tasks 5, 6, 7. GitHub delivery + README → Task 8. No gaps.

**Placeholder scan:** No TBD/TODO; the one stub (`RunAuto` in Task 6) is intentional and explicitly replaced in Task 7. All code is complete and concrete.

**Type/name consistency:** `Ring(cx,cy,r,color)`, `find_rings`, `interior_brightness`, `lane_geometry`, `emit_constants`, `note_present`, `annotate`, `main` are used identically across Python tasks. AHK globals (`laneX1..4`, `scanY`, `probeY`, `ringY`, `gapX`, `BrightnessThreshold`, `HitOffsetPixels`, `KeyHoldMs`, `Key D/F/J/K`) and functions (`ComputeGeometry`, `PixelBright`, `RhythmActive`, `RunCalibration`, `RunAuto`, `DoCast`, `PressKey`, `ShowHud`) are consistent between Tasks 6 and 7.
