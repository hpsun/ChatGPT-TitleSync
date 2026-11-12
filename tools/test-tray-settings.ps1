param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$OutputDirectory){$OutputDirectory=Join-Path $env:TEMP ('chatgpt-titlesync-settings-'+[Guid]::NewGuid().ToString('N'))}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
# App.cs references the shared Unicode rules assembly; build/copy only, never launch its editor.
& (Join-Path $root 'shared/windows/Build.ps1') -OutputDirectory $OutputDirectory
$rulesExe=Join-Path $OutputDirectory 'ChatGPT-TitleSync.Rules.exe'
$fixture=Join-Path $OutputDirectory 'csharp-settings-fixture.exe'
& $csc /nologo /target:exe /optimize+ /main:ChatGptTitle.SettingsFixture "/out:$fixture" "/reference:$rulesExe" /reference:System.Web.Extensions.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll (Join-Path $root 'windows/csharp/App.cs') (Join-Path $root 'windows/csharp/TitleMonitor.cs') (Join-Path $PSScriptRoot 'tests/csharp_settings_fixture.cs')
if($LASTEXITCODE){throw 'Settings fixture compilation failed.'}
& $fixture (Join-Path $OutputDirectory 'csharp')
if($LASTEXITCODE){throw 'C# settings checks failed.'}
$source=Join-Path $root 'windows/powershell/ChatGPT-TitleSync.ps1';$tok=$null;$err=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tok,[ref]$err)
if($err.Count){throw ($err|Out-String)}
foreach($name in @('Write-Result','Save-CgtSettings','Open-CgtScanSettings','Initialize-CgtTray')){
 $fn=$ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)|Select-Object -First 1
 # Prevent owned fixture controls/tray from appearing or taking focus. Event callbacks stay unchanged.
 $text=$fn.Extent.Text.Replace("[void][Windows.Forms.MessageBox]::Show(`$_.Exception.Message,'ChatGPT-TitleSync')",'throw').Replace('$form.Show();[void][CgtNative]::ShowSettingsWindow($form.Handle.ToInt64());$form.Activate()','[void]$form.Handle').Replace('$state.Form.Show();[void][CgtNative]::ShowSettingsWindow($state.Form.Handle.ToInt64());$state.Form.Activate()','[void]$state.Form.Handle').Replace('$tray.Visible=$true','$tray.Visible=$false').Replace('$PSScriptRoot',"'"+(Split-Path $source -Parent).Replace("'","''")+"'")
 . ([ScriptBlock]::Create($text))
}
$checks=[Collections.Generic.List[object]]::new();$failed=0
function Check($name,$yes){$checks.Add(@{Name=$name;Pass=[bool]$yes});if(!$yes){$script:failed++;Write-Output "FAIL $name"}else{Write-Output "PASS $name"}}
function Click-Control($button){$button.GetType().GetMethod('OnClick',[Reflection.BindingFlags]'NonPublic,Instance').Invoke($button,@([EventArgs]::Empty))}
$path=Join-Path $OutputDirectory 'powershell-settings.json';$state=@{Enabled=$true;Foreground=2;Background=5;Revision=0;Quit=$false;Form=$null;Tray=$null;Menu=$null;Icon=$null}
try{
 Initialize-CgtTray $state $path
 Check 'tray_has_enable_settings_startup_and_exit_actions' ($state.Menu.Items.Count -eq 5 -and $state.Menu.Items[2].Name -eq 'AutoStartEnabled' -and $state.Menu.Items[3].Text -like 'Exit*' -and $state.Menu.Items[4].Text -like '*Name replacement*')
 $state.Menu.Items[1].PerformClick();$form=$state.Form
 Check 'settings_menu_callback_builds_inputs' ($null -ne $form -and $form.Controls['ForegroundSeconds'].Text -eq '2' -and $form.Controls['BackgroundSeconds'].Text -eq '5')
 $buttons=@($form.Controls|Where-Object {$_ -is [Windows.Forms.Button]});$save=$buttons|Where-Object {$_.Text -like '*Save*'}
 $form.Controls['ForegroundSeconds'].Text='0';Click-Control $save
 Check 'invalid_range_does_not_save_or_mutate' ($state.Revision -eq 0 -and !(Test-Path -LiteralPath $path))
 $form.Controls['ForegroundSeconds'].Text='2.5';Click-Control $save
 Check 'noninteger_does_not_save_or_mutate' ($state.Revision -eq 0)
 $form.Controls['ForegroundSeconds'].Text='7';$form.Controls['BackgroundSeconds'].Text='45';Click-Control $save
 $saved=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 Check 'valid_ui_save_is_immediate_and_persistent' ($state.Foreground -eq 7 -and $state.Background -eq 45 -and $state.Revision -eq 1 -and $saved.ForegroundSeconds -eq 7 -and $saved.BackgroundSeconds -eq 45)
 $state.Menu.Items[0].PerformClick();$saved=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 Check 'enable_toggle_preserves_both_saved_intervals' (!$state.Enabled -and !$saved.Enabled -and $saved.ForegroundSeconds -eq 7 -and $saved.BackgroundSeconds -eq 45)
 $state.Menu.Items[1].PerformClick()
 Check 'reopened_dialog_uses_current_live_values' ($state.Form.Controls['ForegroundSeconds'].Text -eq '7' -and $state.Form.Controls['BackgroundSeconds'].Text -eq '45')
 $state.Menu.Items[3].PerformClick();Check 'exit_menu_requests_normal_shutdown' $state.Quit
 Check 'atomic_save_has_no_leftover_temporary_files' (@(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.tmp').Count -eq 0)
}finally{if($state.Form){$state.Form.Dispose()};if($state.Tray){$state.Tray.Dispose()};if($state.Menu){$state.Menu.Dispose()};if($state.Icon){$state.Icon.Dispose()}}
$report=@{Pass=($failed -eq 0);Count=$checks.Count;Failed=$failed;PowerShell=$PSVersionTable.PSVersion.ToString();Scope='Never-shown owned controls and tray; no real ChatGPT, UIA, singleton or shared stop';Checks=$checks.ToArray()}
Write-Result (Join-Path $OutputDirectory 'powershell-tray-settings-tests.json') $report
if($failed){throw 'PowerShell settings checks failed.'}

# A separate owned WinExe confirms the actual STARTUPINFO Hidden first-show behavior.
# Its windows are offscreen and WS_EX_NOACTIVATE; no real foreground target is accessed.
$nativeText=[regex]::Match([IO.File]::ReadAllText($source),"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
# The application and PowerShell bridge intentionally share the same theme backend.
# This fixture needs only CgtNative/CgtAutoStart; App.cs supplies TitleSyncThemes once.
$themeBoundary=$nativeText.IndexOf('namespace TitleSyncThemes {',[StringComparison]::Ordinal)
if($themeBoundary -lt 0){throw 'The expected shared theme backend boundary was not found.'}
$nativeText=$nativeText.Substring(0,$themeBoundary)
$bridgeSource=Join-Path $OutputDirectory 'PowerShellNativeBridge.cs'
[IO.File]::WriteAllText($bridgeSource,$nativeText,[Text.UTF8Encoding]::new($false))
$startupFixture=Join-Path $OutputDirectory 'startup-hidden-fixture.exe'
& $csc /nologo /target:winexe /optimize+ /main:ChatGptTitle.StartupHiddenFixture "/out:$startupFixture" "/reference:$rulesExe" /reference:System.Web.Extensions.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll (Join-Path $root 'windows/csharp/App.cs') (Join-Path $root 'windows/csharp/TitleMonitor.cs') $bridgeSource (Join-Path $PSScriptRoot 'tests/startup_hidden_fixture.cs')
if($LASTEXITCODE){throw 'Hidden startup fixture compilation failed.'}
foreach($implementation in @('csharp','powershell')){
 $receipt=Join-Path $OutputDirectory ($implementation+'-startup-hidden.json')
 $owned=Start-Process -FilePath $startupFixture -ArgumentList @($implementation,('"'+$receipt+'"')) -WindowStyle Hidden -PassThru -Wait
 $result=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
 if($owned.ExitCode -or !$result.Pass){throw ('Hidden startup visibility check failed: '+$implementation)}
 Write-Output ('PASS actual STARTUPINFO Hidden first-show visibility / '+$implementation)
}
