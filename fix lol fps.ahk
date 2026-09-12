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