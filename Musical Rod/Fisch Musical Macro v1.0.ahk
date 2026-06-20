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
