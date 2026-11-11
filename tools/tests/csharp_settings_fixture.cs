// Self-owned settings controls and fake scheduling only; no native window discovery.
using System;using System.IO;using System.Threading;using System.Windows.Forms;using System.Reflection;using System.Collections.Generic;using System.Web.Script.Serialization;
namespace ChatGptTitle {
 static class SettingsFixture {
  static int failed;static List<object> checks=new List<object>();
  static void Check(string name,bool pass){checks.Add(new{Name=name,Pass=pass});if(!pass)failed++;}
  static void Click(Button button){typeof(Button).GetMethod("OnClick",BindingFlags.NonPublic|BindingFlags.Instance).Invoke(button,new object[]{EventArgs.Empty});}
  [STAThread]static int Main(string[] args){string dir=args[0];Directory.CreateDirectory(dir);string path=Path.Combine(dir,"settings.json");var c=new Config();Check("new_config_defaults_are_foreground2_background5",c.ChatGptTitlePollMilliseconds==2000&&c.ChatGptTitleBackgroundRefreshSeconds==5);
   ScanSettings.Apply(path,c,null,7,45);Check("settings_apply_updates_both_live_config_fields",c.ChatGptTitlePollMilliseconds==7000&&c.ChatGptTitleBackgroundRefreshSeconds==45);
   c.ChatGptWindowTitleEnabled=false;ScanSettings.Save(path,false,7,45);var loaded=new Config();ScanSettings.Load(path,loaded,false,false);Check("restart_restores_enabled_and_intervals",!loaded.ChatGptWindowTitleEnabled&&loaded.ChatGptTitlePollMilliseconds==7000&&loaded.ChatGptTitleBackgroundRefreshSeconds==45);
   var cli=new Config{ChatGptTitlePollMilliseconds=2000,ChatGptTitleBackgroundRefreshSeconds=60};ScanSettings.Load(path,cli,true,true);Check("explicit_cli_intervals_override_saved_values",cli.ChatGptTitlePollMilliseconds==2000&&cli.ChatGptTitleBackgroundRefreshSeconds==60&&!cli.ChatGptWindowTitleEnabled);
   string before=File.ReadAllText(path);foreach(var pair in new[]{new[]{0,30},new[]{1,4},new[]{3601,30},new[]{1,3601}}){try{ScanSettings.Apply(path,c,null,pair[0],pair[1]);Check("invalid_interval_rejected",false);}catch(ArgumentOutOfRangeException){Check("invalid_interval_rejected",File.ReadAllText(path)==before&&c.ChatGptTitlePollMilliseconds==7000);}}
   int saves=0;using(var form=ScanSettings.CreateForm(c,delegate(int fg,int bg){saves++;ScanSettings.Apply(path,c,null,fg,bg);})){
    var fg=(TextBox)form.Controls["ForegroundSeconds"];var bg=(TextBox)form.Controls["BackgroundSeconds"];var save=(Button)form.Controls["Save"];
    fg.Text="1.5";Click(save);Check("noninteger_ui_input_keeps_dialog_and_config",saves==0&&!form.IsDisposed&&form.Controls["Error"].Text.Length>0);
    fg.Text="1";bg.Text="4";Click(save);Check("out_of_range_ui_input_is_inline_without_save",saves==0&&!form.IsDisposed);
    fg.Text="3";bg.Text="15";Click(save);Check("valid_ui_values_save_and_apply",saves==1&&c.ChatGptTitlePollMilliseconds==3000&&c.ChatGptTitleBackgroundRefreshSeconds==15);
   }
   Check("atomic_persistence_leaves_no_temporary_files",Directory.GetFiles(dir,"*.tmp").Length==0);
   File.WriteAllText(Path.Combine(dir,"csharp-settings-tests.json"),new JavaScriptSerializer().Serialize(new{Pass=failed==0,Count=checks.Count,Failed=failed,Scope="Never-shown owned WinForms controls; no real ChatGPT, UIA or shared stop",Checks=checks}));Console.WriteLine("Settings="+checks.Count+" Failed="+failed);return failed==0?0:2;
  }
 }
}
