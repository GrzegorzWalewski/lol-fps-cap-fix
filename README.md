# LoL Cross-Monitor FPS Fix

A small AutoHotkey script that fixes a Windows bug where League of Legends
(and likely other borderless-windowed games) gets stuck at a low, capped
framerate after alt-tabbing to a window on a **different physical monitor**,
in a multi-monitor setup.

## The problem

**Setup:** 3 monitors, AMD Radeon RX 6900 XT, League of Legends running in
Borderless mode on the main display.

**Symptom:** After alt-tabbing away to a window on a *different* monitor
(browser, Discord, etc.) and back, League's framerate drops from its normal
uncapped rate down to a hard cap matching the desktop's refresh rate (e.g.
60 fps on 60Hz displays). It doesn't recover on its own reliably — sometimes
several more alt-tabs eventually "unstick" it, sometimes not.

Critically: alt-tabbing to another window **on the same monitor** as the game
never triggers this. Only a focus change to a different display does.

## Root cause

Confirmed using [PresentMon](https://github.com/GameTechDev/PresentMon)
(non-injecting ETW-based frame analysis tool):

- Normal / uncapped: `PresentMode = Hardware: Independent Flip`
- Capped: `PresentMode = Composed: Flip`

Windows' compositor (DWM) only grants a borderless window **Independent
Flip** (direct hardware presentation, uncapped) when it meets certain
foreground/focus conditions. Moving focus to a window on another monitor
makes the game lose eligibility, and it falls back to **Composed Flip** —
presentation routed through DWM's compositor, which locks it to the desktop
refresh rate. Refocusing the game window doesn't reliably re-trigger
Windows' re-evaluation of flip eligibility, so it stays stuck in composed
mode until something else (e.g. a minimize/restore) forces DWM to
re-evaluate it.

This is a **Windows DWM/multi-monitor limitation**, not an AMD driver bug,
a game bug, or a network/anti-cheat issue — it reproduced independent of
driver version, Discord, and overlay settings.

## The fix

Forcing a quick **minimize → restore** of the game window makes DWM
re-evaluate flip eligibility immediately and restores Independent Flip
(full, uncapped fps). This script automates that: it listens system-wide
for foreground-window-change events (via the Win32 `SetWinEventHook` API)
and, the instant focus switches *into* the League game process from
something else, automatically minimizes and restores it — restoring full
fps with no user action needed.

It uses a real OS event hook rather than polling, so it does effectively
nothing between focus changes (no periodic CPU cost), and it only calls
public window-management APIs on the process from outside — it does not
inject into, hook, or read memory from the game process itself.

## What I've tried that *didn't* fix it

In case you land here with a similar bug, here's what was ruled out along
the way, roughly in the order tried:

1. **Clean driver reinstall (DDU) + reinstalling AMD Adrenalin** — fixed an
   unrelated full driver-crash/TDR issue (bugcheck `0x117`,
   `VIDEO_TDR_TIMEOUT_DETECTED`), but not the fps cap.
2. **Disabling Discord's in-game overlay and hardware acceleration** — fixed
   the crash-on-Discord-focus issue, not the fps cap.
3. **Disabling all per-game AMD Adrenalin features** (Chill, Anti-Lag,
   Enhanced Sync, Image Sharpening, Radeon Boost) for League specifically.
4. **Windows power plan → High Performance + disabling PCIe Link State
   Power Management.**
5. **Manually setting a GPU clock floor** in Radeon Software Tuning.
6. **Disabling "Fullscreen optimizations"** on the game exe (Compatibility
   tab) — and separately, re-enabling it again.
7. **Toggling Hardware-accelerated GPU Scheduling** — not available at all
   on this Windows 10 22H2 build.
8. **Disabling Multi-Plane Overlay** via the
   `HKLM\SOFTWARE\Microsoft\Windows\Dwm\OverlayTestMode = 5` registry key
   — confirmed via reboot that it was active; made no difference.
9. **Updating to a newer (optional) AMD driver release.**
10. **Checking for mismatched monitor refresh rates** — all 3 displays were
    already at 60Hz, ruling this out.
11. **Testing different monitor ports** (DisplayPort vs HDMI) — both
    triggered the bug equally, ruling out a port/cable-specific cause.
12. **Windows Game Mode toggle off.**
13. **Task Manager "Efficiency Mode"** — not available on Windows 10 (this
    is a Windows 11 feature).

None of the above were wrong things to check — each one ruled out a real,
plausible cause — but the actual root cause turned out to be the DWM
flip-model fallback described above, which none of those settings touch.

### A note on third-party tools

Tools like **Special K**, which fix similar presentation-mode bugs by
hooking directly into a game's DirectX calls, are explicitly flagged by
their own documentation as risking a ban in anti-cheat-protected games.
League of Legends runs Riot **Vanguard**, a kernel-level anti-cheat that
watches for process injection/hooking system-wide. This script deliberately
avoids that category entirely — it only calls standard Win32
window-management APIs from outside the game process (the same class of
API used by ordinary window-snapping utilities), never touching the game's
memory or render pipeline.

## Requirements

- [AutoHotkey v2.0](https://www.autohotkey.com/)
- Windows 10/11 with a multi-monitor setup exhibiting the same symptom
- League of Legends (or adjust `League of Legends.exe` in the script to
  match another game's process name — check with AutoHotkey's bundled
  **Window Spy** tool if unsure)

## Usage

1. Install AutoHotkey v2.
2. Save `fix-fps.ahk` (script below) anywhere convenient.
3. Double-click it to run — no tray icon interaction needed; it runs
   silently in the background.
4. Optionally, add a shortcut to it in your Startup folder
   (`Win+R` → `shell:startup`) so it's always active.

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global lastWasLoL := false

cbPtr := CallbackCreate(WinEventProc, "F", 7)
hHook := DllCall("SetWinEventHook"
    , "UInt", 0x3, "UInt", 0x3
    , "Ptr", 0
    , "Ptr", cbPtr
    , "UInt", 0, "UInt", 0
    , "UInt", 0
    , "Ptr")

WinEventProc(hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime) {
    global lastWasLoL
    if (!hwnd)
        return
    exe := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    isLoL := (exe = "League of Legends.exe")
    if (isLoL && !lastWasLoL) {
        SetTimer(() => FixWindow(hwnd), -10)
    }
    lastWasLoL := isLoL
}

FixWindow(hwnd) {
    if !WinExist("ahk_id " hwnd)
        return
    WinMinimize("ahk_id " hwnd)
    Sleep(50)
    WinActivate("ahk_id " hwnd)
}

OnExit((*) => DllCall("UnhookWinEvent", "Ptr", hHook))
```

## Diagnostic tools used

- [HWiNFO64](https://www.hwinfo.com/) — GPU/memory temps, clocks
- [PresentMon](https://github.com/GameTechDev/PresentMon) — frame
  presentation mode logging (non-injecting, ETW-based)
- Windows Event Viewer — WHEA-Logger entries for hardware-level errors
- Windows minidump analysis (bugcheck code + parameters) for the original
  driver-crash issue
