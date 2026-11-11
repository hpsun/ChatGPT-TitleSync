// Standalone Windows application. C# 5 / .NET Framework 4.x.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Drawing;
using Microsoft.Win32;
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

namespace ChatGptTitle {
 public sealed class Config {
  public volatile bool ChatGptWindowTitleEnabled=true;
  public volatile int ChatGptTitlePollMilliseconds=2000;
  public volatile int ChatGptTitleBackgroundRefreshSeconds=5;
 }
 // Shared current-user preference; constructors and command formatting have no registry side effects.
 internal sealed class AutoStartRegistration {
  internal const string RunPath=@"Software\Microsoft\Windows\CurrentVersion\Run", PreferencePath=@"Software\ChatGPT-TitleSync", ValueName="ChatGPT-TitleSync";
  readonly string runPath,preferencePath,valueName;readonly Action beforePreferenceWrite;
  internal AutoStartRegistration():this(RunPath,PreferencePath,ValueName,null){}
  internal AutoStartRegistration(string run,string preference,string name,Action fault){runPath=run;preferencePath=preference;valueName=name;beforePreferenceWrite=fault;}
  sealed class SavedValue {internal bool Exists;internal object Value;internal RegistryValueKind Kind;}
  static SavedValue Capture(string path,string name){using(var key=Registry.CurrentUser.OpenSubKey(path,false)){if(key==null||!key.GetValueNames().Contains(name,StringComparer.OrdinalIgnoreCase))return new SavedValue();return new SavedValue{Exists=true,Value=key.GetValue(name,null,RegistryValueOptions.DoNotExpandEnvironmentNames),Kind=key.GetValueKind(name)};}}
  static void Restore(string path,string name,SavedValue saved){using(var key=Registry.CurrentUser.CreateSubKey(path)){if(key==null)throw new IOException("Cannot open the current-user startup key.");if(saved.Exists)key.SetValue(name,saved.Value,saved.Kind);else key.DeleteValue(name,false);}}
  internal bool ReadPreference(){using(var key=Registry.CurrentUser.OpenSubKey(preferencePath,false)){if(key==null)return true;object value=key.GetValue("AutoStartEnabled");return !(value is int&&(int)value==0);}}
  internal static string Command(string executable){if(String.IsNullOrWhiteSpace(executable)||!Path.IsPathRooted(executable)||executable.IndexOf('"')>=0)throw new ArgumentException("An absolute executable path is required.");return "\""+Path.GetFullPath(executable)+"\"";}
  internal bool Initialize(string command){bool enabled=ReadPreference();Apply(enabled,command);return enabled;}
  internal void Apply(bool enabled,string command){
   if(enabled&&String.IsNullOrWhiteSpace(command))throw new ArgumentException("The startup command is empty.");
   if(enabled&&command.Length>260)throw new ArgumentException("Windows Run startup commands cannot exceed 260 characters. Move the program to a shorter path.");
   var oldRun=Capture(runPath,valueName);var oldPreference=Capture(preferencePath,"AutoStartEnabled");
   bool runMatches=enabled?oldRun.Exists&&oldRun.Kind==RegistryValueKind.String&&String.Equals(oldRun.Value as string,command,StringComparison.Ordinal):!oldRun.Exists;
   bool preferenceMatches=oldPreference.Exists&&oldPreference.Kind==RegistryValueKind.DWord&&oldPreference.Value is int&&(int)oldPreference.Value==(enabled?1:0);
   if(runMatches&&preferenceMatches)return;
   try {
    using(var key=Registry.CurrentUser.CreateSubKey(runPath)){if(key==null)throw new IOException("Cannot open the current-user startup key.");if(enabled)key.SetValue(valueName,command,RegistryValueKind.String);else key.DeleteValue(valueName,false);}
    if(beforePreferenceWrite!=null)beforePreferenceWrite();
    using(var key=Registry.CurrentUser.CreateSubKey(preferencePath)){if(key==null)throw new IOException("Cannot open the current-user preference key.");key.SetValue("AutoStartEnabled",enabled?1:0,RegistryValueKind.DWord);}
   }catch(Exception cause){
    var errors=new List<Exception>{cause};try{Restore(runPath,valueName,oldRun);}catch(Exception e){errors.Add(e);}try{Restore(preferencePath,"AutoStartEnabled",oldPreference);}catch(Exception e){errors.Add(e);}
    throw new InvalidOperationException(errors.Count==1?"Auto-start could not be changed; previous values were restored.":"Auto-start failed and rollback was incomplete.",new AggregateException(errors));
   }
  }
 }
 // Only a successful persistence callback changes UI state. Tests can inject an owned registry or a fake callback.
 internal sealed class AutoStartUiState {
  internal bool Enabled{get;private set;}readonly Action<bool> persist;internal event Action<bool> Changed;
  internal AutoStartUiState(bool enabled,Action<bool> save){Enabled=enabled;persist=save;}
  internal void Set(bool enabled){persist(enabled);Enabled=enabled;if(Changed!=null)Changed(enabled);}
  internal ToolStripMenuItem CreateMenu(Func<Form> currentForm,Action<Exception> error){
   var item=new ToolStripMenuItem("开机自启动 / Start at sign-in"){Name="AutoStartEnabled",Checked=Enabled};
   Changed+=delegate(bool enabled){item.Checked=enabled;Form form=currentForm();if(form!=null&&!form.IsDisposed){var check=form.Controls["AutoStartEnabled"] as CheckBox;if(check!=null)check.Checked=enabled;}};
   item.Click+=delegate{try{Set(!Enabled);}catch(Exception e){error(e);}};return item;
  }
 }
 internal static class ScanSettings {
  [System.Runtime.InteropServices.DllImport("user32.dll")]static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int width,int height,uint flags);
  // STARTUPINFO(SW_HIDE) can consume the first Show. Explicitly reveal this owned settings form.
  internal static void RevealPreparedHandle(IntPtr handle){SetWindowPos(handle,IntPtr.Zero,0,0,0,0,0x0040|0x0001|0x0002|0x0004|0x0010);}
  internal static void ShowPrepared(Form form,bool activate=true){form.Show();RevealPreparedHandle(form.Handle);if(activate)form.Activate();}

