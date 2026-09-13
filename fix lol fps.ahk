#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global lastWasLoL := false
global seenPids := Map()
global startupGraceMs := 15000  ; ignore the first 15s after the game window appears

cbPtr := CallbackCreate(WinEventProc, "F", 7)
hHook := DllCall("SetWinEventHook"
    , "UInt", 0x3, "UInt", 0x3
    , "Ptr", 0
    , "Ptr", cbPtr
    , "UInt", 0, "UInt", 0
    , "UInt", 0
    , "Ptr")

WinEventProc(hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime) {
    global lastWasLoL, seenPids, startupGraceMs
    if (!hwnd)
        return
    exe := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    isLoL := (exe = "League of Legends.exe")
    if (isLoL) {
        pid := 0
        try pid := WinGetPID("ahk_id " hwnd)
        if (pid) {
            if (!seenPids.Has(pid))
                seenPids[pid] := A_TickCount
            elapsed := A_TickCount - seenPids[pid]
            if (!lastWasLoL && elapsed > startupGraceMs) {
                SetTimer(() => FixWindow(hwnd), -10)
            }
        }
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
