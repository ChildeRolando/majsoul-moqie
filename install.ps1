#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([string]$GameDirectory, [string]$LoaderArchive, [string]$PluginArchive)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$loaderHash = 'D5954A5993EC39CD1133603D85BFF93875D30B6411B712CC13DCF03C8E08A4D3'
$packageHash = '16E809D044EDE9E3ADBAAF5043E3A27EBA0805D5354990503431E46A439A5D5D'
$dllHash = '6DDD98C1643A42D0AE8D448929556177A236091144D4764C60E6B2D85B96E78D'
$loaderUrl = 'https://builds.bepinex.dev/projects/bepinex_be/788/BepInEx-Unity.IL2CPP-win-x86-6.0.0-be.788%2B5b766a3.zip'
$assetName = 'native-tsumogiri-0.3.0-release.zip'

function Find-Game {
    $roots = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $value = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($value) {
            foreach ($name in @('SteamPath', 'InstallPath')) {
                if ($value.PSObject.Properties[$name]) { $roots += $value.$name }
            }
        }
    }
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    $libraries = @($roots)
    foreach ($root in $roots) {
        $vdf = Join-Path $root 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    foreach ($library in ($libraries | Select-Object -Unique)) {
        $manifest = Join-Path $library 'steamapps/appmanifest_1329410.acf'
        if (Test-Path -LiteralPath $manifest) {
            $match = [regex]::Match([IO.File]::ReadAllText($manifest), '"installdir"\s+"([^"]+)"')
            if ($match.Success) {
                $candidate = Join-Path $library ('steamapps/common/' + $match.Groups[1].Value)
                if (Test-Path -LiteralPath (Join-Path $candidate 'Jantama_MahjongSoul.exe')) { $candidate }
            }
        }
    }
}
function Assert-Hash([string]$Path, [string]$Expected) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) { throw "Checksum mismatch: $Path" }
}
function Assert-Stopped {
    if (Get-Process -Name 'Jantama_MahjongSoul' -ErrorAction SilentlyContinue) { throw 'Exit Mahjong Soul, including its exit confirmation, before installing.' }
}
function Expand-Checked([string]$Zip, [string]$Destination) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $prefix = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
        foreach ($entry in $archive.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe ZIP entry.' }
        }
    } finally { $archive.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Destination)
}

if (-not $GameDirectory) {
    $found = @(Find-Game | Select-Object -Unique)
    if ($found.Count -ne 1) { throw 'Could not select one Steam installation. Specify -GameDirectory "D:\SteamLibrary\steamapps\common\MahjongSoul".' }
    $GameDirectory = $found[0]
}
$GameDirectory = (Resolve-Path -LiteralPath $GameDirectory).Path
$exe = Join-Path $GameDirectory 'Jantama_MahjongSoul.exe'
foreach ($required in @($exe, (Join-Path $GameDirectory 'GameAssembly.dll'), (Join-Path $GameDirectory 'Jantama_MahjongSoul_Data'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Not a supported IL2CPP game directory: $required" }
}
$reader = [IO.BinaryReader]::new([IO.File]::OpenRead($exe))
try {
    if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Invalid game executable.' }
    $reader.BaseStream.Position = 0x3c
    $offset = $reader.ReadInt32()
    $reader.BaseStream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x14c) { throw 'Only the tested Windows x86 client is supported.' }
} finally { $reader.Dispose() }
Assert-Stopped
if (-not $PSCmdlet.ShouldProcess($GameDirectory, 'Install verified BepInEx 788 and native tsumogiri plugin')) { return }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$work = Join-Path ([IO.Path]::GetTempPath()) ('majsoul-moqie-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Write-Host "Game: $GameDirectory"
Write-Host "Downloads and diagnostics: $work"
if (-not $LoaderArchive) {
    $LoaderArchive = Join-Path $work 'bepinex.zip'
    Write-Host 'Downloading BepInEx IL2CPP x86 build 788...'
    Invoke-WebRequest -Uri $loaderUrl -OutFile $LoaderArchive -UseBasicParsing -TimeoutSec 120
}
if (-not $PluginArchive) {
    $PluginArchive = Join-Path $PSScriptRoot $assetName
    if (-not (Test-Path -LiteralPath $PluginArchive)) {
        $PluginArchive = Join-Path $PSScriptRoot ('dist/' + $assetName)
    }
    if (-not (Test-Path -LiteralPath $PluginArchive)) {
        $PluginArchive = Join-Path $work $assetName
        Invoke-WebRequest -Uri ('https://github.com/ChildeRolando/majsoul_moqie/releases/download/v0.3.0/' + $assetName) -OutFile $PluginArchive -UseBasicParsing -TimeoutSec 120
    }
}
Assert-Hash $LoaderArchive $loaderHash
Assert-Hash $PluginArchive $packageHash
$loader = Join-Path $work 'loader'
$plugin = Join-Path $work 'plugin'
Expand-Checked $LoaderArchive $loader
Expand-Checked $PluginArchive $plugin
$relativeDll = 'BepInEx/plugins/NativeTsumogiri/MahjongSoulNative.dll'
Assert-Hash (Join-Path $plugin $relativeDll) $dllHash
$files = @(Get-ChildItem -LiteralPath $loader -Recurse -File)
$plan = @()
foreach ($file in $files) {
    $relative = $file.FullName.Substring($loader.Length + 1)
    $target = Join-Path $GameDirectory $relative
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
            throw "Existing loader file differs; nothing installed. Resolve this BepInEx conflict manually: $target"
        }
    } else { $plan += @{ Source = $file.FullName; Target = $target } }
}
# Refuse unrelated or partially installed loaders before creating any game files.
if (($plan.Count -eq $files.Count) -and (Test-Path -LiteralPath (Join-Path $GameDirectory 'BepInEx/core'))) { throw 'Unknown existing BepInEx loader; nothing installed.' }
$destination = Join-Path $GameDirectory $relativeDll
$backup = $null
if ((Test-Path -LiteralPath $destination) -and ((Get-FileHash -LiteralPath $destination).Hash -ne $dllHash)) {
    $backup = Join-Path $work 'previous-MahjongSoulNative.dll'
    Copy-Item -LiteralPath $destination -Destination $backup
}
$created = [Collections.Generic.List[string]]::new()
$pluginWasPresent = Test-Path -LiteralPath $destination
Assert-Stopped
try {
    foreach ($item in $plan) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $item.Target) -Force | Out-Null
        if (Test-Path -LiteralPath $item.Target) { throw 'Game files changed during installation; rerun after checking.' }
        $created.Add($item.Target)
        Copy-Item -LiteralPath $item.Source -Destination $item.Target
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $plugin $relativeDll) -Destination $destination -Force
    Assert-Hash $destination $dllHash
} catch {
    foreach ($path in $created) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
    if ($backup) { Copy-Item -LiteralPath $backup -Destination $destination -Force }
    elseif (-not $pluginWasPresent -and (Test-Path -LiteralPath $destination)) { Remove-Item -LiteralPath $destination -Force }
    throw
}
Write-Host 'Installed. Start Mahjong Soul normally. F8 toggles the plugin; existing settings are preserved.'
if ($backup) { Write-Host "Previous plugin backup: $backup" }
# Keep the bounded temporary directory for download reuse and failure diagnosis.
