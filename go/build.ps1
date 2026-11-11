param([string]$GoExe)
$ErrorActionPreference='Stop'
if(-not $GoExe){$found=Get-Command go -ErrorAction SilentlyContinue;if($found){$GoExe=$found.Source}else{throw 'Go SDK not found; install Go or supply -GoExe with its executable path.'}}
if(-not(Test-Path -LiteralPath $GoExe)){throw 'Go SDK not found; supply -GoExe.'}
Push-Location $PSScriptRoot
$old=$env:GOTOOLCHAIN;$resource=$null;$resourceCreated=$false
try{
 $env:GOTOOLCHAIN='local'
 $targetOs=(& $GoExe env GOOS).Trim();if($LASTEXITCODE){throw 'Unable to determine Go target OS.'}
 $targetArch=(& $GoExe env GOARCH).Trim();if($LASTEXITCODE){throw 'Unable to determine Go target architecture.'}
 if($targetOs -eq 'windows'){
  if($targetArch -ne 'amd64'){throw 'The Windows native implementation and icon build support x64 only.'}
  # A stable temporary basename keeps the Go build ID reproducible. CreateNew refuses concurrent/stale outputs.
  $resource=Join-Path $PSScriptRoot 'zz_baseline45_windows_amd64.syso'
  $reservation=[IO.File]::Open($resource,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$reservation.Dispose();$resourceCreated=$true
  & (Join-Path $PSScriptRoot '../tools/Make-IconResource.ps1') -IconPath (Join-Path $PSScriptRoot '../assets/chatgpt-titlesync.ico') -OutputObject $resource
 }
 & $GoExe test .;if($LASTEXITCODE){throw 'Tests failed'}
 & $GoExe build -trimpath -ldflags="-H=windowsgui" -o (Join-Path $PSScriptRoot 'chatgpt-titlesync-go.exe') .;if($LASTEXITCODE){throw 'Build failed'}
}
finally{
 if($resourceCreated -and $resource -and [IO.File]::Exists($resource)){[IO.File]::Delete($resource)}
 $env:GOTOOLCHAIN=$old;Pop-Location
}
