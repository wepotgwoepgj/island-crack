$ErrorActionPreference = 'Stop'
$exe = Join-Path $env:LOCALAPPDATA 'Island\island.exe'

function Ok($t)  { Write-Host '  ' -NoNewline; Write-Host $t -ForegroundColor Green }
function Bad($t) { Write-Host '  ' -NoNewline; Write-Host $t -ForegroundColor Red }

Write-Host ''
Write-Host '  Island 1.2.10 - патч Pro' -ForegroundColor White
Write-Host ''

if (-not (Test-Path $exe)) {
    Bad 'не нашёл установленный Island:'
    Write-Host "     $exe"
    Write-Host '     поставь официальный 1.2.10 или скопируй island.exe из архива по этому пути.'
    exit 1
}

$ver = (Get-Item $exe).VersionInfo.ProductVersion
Write-Host "  Найден Island $ver" -ForegroundColor DarkGray
if ($ver -notlike '1.2.10*') {
    Write-Host '  Версия не 1.2.10 — на ней смещения могут не совпасть.' -ForegroundColor DarkYellow
}

Get-Process island -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 700

$bytes = [System.IO.File]::ReadAllBytes($exe)

function SameBytes([byte[]]$data, [int]$offset, [byte[]]$want) {
    for ($i = 0; $i -lt $want.Length; $i++) {
        if ($data[$offset + $i] -ne $want[$i]) { return $false }
    }
    return $true
}

$patches = @(
    @{ Off = 0x168FED; From = [byte[]](0x0F,0x85,0x92,0x00,0x00,0x00); To = [byte[]](0x90,0x90,0x90,0x90,0x90,0x90); What = 'проверка подписи ключа' },
    @{ Off = 0x168B1B; From = [byte[]](0x84,0xDB,0x74,0x44,0x0F,0xB6,0xC3); To = [byte[]](0x31,0xC0,0x90,0x90,0x90,0x90,0x90); What = 'статус Pro' }
)

$changed = $false
$failed = $false
foreach ($p in $patches) {
    if (SameBytes $bytes $p.Off $p.To) {
        Ok ($p.What + ' — уже пропатчено')
        continue
    }
    if (-not (SameBytes $bytes $p.Off $p.From)) {
        Bad ('не совпали байты: ' + $p.What + ' (0x' + $p.Off.ToString('X') + ')')
        $failed = $true
        continue
    }
    [Array]::Copy($p.To, 0, $bytes, $p.Off, $p.To.Length)
    $changed = $true
    Ok ('пропатчено: ' + $p.What)
}

if ($failed) {
    Write-Host ''
    Write-Host '  Ничего не изменено: это другая версия Island.' -ForegroundColor DarkYellow
    Write-Host '  Возьми island.exe 1.2.10 из архива и скопируй в:' -ForegroundColor DarkYellow
    Write-Host "  $exe" -ForegroundColor DarkYellow
    exit 1
}

if ($changed) {
    [System.IO.File]::WriteAllBytes($exe, $bytes)
    Ok 'файл сохранён'
} else {
    Write-Host '  Менять нечего, всё на месте.' -ForegroundColor DarkGray
}

Start-Sleep -Milliseconds 300
Start-Process -FilePath $exe | Out-Null
Ok 'Island запущен'
Write-Host ''
Write-Host '  Если Pro не появился: настройки → Island Pro (там должно быть «Куплен»).' -ForegroundColor DarkGray
Write-Host '  Чтобы не слетало снова — сними галочку в настройках → Обновления.' -ForegroundColor DarkGray