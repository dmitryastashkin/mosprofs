param([switch]$Background)

# === Self-relaunch hidden ===
if (-not $Background) {
    $self = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$self`" -Background"
    Write-Host "Started in background. This window can be closed." -ForegroundColor Green
    exit
}

# === Data (Base64, encoding-safe) ===
$encodedData = "0KHRgtGA0L7QutCwMQrQodGC0YDQvtC60LAyCtCh0YLRgNC+0LrQsDM="
$dataPath = "$env:TEMP\data.txt"
if (-not (Test-Path $dataPath)) {
    [System.IO.File]::WriteAllBytes($dataPath, [Convert]::FromBase64String($encodedData))
}

# === Autostart (points to this file, with -Background) ===
$self = $MyInvocation.MyCommand.Path
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SystemUpdater" /d "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Background" /f | Out-Null

# === Single instance check (mutex) ===
$mutex = New-Object System.Threading.Mutex($false, "Global\SystemUpdaterHotkey")
if (-not $mutex.WaitOne(0)) { exit }  # already running

# === Global hotkey Ctrl+Alt+Q ===
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class GlobalHotKey {
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")]
    public static extern bool GetMessage(out MSG lpMsg, IntPtr hWnd, uint min, uint max);

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG {
        public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam;
        public uint time; public int x; public int y;
    }

    public static bool Register() {
        return RegisterHotKey(IntPtr.Zero, 1, 0x0002 | 0x0001, (uint)'Q');
    }
    public static void Listen(Action onTrigger) {
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0)) {
            if (msg.message == 0x0312 && msg.wParam.ToInt32() == 1) onTrigger();
        }
    }
}
"@

Add-Type -AssemblyName System.Windows.Forms

function Invoke-Paste {
    $content = Get-Content $dataPath -First 1 -Encoding UTF8
    [System.Windows.Forms.SendKeys]::SendWait($content)
}

if ([GlobalHotKey]::Register()) {
    [GlobalHotKey]::Listen({ Invoke-Paste })
} else {
    Add-Content "$env:USERPROFILE\hotkey_error.log" "$(Get-Date): RegisterHotKey failed (combo taken)"
    exit
}