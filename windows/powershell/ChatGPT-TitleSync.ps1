#requires -Version 5.1
[CmdletBinding()]
param([ValidateRange(1,3600)][Alias("interval")][int]$IntervalSeconds=2,
 [ValidateRange(1000,15000)][int]$ReaderTimeoutMilliseconds=6000,
 [ValidateRange(5,3600)][Alias("background-interval")][int]$BackgroundIntervalSeconds=5,
 [switch]$ReadOnly,[switch]$Once,[switch]$Stop,[switch]$Settings,[switch]$Worker,[switch]$BackgroundWorker,
 [long]$Hwnd=0,[string]$Output,
 [string]$LogDirectory=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ChatGPT-title'))
$ErrorActionPreference='Stop'
$scriptPath=$PSCommandPath
# Preserve legacy storage and singleton/event identities so upgrades reuse settings and exclude old writers.
$mutexName='Local\TdxChatGptTitleStandalone';$eventName=$mutexName+'.Stop'
if($Settings){try{$e=[Threading.EventWaitHandle]::OpenExisting($mutexName+'.Settings');try{[void]$e.Set()}finally{$e.Dispose()}}catch [Threading.WaitHandleCannotBeOpenedException]{throw 'No compatible resident monitor is running.'};return}
if($Stop){try{$e=[Threading.EventWaitHandle]::OpenExisting($eventName);try{[void]$e.Set()}finally{$e.Dispose()}}catch [Threading.WaitHandleCannotBeOpenedException]{};return}
# Win32 declarations are compiled in memory; the script needs no external EXE.
if(!('CgtNative' -as [type])){
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Diagnostics; using System.IO;
using System.Runtime.InteropServices; using System.Collections.Generic;
public sealed class CgtWindow {
 public long Hwnd;public int Pid;public string Born,ClassName,Path;
 public string Key{get{return Hwnd+"|"+Pid+"|"+Born+"|"+ClassName+"|"+Path.ToUpperInvariant();}}
}
public static class CgtNative {
 delegate bool WindowCallback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")]static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int width,int height,uint flags);
 // Explicit visibility bypasses the first-show STARTUPINFO hint; activation is handled by the UI caller.
 public static bool ShowSettingsWindow(long h){return SetWindowPos(new IntPtr(h),IntPtr.Zero,0,0,0,0,0x0040|0x0001|0x0002|0x0004|0x0010);}

 [DllImport("user32.dll")]static extern bool EnumWindows(WindowCallback cb,IntPtr p);
 [DllImport("user32.dll")]static extern IntPtr GetForegroundWindow();
 [DllImport("kernel32.dll")]static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
 [DllImport("user32.dll")]static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")]static extern IntPtr GetAncestor(IntPtr h,uint flags);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr w,string s,uint f,uint t,out UIntPtr r);
 public static string Class(long h){var c=new StringBuilder(256);GetClassName(new IntPtr(h),c,256);return c.ToString();}
 public static CgtWindow Capture(long h){
  if(!IsWindow(new IntPtr(h))||GetAncestor(new IntPtr(h),2)!=new IntPtr(h))return null;uint pid;GetWindowThreadProcessId(new IntPtr(h),out pid);
  IntPtr process=OpenProcess(0x1000,false,pid);if(process==IntPtr.Zero)return null;
  try{long born,exited,kernel,user;if(!GetProcessTimes(process,out born,out exited,out kernel,out user))return null;var path=new StringBuilder(32768);int n=path.Capacity;if(!QueryFullProcessImageName(process,0,path,ref n))return null;
  return new CgtWindow{Hwnd=h,Pid=(int)pid,Born=DateTime.FromFileTimeUtc(born).ToString("o"),ClassName=Class(h),Path=path.ToString()};}finally{CloseHandle(process);}
 }
 public static bool Same(CgtWindow w){try{var x=Capture(w.Hwnd);return x!=null&&x.Key==w.Key;}catch{return false;}}
 public static bool Target(CgtWindow w){return w!=null&&w.ClassName=="Chrome_WidgetWin_1"&&String.Equals(System.IO.Path.GetFileName(w.Path),"ChatGPT.exe",StringComparison.OrdinalIgnoreCase);}
 public static CgtWindow[] Windows(){try{var h=GetForegroundWindow();if(h==IntPtr.Zero||!IsWindowVisible(h)||Class(h.ToInt64())!="Chrome_WidgetWin_1")return new CgtWindow[0];var w=Capture(h.ToInt64());return Target(w)?new[]{w}:new CgtWindow[0];}catch{return new CgtWindow[0];}}
 public static CgtWindow[] AllWindows(){var result=new List<CgtWindow>();EnumWindows(delegate(IntPtr h,IntPtr p){try{if(IsWindowVisible(h)&&Class(h.ToInt64())=="Chrome_WidgetWin_1"){var w=Capture(h.ToInt64());if(Target(w))result.Add(w);}}catch{}return true;},IntPtr.Zero);return result.ToArray();}
 public static bool SetInactive(CgtWindow w,string expected,string desired){if(Active(w))return false;bool ok=Set(w,expected,desired);if(Active(w)){if(ok)Set(w,desired,expected);return false;}return ok;}
 public static bool Active(CgtWindow w){return w!=null&&GetForegroundWindow()==new IntPtr(w.Hwnd)&&Same(w);}
 public static bool SetFocused(CgtWindow w,string expected,string desired){if(!Active(w))return false;bool ok=Set(w,expected,desired,true);if(!Active(w)){if(ok)Set(w,desired,expected);return false;}return ok;}
 public static string Caption(CgtWindow w){if(!Same(w))return null;var b=new StringBuilder(2048);GetWindowText(new IntPtr(w.Hwnd),b,b.Capacity);return b.ToString();}
 public static bool Set(CgtWindow w,string expected,string desired,bool active=false){
  if(desired==null||desired.Length>1024||!Same(w)||Caption(w)!=expected)return false;
  if(active&&!Active(w))return false;UIntPtr r;var ok=SendMessageTimeout(new IntPtr(w.Hwnd),12,UIntPtr.Zero,desired,0x23,300,out r);
  return ok!=IntPtr.Zero&&r!=UIntPtr.Zero&&Same(w)&&Caption(w)==desired;
 }

 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr h,out long born,out long exited,out long kernel,out long user);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr h,uint flags,StringBuilder path,ref int length);
 [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h,uint milliseconds);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateProcess(IntPtr h,uint code);

 [DllImport("kernel32.dll",EntryPoint="CreateFileW",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenImageFile(string path,uint access,uint share,IntPtr security,uint disposition,uint flags,IntPtr template);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(IntPtr h,StringBuilder path,uint capacity,uint flags);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 public static string CanonicalImage(string path){
  IntPtr file=OpenImageFile(path,0,7,IntPtr.Zero,3,0,IntPtr.Zero);
  if(file==new IntPtr(-1))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  try{var name=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(file,name,(uint)name.Capacity,0);
   if(n==0||n>=name.Capacity)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   string value=name.ToString();if(value.StartsWith(@"\\?\UNC\",StringComparison.OrdinalIgnoreCase))return @"\\"+value.Substring(8);
   return value.StartsWith(@"\\?\",StringComparison.Ordinal)?value.Substring(4):value;
  }finally{CloseHandle(file);}
 }
 public static string ChildImage(IntPtr h,out long born){
  long exited,kernel,user;
  if(!GetProcessTimes(h,out born,out exited,out kernel,out user))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  var path=new StringBuilder(32768);int length=path.Capacity;
  if(!QueryFullProcessImageName(h,0,path,ref length))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  return path.ToString();
 }
 public static uint WaitChild(IntPtr h,uint milliseconds){return WaitForSingleObject(h,milliseconds);}
 public static bool ChildExitedSuccessfully(IntPtr h){uint code;return GetExitCodeProcess(h,out code)&&code==0;}
 // h is retained exclusively from the Process object created by this invocation, never reopened by PID.
 public static void StopOwnedChild(IntPtr h){if(h!=IntPtr.Zero&&WaitForSingleObject(h,0)==258){TerminateProcess(h,1);WaitForSingleObject(h,1000);}}
}
// Shared five-value theme contract. Reads/plans are side-effect free; only a normal resident calls Commit.
namespace TitleSyncThemes {
 public sealed class ThemeChoice {
  public string Mode="fixed",Period="day",Slot="";public int FixedIcon=45,RandomIcon=45;
  public int Icon{get{return Mode=="random"?RandomIcon:FixedIcon;}}
  public ThemeChoice Copy(){return new ThemeChoice{Mode=Mode,Period=Period,Slot=Slot,FixedIcon=FixedIcon,RandomIcon=RandomIcon};}
 }
 public sealed class ThemeRegistryImage {
  internal readonly System.Collections.Generic.Dictionary<string,object[]> Values=new System.Collections.Generic.Dictionary<string,object[]>();internal ThemeChoice Choice;
 }
 public sealed class ThemeService {
  public const string PreferenceKey=@"Software\ChatGPT-TitleSync";
  static readonly string[] Names={"IconMode","FixedIcon","IconPeriod","RandomIcon","IconSlot"};
  readonly string keyPath;readonly System.Func<System.DateTimeOffset> clock;readonly System.Func<int,int> picker;readonly System.Action<int> validateAsset;readonly System.Action<string> beforeWrite;ThemeChoice current=new ThemeChoice();string failedSlot;
  public ThemeChoice Current{get{return current.Copy();}}
  public ThemeService(string path,System.Func<System.DateTimeOffset> now,System.Func<int,int> random,System.Action<int> validate,System.Action<string> fault){keyPath=path;clock=now;picker=random;validateAsset=validate;beforeWrite=fault;}
  public static void Validate(ThemeChoice value){if(value==null||(value.Mode!="fixed"&&value.Mode!="random")||(value.Period!="day"&&value.Period!="hour"&&value.Period!="5min")||value.FixedIcon<45||value.FixedIcon>52||value.RandomIcon<45||value.RandomIcon>52||value.Slot==null||!ValidSlot(value.Slot)||(value.Mode=="random"&&value.Slot.Length>0&&value.Slot.Length!=(value.Period=="day"?8:value.Period=="hour"?15:17)))throw new System.ArgumentException("Invalid icon theme preference.");}
  static bool ValidSlot(string value){if(value.Length==0)return true;if(value.Length!=8&&value.Length!=15&&value.Length!=17)return false;int digits=value.Length==8?8:value.Length-5;for(int i=0;i<digits;i++)if(value[i]<'0'||value[i]>'9')return false;System.DateTime date;if(!System.DateTime.TryParseExact(value.Substring(0,8),"yyyyMMdd",System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.None,out date))return false;if(value.Length==8)return true;if(value[digits]!='+'&&value[digits]!='-')return false;for(int i=digits+1;i<value.Length;i++)if(value[i]<'0'||value[i]>'9')return false;int hour=System.Int32.Parse(value.Substring(8,2)),offsetHour=System.Int32.Parse(value.Substring(digits+1,2)),offsetMinute=System.Int32.Parse(value.Substring(digits+3,2));return hour<24&&offsetHour<=14&&offsetMinute<60&&(offsetHour<14||offsetMinute==0)&&(value.Length!=17||System.Int32.Parse(value.Substring(10,2))<12);}
  static string ReadString(Microsoft.Win32.RegistryKey key,string name,string fallback){if(key==null||key.GetValue(name)==null)return fallback;if(key.GetValueKind(name)!=Microsoft.Win32.RegistryValueKind.String)throw new System.FormatException("Invalid icon preference type: "+name);return (string)key.GetValue(name);}
  static int ReadInt(Microsoft.Win32.RegistryKey key,string name,int fallback){if(key==null||key.GetValue(name)==null)return fallback;if(key.GetValueKind(name)!=Microsoft.Win32.RegistryValueKind.DWord||!(key.GetValue(name) is int))throw new System.FormatException("Invalid icon preference type: "+name);return (int)key.GetValue(name);}
  public void Load(){ThemeChoice loaded;using(var key=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(keyPath,false))loaded=new ThemeChoice{Mode=ReadString(key,"IconMode","fixed"),FixedIcon=ReadInt(key,"FixedIcon",45),Period=ReadString(key,"IconPeriod","day"),RandomIcon=ReadInt(key,"RandomIcon",45),Slot=ReadString(key,"IconSlot","")};Validate(loaded);current=loaded;failedSlot=null;}
  public static string SlotFor(string period,System.DateTimeOffset local){string stamp=local.ToString("yyyyMMddHH",System.Globalization.CultureInfo.InvariantCulture);if(period=="day")return local.ToString("yyyyMMdd",System.Globalization.CultureInfo.InvariantCulture);string offset=local.ToString("zzz",System.Globalization.CultureInfo.InvariantCulture).Replace(":","");if(period=="hour")return stamp+offset;if(period=="5min")return stamp+(local.Minute/5).ToString("00",System.Globalization.CultureInfo.InvariantCulture)+offset;throw new System.ArgumentException("Unknown icon random period.");}
  int PickOther(int previous){int index=picker(7);if(index<0||index>6)throw new System.InvalidOperationException("Icon random picker returned an invalid index.");int selected=45+index;if(selected>=previous)selected++;return selected;}
  public ThemeChoice Plan(string mode,int fixedIcon,string period){var choice=current.Copy();choice.Mode=mode;choice.FixedIcon=fixedIcon;choice.Period=period;if(mode=="random"&&(current.Mode!="random"||current.Period!=period))choice.Slot="";Validate(choice);if(mode=="random"){
    for(int id=45;id<=52;id++)validateAsset(id);string slot=SlotFor(period,clock());
    if(current.Mode!="random"||current.Period!=period||current.Slot!=slot){choice.RandomIcon=PickOther(current.Icon);choice.Slot=slot;}
   }else validateAsset(fixedIcon);return choice;}
  public ThemeChoice PlanTick(){if(current.Mode!="random")return null;string slot=SlotFor(current.Period,clock());if(current.Slot==slot||failedSlot==slot)return null;try{var choice=current.Copy();choice.RandomIcon=PickOther(current.Icon);choice.Slot=slot;validateAsset(choice.RandomIcon);return choice;}catch{failedSlot=slot;throw;}}
  public void MarkTickFailed(){if(current.Mode=="random")failedSlot=SlotFor(current.Period,clock());}
  public ThemeRegistryImage Capture(){var result=new ThemeRegistryImage{Choice=current.Copy()};using(var key=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(keyPath,false)){foreach(string name in Names){object value=key==null?null:key.GetValue(name,null,Microsoft.Win32.RegistryValueOptions.DoNotExpandEnvironmentNames);if(value!=null)result.Values[name]=new object[]{value,key.GetValueKind(name)};}}return result;}
  public void Restore(ThemeRegistryImage saved){using(var key=Microsoft.Win32.Registry.CurrentUser.CreateSubKey(keyPath)){if(key==null)throw new System.IO.IOException("Cannot restore icon preferences.");foreach(string name in Names){object[] value;if(saved.Values.TryGetValue(name,out value))key.SetValue(name,value[0],(Microsoft.Win32.RegistryValueKind)value[1]);else key.DeleteValue(name,false);}}current=saved.Choice.Copy();failedSlot=null;}
  static bool Same(Microsoft.Win32.RegistryKey key,string name,object value,Microsoft.Win32.RegistryValueKind kind){object old=key.GetValue(name);return old!=null&&key.GetValueKind(name)==kind&&old.Equals(value);}
  public void Commit(ThemeChoice choice){Validate(choice);var saved=Capture();try{using(var key=Microsoft.Win32.Registry.CurrentUser.CreateSubKey(keyPath)){if(key==null)throw new System.IO.IOException("Cannot save icon preferences.");object[] values={choice.Mode,choice.FixedIcon,choice.Period,choice.RandomIcon,choice.Slot};for(int index=0;index<Names.Length;index++){var kind=(index==1||index==3)?Microsoft.Win32.RegistryValueKind.DWord:Microsoft.Win32.RegistryValueKind.String;if(Same(key,Names[index],values[index],kind))continue;if(beforeWrite!=null)beforeWrite(Names[index]);key.SetValue(Names[index],values[index],kind);}}current=choice.Copy();failedSlot=null;}catch(System.Exception cause){try{Restore(saved);}catch(System.Exception rollback){throw new System.AggregateException("Icon preference save and rollback failed.",cause,rollback);}throw;}}
 }
}

'@
}
function Write-Result($path,$value){[IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $value -Depth 8 -Compress),[Text.UTF8Encoding]::new($false))}
function Test-CgtWorkerAllowed($w){return [CgtNative]::Same($w) -and ([CgtNative]::Active($w) -ne [bool]$BackgroundWorker)}
if($Worker){
 if(!$Output){throw 'Worker requires -Output'}
 $r=@{Success=$false;Hwnd=$Hwnd;Pid=0;Born=$null;ClassName=$null;Path=$null;Locator=$null;Title=$null;Error='Pending'}
 Write-Result $Output $r
 try{
  $identity=[CgtNative]::Capture($Hwnd)
  if(![CgtNative]::Target($identity) -or !(Test-CgtWorkerAllowed $identity)){throw 'UnexpectedTarget'}
  $r.Pid=$identity.Pid;$r.Born=$identity.Born;$r.ClassName=$identity.ClassName;$r.Path=$identity.Path
  Add-Type -AssemblyName UIAutomationClient;Add-Type -AssemblyName UIAutomationTypes
  $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
  $walker=[Windows.Automation.TreeWalker]::RawViewWalker
  $cache=[Windows.Automation.CacheRequest]::new();$cache.TreeScope=[Windows.Automation.TreeScope]::Element
  $cache.Add([Windows.Automation.AutomationElement]::ClassNameProperty)
  foreach($class in @('RootView','NonClientView','ChromeNodeFrameView','ChromeNodeClientView','View','Chrome_WidgetWin_1','Chrome_RenderWidgetHostHWND')){
   if(!(Test-CgtWorkerAllowed $identity)){throw 'FocusChanged'}
   $matches=@();$child=$walker.GetFirstChild($root,$cache);$count=0
   while($null -ne $child -and $count -lt 32){if(!(Test-CgtWorkerAllowed $identity)){throw 'FocusChanged'};if($child.Cached.ClassName -ceq $class){$matches+=,$child};$child=$walker.GetNextSibling($child,$cache);$count++}
   if($null -ne $child -or $matches.Count -ne 1){throw 'LocatorChanged'};$root=$matches[0]
  }
  $dc=[Windows.Automation.CacheRequest]::new();$dc.TreeScope=[Windows.Automation.TreeScope]::Element
  foreach($p in @([Windows.Automation.AutomationElement]::NameProperty,[Windows.Automation.AutomationElement]::AutomationIdProperty,[Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.AutomationElement]::IsPasswordProperty)){$dc.Add($p)}
  if(!(Test-CgtWorkerAllowed $identity)){throw 'FocusChanged'}
  $root=$root.GetUpdatedCache($dc);$docs=@()
  if($root.Cached.AutomationId -ceq 'RootWebArea' -and $root.Cached.ControlType -eq [Windows.Automation.ControlType]::Document){$docs+=,$root}
  else{
   $child=$walker.GetFirstChild($root,$dc);$count=0
   while($null -ne $child -and $count -lt 16){
    if(!(Test-CgtWorkerAllowed $identity)){throw 'FocusChanged'}
    if($child.Cached.AutomationId -ceq 'RootWebArea' -and $child.Cached.ControlType -eq [Windows.Automation.ControlType]::Document){$docs+=,$child}
    $child=$walker.GetNextSibling($child,$dc);$count++
   }
   if($null -ne $child){throw 'DocumentSiblingLimit'}
  }
  if($docs.Count -ne 1 -or $docs[0].Cached.IsPassword){throw 'DocumentUnavailable'}
  $title=$docs[0].Cached.Name
  if($null -eq $title -or $title.Length -gt 240 -or !(Test-CgtWorkerAllowed $identity) -or ![CgtNative]::Same($identity)){throw 'IdentityOrTitleChanged'}
  $r.Title=$title;$r.Locator="RawDirect/RootView/NonClientView/ChromeNodeFrameView/ChromeNodeClientView/View/Chrome_WidgetWin_1/Chrome_RenderWidgetHostHWND/Document[RootWebArea].Name";$r.Success=$true;$r.Error=$null
 }catch{$r.Error=$_.Exception.GetType().Name}
 Write-Result $Output $r;return
}
[void][IO.Directory]::CreateDirectory($LogDirectory)
function Write-Log($kind,$w,$code){
 try{$r=@{Utc=[DateTime]::UtcNow.ToString('o');Kind=$kind;Hwnd=$w.Hwnd;Pid=$w.Pid;Code=$code}
 [IO.File]::AppendAllText((Join-Path $LogDirectory 'powershell-events.jsonl'),($r|ConvertTo-Json -Compress)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))}catch{}
}
function Convert-CgtReaderJson([string]$json){if((Get-Command ConvertFrom-Json).Parameters.ContainsKey("DateKind")){return ConvertFrom-Json -InputObject $json -DateKind String};return ConvertFrom-Json -InputObject $json}
function Read-Title($w,$cancel){
 $file=Join-Path $LogDirectory ([Guid]::NewGuid().ToString('N')+'.reader.json')
 $child=$null;$ownedHandle=[IntPtr]::Zero;$clock=[Diagnostics.Stopwatch]::StartNew()
 try{
  $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $cmdArgs='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$scriptPath+'" -Worker -Hwnd '+$w.Hwnd+' -Output "'+$file+'"'
  $pi=[Diagnostics.ProcessStartInfo]::new($exe,$cmdArgs);$pi.UseShellExecute=$false;$pi.CreateNoWindow=$true
  $child=[Diagnostics.Process]::Start($pi);$ownedHandle=$child.Handle
  $born=0L;$image=[CgtNative]::ChildImage($ownedHandle,[ref]$born)
  if($born -le 0 -or ([CgtNative]::CanonicalImage($image)) -ine ([CgtNative]::CanonicalImage($exe))){return $null}
  do{
   $wait=[CgtNative]::WaitChild($ownedHandle,50)
   if($cancel.WaitOne(0) -or ![CgtNative]::Active($w) -or $clock.ElapsedMilliseconds -ge $ReaderTimeoutMilliseconds){return $null}
  }while($wait -eq 258)
  if($wait -ne 0 -or ![CgtNative]::ChildExitedSuccessfully($ownedHandle) -or !(Test-Path -LiteralPath $file)){return $null}
  if((Get-Item -LiteralPath $file).Length -gt 32768){return $null}
  $r=Convert-CgtReaderJson ([IO.File]::ReadAllText($file,[Text.Encoding]::UTF8))
  if(!$r.Success -or $r.Hwnd -ne $w.Hwnd -or $r.Pid -ne $w.Pid -or $r.Born -cne $w.Born -or $r.ClassName -cne $w.ClassName -or $r.Path -ine $w.Path -or $r.Locator -cne "RawDirect/RootView/NonClientView/ChromeNodeFrameView/ChromeNodeClientView/View/Chrome_WidgetWin_1/Chrome_RenderWidgetHostHWND/Document[RootWebArea].Name" -or ![CgtNative]::Active($w) -or ![CgtNative]::Same($w)){return $null}
  return $r
 }catch{return $null}
 finally{
  [CgtNative]::StopOwnedChild($ownedHandle)
  if($null -ne $child){$child.Dispose()}
  if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file}
 }
}
function Get-CgtNextDeadline([long]$previous,[long]$elapsed,[long]$interval){$next=$previous+$interval;while($next -lt $elapsed){$next+=$interval};return $next}
# One injectable pass is also used by isolated fake-foreground validation.
function Invoke-CgtActivePass($backend,$states,$cancel,[bool]$readOnly){
 $results=[Collections.Generic.List[object]]::new()
 foreach($w in @(& $backend.Targets)){
  if($cancel.WaitOne(0) -or !(& $backend.Active $w)){continue}
  $key=$w.Key;$now=[DateTime]::UtcNow
  if(!$states.ContainsKey($key)){$states[$key]=@{Window=$w;Original=$null;Last=$null;Retry=[DateTime]::MinValue}}
  $s=$states[$key];if($now -lt $s.Retry){continue}
  $current=& $backend.Caption $w;if($null -eq $current){continue}
  $generic=[string]::IsNullOrWhiteSpace($current) -or $current.Trim() -ieq 'ChatGPT'
  if($null -ne $s.Last -and $current -cne $s.Last -and !$generic){$s.Last=$null;$s.Original=$null;$s.Retry=$now.AddSeconds(30);& $backend.Log 'Skipped' $w 'ExternalCaptionChanged';continue}
  $r=& $backend.Read $w $cancel
  if($null -eq $r){if(& $backend.Active $w){$s.Retry=$now.AddSeconds(1);& $backend.Log 'Skipped' $w 'ReaderUnavailable'};continue}
  if($cancel.WaitOne(0) -or !(& $backend.Active $w) -or !(& $backend.Same $w)){continue}
  $latest=& $backend.Caption $w;if($latest -cne $current){continue}
  if($readOnly){$results.Add($r);continue}
  $title=[regex]::Replace($r.Title,'[\p{Cc}]','').Trim()
  if(!$title -or $title -ieq 'ChatGPT'){
   if($null -ne $s.Last -and (& $backend.Set $w $s.Last $s.Original)){$s.Last=$null;$s.Original=$null};continue
  }
  $desired=$title+' — ChatGPT';if($current -ceq $desired){continue}
  if($null -eq $s.Last){$s.Original=$current}
  if(!(& $backend.Active $w)){continue}
  if(& $backend.Set $w $current $desired){$s.Last=$desired;& $backend.Log 'Changed' $w 'Verified'}
 }
 return ,$results.ToArray()
}

function Remember-CgtWindow($states,$w){if(!$states.ContainsKey($w.Key)){$states[$w.Key]=@{Window=$w;Raw='';Cached='';Last=$null;Original=$null;Own=$false;Version=0L;NextBackground=[DateTime]::MinValue;Pending=0L}};return $states[$w.Key]}
function New-CgtSourceJob($states,$w,[bool]$foreground,[long]$id,[long]$epoch){$e=Remember-CgtWindow $states $w;return @{Window=$w;Foreground=$foreground;ID=$id;Epoch=$epoch;Version=$e.Version}}
function Maintain-CgtKnown($backend,$states,[bool]$readOnly){
 foreach($key in @($states.Keys)){
  $e=$states[$key];$w=$e.Window
  if(!(& $backend.Same $w)){$states.Remove($key);continue}
  if(!$e.Cached -or (& $backend.Active $w)){continue}
  $current=& $backend.Caption $w;if($null -eq $current){continue}
  if($current -ceq $e.Cached){$e.Last=$e.Cached;continue}
  if(![string]::IsNullOrWhiteSpace($current) -and $current.Trim() -ine 'ChatGPT'){$e.Own=$false;$e.Original=$null;$e.Last=$null;continue}
  if(!$readOnly -and !(& $backend.Active $w) -and (& $backend.SetInactive $w $current $e.Cached)){
   if(!$e.Own){$e.Original=$current};$e.Own=$true;$e.Last=$e.Cached
  }
 }
}
function Apply-CgtSource($backend,$states,$job,$result,[long]$epoch,[int]$backgroundSeconds,[bool]$readOnly,[DateTime]$now){
 if($job.Epoch -ne $epoch -or !$states.ContainsKey($job.Window.Key)){return}
 $w=$job.Window;$e=$states[$w.Key]
 if(!(& $backend.Same $w)){$states.Remove($w.Key);return}
 if(!$job.Foreground){if($e.Pending -eq $job.ID){$e.Pending=0L};$e.NextBackground=$now.AddSeconds($backgroundSeconds)}
 if($null -eq $result -or !$result.Success){return}
 if($job.Foreground){if(!(& $backend.Active $w)){return}}
 elseif((& $backend.Active $w) -or $e.Version -ne $job.Version){return}
 $title=[regex]::Replace([string]$result.Title,'[\p{Cc}]','').Trim();if($title.Length -gt 240){return}
 $current=& $backend.Caption $w;if($null -eq $current -or !(& $backend.Same $w)){return}
 if($job.Foreground -and !(& $backend.Active $w)){return}
 $previous=$e.Last;$e.Version++;$e.NextBackground=$now.AddSeconds($backgroundSeconds)
 if(!$title -or $title -ieq 'ChatGPT'){
  $e.Raw='';$e.Cached=''
  if($e.Own -and $current -ceq $e.Last -and !$readOnly){[void](& $backend.Set $w $current $e.Original)}
  $e.Own=$false;$e.Last=$null;$e.Original=$null;return
 }
 $e.Raw=$title;$desired=if($script:CgtNameRules){$script:CgtNameRules.Resolve($title)}else{$title};if(!$desired.EndsWith(' — ChatGPT')){$desired+=' — ChatGPT'};$e.Cached=$desired
 if($current -ceq $desired){$e.Last=$desired;return}
 $generic=[string]::IsNullOrWhiteSpace($current) -or $current.Trim() -ieq 'ChatGPT'
 if(!$generic -and (!$previous -or $current -cne $previous)){$e.Own=$false;$e.Original=$null;$e.Last=$null;return}
 if($readOnly){return}
 if($job.Foreground){$ok=& $backend.SetActive $w $current $desired}else{$ok=& $backend.SetInactive $w $current $desired}
 if($ok){if(!$e.Own){$e.Original=$current};$e.Own=$true;$e.Last=$desired}
}
function Restore-CgtKnown($backend,$states){
 foreach($e in $states.Values){$w=$e.Window;if($e.Own -and (& $backend.Same $w)){if((& $backend.Caption $w) -ceq $e.Last){[void](& $backend.Set $w $e.Last $e.Original)}};$e.Own=$false}
}
function Get-CgtBackgroundJobs($backend,$states,[DateTime]$now,[long]$epoch,[ref]$nextID){
 $jobs=[Collections.Generic.List[object]]::new()
 foreach($key in @($states.Keys|Sort-Object)){
  $e=$states[$key];if($e.Pending -or $now -lt $e.NextBackground -or (& $backend.Active $e.Window) -or !(& $backend.Same $e.Window)){continue}
  $nextID.Value++;$j=New-CgtSourceJob $states $e.Window $false $nextID.Value $epoch;$e.Pending=$j.ID;$jobs.Add($j)
 }
 return $jobs.ToArray()
}
function Stop-CgtReaderTask($task){
 if($null -eq $task){return}
 [CgtNative]::StopOwnedChild($task.Handle)
 if($task.Process){$task.Process.Dispose()}
 if($task.Path -and (Test-Path -LiteralPath $task.Path)){Remove-Item -LiteralPath $task.Path}
}
function Start-CgtReaderTask($job){
 $task=@{Job=$job;Handle=[IntPtr]::Zero;Process=$null;Path=(Join-Path $LogDirectory ([Guid]::NewGuid().ToString('N')+'.reader.json'));Clock=[Diagnostics.Stopwatch]::StartNew()}
 try{
  $exe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
  $args='-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$scriptPath+'" -Worker -Hwnd '+$job.Window.Hwnd+' -Output "'+$task.Path+'"'
  if(!$job.Foreground){$args+=' -BackgroundWorker'}
  $pi=[Diagnostics.ProcessStartInfo]::new($exe,$args);$pi.UseShellExecute=$false;$pi.CreateNoWindow=$true
  $task.Process=[Diagnostics.Process]::Start($pi);$task.Handle=$task.Process.Handle
  $born=0L;$image=[CgtNative]::ChildImage($task.Handle,[ref]$born)
  if($born -le 0 -or ([CgtNative]::CanonicalImage($image)) -ine ([CgtNative]::CanonicalImage($exe))){throw 'OwnedReaderIdentity'}
  if(!$job.Foreground){try{$task.Process.PriorityClass=[Diagnostics.ProcessPriorityClass]::BelowNormal}catch{}}
  return $task
 }catch{Stop-CgtReaderTask $task;return $null}
}
function Receive-CgtReaderTask($task){
 if($null -eq $task){return @{Complete=$true;Result=$null}}
 $wait=[CgtNative]::WaitChild($task.Handle,0)
 if($wait -eq 258 -and $task.Clock.ElapsedMilliseconds -lt $ReaderTimeoutMilliseconds){return @{Complete=$false}}
 $result=$null
 try{
  if($wait -eq 0 -and [CgtNative]::ChildExitedSuccessfully($task.Handle) -and (Test-Path -LiteralPath $task.Path) -and (Get-Item -LiteralPath $task.Path).Length -le 32768){
   $r=Convert-CgtReaderJson ([IO.File]::ReadAllText($task.Path,[Text.Encoding]::UTF8));$w=$task.Job.Window
   if($r.Success -and $r.Locator -ceq "RawDirect/RootView/NonClientView/ChromeNodeFrameView/ChromeNodeClientView/View/Chrome_WidgetWin_1/Chrome_RenderWidgetHostHWND/Document[RootWebArea].Name" -and $r.Hwnd -eq $w.Hwnd -and $r.Pid -eq $w.Pid -and $r.Born -ceq $w.Born -and $r.ClassName -ceq $w.ClassName -and $r.Path -ieq $w.Path -and [CgtNative]::Same($w) -and ([CgtNative]::Active($w) -eq $task.Job.Foreground)){$result=$r}
  }
 }catch{}
 return @{Complete=$true;Result=$result}
}

# Shared current-user startup contract. These helpers do nothing until explicitly called by the resident or an owned fixture.
function Get-CgtAutoStartPreference([string]$PreferenceKey='Software\ChatGPT-TitleSync'){
 $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PreferenceKey,$false)
 try{if($null -eq $key){return $true};$value=$key.GetValue('AutoStartEnabled');return !($value -is [int] -and $value -eq 0)}finally{if($key){$key.Dispose()}}
}
function New-CgtAutoStartCommand([string]$HostPath,[string]$ScriptPath){
 if([string]::IsNullOrWhiteSpace($HostPath) -or [string]::IsNullOrWhiteSpace($ScriptPath) -or ![IO.Path]::IsPathRooted($HostPath) -or ![IO.Path]::IsPathRooted($ScriptPath) -or $HostPath.Contains('"') -or $ScriptPath.Contains('"')){throw 'Absolute host and script paths are required.'}
 return '"'+[IO.Path]::GetFullPath($HostPath)+'" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+[IO.Path]::GetFullPath($ScriptPath)+'"'
}
function Set-CgtAutoStart([bool]$Enabled,[string]$Command,[string]$RunKey='Software\Microsoft\Windows\CurrentVersion\Run',[string]$PreferenceKey='Software\ChatGPT-TitleSync',[string]$ValueName='ChatGPT-TitleSync',[scriptblock]$BeforePreferenceWrite){
 if($Enabled -and [string]::IsNullOrWhiteSpace($Command)){throw 'The startup command is empty.'}
 if($Enabled -and $Command.Length -gt 260){throw 'Windows Run startup commands cannot exceed 260 characters. Move the script to a shorter path.'}
 # Keep capture/restore local so GetNewClosure callbacks do not depend on a later function lookup.
 $capture={param($path,$name)$key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path,$false);try{if(!$key -or $key.GetValueNames() -notcontains $name){return @{Exists=$false}};return @{Exists=$true;Value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);Kind=$key.GetValueKind($name)}}finally{if($key){$key.Dispose()}}}
 $restore={param($path,$name,$saved)$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path);try{if(!$key){throw 'Cannot open the current-user startup key.'};if($saved.Exists){$key.SetValue($name,$saved.Value,$saved.Kind)}else{$key.DeleteValue($name,$false)}}finally{if($key){$key.Dispose()}}}
 $oldRun=& $capture $RunKey $ValueName;$oldPreference=& $capture $PreferenceKey 'AutoStartEnabled'
 $runMatches=if($Enabled){$oldRun.Exists -and $oldRun.Kind -eq [Microsoft.Win32.RegistryValueKind]::String -and $oldRun.Value -ceq $Command}else{!$oldRun.Exists}
 $preferenceMatches=$oldPreference.Exists -and $oldPreference.Kind -eq [Microsoft.Win32.RegistryValueKind]::DWord -and $oldPreference.Value -is [int] -and $oldPreference.Value -eq [int]$Enabled
 if($runMatches -and $preferenceMatches){return}
 try{
  $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($RunKey)
  try{if(!$key){throw 'Cannot open the current-user startup key.'};if($Enabled){$key.SetValue($ValueName,$Command,[Microsoft.Win32.RegistryValueKind]::String)}else{$key.DeleteValue($ValueName,$false)}}finally{if($key){$key.Dispose()}}
  if($BeforePreferenceWrite){& $BeforePreferenceWrite}
  $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($PreferenceKey)
  try{if(!$key){throw 'Cannot open the current-user preference key.'};$key.SetValue('AutoStartEnabled',[int]$Enabled,[Microsoft.Win32.RegistryValueKind]::DWord)}finally{if($key){$key.Dispose()}}
 }catch{
  $cause=$_.Exception;$rollbackFailed=$false
  try{& $restore $RunKey $ValueName $oldRun}catch{$rollbackFailed=$true}
  try{& $restore $PreferenceKey 'AutoStartEnabled' $oldPreference}catch{$rollbackFailed=$true}
  if($rollbackFailed){throw [InvalidOperationException]::new('Auto-start failed and rollback was incomplete.',$cause)}
  throw [InvalidOperationException]::new('Auto-start could not be changed; previous values were restored.',$cause)
 }
}
function Update-CgtAutoStartUi($state,[bool]$Enabled){
 if(!$state.AutoStartApply){throw 'Auto-start changes are unavailable in this mode.'}
 & $state.AutoStartApply $Enabled
 $state.AutoStartEnabled=$Enabled
 if($state.AutoStartMenu){$state.AutoStartMenu.Checked=$Enabled}
 if($state.Form -and !$state.Form.IsDisposed){$check=$state.Form.Controls['AutoStartEnabled'];if($check){$check.Checked=$Enabled}}
}

