$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$names=@('storage','capture','platform','apply','export','ui')
$parts=@($names | ForEach-Object {[IO.File]::ReadAllText((Join-Path $repo "src\$_.ps1"))})
$script:CoreSource=$parts -join "`r`n"
foreach ($part in $parts) { . ([scriptblock]::Create($part)) }
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Throws($Action,$Message) { $caught=$false; try { & $Action | Out-Null } catch {$caught=$true}; Assert $caught $Message }
# All writes are isolated here. Never point these tests at Steam's real userdata.
$fixture=Join-Path $PSScriptRoot ('.tmp-profiles-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
function Assert-GameClosed { }
try {
    $video=[ordered]@{
        Version='16';VendorID='old';DeviceID='old';Autoconfig='2'
        'setting.defaultres'='1440';'setting.defaultresheight'='1080';'setting.fullscreen'='1'
        'setting.refreshrate_numerator'='600000';'setting.refreshrate_denominator'='1000'
        'setting.monitor_index'='0';'setting.msaa_samples'='4';'setting.r_csgo_cmaa_enable'='0'
        'setting.r_texturefilteringquality'='2';'setting.videocfg_hdr_detail'='-1';'setting.videocfg_fsr_detail'='0'
    }
    $profile=[ordered]@{ id=('a'*32);name='Test';updatedAt='';gameFiles=[ordered]@{'autoexec.cfg'="exec custom`r`n";'custom.cfg'='sensitivity 9'};
        user=[ordered]@{sensitivity='2.2';cl_crosshair_length='4';cl_crosshair_thickness='1';cl_crosshair_gap='2';cl_crosshair_screen_height='1080'}
        keys=[ordered]@{SPACE='+jump';v='<unbound>'};machine=[ordered]@{volume='0.25'};video=$video;launchOptions='-novid +exec "my config" -freq 600' }
    $other=Copy-Data $profile; $other.id='b'*32; $other.name='Other'
    $pack=[ordered]@{schemaVersion=1;name='Test config';profiles=@($profile,$other)}
    Assert-Pack $pack
    $hardware=@{Identity=@{VendorID='4318';DeviceID='1234';'setting.knowndevice'='1';Autoconfig='2'};Modes=@(@(1440,1080,60),@(1440,1080,144),@(1920,1080,600));Reason=''}
    $plan=Get-VideoPlan $video ([ordered]@{}) $hardware
    Assert ($plan.Values['setting.refreshrate_numerator'] -eq '144000') 'Refresh fallback used a different resolution or ignored the maximum.'
    Assert ($video['setting.refreshrate_numerator'] -eq '600000') 'Planning mutated the profile.'
    Assert ($plan.Issues.Count -eq 1 -and $plan.Issues[0].Kind -eq 'Adjusted') 'Refresh adjustment was not reported.'
    Assert ($plan.Values.VendorID -eq '4318' -and $plan.Values.DeviceID -eq '1234') 'Source GPU identity leaked into the target.'
    $full=Copy-Data $hardware; $full.Modes=,@(1440,1080,600)
    Assert ((Get-VideoPlan $video ([ordered]@{}) $full).Values['setting.refreshrate_numerator'] -eq '600000') 'Supported refresh was changed.'
    $unsupported=Copy-Data $video; $unsupported['setting.defaultres']='1234'
    $local=[ordered]@{'setting.defaultres'='1920';'setting.defaultresheight'='1080';'setting.refreshrate_numerator'='144000';'setting.refreshrate_denominator'='1000'}
    $bad=Get-VideoPlan $unsupported $local $hardware
    Assert ($bad.Values['setting.defaultres'] -eq '1920' -and $bad.Values['setting.msaa_samples'] -eq '4') 'Display rejection did not preserve display while applying quality.'
    $missing=Copy-Data $video; $missing.Remove('setting.refreshrate_numerator')
    Assert (@((Get-VideoPlan $missing $local $hardware).Issues | Where-Object {$_.Setting -eq 'Display'}).Count -eq 1) 'Missing refresh was silently accepted.'
    $badQuality=Copy-Data $video; $badQuality['setting.msaa_samples']='99'
    Assert (@((Get-VideoPlan $badQuality $local $hardware).Issues | Where-Object {$_.Setting -eq 'Multisampling Anti-Aliasing Mode'}).Count -eq 1) 'Invalid quality value was accepted.'
    $aaLocal=Copy-Data $local; $aaLocal['setting.r_csgo_cmaa_enable']='1'
    Assert ((Get-VideoPlan $badQuality $aaLocal $hardware).Values['setting.r_csgo_cmaa_enable'] -eq '1') 'Skipping antialiasing disabled existing CMAA.'
    $context=[pscustomobject]@{UserCfg=(Join-Path $fixture 'Steam\userdata\42\730\local\cfg');GameCfg=(Join-Path $fixture 'Game\cfg');Steam=(Join-Path $fixture 'Steam');AccountId='42'}
    $result=Invoke-ApplyPlan (New-ApplyPlan $profile $context $hardware)
    Assert ((Get-EffectiveLaunchOptions $profile (New-ApplyPlan $profile $context $hardware)) -match '-freq 144$') 'Launch options undo the adjusted refresh rate.'
    Assert ($profile.launchOptions -match '-freq 600$') 'Adjusted launch options mutated the stored profile.'
    Assert (Test-Path -LiteralPath (Join-Path $context.UserCfg 'cs2_video.txt')) 'First application did not create missing userdata.'
    Assert ($result.Saved.Count -eq 5) 'First application did not save every independent group.'
    $saved=Get-KvSection (Read-KeyValues (Join-Path $context.UserCfg 'cs2_video.txt')) @('video.cfg')
    Assert ($saved['setting.refreshrate_numerator'] -eq '144000') 'Adjustment was not written.'
    $commands=[IO.File]::ReadAllText((Join-Path $context.GameCfg 'cs2-profile-settings.cfg'))
    Assert ($commands.IndexOf('cl_crosshair_screen_height') -gt $commands.IndexOf('cl_crosshair_gap')) 'Crosshair reference height is out of order.'
    $auto=[IO.File]::ReadAllText((Join-Path $context.GameCfg 'autoexec.cfg'))
    Assert ($auto.IndexOf('exec cs2-profile-settings') -gt $auto.IndexOf('exec custom')) 'Captured settings do not override stale custom settings.'
    $userPath=Join-Path $context.UserCfg 'cs2_user_convars_0_slot0.vcfg'
    Merge-SettingsFile $userPath 'convars' ([ordered]@{untouched='keep'})
    [void](Invoke-ApplyPlan (New-ApplyPlan $profile $context $hardware))
    Assert ((Get-SettingsSection $userPath 'convars').untouched -eq 'keep') 'Applying removed unrelated target values.'
    $blocked=Join-Path $fixture 'not-a-directory'; Write-TextFile $blocked 'blocked'
    $partialContext=[pscustomobject]@{UserCfg=$blocked;GameCfg=$context.GameCfg}
    $partial=Invoke-ApplyPlan @{Profile=$profile;Context=$partialContext;Video=$plan}
    Assert ($partial.Issues.Count -gt 1 -and $partial.Saved -contains 'Startup configs') 'Independent write failure stopped all application.'
    $steamConfig=[ordered]@{UserLocalConfigStore=[ordered]@{Software=[ordered]@{Valve=[ordered]@{Steam=[ordered]@{apps=[ordered]@{'999'=[ordered]@{LaunchOptions='wrong'};'730'=[ordered]@{LaunchOptions=$profile.launchOptions}}}}}}}
    Write-TextFile (Join-Path $context.Steam 'userdata\42\config\localconfig.vdf') (ConvertTo-KeyValues $steamConfig)
    Assert ((Get-LaunchOptions $context.Steam '42') -ceq $profile.launchOptions) 'Launch options were filtered or read from the wrong app.'
    $capture=New-CapturedProfile $context 'Captured'
    Assert ($capture.launchOptions -ceq $profile.launchOptions) 'Capture changed launch options.'
    Assert (-not $capture.gameFiles.Contains('cs2-profile-settings.cfg')) 'Capture recaptured its generated overlay.'
    Assert (-not (Select-GameSettings ([ordered]@{password='secret';ui_playsettings_directchallengekey='secret';volume='0.5'})).Contains('password')) 'Capture included a password.'
    $roundtrip=ConvertFrom-KeyValues (ConvertTo-KeyValues $steamConfig)
    Assert ($roundtrip.UserLocalConfigStore.Software.Valve.Steam.apps['730'].LaunchOptions -ceq $profile.launchOptions) 'Quoted VDF roundtrip failed.'
    Throws { ConvertFrom-KeyValues '"root" { "key" "value"' } 'Incomplete VDF was accepted.'
    $evil=Copy-Data $pack; $evil.profiles[0].gameFiles['..\escape.cfg']='bad'
    Throws { Assert-Pack $evil } 'Traversal filename was accepted.'
    $duplicate=Copy-Data $pack; $duplicate.profiles[1].name='test'
    Throws { Assert-Pack $duplicate } 'Case-insensitive duplicate profile name was accepted.'
    $packRoot=Join-Path $fixture ("folder with spaces & apostrophe's " + [char]0x041f)
    Export-Pack $pack $packRoot
    $loaded=Read-Pack $packRoot ''
    $before=ConvertTo-Json -InputObject $loaded.profiles[1] -Depth 30 -Compress
    $loaded.profiles[0].user.sensitivity='3.5'
    Export-Pack $loaded $packRoot
    $after=Read-Pack $packRoot ''
    Assert ((ConvertTo-Json -InputObject $after.profiles[1] -Depth 30 -Compress) -ceq $before) 'Updating one profile changed another.'
    $launcher=[IO.File]::ReadAllText((Join-Path $packRoot 'apply-config.cmd'))
    $scriptText=$launcher.Substring($launcher.IndexOf('::PS1::')+7)
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($scriptText,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Generated launcher failed PowerShell parsing.'
    $extracted=[regex]::Match($scriptText,'(?ms)^# BEGIN CORE\r?\n(.*?)^# END CORE\r?$').Groups[1].Value.Trim()
    Assert ($extracted -ceq ($script:CoreSource.Trim() -replace "`r?`n","`r`n")) 'Launcher source cannot regenerate itself.'
    # Locate the data literal on the final call, without evaluating the launcher.
    $embeddedMatch=[regex]::Match($scriptText, "(?m)^try \{ Start-ConfigTool .* '([A-Za-z0-9+/=]+)' \}")
    $standalone=Read-Pack (Join-Path $fixture 'empty') $embeddedMatch.Groups[1].Value
    Assert ($standalone.profiles.Count -eq 2 -and $standalone.profiles[0].user.sensitivity -eq '3.5') 'Standalone CMD has stale or missing profiles.'
    # Run the actual CMD wrapper with redirected input, including a Unicode path.
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$env:ComSpec
    $start.Arguments='/d /c ""'+(Join-Path $packRoot 'apply-config.cmd')+'" -Mode menu"'
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($start)
    $process.StandardInput.WriteLine('0'); $process.StandardInput.Close()
    $outputTask=$process.StandardOutput.ReadToEndAsync(); $errorTask=$process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(15000)) { $process.Kill(); throw 'CMD smoke test did not exit.' }
    $stdout=$outputTask.Result; $stderr=$errorTask.Result
    Assert ($process.ExitCode -eq 0 -and $stdout -match 'Choose option below:' -and -not $stderr) ('CMD smoke test failed: '+$stdout+$stderr)
    $choices=New-Object 'Collections.Generic.Queue[string]'; $choices.Enqueue('');$choices.Enqueue('9');$choices.Enqueue('1')
    function Read-Host { param($Prompt); return $choices.Dequeue() }
    Assert ((Read-Choice @(0,1)) -eq 1 -and $choices.Count -eq 0) 'Blank input selected a default.'
    function Get-Context { return $context }
    function Get-DisplayHardware { return $hardware }
    foreach ($inputValue in @('1','1','0','0','0')) { $choices.Enqueue($inputValue) }
    Start-ConfigTool 'menu' $packRoot '' 6>$null
    Assert ($choices.Count -eq 0) 'Menu navigation did not return through profile selection.'
    Write-Output 'Profile checks passed: capture, explicit choice, isolation, standalone export, first-run paths, GPU identity, partial writes and refresh fallback.'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $allowed=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike '.tmp-profiles-*') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
