#requires -Version 5.1
param([Parameter(Mandatory)][string]$LoaderArchive, [Parameter(Mandatory)][string]$PluginArchive)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:TEMP ('majsoul-entrypoints-' + [guid]::NewGuid().ToString('N'))
function New-Game([string]$Name) {
    $directory = Join-Path $work $Name
    New-Item -ItemType Directory -Path (Join-Path $directory 'Jantama_MahjongSoul_Data') -Force | Out-Null
    $bytes = New-Object byte[] 128
    $bytes[0] = 0x4d; $bytes[1] = 0x5a; $bytes[0x3c] = 0x40
    $bytes[0x40] = 0x50; $bytes[0x41] = 0x45; $bytes[0x44] = 0x4c; $bytes[0x45] = 0x01
    [IO.File]::WriteAllBytes((Join-Path $directory 'Jantama_MahjongSoul.exe'), $bytes)
    [IO.File]::WriteAllBytes((Join-Path $directory 'GameAssembly.dll'), [byte[]]@(0))
    return $directory
}
function Assert-Installed([string]$Game) {
    $file = Join-Path $Game 'BepInEx/plugins/NativeTsumogiri/MahjongSoulNative.dll'
    if ((Get-FileHash -LiteralPath $file).Hash -ne '6DDD98C1643A42D0AE8D448929556177A236091144D4764C60E6B2D85B96E78D') { throw 'Installed DLL differs.' }
}
# ScriptBlock.Create has no source directory, like the one-line remote command.
$remoteGame = New-Game 'remote block'
$body = [IO.File]::ReadAllText((Join-Path $root 'install.ps1'))
& ([scriptblock]::Create($body)) -GameDirectory $remoteGame -LoaderArchive $LoaderArchive
Assert-Installed $remoteGame
# Exercise argument forwarding (spaces and non-ASCII) and embedded script.
$exeGame = New-Game ('exe ' + [char]0x96c0)
$exe = Join-Path $root 'dist/majsoul_moqie-setup-0.3.0.exe'
& $exe -GameDirectory $exeGame -LoaderArchive $LoaderArchive -PluginArchive $PluginArchive
if ($LASTEXITCODE -ne 0) { throw 'EXE install failed.' }
Assert-Installed $exeGame
& $exe -GameDirectory $exeGame -WhatIf
if ($LASTEXITCODE -ne 0) { throw 'EXE preview failed.' }
$bad = Join-Path $work 'absent'
$start = [Diagnostics.ProcessStartInfo]::new($exe, ('-GameDirectory "' + $bad + '"'))
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$process = [Diagnostics.Process]::Start($start)
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()
try { if ($process.ExitCode -eq 0) { throw 'EXE did not propagate installer failure.' } }
finally { $process.Dispose() }
Write-Output "PASS: remote block without local assets, EXE install, argument quoting, WhatIf, error exit. Fixtures: $work"
$global:LASTEXITCODE = 0
