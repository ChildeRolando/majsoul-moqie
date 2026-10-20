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
$loaderConfig = Join-Path $game 'BepInEx/config/BepInEx.cfg'
if ([IO.File]::ReadAllText($loaderConfig) -notmatch '(?m)^Enabled = false\r?$') { throw 'Fresh install shows console' }
$config = Join-Path $game 'BepInEx/config/keep.cfg'
New-Item -ItemType Directory -Path (Split-Path -Parent $config) -Force | Out-Null
[IO.File]::WriteAllText($config, 'keep settings')
$other = Join-Path $game 'BepInEx/plugins/other.dll'
[IO.File]::WriteAllText($other, 'keep other plugin')
Run-Install $game $true
if ([IO.File]::ReadAllText($config) -ne 'keep settings' -or [IO.File]::ReadAllText($other) -ne 'keep other plugin') { throw 'Existing content changed' }
# Upgrade existing configs without changing disk logging or unrelated sections.
$f8Config = Join-Path $game 'BepInEx/config/local.mahjongsoul.native-tsumogiri.cfg'
[IO.File]::WriteAllText($f8Config, "[Display]`r`nEnabled = false`r`n")
foreach ($case in @(
    @{ Before = "[Logging.Disk]`r`nEnabled = true`r`n[Logging.Console]`r`n# Keep comment`r`nEnabled = true`r`nPreventClose = false`r`n[Other]`r`nEnabled = true`r`n"; After = "[Logging.Disk]`r`nEnabled = true`r`n[Logging.Console]`r`n# Keep comment`r`nEnabled = false`r`nPreventClose = false`r`n[Other]`r`nEnabled = true`r`n" },
    @{ Before = "[Logging.Disk]`nEnabled = false`n"; After = "[Logging.Disk]`nEnabled = false`n`r`n[Logging.Console]`r`nEnabled = false`r`n" },
    @{ Before = '[Logging.Console]'; After = "[Logging.Console]`r`nEnabled = false`r`n" },
    @{ Before = "[Logging.Console]`n# No setting yet`n[Logging.Disk]`nEnabled = true`n"; After = "[Logging.Console]`n# No setting yet`n`r`nEnabled = false`r`n[Logging.Disk]`nEnabled = true`n" }
)) {
    [IO.File]::WriteAllText($loaderConfig, $case.Before)
    Run-Install $game $true -Preview
    if ([IO.File]::ReadAllText($loaderConfig) -cne $case.Before) { throw 'WhatIf changed config' }
    Run-Install $game $true
    if ([IO.File]::ReadAllText($loaderConfig) -cne $case.After) { throw 'Config upgrade changed unrelated settings' }
    Run-Install $game $true
    if ([IO.File]::ReadAllText($loaderConfig) -cne $case.After) { throw 'Config update is not idempotent' }
}
if ([IO.File]::ReadAllText($f8Config) -cne "[Display]`r`nEnabled = false`r`n") { throw 'F8 setting changed' }
# A config write failure must roll back newly copied loader and plugin files.
$lockedGame = New-Game 'locked-config'
$lockedConfig = Join-Path $lockedGame 'BepInEx/config/BepInEx.cfg'
New-Item -ItemType Directory -Path (Split-Path -Parent $lockedConfig) -Force | Out-Null
[IO.File]::WriteAllText($lockedConfig, "[Logging.Console]`r`nEnabled = true`r`n")
$lockedBytes = [IO.File]::ReadAllBytes($lockedConfig)
$lock = [IO.File]::Open($lockedConfig, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try { Run-Install $lockedGame $false } finally { $lock.Dispose() }
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($lockedConfig)) -cne [Convert]::ToBase64String($lockedBytes)) { throw 'Failed install changed config' }
if ((Test-Path -LiteralPath (Join-Path $lockedGame 'winhttp.dll')) -or (Test-Path -LiteralPath (Join-Path $lockedGame 'BepInEx/plugins/NativeTsumogiri/MahjongSoulNative.dll'))) { throw 'Config failure did not roll back installed files' }
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
Write-Output "PASS: Windows PowerShell 5.1 fresh/repeat install, hidden console, preserved disk/F8/settings/plugins, config failure rollback, loader conflict, invalid hash, x64 guard, WhatIf. Fixtures: $root"
$global:LASTEXITCODE = 0
