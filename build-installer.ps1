#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework 4 compiler is required.' }
$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$output = Join-Path $dist 'majsoul_moqie-setup-0.3.0.exe'
& $compiler /nologo /target:exe /platform:anycpu /optimize+ ("/out:" + $output) ("/resource:" + (Join-Path $PSScriptRoot 'install.ps1') + ',install.ps1') (Join-Path $PSScriptRoot 'installer/Program.cs')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Get-FileHash -LiteralPath $output -Algorithm SHA256
