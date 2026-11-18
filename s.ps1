param([switch]$Background)

# ================= SETTINGS =================
# Path to your text file. Put it next to this script as "lines.txt"
# or set an absolute path here, e.g. "C:\Users\dmitry\Documents\text.txt"
$SourceFile = Join-Path $PSScriptRoot "services.txt"
$StateFile  = "$env:TEMP\paste_state.txt"
$LogFile    = "$env:USERPROFILE\hotkey_error.log"
# ============================================

if (-not $Background) {
    $selfPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$selfPath`" -Background"
    Write-Host "Started in background. You can close this window." -ForegroundColor Green
    exit
}

function Write-Log($m) { Add-Content -Path $LogFile -Value "$(Get-Date): $m" }

# Single instance
$mutex = New-Object System.Threading.Mutex($false, "Global\SystemUpdaterHotkey")
if (-not $mutex.WaitOne(0)) { exit }

# Autostart
$selfPath = $MyInvocation.MyCommand.Path
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SystemUpdater" /d "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$selfPath`" -Background" /f | Out-Null

# Shared state between C# hook thread and PowerShell callbacks
$global:Sync = [hashtable]::Synchronized(@{
    Lines = @()
    Index = 0
})

function Load-Lines {
    if (Test-Path $SourceFile) {
        $global:Sync.Lines = @([System.IO.File]::ReadAllLines($SourceFile, [System.Text.Encoding]::UTF8))
    } else {
        $global:Sync.Lines = @()
        Write-Log "Source file not found: $SourceFile"
    }
    if (Test-Path $StateFile) {
        $n = 0
        if ([int]::TryParse((Get-Content $StateFile -First 1), [ref]$n)) { $global:Sync.Index = $n }
    }
}
Load-Lines

Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Collections;
using System.Runtime.InteropServices;

public class HotKeys {
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mod, uint vk);
    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")]
    public static extern bool GetMessage(out MSG lpMsg, IntPtr hWnd, uint min, uint max);

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG {
        public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam;
        public uint time; public int x; public int y;
    }

    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_NOREPEAT = 0x4000;

    // id -> keycode(char). Returns list of failed ids.
    public static string Register(string letters) {
        string failed = "";
        for (int i = 0; i < letters.Length; i++) {
            int id = i + 1;
            if (!RegisterHotKey(IntPtr.Zero, id, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, (uint)letters[i]))
                failed += letters[i] + " ";
        }
        return failed;
    }

    public static void Listen(IDictionary sync, Action<int> onKey) {
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0)) {
            if (msg.message == 0x0312) {
                int id = msg.wParam.ToInt32();
                try { onKey(id); } catch {}
            }
        }
    }
}
"@

function Send-Line([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return }
    # Escape SendKeys special chars: + ^ % ~ ( ) { } [ ]
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $text.ToCharArray()) {
        if ('+^%~(){}[]'.IndexOf($ch) -ge 0) { [void]$sb.Append('{' + $ch + '}') }
        else { [void]$sb.Append($ch) }
    }
    [System.Windows.Forms.SendKeys]::SendWait($sb.ToString())
}

$handler = {
    param($id)
    $lines = $global:Sync.Lines
    $i = $global:Sync.Index

    switch ($id) {
        1 { # Ctrl+Alt+Q : paste current, advance
            if ($lines.Count -gt 0 -and $i -lt $lines.Count) {
                Send-Line $lines[$i]
                $global:Sync.Index = $i + 1
            }
        }
        2 { # Ctrl+Alt+A : step back
            if ($global:Sync.Index -gt 0) { $global:Sync.Index = $global:Sync.Index - 1 }
        }
        3 { # Ctrl+Alt+S : skip forward without pasting
            if ($global:Sync.Index -lt $lines.Count) { $global:Sync.Index = $global:Sync.Index + 1 }
        }
        4 { # Ctrl+Alt+Z : reset to first line
            $global:Sync.Index = 0
        }
        5 { # Ctrl+Alt+X : reload file from disk
            Load-Lines
        }
    }
    Set-Content -Path $StateFile -Value $global:Sync.Index -Encoding ASCII
}

$failed = [HotKeys]::Register("QASZX")
if ($failed.Trim()) { Write-Log ("RegisterHotKey failed for: " + $failed) }

[HotKeys]::Listen($global:Sync, $handler)