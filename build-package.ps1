param([string]$Tag = 'release', [string]$PluginPath)
$ErrorActionPreference = 'Stop'
if ($Tag -notmatch '^[a-z0-9-]+$') { throw 'Use a short lowercase package tag.' }
$plugin = if ($PluginPath) { (Resolve-Path -LiteralPath $PluginPath).Path } else { Join-Path $PSScriptRoot 'src/bin/Release/net6.0/MahjongSoulNative.dll' }
if (-not (Test-Path -LiteralPath $plugin)) { throw 'Build the plugin first.' }
$artifactRoot = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$name = "native-tsumogiri-0.3.1-$Tag"
$zip = Join-Path $artifactRoot "$name.zip"
if (Test-Path -LiteralPath $zip) { throw 'Package already exists. Use a fresh tag; do not overwrite an acceptance target.' }
$currentBuild = @{
   steamBuild = '26802421';
   viewPaiOriginalSha256 = '9ca196d20456c0c6bed438cdf7b4da6d02f3deed491151c011f71bca1db821ca';
   blockQiPaiOriginalSha256 = '44d2f901f9016679c5d8eb99d5beacab661d7ee5fa76b5f18a264807214d635d'
}
$previousBuild = @{
   steamBuild = '25476613';
   viewPaiOriginalSha256 = 'af97809905789b695fdd34d0415aa1d5eaa78240c48bd2d7b20f4e555b9b1d94';
   blockQiPaiOriginalSha256 = 'd3c456d82d76de6b61b0a6e1fb983913205bf415dcb23bc421fa54c40ae6e5cc'
}
$manifest = @{ version = '0.3.1'; patchVersion = 'native-v1';
   pluginSha256 = (Get-FileHash -LiteralPath $plugin).Hash;
   viewPaiOriginalSha256 = $currentBuild.viewPaiOriginalSha256;
   blockQiPaiOriginalSha256 = $currentBuild.blockQiPaiOriginalSha256;
   verifiedSteamBuilds = @($currentBuild, $previousBuild)
} | ConvertTo-Json -Depth 4
Add-Type -AssemblyName System.IO.Compression
$output = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
$archive = [System.IO.Compression.ZipArchive]::new($output, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($item in @(
        @{ Name = 'BepInEx/plugins/NativeTsumogiri/MahjongSoulNative.dll'; Path = $plugin },
        @{ Name = 'README.zh-CN.md'; Path = (Join-Path $PSScriptRoot 'README.md') }
    )) {
        $entry = $archive.CreateEntry($item.Name)
        $target = $entry.Open()
        $input = [System.IO.File]::OpenRead($item.Path)
        try { $input.CopyTo($target) } finally { $input.Dispose(); $target.Dispose() }
    }
    $target = $archive.CreateEntry('manifest.json').Open()
    try { $bytes = [System.Text.Encoding]::UTF8.GetBytes($manifest); $target.Write($bytes, 0, $bytes.Length) } finally { $target.Dispose() }
} finally { $archive.Dispose(); $output.Dispose() }
Get-FileHash -LiteralPath $zip
Write-Output $zip
