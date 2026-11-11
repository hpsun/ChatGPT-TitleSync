param([string]$ReportPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $ReportPath){$ReportPath=Join-Path $env:TEMP ("chatgpt-titlesync-powershell-check-"+[Guid]::NewGuid().ToString("N")+".json")}
$source=Join-Path $root 'windows/powershell/ChatGPT-TitleSync.ps1'
$tok=$null;$err=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tok,[ref]$err)
if($err.Count){throw ($err|Out-String)}
$text=[IO.File]::ReadAllText($source)
$native=[regex]::Match($text,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
Add-Type -TypeDefinition $native
$fn=$ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Invoke-CgtActivePass'},$true)|Select-Object -First 1
. ([ScriptBlock]::Create($fn.Extent.Text))
$deadlineFn=$ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq "Get-CgtNextDeadline"},$true)|Select-Object -First 1
. ([ScriptBlock]::Create($deadlineFn.Extent.Text))
$jsonFn=$ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq "Convert-CgtReaderJson"},$true)|Select-Object -First 1
. ([ScriptBlock]::Create($jsonFn.Extent.Text))
foreach($name in @('Remember-CgtWindow','New-CgtSourceJob','Maintain-CgtKnown','Apply-CgtSource','Restore-CgtKnown','Get-CgtBackgroundJobs')){
 $f=$ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $name},$true)|Select-Object -First 1
 . ([ScriptBlock]::Create($f.Extent.Text))
}
$script:passed=0
function Assert($yes,$name){if(!$yes){throw "FAIL $name"};$script:passed++;Write-Output "PASS $name"}
function Reset-Fake{
 $script:wa=[pscustomobject]@{Key='A';Hwnd=1;Pid=10}
 $script:wb=[pscustomobject]@{Key='B';Hwnd=2;Pid=10}
 $script:front='A';$script:identity=$true;$script:caps=@{A='Original A';B='Original B'};$script:titles=@{A='项目计划';B='资料整理'}
 $script:reads=0;$script:writes=0;$script:switchRead=$null;$script:changeCaption=$false;$script:states=@{};$script:events=@()
}
$backend=@{
 Targets={if($script:front -eq 'A'){$script:wa}elseif($script:front -eq 'B'){$script:wb}}
 Active={param($w)$script:identity -and $w.Key -eq $script:front}
 Same={param($w)$script:identity}
 Caption={param($w)$script:caps[$w.Key]}
 Read={param($w,$cancel)$script:reads++;if($script:switchRead){$script:front=$script:switchRead};if($script:changeCaption){$script:caps[$w.Key]='External'};[pscustomobject]@{Title=$script:titles[$w.Key]}}
 Set={param($w,$a,$b)if(!$script:identity -or $w.Key -ne $script:front -or $script:caps[$w.Key] -cne $a){return $false};$script:caps[$w.Key]=$b;$script:writes++;return $true}
 Log={param($kind,$w,$code)$script:events+=,$code}
}
$cancel=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset)
try{
 Reset-Fake;$script:front='X';$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($reads -eq 0 -and $writes -eq 0) 'non-ChatGPT foreground has zero reads and writes'
 Reset-Fake;$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($caps.A -ceq '项目计划 — ChatGPT' -and $writes -eq 1) 'active A synchronized'
 $script:front='B';$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($caps.A -ceq '项目计划 — ChatGPT' -and $caps.B -ceq '资料整理 — ChatGPT' -and $states.Count -eq 2) 'inactive caption and lease retained'
 $script:front='A';$script:switchRead='B';$script:titles.A='新项目';$old=$writes;$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($writes -eq $old -and $caps.A -ceq '项目计划 — ChatGPT') 'focus change during reader discards old result'
 $script:switchRead=$null;$script:front='A';$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($caps.A -ceq '新项目 — ChatGPT') 'reactivation synchronizes latest title'
 $script:caps.A='ChatGPT';$script:titles.A='后续项目';$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($caps.A -ceq '后续项目 — ChatGPT' -and 'ExternalCaptionChanged' -notin $events) 'generic native reset has no custom-title backoff'
 $script:caps.A='My custom title';$old=$reads;$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($reads -eq $old -and $caps.A -ceq 'My custom title' -and $states.A.Last -eq $null) 'true custom title preserved with released ownership'
 Reset-Fake;$script:changeCaption=$true;$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($writes -eq 0 -and $caps.A -ceq 'External') 'caption changed during read is preserved'
 Reset-Fake;$null=Invoke-CgtActivePass $backend $states $cancel $true
 Assert ($reads -eq 1 -and $writes -eq 0) 'read-only never writes'
 Reset-Fake;$script:identity=$false;$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($reads -eq 0 -and $writes -eq 0) 'identity mismatch prevents source read'
 Reset-Fake;[void]$cancel.Set();$null=Invoke-CgtActivePass $backend $states $cancel $false
 Assert ($reads -eq 0 -and $writes -eq 0) 'stop cancels pass'
 Assert ($text -match 'IntervalSeconds=2' -and $text -match 'nextForeground=Get-CgtNextDeadline') 'default foreground2 deadline scheduler configured'
 Assert ((Get-CgtNextDeadline 0 200 1000) -eq 1000) "deadline independent of read completion"
 Assert ((Get-CgtNextDeadline 0 3200 1000) -eq 4000) "missed deadlines skipped without backlog"
 Assert ((Get-CgtNextDeadline 0 1000 1000) -eq 1000) "exactly due deadline has no extra sleep"
 $sample=Convert-CgtReaderJson '{"Born":"2026-11-10T05:35:05.2353058Z"}'
 Assert ($sample.Born -is [string] -and $sample.Born -ceq "2026-11-10T05:35:05.2353058Z") "reader creation-time JSON stays exact text across PowerShell versions"
 Assert (![CgtNative]::Set($null,'a','b') -and ![CgtNative]::Active($null)) 'native optional restore and active guards compile'
 # Current three-layer controller tests use only synthetic metadata and captions.
 $protocol=@{
  Active=$backend.Active;Same=$backend.Same;Caption=$backend.Caption
  Set={param($w,$a,$b)if(!$script:identity -or $script:caps[$w.Key] -cne $a){return $false};$script:caps[$w.Key]=$b;$script:writes++;return $true}
  SetActive=$backend.Set
  SetInactive={param($w,$a,$b)if(!$script:identity -or $script:front -eq $w.Key -or $script:caps[$w.Key] -cne $a){return $false};$script:caps[$w.Key]=$b;$script:writes++;return $true}
 }
 function Reset-Protocol{Reset-Fake;$script:caps=@{A='ChatGPT';B='ChatGPT'};$script:states=@{};$script:pidcounter=0L;$script:epoch=0L;$script:now=[DateTime]::SpecifyKind([DateTime]'2000-01-01',[DateTimeKind]::Utc)}
 function Observe($w,$foreground,$title){[void](Remember-CgtWindow $states $w);$script:pidcounter++;$j=New-CgtSourceJob $states $w $foreground $pidcounter $epoch;Apply-CgtSource $protocol $states $j ([pscustomobject]@{Success=$true;Title=$title}) $epoch 30 $false $now}
 Reset-Protocol;Observe $wa $true 'First';$script:caps.A='ChatGPT';Maintain-CgtKnown $protocol $states $false
 Assert ($caps.A -ceq 'ChatGPT') 'foreground never receives a cached replay'
 Observe $wa $true 'Second';Assert ($caps.A -ceq 'Second — ChatGPT') 'foreground uses new direct source'
 $script:front='X';$script:caps.A='ChatGPT';$before=$reads;Maintain-CgtKnown $protocol $states $false
 Assert ($caps.A -ceq 'Second — ChatGPT' -and $reads -eq $before) 'inactive generic native caption repaired without source read'
 $script:caps.A='Custom';Maintain-CgtKnown $protocol $states $false;Observe $wa $false 'Updated'
 Assert ($caps.A -ceq 'Custom' -and $states.A.Cached -ceq 'Updated — ChatGPT') 'custom caption protected while remembered source refreshes'
 $script:caps.A='ChatGPT';Maintain-CgtKnown $protocol $states $false;Assert ($caps.A -ceq 'Updated — ChatGPT') 'generic reset uses latest remembered title'
 Reset-Protocol;$script:front='X';[void](Remember-CgtWindow $states $wb)
 $jobs=@(Get-CgtBackgroundJobs $protocol $states $now $epoch ([ref]$script:pidcounter))
 Assert ($jobs.Count -eq 1 -and !$states.B.Cached) 'unknown background queued without invented cache'
 Apply-CgtSource $protocol $states $jobs[0] ([pscustomobject]@{Success=$true;Title='Discovered'}) $epoch 30 $false $now
 Assert ($caps.B -ceq 'Discovered — ChatGPT') 'low-frequency unknown source establishes cache'
 $early=@(Get-CgtBackgroundJobs $protocol $states ($now.AddSeconds(29)) $epoch ([ref]$script:pidcounter))
 $due=@(Get-CgtBackgroundJobs $protocol $states ($now.AddSeconds(30)) $epoch ([ref]$script:pidcounter))
 Assert ($early.Count -eq 0 -and $due.Count -eq 1) 'custom background source is due independently per window at 30 seconds'
 Reset-Protocol;$script:front='X';[void](Remember-CgtWindow $states $wa);$old=New-CgtSourceJob $states $wa $false 1 0
 $script:front='A';Observe $wa $true 'Fresh';$script:front='X';Apply-CgtSource $protocol $states $old ([pscustomobject]@{Success=$true;Title='Stale'}) 0 30 $false $now
 Assert ($states.A.Cached -ceq 'Fresh — ChatGPT') 'old background result cannot replace newer foreground source'
 Reset-Protocol;Observe $wa $true 'Known';$script:front='X';$script:identity=$false;$before=$writes;Maintain-CgtKnown $protocol $states $false
 Assert ($states.Count -eq 0 -and $writes -eq $before) 'changed identity drops remembered cache'
 Reset-Protocol;[void](Remember-CgtWindow $states $wa);$old=New-CgtSourceJob $states $wa $true 1 0
 Apply-CgtSource $protocol $states $old ([pscustomobject]@{Success=$true;Title='Old'}) 1 30 $false $now
 Assert ($writes -eq 0) 'old generation result is rejected'
 Reset-Protocol;Observe $wa $true 'Owned';Restore-CgtKnown $protocol $states;Assert ($caps.A -ceq 'ChatGPT') 'exit restores only its own still-matching caption'
 Reset-Protocol;Observe $wa $true 'Owned';$script:caps.A='Custom';Restore-CgtKnown $protocol $states
 Assert ($caps.A -ceq 'Custom') 'exit preserves manual caption'
 Reset-Protocol;$script:front='X';[void](Remember-CgtWindow $states $wb);$waiting=@(Get-CgtBackgroundJobs $protocol $states $now 0 ([ref]$script:pidcounter));$script:front='A'
 Observe $wa $true 'Foreground immediate'
 Assert ($caps.A -ceq 'Foreground immediate — ChatGPT' -and $states.B.Pending -ne 0) 'pending background source does not block foreground commit'
 Assert ($text -match 'BackgroundIntervalSeconds=5' -and $text -match 'WaitChild\(\$task.Handle,0\)') 'background interval and nonblocking owned-task polling are configured'
 $report=@{Utc=[DateTime]::UtcNow.ToString('o');Passed=$passed;Failed=0;PowerShell=$PSVersionTable.PSVersion.ToString();RealChatGPTAccess=$false;NativeSourceCompiled=$true;Scope='Current three-layer controller plus legacy regressions with synthetic metadata; no real window access'}
 [IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}finally{$cancel.Dispose()}
