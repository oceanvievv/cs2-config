$script:DisplayKeys = @('setting.defaultres','setting.defaultresheight','setting.fullscreen','setting.coop_fullscreen','setting.nowindowborder','setting.refreshrate_numerator','setting.refreshrate_denominator','setting.monitor_index','setting.aspectratiomode')
$script:VideoChoices = [ordered]@{
    'setting.msaa_samples'=@('Multisampling Anti-Aliasing Mode', @{'0'='None';'2'='2x MSAA';'4'='4x MSAA';'8'='8x MSAA'})
    'setting.videocfg_shadow_quality'=@('Global Shadow Quality', @{'0'='Low';'1'='Medium';'2'='High';'3'='Very High'})
    'setting.videocfg_dynamic_shadows'=@('Dynamic Shadows', @{'0'='Sun Only';'1'='All'})
    'setting.videocfg_texture_detail'=@('Model / Texture Detail', @{'0'='Low';'1'='Medium';'2'='High'})
    'setting.r_texturefilteringquality'=@('Texture Filtering Mode', @{'0'='Bilinear';'1'='Trilinear';'2'='Anisotropic 2x';'3'='Anisotropic 4x';'4'='Anisotropic 8x';'5'='Anisotropic 16x'})
    'setting.shaderquality'=@('Shader Detail', @{'0'='Low';'1'='High'})
    'setting.videocfg_particle_detail'=@('Particle Detail', @{'0'='Low';'1'='Medium';'2'='High';'3'='Very High'})
    'setting.videocfg_ao_detail'=@('Ambient Occlusion', @{'0'='Disabled';'2'='Medium';'3'='High'})
    'setting.videocfg_hdr_detail'=@('High Dynamic Range', @{'3'='Performance';'-1'='Quality'})
    'setting.videocfg_fsr_detail'=@('FidelityFX Super Resolution', @{'0'='Disabled (Highest Quality)';'1'='Ultra Quality';'2'='Quality';'3'='Balanced';'4'='Performance'})
    'setting.mat_vsync'=@('Vertical Sync', @{'0'='Disabled';'1'='Enabled'})
    'setting.r_low_latency'=@('NVIDIA Reflex Low Latency', @{'0'='Disabled';'1'='Enabled';'2'='Enabled + Boost'})
}
function New-Issue($Setting,$Reason,$Kind='Skipped') { [pscustomobject]@{ Setting=$Setting; Reason=$Reason; Kind=$Kind } }
function Get-VideoPlan($Video, $Local, $Hardware) {
    $out = Copy-Data $Local
    $issues = New-Object 'Collections.Generic.List[object]'
    $adjustedRate = 0
    if (-not $Video.Count) { $issues.Add((New-Issue 'Video' 'No video settings in this profile.')); return @{ Values=$out; Issues=$issues; Changed=$false } }
    if (-not $Hardware.Identity.VendorID -or -not $Hardware.Identity.DeviceID) {
        $issues.Add((New-Issue 'Video' 'The graphics device could not be identified.'))
        return @{ Values=$out; Issues=$issues; Changed=$false }
    }
    $reason = $Hardware.Reason
    foreach ($key in @('setting.defaultres','setting.defaultresheight','setting.fullscreen','setting.refreshrate_numerator','setting.refreshrate_denominator')) {
        if (-not $Video.Contains($key)) { $reason = 'Resolution, display mode or refresh rate is missing.' }
    }
    $width=0; $height=0; $num=0; $den=0
    if (-not [int]::TryParse($Video['setting.defaultres'],[ref]$width) -or $width -le 0 -or
        -not [int]::TryParse($Video['setting.defaultresheight'],[ref]$height) -or $height -le 0 -or
        -not [int]::TryParse($Video['setting.refreshrate_numerator'],[ref]$num) -or $num -le 0 -or
        -not [int]::TryParse($Video['setting.refreshrate_denominator'],[ref]$den) -or $den -le 0 -or
        $Video['setting.fullscreen'] -notin @('0','1')) { $reason = 'Resolution, display mode or refresh rate is invalid.' }
    if (-not $reason -and $Video['setting.fullscreen'] -eq '1') {
        $rates = @($Hardware.Modes | Where-Object { $_[0] -eq $width -and $_[1] -eq $height -and $_[2] -gt 1 } | ForEach-Object { $_[2] })
        $maximum = ($rates | Measure-Object -Maximum).Maximum
        if ($rates.Count -and ($num / $den) -gt ($maximum + 1.1)) {
            $adjustedRate = [int]$maximum
            $issues.Add((New-Issue 'Refresh Rate' ("{0:0.###} Hz -> {1} Hz - maximum supported at {2} x {3}." -f ($num/$den),$maximum,$width,$height) 'Adjusted'))
        } elseif (-not @($rates | Where-Object { [Math]::Abs($_ - ($num / $den)) -lt 1.1 }).Count) {
            $reason = 'The requested resolution and refresh rate are unavailable.'
        }
    }
    if ($reason) {
        $issues.Add((New-Issue 'Display' $reason))
        if (-not $Local.Contains('setting.defaultres')) {
            $issues.Add((New-Issue 'Advanced video' 'Choose an available display mode before preparing video settings on this PC.'))
            return @{ Values=$out; Issues=$issues; Changed=$false }
        }
    }
    foreach ($key in $Video.Keys) {
        if ($key -in @('VendorID','DeviceID','Version','Autoconfig','setting.knowndevice')) { continue }
        if ($key -in $script:DisplayKeys -and $reason) { continue }
        if ($key -eq 'setting.r_csgo_cmaa_enable' -and $Video.Contains('setting.msaa_samples') -and -not $script:VideoChoices['setting.msaa_samples'][1].ContainsKey($Video['setting.msaa_samples'])) { continue }
        if ($script:VideoChoices.Contains($key) -and -not $script:VideoChoices[$key][1].ContainsKey($Video[$key])) {
            $issues.Add((New-Issue $script:VideoChoices[$key][0] 'The profile contains an unsupported value.')); continue
        }
        $out[$key] = $Video[$key]
    }
    if ($adjustedRate) {
        $out['setting.refreshrate_numerator'] = [string]($adjustedRate * 1000)
        $out['setting.refreshrate_denominator'] = '1000'
    }
    if (-not $out.Contains('Version')) { $out.Version = $Video.Version }
    foreach ($key in $Hardware.Identity.Keys) { $out[$key] = $Hardware.Identity[$key] }
    return @{ Values=$out; Issues=$issues; Changed=$true }
}
function Merge-SettingsFile($Path,$Section,$Values) {
    $root = Read-KeyValues $Path
    if (-not $root.Contains('config')) { $root.config = [ordered]@{} }
    if (-not $root.config.Contains($Section)) { $root.config[$Section] = [ordered]@{} }
    foreach ($key in $Values.Keys) { $root.config[$Section][$key] = $Values[$key] }
    Write-TextFile $Path (ConvertTo-KeyValues $root)
}
function New-ApplyPlan($Profile,$Context,$Hardware=$null) {
    $path = Join-Path $Context.UserCfg 'cs2_video.txt'
    try {
        $local = Get-KvSection (Read-KeyValues $path) @('video.cfg')
        if ($null -eq $Hardware) { $Hardware = Get-DisplayHardware $Profile.video $path }
        $video = Get-VideoPlan $Profile.video $local $Hardware
    } catch {
        $video=@{Values=@{};Changed=$false;Issues=@((New-Issue 'Video' 'The display or existing video settings could not be read.'))}
    }
    return @{ Video=$video; Context=$Context; Profile=$Profile }
}
function Get-EffectiveLaunchOptions($Profile,$Plan) {
    $line=$Profile.launchOptions
    if (@($Plan.Video.Issues | Where-Object {$_.Kind -eq 'Adjusted' -and $_.Setting -eq 'Refresh Rate'}).Count) {
        $hz=[int]([double]$Plan.Video.Values['setting.refreshrate_numerator'] / [double]$Plan.Video.Values['setting.refreshrate_denominator'])
        $line=[regex]::Replace($line,'(?i)(?<!\S)(-freq|-refresh|-refreshrate)\s+(?:"[^"]*"|\S+)', {param($m) $m.Groups[1].Value+' '+$hz})
    }
    return $line
}
function Invoke-ApplyPlan($Plan) {
    Assert-GameClosed
    $profile=$Plan.Profile; $ctx=$Plan.Context
    $issues = New-Object 'Collections.Generic.List[object]'
    foreach ($issue in $Plan.Video.Issues) { $issues.Add($issue) }
    $saved = New-Object 'Collections.Generic.List[string]'
    # Each independent destination is verified separately; a video failure does not
    # prevent mouse, binds or audio from being written.
    foreach ($item in @(@('user','cs2_user_convars_0_slot0.vcfg','convars','Player settings'), @('machine','cs2_machine_convars.vcfg','convars','Audio, HUD and radar'), @('keys','cs2_user_keys_0_slot0.vcfg','bindings','Controls'))) {
        if (-not $profile[$item[0]].Count) { continue }
        try { Merge-SettingsFile (Join-Path $ctx.UserCfg $item[1]) $item[2] $profile[$item[0]]; $saved.Add($item[3]) }
        catch { $issues.Add((New-Issue $item[3] 'Could not save or verify the settings. Check the folder permissions.')) }
    }
    if ($Plan.Video.Changed) {
        try { Write-TextFile (Join-Path $ctx.UserCfg 'cs2_video.txt') (ConvertTo-KeyValues ([ordered]@{ 'video.cfg'=$Plan.Video.Values })); $saved.Add('Video') }
        catch { $issues.Add((New-Issue 'Video' 'Could not save or verify the settings. Check the folder permissions.')) }
    }
    $gameFailed = $false
    foreach ($name in $profile.gameFiles.Keys) {
        if ($name -in @('autoexec.cfg','cs2-profile-settings.cfg')) { continue }
        try { Write-TextFile (Join-Path $ctx.GameCfg $name) $profile.gameFiles[$name] }
        catch { $gameFailed=$true }
    }
    try {
        Write-TextFile (Join-Path $ctx.GameCfg 'cs2-profile-settings.cfg') ((Get-StartupCommands $profile) -join "`r`n")
        $auto = [string]$profile.gameFiles['autoexec.cfg']
        $auto = $auto -replace '(?m)^\s*exec\s+"?cs2-profile-settings(?:\.cfg)?"?\s*\r?\n?', ''
        Write-TextFile (Join-Path $ctx.GameCfg 'autoexec.cfg') ($auto.TrimEnd() + "`r`nexec cs2-profile-settings`r`n")
    } catch { $gameFailed=$true }
    if ($gameFailed) { $issues.Add((New-Issue 'Startup configs' 'Some config files could not be saved or verified. Check the folder permissions.')) }
    else { $saved.Add('Startup configs') }
    return @{ Saved=$saved.ToArray(); Issues=$issues.ToArray() }
}