  internal static void Validate(int foreground,int background){if(foreground<1||foreground>3600)throw new ArgumentOutOfRangeException("foreground","Foreground interval must be 1..3600 seconds.");if(background<5||background>3600)throw new ArgumentOutOfRangeException("background","Background interval must be 5..3600 seconds.");}
  internal static void Save(string path,bool enabled,int foreground,int background){
   Validate(foreground,background);Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));
   string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
   try{File.WriteAllText(temp,new JavaScriptSerializer().Serialize(new{Enabled=enabled,ForegroundSeconds=foreground,BackgroundSeconds=background}),new System.Text.UTF8Encoding(false));
    for(int attempt=0;;attempt++){try{if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);break;}catch(IOException ex){if(((ex.HResult&65535)!=32&&(ex.HResult&65535)!=33)||(attempt>=4))throw;Thread.Sleep(20*(attempt+1));}}
   }finally{try{if(File.Exists(temp))File.Delete(temp);}catch(IOException){}}
  }
  internal static void Load(string path,Config config,bool explicitForeground,bool explicitBackground){
   try{if(!File.Exists(path))return;Dictionary<string,object> value;using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var text=new StreamReader(file))value=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(text.ReadToEnd());
    if(value.ContainsKey("Enabled"))config.ChatGptWindowTitleEnabled=Convert.ToBoolean(value["Enabled"]);
    int fg=value.ContainsKey("ForegroundSeconds")?Convert.ToInt32(value["ForegroundSeconds"]):config.ChatGptTitlePollMilliseconds/1000;
    int bg=value.ContainsKey("BackgroundSeconds")?Convert.ToInt32(value["BackgroundSeconds"]):config.ChatGptTitleBackgroundRefreshSeconds;Validate(fg,bg);
    if(!explicitForeground)config.ChatGptTitlePollMilliseconds=fg*1000;if(!explicitBackground)config.ChatGptTitleBackgroundRefreshSeconds=bg;
   }catch{}
  }
  internal static void Apply(string path,Config config,ChatGptWindowTitleMonitor monitor,int foreground,int background){
   Save(path,config.ChatGptWindowTitleEnabled,foreground,background);
   config.ChatGptTitlePollMilliseconds=foreground*1000;config.ChatGptTitleBackgroundRefreshSeconds=background;if(monitor!=null)monitor.Wake();
  }
  internal static void ApplyWithAutoStart(string path,Config config,ChatGptWindowTitleMonitor monitor,AutoStartUiState autoStart,int foreground,int background,bool requested){
   Validate(foreground,background);bool previous=autoStart.Enabled;autoStart.Set(requested);
   try{Apply(path,config,monitor,foreground,background);}catch(Exception cause){try{autoStart.Set(previous);}catch(Exception rollback){throw new AggregateException("Settings save failed and auto-start rollback was incomplete.",cause,rollback);}throw;}
  }
  internal static Icon ApplyThemeSettings(string path,Config config,ChatGptWindowTitleMonitor monitor,AutoStartUiState autoStart,TitleSyncThemes.ThemeService themes,int foreground,int background,bool requestedStartup,TitleSyncThemes.ThemeChoice request,Func<int,Icon> prepare){
   Validate(foreground,background);var plan=themes.Plan(request.Mode,request.FixedIcon,request.Period);Icon prepared=prepare(plan.Icon);var snapshot=themes.Capture();
   try{themes.Commit(plan);try{ApplyWithAutoStart(path,config,monitor,autoStart,foreground,background,requestedStartup);}catch{themes.Restore(snapshot);throw;}return prepared;}catch{prepared.Dispose();throw;}
  }
  internal static Form CreateForm(Config config,Action<int,int> save){return CreateForm(config,true,delegate(int foreground,int background,bool autoStart){save(foreground,background);});}
  internal static Form CreateForm(Config config,bool autoStart,Action<int,int,bool> save){return CreateForm(config,autoStart,new TitleSyncThemes.ThemeChoice(),delegate(int a,int b,bool startup,TitleSyncThemes.ThemeChoice theme){save(a,b,startup);});}
  internal static Form CreateForm(Config config,bool autoStart,TitleSyncThemes.ThemeChoice theme,Action<int,int,bool,TitleSyncThemes.ThemeChoice> save){
   var form=new Form{Text="ChatGPT-TitleSync — 设置 / Settings",ClientSize=new Size(500,410),FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false,StartPosition=FormStartPosition.CenterScreen};
   var fg=new TextBox{Name="ForegroundSeconds",Text=(config.ChatGptTitlePollMilliseconds/1000).ToString(),Location=new Point(300,23),Width=100};
   var bg=new TextBox{Name="BackgroundSeconds",Text=config.ChatGptTitleBackgroundRefreshSeconds.ToString(),Location=new Point(300,65),Width=100};
   form.Controls.Add(new Label{Text="前台扫描（秒） / Foreground (1–3600)",AutoSize=true,Location=new Point(16,27)});form.Controls.Add(fg);
   form.Controls.Add(new Label{Text="后台刷新（秒） / Background (5–3600)",AutoSize=true,Location=new Point(16,69)});form.Controls.Add(bg);
   var startup=new CheckBox{Name="AutoStartEnabled",Text="开机自启动 / Start at sign-in",Checked=autoStart,AutoSize=true,Location=new Point(16,104)};form.Controls.Add(startup);
   form.Controls.Add(new Label{Text="后台标题回改检测保持每1秒。 / Native cache repair: 1s.",AutoSize=true,Location=new Point(16,274)});
   var error=new Label{Name="Error",ForeColor=Color.DarkRed,Location=new Point(16,300),Size=new Size(468,44)};form.Controls.Add(error);
   var ok=new Button{Name="Save",Text="保存 / Save",Location=new Point(280,365),Width=90};var cancel=new Button{Name="Cancel",Text="取消 / Cancel",Location=new Point(380,365),Width=100,DialogResult=DialogResult.Cancel};
   ok.Click+=delegate{int a,b;if(!Int32.TryParse(fg.Text.Trim(),out a)||!Int32.TryParse(bg.Text.Trim(),out b)){error.Text="请输入整数秒数。 / Enter whole seconds.";return;}try{Validate(a,b);var draft=theme.Copy();draft.Mode=((ComboBox)form.Controls["IconMode"]).SelectedIndex==0?"fixed":"random";draft.FixedIcon=45+((ComboBox)form.Controls["FixedIcon"]).SelectedIndex;draft.Period=new[]{"day","hour","5min"}[((ComboBox)form.Controls["IconPeriod"]).SelectedIndex];save(a,b,startup.Checked,draft);form.Close();}catch(Exception e){error.Text=e.Message;}};
   // DialogResult alone does not close a modeless form. Cancel must discard the draft and close explicitly.
   cancel.Click+=delegate{form.Close();};
   form.Controls.Add(ok);form.Controls.Add(cancel);form.AcceptButton=ok;form.CancelButton=cancel;
   // Append noneditable controls after existing buttons so the two Edit fields and prior control IDs stay stable.
   var mode=new ComboBox{Name="IconMode",DropDownStyle=ComboBoxStyle.DropDownList,Location=new Point(280,143),Width=200};mode.Items.AddRange(new object[]{"固定 / Fixed","随机 / Random"});mode.SelectedIndex=theme.Mode=="random"?1:0;
   var fixedIcon=new ComboBox{Name="FixedIcon",DropDownStyle=ComboBoxStyle.DropDownList,Location=new Point(280,185),Width=200};fixedIcon.Items.AddRange(new object[]{"45 — 蓝紫 / Violet","46 — 湖蓝 / Lake blue","47 — 琥珀 / Amber","48 — 薄荷 / Mint","49 — 玫红 / Rose","50 — 天蓝 / Sky","51 — 浅紫 / Lavender","52 — 珊瑚 / Coral"});fixedIcon.SelectedIndex=theme.FixedIcon-45;
   var period=new ComboBox{Name="IconPeriod",DropDownStyle=ComboBoxStyle.DropDownList,Location=new Point(280,227),Width=200};period.Items.AddRange(new object[]{"每日 / Daily","每小时 / Hourly","每5分钟 / Every 5 min"});period.SelectedIndex=Array.IndexOf(new[]{"day","hour","5min"},theme.Period);
   Action sync=delegate{fixedIcon.Enabled=mode.SelectedIndex==0;period.Enabled=mode.SelectedIndex==1;};mode.SelectedIndexChanged+=delegate{sync();};sync();
   form.Controls.Add(new Label{Text="图标模式 / Icon mode",AutoSize=true,Location=new Point(16,147)});form.Controls.Add(mode);form.Controls.Add(new Label{Text="固定配色 / Fixed color",AutoSize=true,Location=new Point(16,189)});form.Controls.Add(fixedIcon);form.Controls.Add(new Label{Text="随机换色 / Random period",AutoSize=true,Location=new Point(16,231)});form.Controls.Add(period);return form;
  }
 }
 static class App {
  // Keep the legacy singleton and events so old and renamed versions cannot write concurrently.
  const string MutexName="Local\\TdxChatGptTitleStandalone", StopName=MutexName+".Stop";
  static string Arg(string[] args,string key,string fallback) {
   int i=Array.IndexOf(args,key);return i>=0&&i+1<args.Length?args[i+1]:fallback;
  }
  static string ThemeDirectory(){string root=AppDomain.CurrentDomain.BaseDirectory;foreach(string relative in new[]{Path.Combine("assets","themes"),Path.Combine("..","assets","themes"),Path.Combine("..","..","assets","themes")}){string path=Path.GetFullPath(Path.Combine(root,relative));if(Directory.Exists(path))return path;}return Path.GetFullPath(Path.Combine(root,"..","..","assets","themes"));}
  internal static void ApplyThemeIcon(NotifyIcon tray,Form form,Icon next,ref Icon current,ref Icon formArtwork){
   Icon prior=current,priorForm=formArtwork;Icon nextForm=form!=null&&!form.IsDisposed?(Icon)next.Clone():null;
   try{tray.Icon=next;if(nextForm!=null)form.Icon=nextForm;}catch{try{tray.Icon=prior??SystemIcons.Application;}catch{}if(nextForm!=null)nextForm.Dispose();throw;}
   current=next;formArtwork=nextForm;if(prior!=null)prior.Dispose();if(priorForm!=null)priorForm.Dispose();
  }
  static Icon LoadThemeIcon(string folder,int id){if(id<45||id>52)throw new ArgumentOutOfRangeException("id");return new Icon(Path.Combine(folder,id.ToString()+".ico"));}
  static void ThemeError(string directory,Exception error){try{File.AppendAllText(Path.Combine(directory,"theme-errors.log"),DateTime.UtcNow.ToString("o")+" IconThemeFailure "+error.GetType().Name+Environment.NewLine);}catch{}}
  [STAThread] static int Main(string[] args) {
   if(Array.IndexOf(args,"--settings")>=0){try{using(var e=EventWaitHandle.OpenExisting(MutexName+".Settings"))e.Set();return 0;}catch(WaitHandleCannotBeOpenedException){return 4;}}
   if(Array.IndexOf(args,"--stop")>=0) {
    try{using(var e=EventWaitHandle.OpenExisting(StopName))e.Set();}
    catch(WaitHandleCannotBeOpenedException){}return 0;
   }
   // Preserve the existing settings/log/cache location across the branding-only rename.
   string directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ChatGPT-title","csharp");
   Directory.CreateDirectory(directory);
   string helper=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ChatGPT-TitleSync.Reader.exe");
   var config=new Config();
   int seconds;if(!Int32.TryParse(Arg(args,"--interval","2"),out seconds)||seconds<1||seconds>3600)return 2;
   config.ChatGptTitlePollMilliseconds=seconds*1000;
   int backgroundSeconds;if(!Int32.TryParse(Arg(args,"--background-interval","5"),out backgroundSeconds)||backgroundSeconds<5||backgroundSeconds>3600)return 2;
   config.ChatGptTitleBackgroundRefreshSeconds=backgroundSeconds;
   if(Array.IndexOf(args,"--read-only")>=0) {
    var records=new List<object>();
    using(var cancel=new ManualResetEvent(false)) {
     var reader=new ChatGptProcessHeaderReader(helper,directory);
     foreach(var window in new NativeChatGptTitleWindows().Enumerate()) {
      var result=reader.Read(window,4000,cancel);
      records.Add(new {window.Hwnd,window.Pid,window.ProcessStartUtc,result.Success,result.Title,result.Locator,result.ErrorCode});
     }
    }
    string output=Path.GetFullPath(Arg(args,"--output",Path.Combine(directory,"read-only-results.json")));
    Directory.CreateDirectory(Path.GetDirectoryName(output));
    File.WriteAllText(output,new JavaScriptSerializer().Serialize(records),new System.Text.UTF8Encoding(false));return 0;
   }
   bool owns=false;
   using(var mutex=new Mutex(false,MutexName)) {
    try {
     try{owns=mutex.WaitOne(0);}catch(AbandonedMutexException){owns=true;}
     if(!owns){MessageBox.Show("A standalone ChatGPT-TitleSync monitor is already running.","ChatGPT-TitleSync");return 3;}
     // Register only this normal resident after it owns the shared singleton. Read-only and IPC entries returned above.
     var registration=new AutoStartRegistration();string startupCommand=AutoStartRegistration.Command(Application.ExecutablePath);bool startupEnabled=false;
     try{startupEnabled=registration.Initialize(startupCommand);}catch(Exception e){MessageBox.Show(e.Message,"ChatGPT-TitleSync — Auto-start");}
     var startupState=new AutoStartUiState(startupEnabled,delegate(bool value){registration.Apply(value,startupCommand);});
     string settings=Path.Combine(directory,"settings.json");
     ScanSettings.Load(settings,config,Array.IndexOf(args,"--interval")>=0,Array.IndexOf(args,"--background-interval")>=0);
     Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
     using(var stop=new EventWaitHandle(false,EventResetMode.ManualReset,StopName))
     using(var settingsEvent=new EventWaitHandle(false,EventResetMode.AutoReset,MutexName+".Settings"))
     using(var marshal=new Control())
     using(var tray=new NotifyIcon())
     using(var monitor=new ChatGptWindowTitleMonitor(config,delegate{return false;},helper,directory)) {
      stop.Reset();IntPtr handle=marshal.Handle;
      Form intervalForm=null;Icon settingsArtwork=null;Icon artwork=null;string themeFolder=ThemeDirectory();var random=new Random();
      var themes=new TitleSyncThemes.ThemeService(TitleSyncThemes.ThemeService.PreferenceKey,delegate{return DateTimeOffset.Now;},delegate(int count){return random.Next(count);},delegate(int id){using(var checkedIcon=LoadThemeIcon(themeFolder,id)){}},null);
      try{themes.Load();}catch(Exception e){ThemeError(directory,e);}
      Action<Icon> useIcon=delegate(Icon next){ApplyThemeIcon(tray,intervalForm,next,ref artwork,ref settingsArtwork);};
      try{string iconPath=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"..","..","assets","chatgpt-titlesync.ico"));if(File.Exists(iconPath))artwork=new Icon(iconPath);else artwork=Icon.ExtractAssociatedIcon(Application.ExecutablePath);}catch{}
      tray.Icon=artwork??SystemIcons.Application;
      try{var initial=themes.PlanTick();if(initial!=null){using(var checkedIcon=LoadThemeIcon(themeFolder,initial.Icon)){}themes.Commit(initial);}useIcon(LoadThemeIcon(themeFolder,themes.Current.Icon));}catch(Exception e){themes.MarkTickFailed();ThemeError(directory,e);}
      tray.Text="ChatGPT-TitleSync / ChatGPT 标题同步助手";
      var menu=new ContextMenuStrip();
      var enabled=new ToolStripMenuItem("Enable window titles"){Checked=config.ChatGptWindowTitleEnabled};
      enabled.Click+=delegate {
       bool previous=config.ChatGptWindowTitleEnabled;config.ChatGptWindowTitleEnabled=!previous;
       try {
        ScanSettings.Save(settings,config.ChatGptWindowTitleEnabled,config.ChatGptTitlePollMilliseconds/1000,config.ChatGptTitleBackgroundRefreshSeconds);
        enabled.Checked=config.ChatGptWindowTitleEnabled;monitor.Wake();
       } catch(Exception ex){config.ChatGptWindowTitleEnabled=previous;MessageBox.Show(ex.Message,"ChatGPT-TitleSync");}
      };
      menu.Items.Add(enabled);
      var intervals=new ToolStripMenuItem("扫描间隔设置… / Scan intervals…");
      intervals.Click+=delegate{if(intervalForm!=null&&!intervalForm.IsDisposed){ScanSettings.ShowPrepared(intervalForm);return;}intervalForm=ScanSettings.CreateForm(config,startupState.Enabled,themes.Current,delegate(int foreground,int background,bool autoStart,TitleSyncThemes.ThemeChoice requested){
       Icon prepared=ScanSettings.ApplyThemeSettings(settings,config,monitor,startupState,themes,foreground,background,autoStart,requested,delegate(int id){return LoadThemeIcon(themeFolder,id);});try{useIcon(prepared);prepared=null;}finally{if(prepared!=null)prepared.Dispose();}
      });if(artwork!=null){settingsArtwork=(Icon)artwork.Clone();intervalForm.Icon=settingsArtwork;}intervalForm.FormClosed+=delegate{if(settingsArtwork!=null){settingsArtwork.Dispose();settingsArtwork=null;}};ScanSettings.ShowPrepared(intervalForm);};
      menu.Items.Add(intervals);
      menu.Items.Add(startupState.CreateMenu(delegate{return intervalForm;},delegate(Exception e){MessageBox.Show(e.Message,"ChatGPT-TitleSync — Auto-start");}));
      menu.Items.Add("Exit and restore titles",null,delegate{stop.Set();Application.ExitThread();});
      tray.ContextMenuStrip=menu;tray.Visible=true;monitor.Start();
      var stopWait=ThreadPool.RegisterWaitForSingleObject(stop,delegate(object state,bool timedOut){try{marshal.BeginInvoke((Action)delegate{Application.ExitThread();});}catch{}},null,Timeout.Infinite,true);
      var settingsWait=ThreadPool.RegisterWaitForSingleObject(settingsEvent,delegate(object state,bool timedOut){try{marshal.BeginInvoke((Action)delegate{intervals.PerformClick();});}catch{}},null,Timeout.Infinite,false);
      using(var themeTimer=new System.Windows.Forms.Timer{Interval=1000}){themeTimer.Tick+=delegate{try{var plan=themes.PlanTick();if(plan==null)return;Icon prepared=LoadThemeIcon(themeFolder,plan.Icon);try{themes.Commit(plan);useIcon(prepared);prepared=null;}finally{if(prepared!=null)prepared.Dispose();}}catch(Exception e){themes.MarkTickFailed();ThemeError(directory,e);}};themeTimer.Start();
      try{Application.Run();}
      finally{settingsWait.Unregister(null);stopWait.Unregister(null);stop.Set();if(intervalForm!=null)intervalForm.Dispose();monitor.Dispose();tray.Visible=false;menu.Dispose();if(artwork!=null)artwork.Dispose();}
      }
     }
     return 0;
    }finally{if(owns)mutex.ReleaseMutex();}
   }
  }
 }
}
