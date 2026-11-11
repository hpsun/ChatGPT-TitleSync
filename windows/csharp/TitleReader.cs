using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Automation;

public static class ChatGptWindowTitleReader {
 const int MaxNodes=30000, BudgetMs=10000, WatchdogMs=20000;
 static JavaScriptSerializer Json=new JavaScriptSerializer { MaxJsonLength=100000000, RecursionLimit=200 };
 delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p,IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,EnumProc p,IntPtr l);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool b,uint p);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr h,out long c,out long e,out long k,out long u);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr h,int f,StringBuilder b,ref int n);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left,Top,Right,Bottom; }
 public class Identity {
  public long hwnd; public uint pid,tid; public long processCreatedFileTimeUtc;
  public string exePath,windowClass,windowTitle; public bool visible; public int[] bounds;
 }
 public class Node {
  public int index,parent,depth; public string name,automationId,controlType,className,frameworkId;
  public bool password,isControlElement,isContentElement,isOffscreen;
  public int processId; public long nativeWindowHandle; public double[] bounds; public int[] runtimeId; public string error;
 }
 class WalkItem {public AutomationElement element; public int parent,depth;}
 static Identity Identify(IntPtr hwnd) {
  if(!IsWindow(hwnd))return null;
  uint pid;uint tid=GetWindowThreadProcessId(hwnd,out pid);
  var c=new StringBuilder(256);GetClassName(hwnd,c,c.Capacity);
  var t=new StringBuilder(2048);GetWindowText(hwnd,t,t.Capacity);
  var p=OpenProcess(0x1000,false,pid);if(p==IntPtr.Zero)return null;
  long cr,ex,ke,us;var path=new StringBuilder(32768);int n=path.Capacity;
  try {if(!GetProcessTimes(p,out cr,out ex,out ke,out us)||!QueryFullProcessImageName(p,0,path,ref n))return null;}
  finally{CloseHandle(p);}
  RECT r;GetWindowRect(hwnd,out r);
  return new Identity{hwnd=hwnd.ToInt64(),pid=pid,tid=tid,processCreatedFileTimeUtc=cr,exePath=path.ToString(),windowClass=c.ToString(),windowTitle=t.ToString(),visible=IsWindowVisible(hwnd),bounds=new[]{r.Left,r.Top,r.Right-r.Left,r.Bottom-r.Top}};
 }
 static bool Target(Identity x){return x!=null&&x.visible&&x.windowClass=="Chrome_WidgetWin_1"&&string.Equals(Path.GetFileName(x.exePath),"ChatGPT.exe",StringComparison.OrdinalIgnoreCase);}
 static bool Same(Identity a,Identity b){return a!=null&&b!=null&&a.hwnd==b.hwnd&&a.pid==b.pid&&a.processCreatedFileTimeUtc==b.processCreatedFileTimeUtc&&a.windowClass==b.windowClass&&a.exePath==b.exePath;}
 static string Arg(string[] a,string k,string d){for(int i=0;i+1<a.Length;i++)if(a[i]==k)return a[i+1];return d;}
 static void Write(string path,object data){File.WriteAllText(path,Json.Serialize(data),new UTF8Encoding(false));}
 static Node Read(AutomationElement el,int ix,int parent,int depth){
  var n=new Node{index=ix,parent=parent,depth=depth};
  try {
   var x=el.Cached;n.password=x.IsPassword;n.name=n.password?"[password element: name omitted]":x.Name;
   n.automationId=x.AutomationId;n.controlType=x.ControlType.ProgrammaticName;n.className=x.ClassName;n.frameworkId=x.FrameworkId;
   n.isControlElement=x.IsControlElement;n.isContentElement=x.IsContentElement;n.isOffscreen=x.IsOffscreen;
   n.processId=x.ProcessId;n.nativeWindowHandle=x.NativeWindowHandle;var r=x.BoundingRectangle;
   n.bounds=r.IsEmpty?null:new[]{r.X,r.Y,r.Width,r.Height};n.runtimeId=(int[])el.GetCachedPropertyValue(AutomationElement.RuntimeIdProperty);
  }catch(Exception e){n.error=e.GetType().Name+": "+e.Message;}return n;
 }
 static int Worker(string[] args){
  var hwnd=new IntPtr(long.Parse(Arg(args,"--hwnd","0")));string output=Arg(args,"--output",null);
  var expected=Json.Deserialize<Identity>(File.ReadAllText(output+".identity.json"));
  var begin=Identify(hwnd);if(!Same(expected,begin)||!Target(begin))throw new Exception("Target identity changed before UIA read");
  var sw=Stopwatch.StartNew();int count=0;string reason="complete";bool complete=true;
  using(var writer=new StreamWriter(output+".nodes.jsonl",false,new UTF8Encoding(false))){
   writer.AutoFlush=true;var cache=new CacheRequest();cache.TreeScope=TreeScope.Element; foreach(var p in new[]{AutomationElement.NameProperty,AutomationElement.AutomationIdProperty,AutomationElement.ControlTypeProperty,AutomationElement.ClassNameProperty,AutomationElement.FrameworkIdProperty,AutomationElement.IsPasswordProperty,AutomationElement.IsControlElementProperty,AutomationElement.IsContentElementProperty,AutomationElement.IsOffscreenProperty,AutomationElement.ProcessIdProperty,AutomationElement.NativeWindowHandleProperty,AutomationElement.BoundingRectangleProperty,AutomationElement.RuntimeIdProperty})cache.Add(p);
   var root=AutomationElement.FromHandle(hwnd).GetUpdatedCache(cache);var stack=new Queue<WalkItem>();
   stack.Enqueue(new WalkItem{element=root,parent=-1,depth=0});var walker=TreeWalker.RawViewWalker;
   while(stack.Count>0){
    if(count>=MaxNodes||sw.ElapsedMilliseconds>=BudgetMs){complete=false;reason=count>=MaxNodes?"node_limit":"time_limit";break;}
    var it=stack.Dequeue();int ix=count++;writer.WriteLine(Json.Serialize(Read(it.element,ix,it.parent,it.depth)));
    if(it.depth>=80){complete=false;reason="depth_limit";continue;}
    var children=new List<AutomationElement>();
    try{var ch=walker.GetFirstChild(it.element,cache);while(ch!=null){children.Add(ch);if(children.Count>=MaxNodes||sw.ElapsedMilliseconds>=BudgetMs){complete=false;reason="time_or_child_limit";break;}ch=walker.GetNextSibling(ch,cache);}}
    catch(Exception e){complete=false;reason="walk_error:"+e.GetType().Name;}
    for(int i=0;i<children.Count;i++)stack.Enqueue(new WalkItem{element=children[i],parent=ix,depth=it.depth+1});
   }
  }
  var end=Identify(hwnd);bool same=Same(begin,end);if(!same){complete=false;reason="target_identity_changed";}
  Write(output+".worker.json",new{startedIdentity=begin,endedIdentity=end,identityUnchanged=same,complete=complete,stopReason=reason,nodeCount=count,elapsedMs=sw.ElapsedMilliseconds,view="RawView with control/content flags; Name only; no ValuePattern/TextPattern"});return 0;
 }
 static object Candidate(Node n,List<Node> all){
  var path=new List<object>();int p=n.index;
  for(int i=0;i<20&&p>=0&&p<all.Count;i++){var x=all[p];path.Add(new{index=x.index,parent=x.parent,type=x.controlType,id=x.automationId,name=x.name,bounds=x.bounds,className=x.className});p=x.parent;}
  path.Reverse();return new{node=n,path=path};
 }

 public class TitleResult {
  public long Hwnd; public uint Pid; public string ProcessStartUtc,ClassName,Title,Locator,Error,ObservedUtc,HeartbeatUtc;
  public bool Success,Pending; public long ElapsedMs,Seq,SourceSeq;
 }
 static TitleResult Result(Identity id) {return new TitleResult {Hwnd=id==null?0:id.hwnd,Pid=id==null?0:id.pid,ProcessStartUtc=id==null?null:DateTime.FromFileTimeUtc(id.processCreatedFileTimeUtc).ToString("o"),ClassName=id==null?null:id.windowClass,ObservedUtc=DateTime.UtcNow.ToString("o"),Success=false,Title=null,Locator="UIA RawView immediate-children-only verified native path: RootView/NonClientView/ChromeNodeFrameView/ChromeNodeClientView/View/Chrome_WidgetWin_1/Chrome_RenderWidgetHostHWND/Document[AutomationId=RootWebArea].Name"};}
 static int LightWorker(string[] args) {
  long hwnd=long.Parse(Arg(args,"--hwnd","0"));string output=Arg(args,"--output",null);
  if(string.IsNullOrEmpty(output))throw new Exception("--output is required");
  Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));
  bool direct=Array.IndexOf(args,"--direct")>=0;var id=Identify(new IntPtr(hwnd));
  var expected=direct?id:Json.Deserialize<Identity>(File.ReadAllText(output+".identity.json"));var result=Result(id);var sw=Stopwatch.StartNew();
  if(direct){result.Error="read_pending";Write(output,result);}
  try {
   if(!Target(id)||!Same(id,expected))throw new Exception("target_identity_changed_before_read");
   AutomationElement host=AutomationElement.FromHandle(new IntPtr(hwnd));
   var raw=TreeWalker.RawViewWalker;var pathCache=new CacheRequest();pathCache.TreeScope=TreeScope.Element;pathCache.Add(AutomationElement.ClassNameProperty);
   foreach(string nativeClass in new[]{"RootView","NonClientView","ChromeNodeFrameView","ChromeNodeClientView","View","Chrome_WidgetWin_1","Chrome_RenderWidgetHostHWND"}) {
    var found=new List<AutomationElement>();var child=raw.GetFirstChild(host,pathCache);int examined=0;
    while(child!=null&&examined++<32){if(child.Cached.ClassName==nativeClass)found.Add(child);child=raw.GetNextSibling(child,pathCache);}
    if(child!=null)throw new Exception("direct_path_sibling_limit");
    if(found.Count!=1)throw new Exception("verified_raw_direct_path_"+nativeClass+"_matches_"+found.Count);
    host=found[0];
   }
   var cache=new CacheRequest();cache.TreeScope=TreeScope.Element;
   foreach(var p in new[]{AutomationElement.NameProperty,AutomationElement.AutomationIdProperty,AutomationElement.ControlTypeProperty,AutomationElement.IsPasswordProperty})cache.Add(p);
   host=host.GetUpdatedCache(cache);AutomationElement doc=null;
   if(host.Cached.AutomationId=="RootWebArea"&&host.Cached.ControlType==ControlType.Document)doc=host;
   else {var matches=new List<AutomationElement>();var child=raw.GetFirstChild(host,cache);int examined=0;while(child!=null&&examined++<16){if(child.Cached.AutomationId=="RootWebArea"&&child.Cached.ControlType==ControlType.Document)matches.Add(child);child=raw.GetNextSibling(child,cache);}if(child!=null)throw new Exception("document_direct_child_limit");if(matches.Count!=1)throw new Exception("expected_one_RootWebArea_child_found_"+matches.Count);doc=matches[0];}
   if(doc.Cached.IsPassword)throw new Exception("unexpected_password_element");
   string title=doc.Cached.Name;
   if(string.IsNullOrWhiteSpace(title))throw new Exception("empty_document_title");
   if(title.Length>512)throw new Exception("document_title_exceeds_limit");
   if(!Same(id,Identify(new IntPtr(hwnd))))throw new Exception("target_identity_changed_after_read");
   result.Title=title;result.Error=null;result.Success=true;
  }catch(Exception e){result.Success=false;result.Error=e.GetType().Name+": "+e.Message;}
  result.ObservedUtc=DateTime.UtcNow.ToString("o");result.ElapsedMs=sw.ElapsedMilliseconds;Write(output,result);if(direct)Console.WriteLine(Json.Serialize(result));return result.Success?0:3;
 }

 static bool OwnerAlive(int pid,long born) {
  if(pid<=0||born<=0)return false;
  IntPtr p=OpenProcess(0x1000,false,(uint)pid);if(p==IntPtr.Zero)return false;
  try {long c,e,k,u;return GetProcessTimes(p,out c,out e,out k,out u)&&c==born;}
  finally {CloseHandle(p);}
 }
 static void WriteAtomic(string path,object value) {
  string tmp=path+".tmp";
  File.WriteAllText(tmp,Json.Serialize(value),new UTF8Encoding(false));
  for(int n=0;;n++){
   try {if(File.Exists(path))File.Replace(tmp,path,null);else File.Move(tmp,path);return;}
   catch(IOException){if(n>=4)throw;System.Threading.Thread.Sleep(10);}
  }
 }
 static AutomationElement LocateWatchDocument(IntPtr hwnd) {
  AutomationElement host=AutomationElement.FromHandle(hwnd);
  var raw=TreeWalker.RawViewWalker;var pc=new CacheRequest();pc.TreeScope=TreeScope.Element;pc.Add(AutomationElement.ClassNameProperty);
  foreach(string cls in new[]{"RootView","NonClientView","ChromeNodeFrameView","ChromeNodeClientView","View","Chrome_WidgetWin_1","Chrome_RenderWidgetHostHWND"}){
   AutomationElement match=null;int matches=0,examined=0;var child=raw.GetFirstChild(host,pc);
   while(child!=null&&examined++<32){if(child.Cached.ClassName==cls){match=child;matches++;}child=raw.GetNextSibling(child,pc);}
   if(child!=null||matches!=1)throw new InvalidOperationException("WatchDocumentPathUnavailable");
   host=match;
  }
  var dc=new CacheRequest();dc.TreeScope=TreeScope.Element;
  dc.Add(AutomationElement.AutomationIdProperty);dc.Add(AutomationElement.ControlTypeProperty);dc.Add(AutomationElement.IsPasswordProperty);
  host=host.GetUpdatedCache(dc);
  if(host.Cached.AutomationId=="RootWebArea"&&host.Cached.ControlType==ControlType.Document&&!host.Cached.IsPassword)return host;
  AutomationElement doc=null;int count=0,seen=0;var item=raw.GetFirstChild(host,dc);
  while(item!=null&&seen++<16){
   if(item.Cached.AutomationId=="RootWebArea"&&item.Cached.ControlType==ControlType.Document&&!item.Cached.IsPassword){doc=item;count++;}
   item=raw.GetNextSibling(item,dc);
  }
  if(item!=null||count!=1)throw new InvalidOperationException("WatchDocumentUnavailable");
  return doc;
 }
 static int Watch(string[] args) {
  long rawHwnd=long.Parse(Arg(args,"--hwnd","0"));IntPtr hwnd=new IntPtr(rawHwnd);
  string output=Arg(args,"--output",null);
  int owner=int.Parse(Arg(args,"--owner-pid","0"));long ownerBorn=long.Parse(Arg(args,"--owner-born","0"));
  int interval=Math.Max(100,Math.Min(3600000,int.Parse(Arg(args,"--interval-ms","2000"))));
  if(string.IsNullOrEmpty(output))throw new ArgumentException("WatchOutputRequired");
  if(GetForegroundWindow()!=hwnd||!OwnerAlive(owner,ownerBorn))return 3;
  var expected=Identify(hwnd);if(!Target(expected))return 3;
  Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));
  var pending=Result(expected);pending.Pending=true;pending.Error="Attaching";WriteAtomic(output,pending);
  AutomationElement doc=null;long seq=0,sourceSeq=0;var clock=Stopwatch.StartNew();long nextRead=0,nextBeat=0;
  TitleResult latest=null;
  while(GetForegroundWindow()==hwnd&&OwnerAlive(owner,ownerBorn)) {
   if(!Same(expected,Identify(hwnd)))break;
   if(latest==null||clock.ElapsedMilliseconds>=nextRead){
    var result=Result(expected);result.SourceSeq=++sourceSeq;result.Pending=false;var readTime=Stopwatch.StartNew();
    try {
     if(doc==null)doc=LocateWatchDocument(hwnd);
     if(doc.Current.ControlType!=ControlType.Document||doc.Current.AutomationId!="RootWebArea"||doc.Current.IsPassword)
      throw new InvalidOperationException("WatchDocumentIdentityChanged");
     string title=doc.Current.Name;
     if(title!=null&&title.Length>512)throw new InvalidOperationException("WatchTitleTooLong");
     if(GetForegroundWindow()!=hwnd||!Same(expected,Identify(hwnd))||!OwnerAlive(owner,ownerBorn))break;
     result.Title=title??"";result.Success=true;result.Error=null;
    }
    catch(ElementNotAvailableException){doc=null;result.Error="WatchElementUnavailable";}
    catch(Exception e){doc=null;result.Error=e.GetType().Name;}
    result.ElapsedMs=readTime.ElapsedMilliseconds;result.ObservedUtc=DateTime.UtcNow.ToString("o");latest=result;
    nextRead+=interval;while(nextRead<=clock.ElapsedMilliseconds)nextRead+=interval;
   }
   if(GetForegroundWindow()!=hwnd||!OwnerAlive(owner,ownerBorn))break;
   latest.Seq=++seq;latest.HeartbeatUtc=DateTime.UtcNow.ToString("o");WriteAtomic(output,latest);
   nextBeat+=1000;long wait=nextBeat-clock.ElapsedMilliseconds;
   if(wait>0)System.Threading.Thread.Sleep((int)Math.Min(wait,1000));else nextBeat=clock.ElapsedMilliseconds;
  }
  return 0;
 }

 static int Light(string[] args) {
  long hwnd=long.Parse(Arg(args,"--hwnd","0"));string output=Arg(args,"--output",null);
  if(string.IsNullOrEmpty(output))throw new Exception("--output is required");
  Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));
  var id=Identify(new IntPtr(hwnd));var result=Result(id);
  if(!Target(id)){result.Hwnd=hwnd;result.Error="target_must_be_visible_ChatGPT.exe_Chrome_WidgetWin_1";Write(output,result);return 3;}
  result.Error="read_pending";Write(output,result);Write(output+".identity.json",id);
  int limit=3000;int parsed;if(int.TryParse(Arg(args,"--timeout-ms","3000"),out parsed))limit=Math.Max(500,Math.Min(5000,parsed));
  var sw=Stopwatch.StartNew();var psi=new ProcessStartInfo {FileName=Process.GetCurrentProcess().MainModule.FileName,Arguments="--light-worker --hwnd "+hwnd+" --output \""+output+"\"",UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden};
  using(var child=Process.Start(psi)){
   if(!child.WaitForExit(limit)){child.Kill();child.WaitForExit(1000);result.Error="UIA_reader_timeout_"+limit+"ms";result.ElapsedMs=sw.ElapsedMilliseconds;Write(output,result);File.Delete(output+".identity.json");return 4;}
  }
  File.Delete(output+".identity.json");
  if(!File.Exists(output)){result.Error="UIA_worker_did_not_write_result";Write(output,result);return 5;}
  result=Json.Deserialize<TitleResult>(File.ReadAllText(output));result.ElapsedMs=sw.ElapsedMilliseconds;Write(output,result);
  Console.WriteLine(Json.Serialize(result));return result.Success?0:3;
 }

 [STAThread] public static int Main(string[] args){
  try{
   if(Array.IndexOf(args,"--watch")>=0)return Watch(args);
   if(Array.IndexOf(args,"--worker")>=0)return Worker(args);
   if(Array.IndexOf(args,"--light-worker")>=0||Array.IndexOf(args,"--direct")>=0)return LightWorker(args);
   if(Array.IndexOf(args,"--full")<0)return Light(args);
   string output=Arg(args,"--output",Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"tree.json"));
   long preferred=long.Parse(Arg(args,"--hwnd","0"));var targets=new List<Identity>();
   EnumWindows(delegate(IntPtr h,IntPtr l){var x=Identify(h);if(Target(x))targets.Add(x);return true;},IntPtr.Zero);
   Identity selected=targets.Find(x=>x.hwnd==preferred);if(selected==null&&targets.Count==1)selected=targets[0];
   if(selected==null){Write(output+".selection.json",new{preferredHwnd=preferred,candidates=targets});Console.WriteLine("No unique verified target; selection metadata only");return 2;}
   Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));Write(output+".identity.json",selected);
   var psi=new ProcessStartInfo{FileName=Process.GetCurrentProcess().MainModule.FileName,Arguments="--worker --hwnd "+selected.hwnd+" --output \""+output+"\"",UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden};
   var overall=Stopwatch.StartNew();bool timedOut=false;int workerPid;
   using(var child=Process.Start(psi)){workerPid=child.Id;if(!child.WaitForExit(WatchdogMs)){timedOut=true;child.Kill();child.WaitForExit(2000);}}
   var nodes=new List<Node>();if(File.Exists(output+".nodes.jsonl"))foreach(var line in File.ReadAllLines(output+".nodes.jsonl"))try{nodes.Add(Json.Deserialize<Node>(line));}catch{}
   object worker=File.Exists(output+".worker.json")?Json.DeserializeObject(File.ReadAllText(output+".worker.json")):null;
   var ended=Identify(new IntPtr(selected.hwnd));
   // Retain the existing diagnostic JSON schema identifier for downstream readers.
   Write(output,new{schema="chatgpt-title-probe-v1",capturedUtc=DateTime.UtcNow.ToString("o"),identity=selected,endedIdentity=ended,identityUnchanged=Same(selected,ended),workerPid=workerPid,watchdogMs=WatchdogMs,timeBudgetMs=BudgetMs,maxNodes=MaxNodes,timedOut=timedOut,elapsedMs=overall.ElapsedMilliseconds,worker=worker,nodes=nodes});
   string hash;using(var sha=SHA256.Create())using(var f=File.OpenRead(output))hash=BitConverter.ToString(sha.ComputeHash(f)).Replace("-","").ToLowerInvariant();
   var candidates=new List<object>();
   foreach(var n in nodes)if(!n.password&&!string.IsNullOrWhiteSpace(n.name)&&n.name.Length<=150&&n.bounds!=null&&n.bounds[1]>=selected.bounds[1]&&n.bounds[1]<selected.bounds[1]+160&&n.bounds[3]>0&&n.bounds[3]<=80&&n.depth>0)candidates.Add(Candidate(n,nodes));
   Write(output+".header_candidates.json",new{identity=selected,outputSha256=hash,nodeCount=nodes.Count,timedOut=timedOut,candidates=candidates});
   Console.WriteLine(Json.Serialize(new{identity=selected,nodeCount=nodes.Count,timedOut=timedOut,identityUnchanged=Same(selected,ended),elapsedMs=overall.ElapsedMilliseconds,output=output,sha256=hash,headerCandidateCount=candidates.Count}));return 0;
  }catch(Exception e){Console.Error.WriteLine(e.GetType().FullName+": "+e.Message);return 1;}
 }
}