# Native WinForms tray UI is initialized only by the normal resident entry point.
function Save-CgtSettings([string]$path,[bool]$enabled,[int]$foreground,[int]$background){
 if($foreground -lt 1 -or $foreground -gt 3600 -or $background -lt 5 -or $background -gt 3600){throw 'Foreground: 1..3600 seconds; background: 5..3600 seconds.'}
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));$temp=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 try{
  [IO.File]::WriteAllText($temp,(@{Enabled=$enabled;ForegroundSeconds=$foreground;BackgroundSeconds=$background}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  for($i=0;;$i++){try{if([IO.File]::Exists($path)){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)};break}catch [IO.IOException]{if(($_.Exception.HResult -band 65535) -notin @(32,33) -or $i -ge 4){throw};Start-Sleep -Milliseconds (20*($i+1))}}
 }finally{try{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}catch{}}
}
function Get-CgtRulesTool {
 foreach($relative in @('ChatGPT-TitleSync.Rules.exe','../../shared/windows/ChatGPT-TitleSync.Rules.exe','../shared/windows/ChatGPT-TitleSync.Rules.exe')){$path=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relative));if([IO.File]::Exists($path)){return $path}}
 throw 'The packaged ChatGPT-TitleSync.Rules.exe companion is missing.'
}
function Open-CgtNameRules($state){
 try{if(!$state.NameRules){throw 'Name replacement is unavailable in this mode.'};$name=if([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'zh'){'name-replacement.zh-CN.html'}else{'name-replacement.html'};$help=$null
  foreach($relative in @('docs','../../docs','../docs')){$path=[IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot $relative) $name));if([IO.File]::Exists($path)){$help=$path;break}}
  if(!$help){throw 'Packaged local name-replacement help is unavailable.'};[void]$state.NameRules.OpenEditor($help)
 }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'ChatGPT-TitleSync — Name replacement')}
}
function Refresh-CgtRuleDisplays($backend,$states,[bool]$readOnly){
 if(!$script:CgtNameRules){return};$sources=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
 foreach($entry in $states.Values){$w=$entry.Window;if(!$entry.Raw -or !(& $backend.Same $w)){continue};$sources[$w.Key]=[string]$entry.Raw;$desired=$script:CgtNameRules.Resolve([string]$entry.Raw);if(!$desired.EndsWith(' — ChatGPT')){$desired+=' — ChatGPT'};$entry.Cached=$desired
  if($readOnly -or !$entry.Own -or !$entry.Last){continue};$current=& $backend.Caption $w;if($current -cne $entry.Last -or $current -ceq $desired){continue};$active=& $backend.Active $w
  $ok=if($active){& $backend.SetActive $w $current $desired}else{& $backend.SetInactive $w $current $desired};if($ok){$entry.Last=$desired}
 }
 try{$script:CgtNameRules.PublishSources($sources)}catch{}
}
function Get-CgtThemeFolder {
 foreach($relative in @('assets/themes','../assets/themes','../../assets/themes')){$path=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relative));if([IO.Directory]::Exists($path)){return $path}}
 return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../assets/themes'))
}
function Set-CgtThemeIcon($state,[int]$id,$prepared){
 if($null -eq $prepared){$prepared=[Drawing.Icon]::new((Join-Path $state.ThemeFolder ([string]$id+'.ico')))}
 $previous=$state.Icon;$previousForm=$state.FormIcon;$nextForm=$null
 if($state.Form -and !$state.Form.IsDisposed){$nextForm=$prepared.Clone()}
 $state.Tray.Icon=$prepared;$state.Icon=$prepared;$state.ThemeDisplayedId=$id
 if($nextForm){$state.Form.Icon=$nextForm};$state.FormIcon=$nextForm
 if($previous){$previous.Dispose()};if($previousForm){$previousForm.Dispose()}
}
function Write-CgtThemeError($state,$errorValue){
 try{[IO.File]::AppendAllText($state.ThemeErrorPath,([DateTime]::UtcNow.ToString('o')+' IconThemeFailure '+$errorValue.GetType().Name+[Environment]::NewLine))}catch{}
}
function Open-CgtScanSettings($state,[string]$path,[scriptblock]$saveAction){
 if(!$saveAction){$saveAction=${function:Save-CgtSettings}}
 if($state.Form -and !$state.Form.IsDisposed){$state.Form.Show();[void][CgtNative]::ShowSettingsWindow($state.Form.Handle.ToInt64());$state.Form.Activate();return}
 $form=[Windows.Forms.Form]::new();$form.Text='ChatGPT-TitleSync — 设置 / Settings';$form.ClientSize=[Drawing.Size]::new(510,410);$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false
 $fg=[Windows.Forms.TextBox]::new();$fg.Name='ForegroundSeconds';$fg.Text=[string]$state.Foreground;$fg.Location=[Drawing.Point]::new(300,22);$fg.Width=100
 $bg=[Windows.Forms.TextBox]::new();$bg.Name='BackgroundSeconds';$bg.Text=[string]$state.Background;$bg.Location=[Drawing.Point]::new(300,64);$bg.Width=100
 $fl=[Windows.Forms.Label]::new();$fl.AutoSize=$true;$fl.Text='前台扫描（秒） / Foreground (1–3600)';$fl.Location=[Drawing.Point]::new(14,26)
 $bl=[Windows.Forms.Label]::new();$bl.AutoSize=$true;$bl.Text='后台刷新（秒） / Background (5–3600)';$bl.Location=[Drawing.Point]::new(14,68)
 $startup=[Windows.Forms.CheckBox]::new();$startup.Name='AutoStartEnabled';$startup.Text='开机自启动 / Start at sign-in';$startup.Checked=[bool]$state.AutoStartEnabled;$startup.Enabled=[bool]$state.AutoStartApply;$startup.AutoSize=$true;$startup.Location=[Drawing.Point]::new(14,103)
 $changeAutoStart=$state.AutoStartUiAction
 $note=[Windows.Forms.Label]::new();$note.AutoSize=$true;$note.Text='后台标题回改检测保持每1秒。 / Native cache repair: 1s.';$note.Location=[Drawing.Point]::new(14,274)
 $errorLabel=[Windows.Forms.Label]::new();$errorLabel.ForeColor=[Drawing.Color]::DarkRed;$errorLabel.Location=[Drawing.Point]::new(14,300);$errorLabel.Size=[Drawing.Size]::new(480,44)
 $save=[Windows.Forms.Button]::new();$save.Text='保存 / Save';$save.Location=[Drawing.Point]::new(290,365);$save.Width=90
 $cancel=[Windows.Forms.Button]::new();$cancel.Text='取消 / Cancel';$cancel.Location=[Drawing.Point]::new(390,365);$cancel.Width=100
 $iconMode=$null;$fixedIcon=$null;$iconPeriod=$null
 $save.add_Click({
  $a=0;$b=0
  if(![int]::TryParse($fg.Text.Trim(),[ref]$a) -or ![int]::TryParse($bg.Text.Trim(),[ref]$b)){$errorLabel.Text='请输入整数秒数。 / Enter whole seconds.';return}
  if($a -lt 1 -or $a -gt 3600 -or $b -lt 5 -or $b -gt 3600){$errorLabel.Text='Foreground: 1..3600 seconds; background: 5..3600 seconds.';return}
  $previousAutoStart=[bool]$state.AutoStartEnabled;$autoStartApplied=$false;$themeCommitted=$false;$themeSnapshot=$null;$preparedTheme=$null
  try{
   if($state.ThemeService){
    $mode=if($form.Controls['IconMode'].SelectedIndex -eq 0){'fixed'}else{'random'};$period=@('day','hour','5min')[$form.Controls['IconPeriod'].SelectedIndex]
    $themePlan=$state.ThemeService.Plan($mode,(45+$form.Controls['FixedIcon'].SelectedIndex),$period)
    $preparedTheme=[Drawing.Icon]::new((Join-Path $state.ThemeFolder ([string]$themePlan.Icon+'.ico')))
    $themeSnapshot=$state.ThemeService.Capture();$state.ThemeService.Commit($themePlan);$themeCommitted=$true
   }
   try{
    if($changeAutoStart -and $state.AutoStartApply){& $changeAutoStart $state $startup.Checked;$autoStartApplied=$true}
    try{& $saveAction $path $state.Enabled $a $b}catch{if($autoStartApplied){try{& $changeAutoStart $state $previousAutoStart}catch{throw 'Settings save failed and auto-start rollback was incomplete.'}};throw}
   }catch{if($themeCommitted){try{$state.ThemeService.Restore($themeSnapshot)}catch{throw 'Settings save failed and icon preference rollback was incomplete.'}};throw}
   if($preparedTheme){& $state.ThemeApplyIcon $state $themePlan.Icon $preparedTheme;$preparedTheme=$null}
   $state.Foreground=$a;$state.Background=$b;$state.Revision++;$form.Close()
  }catch{$errorLabel.Text=$_.Exception.Message}finally{if($preparedTheme){$preparedTheme.Dispose()}}
 }.GetNewClosure())
 $cancel.add_Click({$form.Close()}.GetNewClosure())
 $form.Controls.AddRange(@($fg,$bg,$fl,$bl,$startup,$note,$errorLabel,$save,$cancel));$form.AcceptButton=$save;$form.CancelButton=$cancel
 # Append DropDownList controls after the existing buttons; no child Edit fields are introduced.
 $theme=if($state.ThemeService){$state.ThemeService.Current}else{@{Mode='fixed';FixedIcon=45;Period='day'}}
 $iconMode=[Windows.Forms.ComboBox]::new();$iconMode.Name='IconMode';$iconMode.DropDownStyle='DropDownList';$iconMode.Location=[Drawing.Point]::new(290,143);$iconMode.Width=200;[void]$iconMode.Items.AddRange(@('固定 / Fixed','随机 / Random'));$iconMode.SelectedIndex=if($theme.Mode -eq 'random'){1}else{0}
 $fixedIcon=[Windows.Forms.ComboBox]::new();$fixedIcon.Name='FixedIcon';$fixedIcon.DropDownStyle='DropDownList';$fixedIcon.Location=[Drawing.Point]::new(290,185);$fixedIcon.Width=200;[void]$fixedIcon.Items.AddRange(@('45 — 蓝紫 / Violet','46 — 湖蓝 / Lake blue','47 — 琥珀 / Amber','48 — 薄荷 / Mint','49 — 玫红 / Rose','50 — 天蓝 / Sky','51 — 浅紫 / Lavender','52 — 珊瑚 / Coral'));$fixedIcon.SelectedIndex=$theme.FixedIcon-45
 $iconPeriod=[Windows.Forms.ComboBox]::new();$iconPeriod.Name='IconPeriod';$iconPeriod.DropDownStyle='DropDownList';$iconPeriod.Location=[Drawing.Point]::new(290,227);$iconPeriod.Width=200;[void]$iconPeriod.Items.AddRange(@('每日 / Daily','每小时 / Hourly','每5分钟 / Every 5 min'));$iconPeriod.SelectedIndex=[Array]::IndexOf(@('day','hour','5min'),$theme.Period)
 $canTheme=[bool]$state.ThemeService;$syncThemeFields={ $iconMode.Enabled=$canTheme;$fixedIcon.Enabled=$canTheme -and ($iconMode.SelectedIndex -eq 0);$iconPeriod.Enabled=$canTheme -and ($iconMode.SelectedIndex -eq 1) }.GetNewClosure();$iconMode.add_SelectedIndexChanged($syncThemeFields);& $syncThemeFields
 $ml=[Windows.Forms.Label]::new();$ml.Text='图标模式 / Icon mode';$ml.AutoSize=$true;$ml.Location=[Drawing.Point]::new(14,147)
 $cl=[Windows.Forms.Label]::new();$cl.Text='固定配色 / Fixed color';$cl.AutoSize=$true;$cl.Location=[Drawing.Point]::new(14,189)
 $pl=[Windows.Forms.Label]::new();$pl.Text='随机换色 / Random period';$pl.AutoSize=$true;$pl.Location=[Drawing.Point]::new(14,231)
 $form.Controls.AddRange(@($ml,$iconMode,$cl,$fixedIcon,$pl,$iconPeriod));$state.Form=$form
 $nameRules=[Windows.Forms.Button]::new();$nameRules.Name='NameReplacement';$nameRules.Text='Name replacement… / 名称替换…';$nameRules.Location=[Drawing.Point]::new(14,365);$nameRules.Size=[Drawing.Size]::new(265,28);$nameRules.Enabled=[bool]$state.NameRules;$openRules=${function:Open-CgtNameRules};$nameRules.add_Click({& $openRules $state}.GetNewClosure());$form.Controls.Add($nameRules)
 if($state.Icon){$state.FormIcon=$state.Icon.Clone();$form.Icon=$state.FormIcon}
 $form.add_FormClosed({if($state.FormIcon){$state.FormIcon.Dispose();$state.FormIcon=$null}}.GetNewClosure())
 $form.Show();[void][CgtNative]::ShowSettingsWindow($form.Handle.ToInt64());$form.Activate()
}
function Initialize-CgtTray($state,[string]$path){
 Add-Type -AssemblyName System.Windows.Forms;Add-Type -AssemblyName System.Drawing
 [Windows.Forms.Application]::EnableVisualStyles()
 $tray=[Windows.Forms.NotifyIcon]::new();$tray.Text='ChatGPT-TitleSync / ChatGPT 标题同步助手'
 $iconPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\assets\chatgpt-titlesync.ico'))
 if([IO.File]::Exists($iconPath)){$state.Icon=[Drawing.Icon]::new($iconPath);$tray.Icon=$state.Icon}else{$tray.Icon=[Drawing.SystemIcons]::Application}
 $saveSettings=${function:Save-CgtSettings};$openSettings=${function:Open-CgtScanSettings}
 $menu=[Windows.Forms.ContextMenuStrip]::new()
 $enabled=[Windows.Forms.ToolStripMenuItem]::new('Enable window titles');$enabled.Checked=$state.Enabled
 $enabled.add_Click({try{$value=!$state.Enabled;& $saveSettings $path $value $state.Foreground $state.Background;$state.Enabled=$value;$state.Revision++;$enabled.Checked=$value}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'ChatGPT-TitleSync')}}.GetNewClosure())
 [void]$menu.Items.Add($enabled)
 $interval=[Windows.Forms.ToolStripMenuItem]::new('扫描间隔设置… / Scan intervals…');$interval.add_Click({& $openSettings $state $path $saveSettings}.GetNewClosure());[void]$menu.Items.Add($interval)
 $autoStart=[Windows.Forms.ToolStripMenuItem]::new('开机自启动 / Start at sign-in');$autoStart.Name='AutoStartEnabled';$autoStart.Checked=[bool]$state.AutoStartEnabled;$autoStart.Enabled=[bool]$state.AutoStartApply
 $changeAutoStart=$state.AutoStartUiAction;$state.AutoStartMenu=$autoStart
 $autoStart.add_Click({try{& $changeAutoStart $state (!$state.AutoStartEnabled)}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'ChatGPT-TitleSync — Auto-start')}}.GetNewClosure());[void]$menu.Items.Add($autoStart)
 $exit=[Windows.Forms.ToolStripMenuItem]::new('Exit and restore titles');$exit.add_Click({$state.Quit=$true}.GetNewClosure());[void]$menu.Items.Add($exit)
 $nameRules=[Windows.Forms.ToolStripMenuItem]::new('Name replacement… / 名称替换…');$nameRules.Enabled=[bool]$state.NameRules;$openRules=${function:Open-CgtNameRules};$nameRules.add_Click({& $openRules $state}.GetNewClosure());[void]$menu.Items.Add($nameRules)
 $tray.ContextMenuStrip=$menu;$tray.Visible=$true;$state.Tray=$tray;$state.Menu=$menu
}

