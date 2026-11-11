param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $OutputDirectory){$OutputDirectory=Join-Path $env:TEMP ('chatgpt-titlesync-csharp-check-'+[Guid]::NewGuid().ToString('N'))}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if(-not(Test-Path -LiteralPath $csc)){throw '.NET Framework compiler was not found.'}
$fixture=Join-Path $OutputDirectory 'csharp-active-fixture.exe'
& $csc /nologo /target:exe /optimize+ /main:ChatGptTitle.ReleaseFixture "/out:$fixture" /reference:System.Web.Extensions.dll (Join-Path $root 'windows/csharp/TitleMonitor.cs') (Join-Path $PSScriptRoot 'tests/csharp_active_fixture.cs')
if($LASTEXITCODE){throw 'C# fixture compilation failed.'}
& $fixture
if($LASTEXITCODE){throw 'C# controlled three-layer checks failed.'}
