$ErrorActionPreference = 'Stop'
$exe = Join-Path $env:LOCALAPPDATA 'Island\island.exe'

function Ok($t)  { Write-Host '  ' -NoNewline; Write-Host $t -ForegroundColor Green }
function Bad($t) { Write-Host '  ' -NoNewline; Write-Host $t -ForegroundColor Red }

Write-Host ''
Write-Host '  Island - патч Pro' -ForegroundColor White
Write-Host ''

if (-not (Test-Path $exe)) {
    Bad 'не нашёл установленный Island:'
    Write-Host "     $exe"
    Write-Host '     поставь официальную версию или скопируй island.exe из архива по этому пути.'
    exit 1
}

$ver = (Get-Item $exe).VersionInfo.ProductVersion
if ($ver -match '^(\d+\.\d+\.\d+)') { $ver = $Matches[1] }
Write-Host "  Найден Island $ver" -ForegroundColor DarkGray

# известные версии: смещения проверены руками
$known = @{
    '1.2.10' = @(
        @{ Off = 0x168FED; From = [byte[]](0x0F,0x85,0x92,0x00,0x00,0x00); To = [byte[]](0x90,0x90,0x90,0x90,0x90,0x90); What = 'проверка подписи ключа' },
        @{ Off = 0x168B1B; From = [byte[]](0x84,0xDB,0x74,0x44,0x0F,0xB6,0xC3); To = [byte[]](0x31,0xC0,0x90,0x90,0x90,0x90,0x90); What = 'статус Pro' }
    )
    '1.2.11' = @(
        @{ Off = 0x180F39; From = [byte[]](0x0F,0x84,0xC8,0x00,0x00,0x00); To = [byte[]](0xE9,0xC8,0x00,0x00,0x00,0x90); What = 'проверка подписи ключа' },
        @{ Off = 0x180547; From = [byte[]](0x84,0xDB,0x74,0x44,0x0F,0xB6,0xC3); To = [byte[]](0x31,0xC0,0x90,0x90,0x90,0x90,0x90); What = 'статус Pro' }
    )
}

Get-Process island -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 700

$bytes = [System.IO.File]::ReadAllBytes($exe)

function SameBytes([byte[]]$data, [int]$offset, [byte[]]$want) {
    if ($offset -lt 0 -or $offset + $want.Length -gt $data.Length) { return $false }
    for ($i = 0; $i -lt $want.Length; $i++) {
        if ($data[$offset + $i] -ne $want[$i]) { return $false }
    }
    return $true
}

function Find-Sig([byte[]]$data, [byte[]]$sig) {
    $last = $data.Length - $sig.Length
    for ($i = 0; $i -le $last; $i++) {
        if ($data[$i] -ne $sig[0]) { continue }
        $hit = $true
        for ($j = 1; $j -lt $sig.Length; $j++) {
            if ($data[$i + $j] -ne $sig[$j]) { $hit = $false; break }
        }
        if ($hit) { return $i }
    }
    return -1
}

# если версия незнакомая — ищем по сигнатурам
$patches = $known[$ver]
if (-not $patches) {
    Write-Host '  Версия незнакомая, ищу по коду...' -ForegroundColor DarkYellow
    $patches = @()

    $statSig = [byte[]](0x84,0xDB,0x74,0x00,0x0F,0xB6,0xC3,0xBB,0x03,0x00,0x00,0x00,0x41,0xB5,0x01)
    $i = 0
    $statOff = -1
    while ($i -lt $bytes.Length - $statSig.Length) {
        $i = Find-Sig $bytes[ $i..($bytes.Length - 1) ] $statSig
        if ($i -lt 0) { break }
        $statOff = $i
        break
    }
    if ($statOff -ge 0) {
        $from = New-Object byte[] 7
        [Array]::Copy($bytes, $statOff, $from, 0, 7)
        $patches += @{ Off = $statOff; From = $from; To = [byte[]](0x31,0xC0,0x90,0x90,0x90,0x90,0x90); What = 'статус Pro' }
    }

    $callSig = [byte[]](0x48,0xC7,0x44,0x24,0x30,0x40,0x00,0x00,0x00)
    $i = 0
    while ($true) {
        $rest = $bytes[$i..($bytes.Length - 1)]
        $p = Find-Sig $rest $callSig
        if ($p -lt 0) { break }
        $pos = $i + $p
        $i = $pos + 9
        $end = [Math]::Min($pos + 48, $bytes.Length - 6)
        for ($k = $pos; $k -lt $end; $k++) {
            if ($bytes[$k] -eq 0x84 -and $bytes[$k+1] -eq 0xC0) {
                if ($bytes[$k+2] -eq 0x0F -and $bytes[$k+3] -eq 0x84) {
                    $rel = [BitConverter]::ToInt32($bytes, $k + 4)
                    $target = $k + 6 + $rel
                    $newRel = $target - ($k + 6)
                    $to = [byte[]](0xE9, 0,0,0,0, 0x90)
                    [Array]::Copy([BitConverter]::GetBytes([int32]$newRel), 0, $to, 1, 4)
                    $from = New-Object byte[] 6
                    [Array]::Copy($bytes, $k, $from, 0, 6)
                    $patches += @{ Off = $k; From = $from; To = $to; What = 'проверка подписи ключа' }
                } elseif ($bytes[$k+2] -eq 0x0F -and $bytes[$k+3] -eq 0x85) {
                    $from = New-Object byte[] 6
                    [Array]::Copy($bytes, $k, $from, 0, 6)
                    $patches += @{ Off = $k; From = $from; To = [byte[]](0x90,0x90,0x90,0x90,0x90,0x90); What = 'проверка подписи ключа' }
                }
                break
            }
        }
    }
}

if (-not $patches -or $patches.Count -eq 0) {
    Bad 'не смог найти места для патча'
    exit 1
}

$changed = $false
$failed = $false
foreach ($p in $patches) {
    if (SameBytes $bytes $p.Off $p.To) {
        Ok ($p.What + ' — уже пропатчено')
        continue
    }
    if (-not (SameBytes $bytes $p.Off $p.From)) {
        Bad ('не совпали байты: ' + $p.What)
        $failed = $true
        continue
    }
    [Array]::Copy($p.To, 0, $bytes, $p.Off, $p.To.Length)
    $changed = $true
    Ok ('пропатчено: ' + $p.What)
}

if ($failed) {
    Write-Host ''
    Write-Host '  Ничего не изменено: байты не совпали.' -ForegroundColor DarkYellow
    Write-Host '  Скинь версию тому, кто собирал — подгоню.' -ForegroundColor DarkYellow
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
Write-Host '  Проверить: настройки → Island Pro (должно быть «Куплен»).' -ForegroundColor DarkGray
Write-Host '  Чтобы не слетало снова — сними галочку в настройках → Обновления.' -ForegroundColor DarkGray
