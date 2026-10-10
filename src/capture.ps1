function Get-LaunchOptions($Steam, $AccountId) {
    $map = Read-KeyValues (Join-Path $Steam "userdata\$AccountId\config\localconfig.vdf")
    $app = Get-KvSection $map @('UserLocalConfigStore','Software','Valve','Steam','apps','730')
    if ($app.Contains('LaunchOptions')) { return [string]$app['LaunchOptions'] }
    return ''
}
function Get-SettingsSection($Path, $Section) {
    Get-KvSection (Read-KeyValues $Path) @('config', $Section)
}
function Get-CurrentCrosshair($map) {
    $result = [ordered]@{}
    $legacy = @('cl_crosshairalpha','cl_crosshaircolor','cl_crosshairsize','cl_crosshairthickness','cl_crosshairgap','cl_crosshairusealpha','cl_crosshairgap_useweaponvalue','cl_fixedcrosshairgap','cl_crosshair_outlinethickness')
    if (-not ($map.Contains('cl_crosshair_length') -and $map.Contains('cl_crosshair_thickness') -and $map.Contains('cl_crosshair_gap'))) {
        if ($map.Contains('cl_crosshairsize') -or $map.Contains('cl_crosshairthickness')) { throw 'The saved crosshair uses the old format. Save it in the current CS2 version before capturing this profile.' }
        return $result
    }
    if (-not $map.Contains('cl_crosshair_screen_height')) { throw 'The crosshair reference resolution is missing. Save the crosshair in CS2 first.' }
    foreach ($key in $map.Keys) {
        if ($key -match '^cl_crosshair' -and $key -notin $legacy -and $key -ne 'cl_crosshair_screen_height') { $result[$key] = $map[$key] }
    }
    $result['cl_crosshair_screen_height'] = $map['cl_crosshair_screen_height']
    return $result
}
function Select-GameSettings($Map) {
    $result = [ordered]@{}
    # Only player settings; do not publish passwords, session keys or cached account IDs.
    foreach ($key in $Map.Keys) {
        if ($key -match '^(cl_(crosshair|radar|hud|teamid|radial|quickinventory|scoreboard|predict|buy|sniper|show|mute|color|autohelp|player_ping|ping_fade|observed|net_buffer|hide_avatar|allow_animated|sanitize|deathcampanel|disable_round|dm_buy|enable_party|force_spec|teammate|timeout|use_last|versus|weapon_selection|debounce_zoom|grenadecrosshair|inventory_radial|ironsight|prefer_lefthanded|silencer_mode|use_opens_buy_menu)|snd_|voice_|viewmodel_|spec_|sensitivity|zoom_sensitivity_ratio|m_pitch|m_yaw|mouse_|hud_|safezone|fov_desired$|volume$|dsp_volume$|fps_max|speaker_config$|closecaption$|sv_voiceenable$|rate$|r_(drawtracers_firstperson|fullscreen_gamma|player_visibility_mode|show_build_info|spectator_flashbang_opacity|icon_image_cache_to_disk)|engine_low_latency_sleep_after_client_tick$|mapoverview_|csgo_map_preview_scale$|con_enable$|crosshair$|input_button_code_is_scan_code_scd$|joy_|option_|player_nevershow_communityservermessage$)') {
            $result[$key] = [string]$Map[$key]
        }
    }
    return $result
}
function Get-UserGameFiles($Dir) {
    $files = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Dir -Filter '*.cfg' -File | Sort-Object Name) {
        if ($file.Name -match '^(gamemode_|valve_|subscribed_|banned_|default_|360|joystick|undo_|config_default|cs2-profile-settings\.)' -or $file.Name -in @('server.cfg','server_default.cfg','perftest.cfg','default.cfg','config.cfg','video.cfg','videodefaults.cfg')) { continue }
        $text = [IO.File]::ReadAllText($file.FullName)
        if ($file.Name -eq 'autoexec.cfg') { $text = $text -replace '(?m)^\s*exec\s+"?cs2-profile-settings(?:\.cfg)?"?\s*\r?\n?', '' }
        $files[$file.Name] = $text
    }
    return $files
}
function New-CapturedProfile($Context, $Name, $Id = '') {
    Assert-GameClosed
    $user = Get-SettingsSection (Join-Path $Context.UserCfg 'cs2_user_convars_0_slot0.vcfg') 'convars'
    $video = Get-KvSection (Read-KeyValues (Join-Path $Context.UserCfg 'cs2_video.txt')) @('video.cfg')
    if (-not $user.Count -or -not $video.Count) { throw 'No saved CS2 settings to read. Choose your settings in CS2, exit the game, then retry.' }
    $crosshair = Get-CurrentCrosshair $user
    $filtered = Select-GameSettings $user
    foreach ($key in @($filtered.Keys)) { if ($key -match '^cl_crosshair') { $filtered.Remove($key) } }
    foreach ($key in $crosshair.Keys) { $filtered[$key] = $crosshair[$key] }
    if (-not $Id) { $Id = [guid]::NewGuid().ToString('N') }
    return [ordered]@{
        id = $Id; name = $Name; updatedAt = [DateTime]::UtcNow.ToString('o')
        gameFiles = Get-UserGameFiles $Context.GameCfg
        user = $filtered
        keys = Get-SettingsSection (Join-Path $Context.UserCfg 'cs2_user_keys_0_slot0.vcfg') 'bindings'
        machine = Select-GameSettings (Get-SettingsSection (Join-Path $Context.UserCfg 'cs2_machine_convars.vcfg') 'convars')
        video = $video
        launchOptions = Get-LaunchOptions $Context.Steam $Context.AccountId
    }
}
function Get-StartupCommands($Profile) {
    $lines = New-Object 'Collections.Generic.List[string]'
    foreach ($section in @('machine','user')) {
        foreach ($key in $Profile[$section].Keys) {
            if ($key -eq 'cl_crosshair_screen_height') { continue }
            $name = $key -replace '\$\d+$',''
            if ($name -match '^[a-zA-Z_][a-zA-Z0-9_]*$') { $lines.Add($name + ' ' + (Quote-Kv $Profile[$section][$key])) }
        }
    }
    if ($Profile.user.Contains('cl_crosshair_screen_height')) { $lines.Add('cl_crosshair_screen_height ' + (Quote-Kv $Profile.user['cl_crosshair_screen_height'])) }
    foreach ($key in $Profile.keys.Keys) {
        if ($Profile.keys[$key] -eq '<unbound>') { $lines.Add('unbind ' + (Quote-Kv $key)) }
        else { $lines.Add('bind ' + (Quote-Kv $key) + ' ' + (Quote-Kv $Profile.keys[$key])) }
    }
    return ,$lines.ToArray()
}
