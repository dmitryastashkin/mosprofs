# === Данные ===
$data = [System.Text.Encoding]::UTF8.GetBytes("Строка1`nСтрока2`nСтрока3")
$encodedData = [Convert]::ToBase64String($data)

if (-not (Test-Path "$env:TEMP\data.txt")) {
    Set-Content -Path "$env:TEMP\data.txt" -Value ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedData))) -Encoding UTF8
}

# === Автозагрузка ===
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SystemUpdater" /d "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:TEMP\script.ps1`"" /f | Out-Null

# === Копирование себя в TEMP и APPDATA ===
$self = $MyInvocation.MyCommand.Path
$dirs = @("$env:TEMP", "$env:APPDATA")
foreach ($dir in $dirs) {
    Copy-Item -Path $self -Destination "$dir\backup_$([Guid]::NewGuid().ToString().Substring(0,8)).ps1" -Force -ErrorAction SilentlyContinue
}

# === Глобальный хоткей Ctrl+Alt+Q (WinAPI + цикл сообщений) ===
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
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int x;
        public int y;
    }

    public static bool Register() {
        return RegisterHotKey(IntPtr.Zero, 1, 0x0002 | 0x0001, (uint)'Q'); // Ctrl+Alt+Q
    }

    public static void Listen(Action onTrigger) {
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0)) {
            if (msg.message == 0x0312 && msg.wParam.ToInt32() == 1) {
                onTrigger();
            }
        }
    }
}
"@

Add-Type -AssemblyName System.Windows.Forms

function Invoke-Paste {
    $content = Get-Content "$env:TEMP\data.txt" -First 1
    [System.Windows.Forms.SendKeys]::SendWait($content)
}

# === Регистрация с проверкой результата ===
if ([GlobalHotKey]::Register()) {
    Write-Host "Хоткей Ctrl+Alt+Q зарегистрирован. Не закрывайте это окно." -ForegroundColor Green
    [GlobalHotKey]::Listen({ Invoke-Paste })
} else {
    Write-Host "ОШИБКА: не удалось зарегистрировать Ctrl+Alt+Q — комбинация занята другим приложением или старым процессом PowerShell." -ForegroundColor Red
    Write-Host "Закройте лишние процессы PowerShell и запустите скрипт снова." -ForegroundColor Yellow
}