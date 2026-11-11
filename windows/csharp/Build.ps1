param([string]$OutputDirectory=$PSScriptRoot)
$ErrorActionPreference='Stop'
$base=$PSScriptRoot
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(!(Test-Path -LiteralPath $csc)){throw '.NET Framework 4.x compiler was not found.'}
$wpf=Join-Path (Split-Path -Parent $csc) 'WPF'
$icon=Join-Path $base '..\..\assets\chatgpt-titlesync.ico'
& $csc /nologo /target:winexe /platform:anycpu /optimize+ "/out:$(Join-Path $OutputDirectory 'ChatGPT-TitleSync.exe')" "/win32icon:$icon" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll (Join-Path $base 'App.cs') (Join-Path $base 'TitleMonitor.cs')
if($LASTEXITCODE -ne 0){throw 'Application build failed.'}
& $csc /nologo /target:winexe /platform:anycpu /optimize+ "/out:$(Join-Path $OutputDirectory 'ChatGPT-TitleSync.Reader.exe')" /reference:System.Web.Extensions.dll "/reference:$(Join-Path $wpf 'UIAutomationClient.dll')" "/reference:$(Join-Path $wpf 'UIAutomationTypes.dll')" "/reference:$(Join-Path $wpf 'WindowsBase.dll')" (Join-Path $base 'TitleReader.cs')
if($LASTEXITCODE -ne 0){throw 'UIA reader build failed.'}
Get-FileHash -LiteralPath (Join-Path $OutputDirectory 'ChatGPT-TitleSync.exe'),(Join-Path $OutputDirectory 'ChatGPT-TitleSync.Reader.exe')