$backend=@{
 Targets={@([CgtNative]::Windows())|Where-Object {!$Hwnd -or $_.Hwnd -eq $Hwnd}}
 Active={param($w)[CgtNative]::Active($w)};Same={param($w)[CgtNative]::Same($w)}
 Caption={param($w)[CgtNative]::Caption($w)}
 Set={param($w,$a,$b)[CgtNative]::Set($w,$a,$b)}
 SetActive={param($w,$a,$b)[CgtNative]::SetFocused($w,$a,$b)}
 SetInactive={param($w,$a,$b)[CgtNative]::SetInactive($w,$a,$b)}
}
$mutex=[Threading.Mutex]::new($false,$mutexName);$owns=$false;$event=$null;$settingsEvent=$null;$states=@{};$fgTask=$null;$bgTask=$null
try{
 try{$owns=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owns=$true}
 if(!$owns){throw 'Another standalone ChatGPT-TitleSync monitor is already running.'}
 $event=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$eventName);[void]$event.Reset()
 $nextID=0L;$epoch=0L
 if($Once){
  $results=[Collections.Generic.List[object]]::new()
  foreach($w in @(& $backend.Targets)){
   [void](Remember-CgtWindow $states $w);$nextID++;$job=New-CgtSourceJob $states $w $true $nextID $epoch
   $result=Read-Title $w $event
   Apply-CgtSource $backend $states $job $result $epoch $BackgroundIntervalSeconds ([bool]$ReadOnly) ([DateTime]::UtcNow)
   if($ReadOnly -and $result){$results.Add($result)}
  }
  if($ReadOnly){if($Output){Write-Result $Output ($results.ToArray())}else{$results.ToArray()|ForEach-Object{$_|ConvertTo-Json -Compress}}}
  return
 }
 $settingsPath=Join-Path $LogDirectory 'powershell-settings.json'
 $ui=@{Enabled=$true;Foreground=$IntervalSeconds;Background=$BackgroundIntervalSeconds;Revision=0;Quit=$false;Form=$null;Tray=$null;Menu=$null;Icon=$null;AutoStartEnabled=$false;AutoStartApply=$null;AutoStartUiAction=${function:Update-CgtAutoStartUi};AutoStartMenu=$null;AutoStartError=$null;ThemeService=$null;ThemeFolder=$null;ThemeApplyIcon=${function:Set-CgtThemeIcon};ThemeDisplayedId=45;ThemeErrorPath=(Join-Path $LogDirectory 'theme-errors.log');FormIcon=$null}
 try{if(Test-Path -LiteralPath $settingsPath){$saved=Convert-CgtReaderJson ([IO.File]::ReadAllText($settingsPath));if($null -ne $saved.Enabled){$ui.Enabled=[bool]$saved.Enabled};if(!$PSBoundParameters.ContainsKey('IntervalSeconds') -and $saved.ForegroundSeconds -ge 1 -and $saved.ForegroundSeconds -le 3600){$ui.Foreground=[int]$saved.ForegroundSeconds};if(!$PSBoundParameters.ContainsKey('BackgroundIntervalSeconds') -and $saved.BackgroundSeconds -ge 5 -and $saved.BackgroundSeconds -le 3600){$ui.Background=[int]$saved.BackgroundSeconds}}}catch{}
 $IntervalSeconds=$ui.Foreground;$BackgroundIntervalSeconds=$ui.Background
 $settingsEvent=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$mutexName+'.Settings')
 # Normal resident only: the shared mutex is owned and all Once/worker/IPC paths returned above.
 if(!$ReadOnly -and !$BackgroundWorker){
  $startupCommand=New-CgtAutoStartCommand ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) $scriptPath
  $applyAutoStart=${function:Set-CgtAutoStart};$ui.AutoStartApply={param($value)& $applyAutoStart ([bool]$value) $startupCommand}.GetNewClosure()
  try{$preferred=Get-CgtAutoStartPreference;& $ui.AutoStartApply $preferred;$ui.AutoStartEnabled=$preferred}catch{$ui.AutoStartError=$_.Exception.Message}
 }
 if(!$ReadOnly -and !$BackgroundWorker){
  $ui.ThemeFolder=Get-CgtThemeFolder;$themeFolder=$ui.ThemeFolder;$random=[Random]::new()
  $choose={param($count)$random.Next($count)}.GetNewClosure();$validate={param($id)$path=Join-Path $themeFolder ([string]$id+'.ico');$icon=[Drawing.Icon]::new($path);$icon.Dispose()}.GetNewClosure()
  $ui.ThemeService=[TitleSyncThemes.ThemeService]::new([TitleSyncThemes.ThemeService]::PreferenceKey,[Func[DateTimeOffset]]{[DateTimeOffset]::Now},[Func[int,int]]$choose,[Action[int]]$validate,$null)
  try{$ui.ThemeService.Load()}catch{Write-CgtThemeError $ui $_.Exception}
 }
 # The common Unicode formatter is loaded only by the normal resident, after readonly/worker entries returned.
 $script:CgtNameRules=$null
 if(!$ReadOnly -and !$BackgroundWorker){
  try{$rulesTool=Get-CgtRulesTool;[void][Reflection.Assembly]::LoadFrom($rulesTool)
   $emptyInspector=[TitleSyncRules.IdentityInspector]{param($bytes)$config=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)|ConvertFrom-Json;if($config.schema_version -ne 1 -or $config.enabled -isnot [bool] -or $null -eq $config.rules){throw 'Invalid rule configuration'};return (!$config.enabled -or @($config.rules|Where-Object {$_.enabled}).Count -eq 0)}
   $rulePath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ChatGPT-TitleSync/title-rules.json';$script:CgtNameRules=[TitleSyncRules.RulesClient]::new($rulesTool,$rulePath,[IO.Path]::GetFullPath($LogDirectory),$emptyInspector)
  }catch{$script:CgtNameRules=$null}
 }
 $ui.NameRules=$script:CgtNameRules
 Initialize-CgtTray $ui $settingsPath
 if($ui.ThemeService){try{$initial=$ui.ThemeService.PlanTick();if($initial){$ready=[Drawing.Icon]::new((Join-Path $ui.ThemeFolder ([string]$initial.Icon+'.ico')));try{$ui.ThemeService.Commit($initial);& $ui.ThemeApplyIcon $ui $initial.Icon $ready;$ready=$null}finally{if($ready){$ready.Dispose()}}}elseif($ui.ThemeDisplayedId -ne $ui.ThemeService.Current.Icon){& $ui.ThemeApplyIcon $ui $ui.ThemeService.Current.Icon $null}}catch{$ui.ThemeService.MarkTickFailed();Write-CgtThemeError $ui $_.Exception}}
 if($ui.AutoStartError){[void][Windows.Forms.MessageBox]::Show($ui.AutoStartError,'ChatGPT-TitleSync — Auto-start')}
 $seenSettingsRevision=0
 $schedule=[Diagnostics.Stopwatch]::StartNew();$nextNative=0L;$nextForeground=0L;$nextDiscovery=0L;$nextTheme=0L
 $bgQueue=[Collections.Generic.Queue[object]]::new()
 while(!$event.WaitOne(0)){
  [Windows.Forms.Application]::DoEvents()
  if($settingsEvent.WaitOne(0)){$ui.Menu.Items[1].PerformClick()}
  if($ui.Quit){break}
  # Cheap slot maintenance remains active even while title monitoring is disabled.
  if($ui.ThemeService -and $schedule.ElapsedMilliseconds -ge $nextTheme){
   $nextTheme=$schedule.ElapsedMilliseconds+1000L
   try{$plan=$ui.ThemeService.PlanTick();if($plan){$ready=[Drawing.Icon]::new((Join-Path $ui.ThemeFolder ([string]$plan.Icon+'.ico')));try{$ui.ThemeService.Commit($plan);& $ui.ThemeApplyIcon $ui $plan.Icon $ready;$ready=$null}finally{if($ready){$ready.Dispose()}}}}catch{$ui.ThemeService.MarkTickFailed();Write-CgtThemeError $ui $_.Exception}
  }
  if($seenSettingsRevision -ne $ui.Revision){
   Stop-CgtReaderTask $fgTask;Stop-CgtReaderTask $bgTask;$fgTask=$null;$bgTask=$null;$bgQueue.Clear();$epoch++
   foreach($entry in $states.Values){$entry.Version++;$entry.Pending=0L;$entry.NextBackground=[DateTime]::MinValue}
   if(!$ui.Enabled){Restore-CgtKnown $backend $states}
   $IntervalSeconds=$ui.Foreground;$BackgroundIntervalSeconds=$ui.Background
   $nextNative=0L;$nextForeground=0L;$nextDiscovery=0L;$seenSettingsRevision=$ui.Revision
  }
  if(!$ui.Enabled){[void]$event.WaitOne(50);continue}
  $now=[DateTime]::UtcNow;$elapsed=$schedule.ElapsedMilliseconds
  foreach($kind in @('fg','bg')){
   $task=if($kind -eq 'fg'){$fgTask}else{$bgTask};if($null -eq $task){continue}
   $role=[CgtNative]::Same($task.Job.Window) -and ([CgtNative]::Active($task.Job.Window) -eq $task.Job.Foreground)
   $received=if($role){Receive-CgtReaderTask $task}else{@{Complete=$true;Result=$null}}
   if($received.Complete){
    Apply-CgtSource $backend $states $task.Job $received.Result $epoch $BackgroundIntervalSeconds ([bool]$ReadOnly) $now
    Stop-CgtReaderTask $task;if($kind -eq 'fg'){$fgTask=$null}else{$bgTask=$null}
   }
  }
  if($elapsed -ge $nextNative){
   Refresh-CgtRuleDisplays $backend $states ([bool]$ReadOnly)
   Maintain-CgtKnown $backend $states ([bool]$ReadOnly)
   $nextNative=Get-CgtNextDeadline $nextNative $elapsed 1000
  }
  if($elapsed -ge $nextForeground){
   $targets=@(& $backend.Targets)
   if($targets.Count -gt 0 -and $null -eq $fgTask){$nextID++;$j=New-CgtSourceJob $states $targets[0] $true $nextID $epoch;$fgTask=Start-CgtReaderTask $j}
   $nextForeground=Get-CgtNextDeadline $nextForeground $elapsed ($IntervalSeconds*1000L)
  }
  if($elapsed -ge $nextDiscovery){
   foreach($w in [CgtNative]::AllWindows()){if(!$Hwnd -or $w.Hwnd -eq $Hwnd){[void](Remember-CgtWindow $states $w)}}
   $nextDiscovery=Get-CgtNextDeadline $nextDiscovery $elapsed ($BackgroundIntervalSeconds*1000L)
  }
  foreach($j in @(Get-CgtBackgroundJobs $backend $states $now $epoch ([ref]$nextID))){$bgQueue.Enqueue($j)}
  if($null -eq $bgTask){
   while($bgQueue.Count -gt 0 -and $null -eq $bgTask){
    $j=$bgQueue.Dequeue()
    if(!$states.ContainsKey($j.Window.Key)){continue};$e=$states[$j.Window.Key]
    if(![CgtNative]::Same($j.Window) -or [CgtNative]::Active($j.Window) -or $e.Version -ne $j.Version){$e.Pending=0L;continue}
    $bgTask=Start-CgtReaderTask $j
    if($null -eq $bgTask){$e.Pending=0L;$e.NextBackground=$now.AddSeconds($BackgroundIntervalSeconds)}
   }
  }
  [void]$event.WaitOne(50)
 }
}finally{
 if($ui){if($ui.Form){$ui.Form.Dispose()};if($ui.Tray){$ui.Tray.Visible=$false;$ui.Tray.Dispose()};if($ui.Menu){$ui.Menu.Dispose()};if($ui.Icon){$ui.Icon.Dispose()}}
 Stop-CgtReaderTask $fgTask;Stop-CgtReaderTask $bgTask
 Restore-CgtKnown $backend $states
 if($script:CgtNameRules){$script:CgtNameRules.Dispose();$script:CgtNameRules=$null}
 if($null -ne $settingsEvent){$settingsEvent.Dispose()};if($null -ne $event){$event.Dispose()};if($owns){$mutex.ReleaseMutex()};$mutex.Dispose()
}
