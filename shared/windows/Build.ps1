param([string]$OutputDirectory=$PSScriptRoot)
$ErrorActionPreference='Stop'
# Compile the shared editor/Unicode formatter only; do not run it or create preferences.
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(!(Test-Path -LiteralPath $csc)){throw '.NET Framework 4.x compiler was not found.'}
$source=Join-Path $PSScriptRoot 'TitleRules.cs'
$icon=Join-Path $PSScriptRoot '..\..\assets\chatgpt-titlesync.ico'
$output=Join-Path $OutputDirectory 'ChatGPT-TitleSync.Rules.exe'
& $csc /nologo /target:winexe /platform:anycpu /optimize+ "/out:$output" "/win32icon:$icon" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll $source
if($LASTEXITCODE -ne 0){throw 'Name replacement companion build failed.'}
Get-FileHash -LiteralPath $output -Algorithm SHA256
