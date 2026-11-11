$ErrorActionPreference='Stop'
$oldLinker=$env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER
$oldLib=$env:LIB
$vsRoot='C:/Program Files (x86)/Microsoft Visual Studio/2019/BuildTools/VC/Tools/MSVC/14.29.30133'
$sdk='C:/Program Files (x86)/Windows Kits/10/Lib/10.0.19041.0'
Push-Location $PSScriptRoot
try{
 if(Test-Path -LiteralPath "$vsRoot/bin/Hostx64/x64/link.exe"){$env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER="$vsRoot/bin/Hostx64/x64/link.exe";$env:LIB="$vsRoot/lib/x64;$sdk/um/x64;$sdk/ucrt/x64"}
 & cargo test --offline;if($LASTEXITCODE){throw 'Tests failed'}
 & cargo build --release --offline;if($LASTEXITCODE){throw 'Build failed'}
}
finally{$env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER=$oldLinker;$env:LIB=$oldLib;Pop-Location}
