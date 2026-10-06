#requires -Version 5.1
param([Parameter(Mandatory)][string]$LoaderArchive, [Parameter(Mandatory)][string]$PluginArchive)
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install.ps1'
$root = Join-Path $env:TEMP ('majsoul-install-test-' + [guid]::NewGuid().ToString('N'))
function New-Game([string]$Name, [int]$Machine = 0x14c) {
    $path = Join-Path $root $Name
    New-Item -ItemType Directory -Path (Join-Path $path 'Jantama_MahjongSoul_Data') -Force | Out-Null
    $bytes = New-Object byte[] 128
    $bytes[0] = 0x4d; $bytes[1] = 0x5a; $bytes[0x3c] = 0x40
    $bytes[0x40] = 0x50; $bytes[0x41] = 0x45
    [BitConverter]::GetBytes([uint16]$Machine).CopyTo($bytes, 0x44)
    [IO.File]::WriteAllBytes((Join-Path $path 'Jantama_MahjongSoul.exe'), $bytes)
    [IO.File]::WriteAllBytes((Join-Path $path 'GameAssembly.dll'), [byte[]]@(0))
    return $path
}
function Run-Install([string]$Game, [bool]$Success, [string]$Package = $PluginArchive, [switch]$Preview) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-GameDirectory', $Game, '-LoaderArchive', $LoaderArchive, '-PluginArchive', $Package)
    if ($Preview) { $arguments += '-WhatIf' }
    $output = & powershell.exe @arguments 2>&1
    if (($LASTEXITCODE -eq 0) -ne $Success) { throw "Unexpected installation result: $output" }
}
$game = New-Game 'fresh'
Run-Install $game $true -Preview
if (Test-Path -LiteralPath (Join-Path $game 'BepInEx')) { throw 'WhatIf wrote game files' }
Run-Install $game $true
$dll = Join-Path $game 'BepInEx/plugins/NativeTsumogiri/MahjongSoulNative.dll'
if ((Get-FileHash -LiteralPath $dll).Hash -ne '6DDD98C1643A42D0AE8D448929556177A236091144D4764C60E6B2D85B96E78D') { throw 'DLL mismatch' }
$config = Join-Path $game 'BepInEx/config/keep.cfg'
New-Item -ItemType Directory -Path (Split-Path -Parent $config) -Force | Out-Null
[IO.File]::WriteAllText($config, 'keep settings')
$other = Join-Path $game 'BepInEx/plugins/other.dll'
[IO.File]::WriteAllText($other, 'keep other plugin')
Run-Install $game $true
if ([IO.File]::ReadAllText($config) -ne 'keep settings' -or [IO.File]::ReadAllText($other) -ne 'keep other plugin') { throw 'Existing content changed' }
# A loader conflict must prevent replacement of the existing plugin.
[IO.File]::WriteAllText((Join-Path $game 'winhttp.dll'), 'different loader')
[IO.File]::WriteAllText($dll, 'previous plugin')
Run-Install $game $false
if ([IO.File]::ReadAllText($dll) -ne 'previous plugin') { throw 'Conflict changed plugin' }
$invalid = New-Game 'bad-hash'
$bad = Join-Path $root 'bad.zip'
[IO.File]::WriteAllText($bad, 'corrupt package')
Run-Install $invalid $false $bad
if (Test-Path -LiteralPath (Join-Path $invalid 'BepInEx')) { throw 'Invalid package wrote game files' }
$x64 = New-Game 'x64' 0x8664
Run-Install $x64 $false
if (Test-Path -LiteralPath (Join-Path $x64 'BepInEx')) { throw 'x64 client modified' }
Write-Output "PASS: Windows PowerShell 5.1 fresh install, repeat install, preserved settings/plugins, loader conflict, invalid hash, x64 guard, WhatIf. Fixtures: $root"
$global:LASTEXITCODE = 0
