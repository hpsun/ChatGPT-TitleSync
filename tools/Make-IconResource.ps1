# Generates an x64 COFF icon resource using Windows PowerShell/.NET only.
# Resource layout references (Microsoft):
# https://learn.microsoft.com/windows/win32/menurc/resourceheader
# https://learn.microsoft.com/windows/win32/menurc/resource-file-formats
# https://learn.microsoft.com/windows/win32/menurc/newheader
# https://learn.microsoft.com/windows/win32/menurc/resdir
# https://learn.microsoft.com/windows/win32/debug/pe-format
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$IconPath,[Parameter(Mandatory=$true)][string]$OutputObject)
$ErrorActionPreference='Stop'
$icon=[IO.Path]::GetFullPath($IconPath);$output=[IO.Path]::GetFullPath($OutputObject)
if(-not [IO.File]::Exists($icon)){throw 'The baseline ICO file is missing.'}
$cvtres=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/cvtres.exe'
if(-not [IO.File]::Exists($cvtres)){throw 'Windows x64 icon builds require .NET Framework 4.x cvtres.exe under Windows/Microsoft.NET/Framework64/v4.0.30319.'}
[byte[]]$bytes=[IO.File]::ReadAllBytes($icon)
if($bytes.Length -lt 22 -or $bytes.Length -gt 16777216){throw 'ICO length is outside the supported bounded range.'}
$count=[BitConverter]::ToUInt16($bytes,4)
if([BitConverter]::ToUInt16($bytes,0) -ne 0 -or [BitConverter]::ToUInt16($bytes,2) -ne 1 -or $count -lt 1 -or $count -gt 256 -or 6+16*$count -gt $bytes.Length){throw 'Invalid bounded ICO directory.'}
$entries=@()
for($i=0;$i -lt $count;$i++){
 $position=6+16*$i;$length=[BitConverter]::ToUInt32($bytes,$position+8);$offset=[BitConverter]::ToUInt32($bytes,$position+12)
 if($length -eq 0 -or $offset -lt 6+16*$count -or ([uint64]$offset+[uint64]$length) -gt [uint64]$bytes.Length){throw 'ICO image data is out of bounds.'}
 $entries+=@{Position=$position;Length=$length;Offset=$offset;Id=$i+1}
}
$stream=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($stream)
function Add-IconResource([uint16]$Type,[uint16]$Id,[byte[]]$Data,[uint16]$Flags=0x1030){
 # Fixed ordinal header: 32 bytes including DataSize/HeaderSize. All entries align to DWORD.
 while(($stream.Position % 4) -ne 0){$writer.Write([byte]0)}
 $writer.Write([uint32]$Data.Length);$writer.Write([uint32]32)
 $writer.Write([uint16]65535);$writer.Write($Type);$writer.Write([uint16]65535);$writer.Write($Id)
 $writer.Write([uint32]0);$writer.Write($Flags);$writer.Write([uint16]0)
 $writer.Write([uint32]0);$writer.Write([uint32]0);$writer.Write($Data)
 while(($stream.Position % 4) -ne 0){$writer.Write([byte]0)}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('CTSIcon_'+[Guid]::NewGuid().ToString('N')+'.res')
try{
 Add-IconResource 0 0 ([byte[]]@()) 0
 foreach($entry in $entries){[byte[]]$frame=New-Object byte[] $entry.Length;[Array]::Copy($bytes,[long]$entry.Offset,$frame,0,[long]$entry.Length);Add-IconResource 3 $entry.Id $frame}
 $group=[IO.MemoryStream]::new();$groupWriter=[IO.BinaryWriter]::new($group)
 try{
  $groupWriter.Write([uint16]0);$groupWriter.Write([uint16]1);$groupWriter.Write([uint16]$count)
  foreach($entry in $entries){$groupWriter.Write($bytes,[int]$entry.Position,12);$groupWriter.Write([uint16]$entry.Id)}
  $groupWriter.Flush();[byte[]]$groupData=$group.ToArray()
 }finally{$groupWriter.Dispose();$group.Dispose()}
 Add-IconResource 14 1 $groupData
 $writer.Flush();[IO.File]::WriteAllBytes($temp,$stream.ToArray())
 $parent=[IO.Path]::GetDirectoryName($output);[void][IO.Directory]::CreateDirectory($parent)
 & $cvtres /NOLOGO /MACHINE:X64 "/OUT:$output" $temp
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($output)){throw "Windows resource conversion failed ($LASTEXITCODE)."}
 [byte[]]$coff=[IO.File]::ReadAllBytes($output)
 if($coff.Length -lt 20 -or [BitConverter]::ToUInt16($coff,0) -ne 0x8664 -or [BitConverter]::ToUInt16($coff,16) -ne 0){throw 'cvtres did not produce a standard x64 COFF object.'}
 # COFF TimeDateStamp is at offset 4. Zero denotes no meaningful timestamp and makes resource output reproducible.
 for($i=4;$i -lt 8;$i++){$coff[$i]=0}
 # cvtres adds a discardable CodeView section containing its temporary input path.
 # Remove its data using standard COFF section/symbol fields, preserving resource relocations.
 $sections=[BitConverter]::ToUInt16($coff,2);$symbolOffset=[BitConverter]::ToUInt32($coff,8);$symbols=[BitConverter]::ToUInt32($coff,12)
 if(20+40*$sections -gt $coff.Length -or ([uint64]$symbolOffset+18*[uint64]$symbols) -gt [uint64]$coff.Length){throw 'COFF section/symbol bounds are invalid.'}
 for($section=0;$section -lt $sections;$section++){
  $header=20+40*$section;$name=[Text.Encoding]::ASCII.GetString($coff,$header,8).TrimEnd([char]0)
  if($name.StartsWith('.debug',[StringComparison]::Ordinal)){
   $size=[BitConverter]::ToUInt32($coff,$header+16);$raw=[BitConverter]::ToUInt32($coff,$header+20)
   if(([uint64]$raw+[uint64]$size) -gt [uint64]$coff.Length){throw 'COFF debug section is out of bounds.'}
   [Array]::Clear($coff,[int]$raw,[int]$size);[Array]::Clear($coff,$header+16,8)
   $flags=[BitConverter]::ToUInt32($coff,$header+36) -bor 0x800
   [Array]::Copy([BitConverter]::GetBytes([uint32]$flags),0,$coff,$header+36,4)
   for($symbol=0;$symbol -lt $symbols;){
    $pos=[int]$symbolOffset+18*$symbol;$aux=[int]$coff[$pos+17]
    if($symbol+1+$aux -gt $symbols){throw 'COFF auxiliary symbol is out of bounds.'}
    if([BitConverter]::ToInt16($coff,$pos+12) -eq $section+1 -and $coff[$pos+16] -eq 3 -and $aux -gt 0){[Array]::Clear($coff,$pos+18,4)}
    $symbol+=1+$aux
   }
  }
 }
 # Go's internal COFF linker rejects cvtres's unreferenced absolute compiler metadata
 # (@comp.id/@feat.00). Keep section/data symbols and remap every relocation index.
 $mapping=[Collections.Generic.Dictionary[uint32,uint32]]::new();$symbolStream=[IO.MemoryStream]::new();$symbolWriter=[IO.BinaryWriter]::new($symbolStream)
 try{
  $next=[uint32]0
  for($index=[uint32]0;$index -lt $symbols;){
   $pos=[int]$symbolOffset+18*[int]$index;$aux=[int]$coff[$pos+17];$length=18*(1+$aux)
   if($index+1+$aux -gt $symbols){throw 'COFF symbol group is out of bounds.'}
   $sectionNumber=[BitConverter]::ToInt16($coff,$pos+12)
   if($sectionNumber -ge 0){
    for($j=0;$j -le $aux;$j++){$mapping[[uint32]($index+$j)]=[uint32]($next+$j)}
    $symbolWriter.Write($coff,$pos,$length);$next+=[uint32](1+$aux)
   }
   $index+=[uint32](1+$aux)
  }
  $symbolWriter.Flush();[byte[]]$keptSymbols=$symbolStream.ToArray()
 }finally{$symbolWriter.Dispose();$symbolStream.Dispose()}
 for($section=0;$section -lt $sections;$section++){
  $header=20+40*$section;$relocations=[BitConverter]::ToUInt32($coff,$header+24);$countRelocations=[BitConverter]::ToUInt16($coff,$header+32)
  if(([uint64]$relocations+10*[uint64]$countRelocations) -gt [uint64]$symbolOffset){throw 'COFF relocation table is out of bounds.'}
  for($i=0;$i -lt $countRelocations;$i++){
   $pos=[int]$relocations+10*$i+4;$oldIndex=[BitConverter]::ToUInt32($coff,$pos);$newIndex=[uint32]0
   if(-not $mapping.TryGetValue($oldIndex,[ref]$newIndex)){throw 'A resource relocation unexpectedly references removed compiler metadata.'}
   [Array]::Copy([BitConverter]::GetBytes($newIndex),0,$coff,$pos,4)
  }
 }
 $stringOffset=[int]$symbolOffset+18*[int]$symbols
 if($stringOffset+4 -gt $coff.Length){throw 'COFF string table is missing.'}
 $stringLength=[BitConverter]::ToUInt32($coff,$stringOffset)
 # cvtres emits four zero bytes for an empty table; canonical COFF length includes this DWORD.
 if($stringLength -eq 0 -and $stringOffset+4 -eq $coff.Length){$stringLength=[uint32]4;[Array]::Copy([BitConverter]::GetBytes($stringLength),0,$coff,$stringOffset,4)}
 if($stringLength -lt 4 -or [uint64]$stringOffset+[uint64]$stringLength -ne [uint64]$coff.Length){throw 'COFF string table bounds are invalid.'}
 [byte[]]$normalized=New-Object byte[] ([int]$symbolOffset+$keptSymbols.Length+[int]$stringLength)
 [Array]::Copy($coff,0,$normalized,0,[int]$symbolOffset);[Array]::Copy($keptSymbols,0,$normalized,[int]$symbolOffset,$keptSymbols.Length);[Array]::Copy($coff,$stringOffset,$normalized,[int]$symbolOffset+$keptSymbols.Length,[int]$stringLength)
 [Array]::Copy([BitConverter]::GetBytes([uint32]$next),0,$normalized,12,4)
 [IO.File]::WriteAllBytes($output,$normalized)
 [pscustomobject]@{Object=$output;Frames=[int]$count;GroupIconId=1;Machine='x64';CoffTimestamp=0}|ConvertTo-Json -Compress
}finally{
 $writer.Dispose();$stream.Dispose()
 if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
}
