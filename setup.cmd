@echo off
setlocal
title CS2 CONFIG
set "CS2_OLD_CP="
for /f "tokens=2 delims=:" %%c in ('chcp') do set "CS2_OLD_CP=%%c"
chcp 65001 >nul
set "CS2_LAUNCHER=%~f0"
set "CS2_PACK_ROOT=%~dp0"
set "CS2_RUN_FILE=%TEMP%\cs2-config-%RANDOM%-%RANDOM%.ps1"
powershell -NoProfile -Command "$t=[IO.File]::ReadAllText($env:CS2_LAUNCHER); $m=[Environment]::NewLine+'::'+'PS1'+'::'+[Environment]::NewLine; $i=$t.IndexOf($m); if($i -lt 0){exit 1}; [IO.File]::WriteAllText($env:CS2_RUN_FILE,$t.Substring($i+$m.Length),(New-Object Text.UTF8Encoding($true)))"
if errorlevel 1 goto broken
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%CS2_RUN_FILE%" %*
set "CS2_RESULT=%ERRORLEVEL%"
if exist "%CS2_RUN_FILE%" del "%CS2_RUN_FILE%"
if defined CS2_OLD_CP chcp %CS2_OLD_CP% >nul
exit /b %CS2_RESULT%
:broken
echo This file could not be opened. Download it again or use the console instructions.
pause
if defined CS2_OLD_CP chcp %CS2_OLD_CP% >nul
exit /b 1
::PS1::
param([ValidateSet('menu','create','update','apply')][string]$Mode = 'create')
$ErrorActionPreference = 'Stop'
# BEGIN CORE
# Windows PowerShell 5.1. Profiles are data, never executable PowerShell.
$TOOL_VERSION = '2.0.5'
$script:Utf8 = New-Object Text.UTF8Encoding($false)
function ConvertTo-Map($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $map = [ordered]@{}
        foreach ($key in $Value.Keys) { $map[$key] = ConvertTo-Map $Value[$key] }
        return $map
    }
    if ($Value -is [pscustomobject]) {
        $map = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $map[$property.Name] = ConvertTo-Map $property.Value }
        return $map
    }
    if ($Value -is [array]) { return ,@($Value | ForEach-Object { ConvertTo-Map $_ }) }
    return $Value
}
function Copy-Data($Value) { ConvertTo-Map (ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 50)) }
function ConvertFrom-KeyValues([string]$Text) {
    $tokens = [regex]::Matches($Text, '(?m)//[^\r\n]*|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+')
    $state = @{ Index = 0; Tokens = @($tokens | Where-Object { -not $_.Value.StartsWith('//') } | ForEach-Object { $_.Value }) }
    function Read-KvToken($token) {
        if ($token.StartsWith('"')) { return $token.Substring(1, $token.Length - 2).Replace('\"','"').Replace('\\','\') }
        return $token
    }
    function Read-KvObject($state, $nested) {
        $map = [ordered]@{}
        while ($state.Index -lt $state.Tokens.Count) {
            $key = $state.Tokens[$state.Index++ ]
            if ($key -eq '}') { if (-not $nested) { throw 'Invalid settings file.' }; return $map }
            if ($key -eq '{' -or $state.Index -ge $state.Tokens.Count) { throw 'Invalid settings file.' }
            $key = Read-KvToken $key
            $value = $state.Tokens[$state.Index++ ]
            if ($value -eq '{') { $value = Read-KvObject $state $true }
            elseif ($value -eq '}') { throw 'Invalid settings file.' }
            else { $value = Read-KvToken $value }
            $map[$key] = $value
        }
        if ($nested) { throw 'Incomplete settings file.' }
        return $map
    }
    Read-KvObject $state $false
}
function Read-KeyValues($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [ordered]@{} }
    ConvertFrom-KeyValues ([IO.File]::ReadAllText($Path))
}
function Quote-Kv([string]$Text) { '"' + $Text.Replace('\','\\').Replace('"','\"').Replace("`r",'').Replace("`n",' ') + '"' }
function ConvertTo-KeyValues($Map, [int]$Depth = 0) {
    $lines = New-Object 'Collections.Generic.List[string]'
    foreach ($key in $Map.Keys) {
        $prefix = ("`t" * $Depth) + (Quote-Kv $key)
        if ($Map[$key] -is [System.Collections.IDictionary]) {
            $lines.Add($prefix); $lines.Add(("`t" * $Depth) + '{')
            $lines.Add((ConvertTo-KeyValues $Map[$key] ($Depth + 1)))
            $lines.Add(("`t" * $Depth) + '}')
        } else { $lines.Add($prefix + "`t`t" + (Quote-Kv $Map[$key])) }
    }
    return ($lines -join "`r`n") + "`r`n"
}
function Get-KvSection($Map, [string[]]$Path) {
    foreach ($key in $Path) {
        if ($Map -isnot [System.Collections.IDictionary] -or -not $Map.Contains($key)) { return [ordered]@{} }
        $Map = $Map[$key]
    }
    return $Map
}
function Write-TextFile($Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temp = Join-Path $parent ('.cs2-write-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temp, $Text, $script:Utf8)
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
        if ([IO.File]::ReadAllText($Path) -cne $Text) { throw 'The saved file could not be verified.' }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
function Assert-Pack($Pack) {
    if ($Pack.schemaVersion -ne 1 -or -not $Pack.name -or $Pack.profiles -isnot [array]) { throw 'This config could not be read. Check profiles.json.' }
    $names = @{}; $ids = @{}
    foreach ($profile in $Pack.profiles) {
        if (-not $profile.name -or $profile.name -match '[\x00-\x1f]' -or $names.ContainsKey($profile.name)) { throw 'Profile names must be unique and non-empty.' }
        if ($profile.id -notmatch '^[a-f0-9]{32}$' -or $ids.ContainsKey($profile.id)) { throw 'Invalid profile identifier.' }
        $names[$profile.name] = $true; $ids[$profile.id] = $true
        foreach ($section in @('gameFiles','user','keys','machine','video')) {
            if ($profile[$section] -isnot [System.Collections.IDictionary]) { throw "Profile '$($profile.name)' is incomplete." }
        }
        foreach ($name in $profile.gameFiles.Keys) {
            if ($name -notmatch '^[^<>:"/\\|?*\x00-\x1f]+\.cfg$' -or $name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])\.') { throw 'A config contains an invalid filename.' }
            if ($profile.gameFiles[$name] -isnot [string]) { throw 'Invalid game config content.' }
        }
        foreach ($section in @('user','keys','machine','video')) {
            foreach ($key in $profile[$section].Keys) {
                if ($profile[$section][$key] -isnot [string] -or $key -match '[\r\n\x00]') { throw 'Invalid setting value.' }
            }
        }
        if ($profile.launchOptions -isnot [string] -or $profile.launchOptions -match '[\r\n\x00]') { throw 'Invalid launch options.' }
    }
}
function Read-Pack($Root, $Embedded) {
    $path = Join-Path $Root 'profiles.json'
    if (Test-Path -LiteralPath $path) { $pack = ConvertTo-Map (ConvertFrom-Json ([IO.File]::ReadAllText($path))) }
    elseif ($Embedded) { $pack = ConvertTo-Map (ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Embedded)))) }
    else { $pack = [ordered]@{ schemaVersion = 1; name = 'cs2-config'; profiles = @() } }
    Assert-Pack $pack
    return $pack
}

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

function Copy-LaunchOptions([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $data = New-Object System.Windows.Forms.DataObject
        $data.SetText($Text, [System.Windows.Forms.TextDataFormat]::UnicodeText)
        # Persist after this process exits; retry when another app has the clipboard open.
        [System.Windows.Forms.Clipboard]::SetDataObject($data, $true, 10, 100)
        $copied = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::UnicodeText)
        return [string]::Equals($copied, $Text, [StringComparison]::Ordinal)
    } catch { return $false }
}
function Assert-GameClosed {
    if (Get-Process -Name cs2 -ErrorAction SilentlyContinue) { throw 'Close CS2 to continue. Exit the game normally, then retry.' }
}
function Find-Steam {
    foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')) {
        $item = Get-ItemProperty $key -ErrorAction SilentlyContinue
        foreach ($path in @($item.SteamPath,$item.InstallPath)) {
            if ($path -and (Test-Path -LiteralPath $path -PathType Container)) { return [IO.Path]::GetFullPath($path.Replace('/','\')) }
        }
    }
    return ''
}
function Find-Game($Steam) {
    $roots = @($Steam)
    $libraries = Get-KvSection (Read-KeyValues (Join-Path $Steam 'steamapps\libraryfolders.vdf')) @('libraryfolders')
    foreach ($value in $libraries.Values) { if ($value -is [System.Collections.IDictionary] -and $value.Contains('path')) { $roots += $value.path } }
    foreach ($root in $roots | Select-Object -Unique) {
        $path = Join-Path $root 'steamapps\common\Counter-Strike Global Offensive'
        if (Test-Path -LiteralPath (Join-Path $path 'game\csgo\cfg') -PathType Container) { return $path }
    }
    return ''
}
function Get-SteamAccounts($Steam) {
    $users = Get-KvSection (Read-KeyValues (Join-Path $Steam 'config\loginusers.vdf')) @('users')
    foreach ($steamId in $users.Keys) {
        if ($steamId -notmatch '^\d{17}$') { continue }
        $account = [uint64]$steamId - [uint64]76561197960265728
        if ($account -gt [uint32]::MaxValue) { continue }
        [pscustomobject]@{ Id = [string]$account; Name = [string]$users[$steamId].PersonaName }
    }
}
function Get-Context {
    Assert-GameClosed
    $steam = Find-Steam
    while (-not $steam -or -not (Test-Path -LiteralPath (Join-Path $steam 'steam.exe'))) {
        Show-Header 'Steam installation not found'
        $steam = Read-Host 'Steam folder (0 to go back)'
        if ($steam -eq '0') { return $null }
        $steam = $steam.Trim().Trim('"')
    }
    $game = Find-Game $steam
    while (-not $game -or -not (Test-Path -LiteralPath (Join-Path $game 'game\csgo\cfg'))) {
        Show-Header 'CS2 installation not found'
        $game = Read-Host 'CS2 installation folder (0 to go back)'
        if ($game -eq '0') { return $null }
        $game = $game.Trim().Trim('"')
    }
    # ActiveUser does not depend on an existing 730 directory: this also works before
    # the account's first CS2 launch. Never guess the most recently modified folder.
    $active = (Get-ItemProperty 'HKCU:\Software\Valve\Steam\ActiveProcess' -ErrorAction SilentlyContinue).ActiveUser
    $accounts = @(Get-SteamAccounts $steam)
    $accountId = ''
    if ($active -and $active -gt 0 -and (Get-Process -Name steam -ErrorAction SilentlyContinue)) { $accountId = [string]$active }
    if (-not $accountId) {
        if (-not $accounts.Count) { throw 'Sign in to Steam with the account you want to use, then retry.' }
        Show-Header 'Choose a Steam account'
        for ($i=0; $i -lt $accounts.Count; $i++) { Write-Host "  [$($i+1)] $($accounts[$i].Name) (account $($accounts[$i].Id))" }
        Write-Host '  [0] Back'
        $index = Read-Choice (0..$accounts.Count)
        if ($index -eq 0) { return $null }
        $accountId = $accounts[$index-1].Id
    }
    return [pscustomobject]@{ Steam=$steam; GameCfg=(Join-Path $game 'game\csgo\cfg'); AccountId=$accountId; UserCfg=(Join-Path $steam "userdata\$accountId\730\local\cfg") }
}
function Initialize-DisplayApi {
    if ('CS2Displays' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class CS2Display {
    public string Device, Name, HardwareId;
    public List<int[]> Modes = new List<int[]>();
}
public static class CS2Displays {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string device, int index, ref DISPLAY_DEVICE result, int flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE result);
    public static CS2Display[] Read() {
        var displays = new List<CS2Display>();
        for (int i=0; i<32; i++) {
            var device = new DISPLAY_DEVICE(); device.cb=Marshal.SizeOf(device);
            if (!EnumDisplayDevices(null,i,ref device,0)) break;
            if ((device.StateFlags & 1)==0 || (device.StateFlags & 8)!=0) continue;
            var display = new CS2Display { Device=device.DeviceName, Name=device.DeviceString, HardwareId=device.DeviceID };
            for (int m=0; m<4096; m++) {
                var mode=new DEVMODE(); mode.dmSize=(short)Marshal.SizeOf(mode);
                if (!EnumDisplaySettings(device.DeviceName,m,ref mode)) break;
                display.Modes.Add(new int[] {mode.dmPelsWidth,mode.dmPelsHeight,mode.dmDisplayFrequency});
            }
            displays.Add(display);
        }
        return displays.ToArray();
    }
}
'@
}
function Get-DisplayHardware($Video, $Destination) {
    Initialize-DisplayApi
    $displays = @([CS2Displays]::Read())
    $index = 0
    if ($Video.Contains('setting.monitor_index')) { [void][int]::TryParse($Video['setting.monitor_index'], [ref]$index) }
    if ($index -lt 0 -or $index -ge $displays.Count) { return @{ Identity=@{}; Modes=@(); Reason='The selected display could not be found.' } }
    $display = $displays[$index]
    $identity = @{}
    if ($display.HardwareId -match 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})') {
        $identity.VendorID = [string][Convert]::ToInt32($matches[1],16)
        $identity.DeviceID = [string][Convert]::ToInt32($matches[2],16)
    }
    $local = Get-KvSection (Read-KeyValues $Destination) @('video.cfg')
    if ($local.Contains('Version')) { $identity.Version = $local.Version }
    $identity['setting.knowndevice'] = '1'
    $identity.Autoconfig = '2'
    return @{ Identity=$identity; Modes=@($display.Modes); Reason='' }
}

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

function New-LauncherText($Core,$Pack,$Mode) {
    $json = ConvertTo-Json -InputObject $Pack -Depth 50 -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $header = @'
@echo off
setlocal
title CS2 CONFIG
set "CS2_OLD_CP="
for /f "tokens=2 delims=:" %%c in ('chcp') do set "CS2_OLD_CP=%%c"
chcp 65001 >nul
set "CS2_LAUNCHER=%~f0"
set "CS2_PACK_ROOT=%~dp0"
set "CS2_RUN_FILE=%TEMP%\cs2-config-%RANDOM%-%RANDOM%.ps1"
powershell -NoProfile -Command "$t=[IO.File]::ReadAllText($env:CS2_LAUNCHER); $m=[Environment]::NewLine+'::'+'PS1'+'::'+[Environment]::NewLine; $i=$t.IndexOf($m); if($i -lt 0){exit 1}; [IO.File]::WriteAllText($env:CS2_RUN_FILE,$t.Substring($i+$m.Length),(New-Object Text.UTF8Encoding($true)))"
if errorlevel 1 goto broken
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%CS2_RUN_FILE%" %*
set "CS2_RESULT=%ERRORLEVEL%"
if exist "%CS2_RUN_FILE%" del "%CS2_RUN_FILE%"
if defined CS2_OLD_CP chcp %CS2_OLD_CP% >nul
exit /b %CS2_RESULT%
:broken
echo This file could not be opened. Download it again or use the console instructions.
pause
if defined CS2_OLD_CP chcp %CS2_OLD_CP% >nul
exit /b 1
::PS1::
'@
    $entry = @'
param([ValidateSet('menu','create','update','apply')][string]$Mode = '__MODE__')
$ErrorActionPreference = 'Stop'
'@
    $tail = @'
$script:CoreSource = [IO.File]::ReadAllText($PSCommandPath)
$script:CoreSource = [regex]::Match($script:CoreSource,'(?ms)^# BEGIN CORE\r?\n(.*?)^# END CORE\r?$').Groups[1].Value.Trim()
try { Start-ConfigTool $Mode $env:CS2_PACK_ROOT '__PAYLOAD__' }
catch { Write-Host ''; Write-Host $_.Exception.Message -ForegroundColor Yellow; [void](Read-Host 'Press Enter to close'); exit 1 }
'@
    $text = $header + "`n" + $entry.Replace('__MODE__',$Mode) + "`n# BEGIN CORE`n" + $Core.Trim() + "`n# END CORE`n" + $tail.Replace('__PAYLOAD__',$encoded)
    return ($text -replace "`r?`n", "`r`n") + "`r`n"
}
function Get-ConsoleCommands($Profile) {
    $lines = New-Object 'Collections.Generic.List[string]'
    $visiting = @{}
    function Expand-Config($Name, $Depth) {
        if ($Depth -gt 20 -or $visiting.ContainsKey($Name) -or -not $Profile.gameFiles.Contains($Name)) { return }
        $visiting[$Name]=$true
        foreach ($line in ($Profile.gameFiles[$Name] -split '\r?\n')) {
            if ($line.Trim() -match '^(//|$)') { continue }
            if ($line -match '^\s*exec\s+"?([^"\s;]+)"?\s*(?://.*)?$') {
                $next=$matches[1]; if (-not $next.EndsWith('.cfg')) { $next+='.cfg' }
                Expand-Config $next ($Depth+1)
            } else { $lines.Add($line.TrimEnd()) }
        }
        $visiting.Remove($Name)
    }
    Expand-Config 'autoexec.cfg' 0
    foreach ($line in (Get-StartupCommands $Profile)) { $lines.Add($line) }
    return $lines -join "`r`n"
}
function Get-ConsoleFilename($Profile) {
    $name = $Profile.name -replace '[<>:"/\\|?*\x00-\x1f]', '_'
    $name=$name.Trim().TrimEnd('.')
    if ($name.Length -gt 60) { $name=$name.Substring(0,60) }
    return 'profile-' + $name + '-' + $Profile.id.Substring(0,8) + '.txt'
}
function Export-Pack($Pack,$Root) {
    Assert-Pack $Pack
    $rootPath=[IO.Path]::GetFullPath($Root)
    if (-not $script:CoreSource) { throw 'The application source is unavailable. Run setup.cmd again.' }
    # Prepare every output before replacing anything. profiles.json is authoritative;
    # a failed launcher write can be retried without losing the new profile.
    $outputs=[ordered]@{}
    $outputs['profiles.json']=(ConvertTo-Json -InputObject $Pack -Depth 50) + "`r`n"
    $outputs['apply-config.cmd']=New-LauncherText $script:CoreSource $Pack 'menu'
    $outputs['update-config.cmd']=New-LauncherText $script:CoreSource $Pack 'update'
    $outputs['setup.cmd']=New-LauncherText $script:CoreSource $Pack 'create'
    $readme=New-Object 'Collections.Generic.List[string]'
    $readme.Add('# ' + $Pack.name)
    $readme.Add("`nRun **apply-config.cmd**, choose **Apply profile**, then choose a profile explicitly. Review the settings and select **Apply**.")
    $readme.Add("`nClose CS2 before applying or capturing settings. Sign in to Steam first. Applying a profile creates missing settings folders; no preliminary CS2 launch is required.")
    $readme.Add("`n## Profiles`n")
    foreach ($profile in $Pack.profiles) {
        $name=Get-ConsoleFilename $profile
        $outputs['console\'+$name]=Get-ConsoleCommands $profile
        $readme.Add('- **' + $profile.name + '**: [console commands](console/' + [Uri]::EscapeDataString($name) + ')')
    }
    $readme.Add("`n## Update a profile`n`nChange settings in CS2 or launch options in Steam, exit CS2, run **update-config.cmd**, and select the profile to update. Review the changes and choose **Save changes**. Only the selected profile is replaced. No previous versions are retained.")
    $readme.Add("`n## Create a profile`n`nRun **setup.cmd** or choose **Create profile** in the main menu. Enter any unique name, review the settings and destination, then choose **Create profile**.")
    $readme.Add("`n## Launch options`n`nThe profile stores the exact launch options read from Steam. After applying, paste the displayed line into **Steam > CS2 > Properties > General > Launch Options**. An empty line means clearing that field. Launch options are a manual step.")
    $readme.Add("`nIf the requested fullscreen refresh rate exceeds the maximum available at the profile's resolution, the utility uses that maximum and reports the adjustment. The saved profile is unchanged. Explicit refresh arguments in the displayed launch-options line are adjusted for this application too. Unavailable resolutions are skipped.")
    $readme.Add("`n## Console alternative`n`nOpen the command file for your profile above. Paste its commands into the CS2 console in small batches, then check your settings in CS2.`n`nSupported settings: crosshair, mouse, audio and controls.")
    $readme.Add("`n## Files and results`n`n**profiles.json** is the editable source for this config. Keep it beside the CMD files. Each CMD also contains all profiles, so a downloaded **apply-config.cmd** can run on its own. Rebuilding updates all launchers and console files. Saved and checked means the values were verified on disk; check the actual result after starting CS2. Skipped settings and write failures are listed separately.")
    $readme.Add("`n## Publish or update on GitHub`n`nOpen your config repository, choose **Add file > Upload files**, upload the updated folder contents and choose **Commit changes**. Download a fresh **apply-config.cmd** on another PC; previously downloaded files keep their embedded settings.")
    if ($Pack.Contains('notes') -and $Pack.notes) {
        $readme.Add("`n## Config notes`n")
        foreach ($note in $Pack.notes) { $readme.Add([string]$note) }
    }
    $outputs['README.md']=$readme -join "`r`n"
    $outputs['.gitattributes']="*.cmd -text`r`n*.ps1 text eol=crlf`r`n"
    foreach ($name in $outputs.Keys) { Write-TextFile (Join-Path $rootPath $name) $outputs[$name] }
}
function Import-LegacyProfile($Root,$Name) {
    $user=Get-SettingsSection (Join-Path $Root 'cloud-backup\cs2_user_convars_0_slot0.vcfg') 'convars'
    $crosshair=Get-CurrentCrosshair $user
    $user=Select-GameSettings $user
    foreach ($key in @($user.Keys)) { if ($key -match '^cl_crosshair') { $user.Remove($key) } }
    foreach ($key in $crosshair.Keys) { $user[$key]=$crosshair[$key] }
    $launch=''
    $launcher=Join-Path $Root 'apply-config.cmd'
    if (Test-Path -LiteralPath $launcher) {
        # Only read a literal; never evaluate a downloaded old launcher.
        $match=[regex]::Match([IO.File]::ReadAllText($launcher), '(?m)^\$LaunchOptions\s*=\s*''((?:''''|[^''])*)''\s*$')
        if ($match.Success) { $launch=$match.Groups[1].Value.Replace("''", "'") }
    }
    return [ordered]@{
        id=[guid]::NewGuid().ToString('N'); name=$Name; updatedAt=[DateTime]::UtcNow.ToString('o')
        gameFiles=Get-UserGameFiles (Join-Path $Root 'cfg'); user=$user
        keys=Get-SettingsSection (Join-Path $Root 'cloud-backup\cs2_user_keys_0_slot0.vcfg') 'bindings'
        machine=Select-GameSettings (Get-SettingsSection (Join-Path $Root 'machine\cs2_machine_convars.vcfg') 'convars')
        video=Get-KvSection (Read-KeyValues (Join-Path $Root 'video\cs2_video.txt')) @('video.cfg')
        launchOptions=$launch
    }
}

function Initialize-TerminalWindowApi {
    if ('CS2TerminalWindow' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CS2TerminalWindow {
    [StructLayout(LayoutKind.Sequential)]
    struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    struct Coord { public short X, Y; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct ConsoleFont {
        public uint Size, Index;
        public Coord Cell;
        public int Family, Weight;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Face;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int handle);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool SetCurrentConsoleFontEx(IntPtr output, bool maximum, ref ConsoleFont font);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect rect, int size);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    public static bool SetFont() {
        ConsoleFont font = new ConsoleFont();
        font.Size = (uint)Marshal.SizeOf(typeof(ConsoleFont));
        font.Cell.Y = 16;
        font.Family = 54;
        font.Weight = 400;
        font.Face = "Consolas";
        return SetCurrentConsoleFontEx(GetStdHandle(-11), false, ref font);
    }
    public static int SetHeight(int pixels) {
        IntPtr window = GetConsoleWindow();
        // Pseudoconsole hosts expose a hidden handle, not their visible terminal.
        if (window == IntPtr.Zero || !IsWindowVisible(window)) return 0;
        SetFont();
        return Resize(window, pixels);
    }
    public static int Resize(IntPtr window, int pixels) {
        IntPtr previous = IntPtr.Zero;
        try {
            // Use physical pixels even when the PowerShell host is DPI-unaware.
            try { previous = SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) { }
            Rect rect, client, visible;
            if (!GetWindowRect(window, out rect)) return 0;
            int width = rect.Right - rect.Left;
            if (GetClientRect(window, out client) && Console.WindowHeight > 0) {
                double rowHeight = (double)(client.Bottom - client.Top) / Console.WindowHeight;
                if (rowHeight > 0) {
                    int rows = (int)Math.Ceiling(pixels / rowHeight);
                    if (Console.BufferHeight < rows) Console.BufferHeight = rows;
                }
            }
            int requested = pixels;
            int actual = 0;
            for (int attempt = 0; attempt < 3; attempt++) {
                if (!SetWindowPos(window, IntPtr.Zero, 0, 0, width, requested, 0x0002 | 0x0004 | 0x0010)) return actual;
                // DWM bounds exclude the invisible resize border and are physical pixels.
                if (DwmGetWindowAttribute(window, 9, out visible, Marshal.SizeOf(typeof(Rect))) == 0)
                    actual = visible.Bottom - visible.Top;
                else if (GetWindowRect(window, out rect)) actual = rect.Bottom - rect.Top;
                else return 0;
                if (Math.Abs(actual - pixels) <= 1) break;
                requested += pixels - actual;
            }
            return actual;
        } finally {
            if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous);
        }
    }
}
'@
}
function Initialize-Terminal {
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { return }
    try { $Host.UI.RawUI.WindowTitle = 'CS2 CONFIG - ' + $script:Pack.name } catch { }
    try {
        Initialize-TerminalWindowApi
        [void][CS2TerminalWindow]::SetHeight(530)
    } catch { } # Some terminal hosts manage their own window dimensions.
}
function Show-Header($Title, [switch]$MainMenu) {
    if (-not [Console]::IsOutputRedirected) { try { Clear-Host } catch { } }
    if ($MainMenu) {
        Write-Host 'CS2 CONFIG' -ForegroundColor Cyan
        Write-Host ''
        Write-Host ('Config name: ' + $script:Pack.name)
    }
    Write-Host ''
    if ($Title) { Write-Host $Title -ForegroundColor White; Write-Host '' }
}
function Read-Choice([int[]]$Allowed) {
    while ($true) {
        $value=Read-Host 'Select an option'
        $number=-1
        if ([int]::TryParse($value,[ref]$number) -and $number -in $Allowed) { return $number }
        Write-Host 'Enter one of the listed numbers.' -ForegroundColor Yellow
    }
}
function Wait-Back { Write-Host ''; [void](Read-Host 'Press Enter to go back') }
function Select-Profile($Purpose) {
    Show-Header ('Choose a profile to ' + $Purpose)
    if (-not $script:Pack.profiles.Count) { Write-Host 'No profiles yet. Create a profile first.'; Wait-Back; return $null }
    for ($i=0;$i -lt $script:Pack.profiles.Count;$i++) { Write-Host "  [$($i+1)] $($script:Pack.profiles[$i].name)" }
    Write-Host '  [0] Back'; Write-Host ''
    $index=Read-Choice (0..$script:Pack.profiles.Count)
    if ($index -eq 0) { return $null }
    return $script:Pack.profiles[$index-1]
}
function Get-ProfileRows($Profile) {
    $rows=New-Object 'Collections.Generic.List[object]'
    function Row($Group,$Name,$Value) { if ($null -ne $Value -and "$Value" -ne '') { $rows.Add([pscustomobject]@{ Group=$Group; Name=$Name; Value=[string]$Value }) } }
    function Value($Map,$Key) {
        if ($Map.Contains($Key)) { return $Map[$Key] }
        foreach ($candidate in $Map.Keys) { if (($candidate -replace '\$\d+$','') -eq $Key) { return $Map[$candidate] } }
        return $null
    }
    function Toggle($Text) { if ($Text -in @('1','true')) { return 'On' }; if ($Text -in @('0','false')) { return 'Off' }; return $Text }
    $video=$Profile.video
    if ($video.Contains('setting.defaultres')) { Row 'Display' 'Resolution' ($video['setting.defaultres']+' x '+$video['setting.defaultresheight']) }
    if ($video.Contains('setting.fullscreen')) {
        $mode='Windowed'
        if ($video['setting.fullscreen'] -eq '1') { $mode='Fullscreen' }
        elseif ($video['setting.nowindowborder'] -eq '1') { $mode='Fullscreen Windowed' }
        Row 'Display' 'Display Mode' $mode
    }
    $num=0.0; $den=0.0
    if ([double]::TryParse($video['setting.refreshrate_numerator'],[ref]$num) -and [double]::TryParse($video['setting.refreshrate_denominator'],[ref]$den) -and $den -gt 0) { Row 'Display' 'Refresh Rate' (([Math]::Round($num/$den,3)).ToString([Globalization.CultureInfo]::InvariantCulture)+' Hz') }
    foreach ($key in $script:VideoChoices.Keys) {
        if (-not $video.Contains($key)) { continue }
        $value=$script:VideoChoices[$key][1][$video[$key]]
        if ($key -eq 'setting.msaa_samples' -and $video[$key] -eq '0' -and $video['setting.r_csgo_cmaa_enable'] -eq '1') { $value='CMAA2' }
        if (-not $value) { $value='Unsupported value' }
        Row 'Advanced video' $script:VideoChoices[$key][0] $value
    }
    $all=Copy-Data $Profile.machine
    foreach ($key in $Profile.user.Keys) { $all[$key]=$Profile.user[$key] }
    $labels=@(
        @('Mouse','Sensitivity','sensitivity'),@('Mouse','Zoom Sensitivity','zoom_sensitivity_ratio'),
        @('Crosshair','Length (px)','cl_crosshair_length'),@('Crosshair','Thickness (px)','cl_crosshair_thickness'),@('Crosshair','Gap (px)','cl_crosshair_gap'),
        @('Crosshair','Center Dot','cl_crosshairdot'),@('Crosshair','Follow Recoil','cl_crosshair_recoil'),@('Crosshair','T Style','cl_crosshair_t'),
        @('Audio','Master Volume','volume'),@('Audio','Voice Chat Volume','snd_voipvolume'),@('Audio','Music Volume','snd_musicvolume'),
        @('HUD and radar','HUD Scale','hud_scaling'),@('HUD and radar','Radar Scale','cl_radar_scale'),@('HUD and radar','Radar Always Centered','cl_radar_always_centered'),@('HUD and radar','Rotate Radar','cl_radar_rotate'),
        @('Viewmodel','Field of View','viewmodel_fov'),@('Viewmodel','Horizontal Position','viewmodel_offset_x'),@('Viewmodel','Forward Position','viewmodel_offset_y'),@('Viewmodel','Vertical Position','viewmodel_offset_z'),
        @('Game','Maximum FPS','fps_max'),@('Game','Menu Maximum FPS','fps_max_ui'),@('Game','Invert Mouse','mouse_inverty')
    )
    foreach ($label in $labels) {
        $value=Value $all $label[2]
        if ($label[2] -in @('cl_crosshairdot','cl_crosshair_recoil','cl_crosshair_t','cl_radar_always_centered','cl_radar_rotate','mouse_inverty')) { $value=Toggle $value }
        elseif ($null -ne $value -and $label[2] -in @('volume','snd_voipvolume','snd_musicvolume','hud_scaling','cl_radar_scale')) {
            $amount=0.0
            if ([double]::TryParse($value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$amount)) { $value=([Math]::Round($amount*100,1)).ToString([Globalization.CultureInfo]::InvariantCulture)+'%' }
        }
        elseif ($value -eq '0' -and $label[2] -in @('fps_max','fps_max_ui')) { $value='Unlimited' }
        Row $label[0] $label[1] $value
    }
    if ($all.Contains('cl_crosshairstyle')) { Row 'Crosshair' 'Style' (@{'2'='Classic';'4'='Classic Static';'5'='Legacy'}[$all.cl_crosshairstyle]) }
    if ($all.Contains('cl_crosshair_drawoutline')) { Row 'Crosshair' 'Outline' (@{'0'='Off';'1'='Full Outline';'2'='Half Outline'}[$all.cl_crosshair_drawoutline]) }
    if ($all.Contains('cl_crosshaircolor_r')) { Row 'Crosshair' 'Color (RGB)' ($all.cl_crosshaircolor_r+', '+$all.cl_crosshaircolor_g+', '+$all.cl_crosshaircolor_b) }
    $actions=@{ '+jump'='Jump';'+attack'='Fire';'+attack2'='Secondary Fire';'+forward'='Move Forward';'+back'='Move Back';'+left'='Move Left';'+right'='Move Right';'+duck'='Crouch';'+sprint'='Walk';'+use'='Use';'+reload'='Reload';'+voicerecord'='Voice Chat';'switchhands'='Switch Hands';'drop'='Drop Weapon' }
    foreach ($key in $Profile.keys.Keys) {
        $action=$Profile.keys[$key]
        if ($actions.ContainsKey($action)) { Row 'Controls' ($actions[$action]+' ('+$key+')') $key }
    }
    Row 'Included settings' 'Player preferences' ($Profile.user.Count.ToString()+' saved values')
    Row 'Included settings' 'Audio, HUD and other preferences' ($Profile.machine.Count.ToString()+' saved values')
    Row 'Included settings' 'Key bindings' ($Profile.keys.Count.ToString()+' saved bindings')
    Row 'Included settings' 'Custom configs' ($Profile.gameFiles.Keys -join ', ')
    Row 'Launch options' 'Steam Launch Options' $(if ($Profile.launchOptions) { $Profile.launchOptions } else { '(empty)' })
    return ,$rows.ToArray()
}
function Show-Profile($Profile) {
    Write-Host ('Profile: ' + $Profile.name)
    # Preserve capture order without PowerShell 7-only Sort-Object -Stable.
    $rows=Get-ProfileRows $Profile
    foreach ($groupName in ($rows.Group | Select-Object -Unique)) {
        Write-Host ''; Write-Host $groupName -ForegroundColor Cyan
        foreach ($row in $rows | Where-Object { $_.Group -eq $groupName }) {
            if ($row.Name -eq 'Steam Launch Options') { Write-Host $row.Value }
            else { Write-Host ('  {0,-39} {1}' -f $row.Name,$row.Value) }
        }
    }
}
function Show-Changes($Before,$After) {
    $old=@{}; foreach ($row in (Get-ProfileRows $Before)) { $old[$row.Group+'/'+$row.Name]=$row.Value }
    $count=0
    foreach ($row in (Get-ProfileRows $After)) {
        $key=$row.Group+'/'+$row.Name
        if (-not $old.ContainsKey($key) -or $old[$key] -cne $row.Value) { Write-Host ('  {0}: {1} -> {2}' -f $row.Name,$old[$key],$row.Value); $count++ }
    }
    foreach ($section in @('user','machine','keys','gameFiles','video')) {
        if ((ConvertTo-Json -InputObject $Before[$section] -Depth 10 -Compress) -cne (ConvertTo-Json -InputObject $After[$section] -Depth 10 -Compress)) {
            $label=@{user='Player preferences';machine='Audio, HUD and radar';keys='Controls';gameFiles='Custom configs';video='Display and video'}[$section]
            Write-Host "  $label includes updated settings."
            $count++
        }
    }
    return $count
}
function Show-Issues($Issues) {
    foreach ($issue in $Issues) { Write-Host ("  {0}: {1} - {2}" -f $issue.Kind,$issue.Setting,$issue.Reason) -ForegroundColor Yellow }
}
function Show-ClipboardResult([string]$Text) {
    if (Copy-LaunchOptions $Text) { Write-Host 'Copied to clipboard.' -ForegroundColor Green }
    else { Write-Host 'Could not copy to clipboard. Select [3] to retry or copy the launch options above manually.' -ForegroundColor Yellow }
}
function Show-Console($Profile) {
    Show-Header 'Console alternative'
    Write-Host ('Profile: ' + $Profile.name)
    $path=Join-Path $script:Root ('console\'+(Get-ConsoleFilename $Profile))
    Write-TextFile $path (Get-ConsoleCommands $Profile)
    Write-Host "`n1. Open $path"
    Write-Host '2. Copy its commands into the CS2 console in small batches and run them.'
    Write-Host '3. Check your settings in CS2.'
    Write-Host "`nSupported settings: crosshair, mouse, audio and controls."
    Wait-Back
}
function Invoke-ApplyScreen {
    :ChooseProfile while ($true) {
    $profile=Select-Profile 'apply'; if ($null -eq $profile) { return }
    $context=Get-Context; if ($null -eq $context) { return }
    while ($true) {
        $plan=New-ApplyPlan $profile $context
        Show-Header 'Apply profile'; Show-Profile $profile
        Write-Host ''; Show-Issues $plan.Video.Issues
        $label=if (@($plan.Video.Issues | Where-Object {$_.Kind -eq 'Skipped'}).Count) {'Apply available settings'} else {'Apply'}
        Write-Host "`n  [1] $label"; Write-Host '  [0] Back'
        if ((Read-Choice @(0,1)) -eq 0) { continue ChooseProfile }
        $result=Invoke-ApplyPlan $plan
        $failed=@($result.Issues | Where-Object {$_.Kind -eq 'Skipped'})
        Show-Header $(if ($failed.Count) {'Profile partially saved'} else {'Profile saved for the next CS2 launch'})
        Write-Host ('Profile: ' + $profile.name)
        if ($result.Saved.Count) { Write-Host ('Saved and checked: ' + ($result.Saved -join ', ')) -ForegroundColor Green }
        Show-Issues $result.Issues
        Write-Host "`nLaunch options"
        $launch=Get-EffectiveLaunchOptions $profile $plan
        Write-Host $(if ($launch) {$launch} else {'(empty - clear the Launch Options field)'})
        Write-Host 'Paste into Steam > CS2 > Properties > General > Launch Options.'
        if (@($result.Issues | Where-Object {$_.Setting -in @('Display','Refresh Rate')}).Count) { Write-Host 'Check any display parameters in this line before pasting.' -ForegroundColor Yellow }
        if ($launch) { Show-ClipboardResult $launch }
        Write-Host "`nStart CS2 to use the saved settings."
        if ($failed.Count) { Write-Host '  [1] Retry'; Write-Host '  [2] Console alternative' }
        if ($launch) { Write-Host '  [3] Copy launch options' }
        Write-Host '  [0] Back to main menu'; Write-Host '  [9] Exit'
        $options=if ($failed.Count) {@(0,1,2,9)} else {@(0,9)}
        if ($launch) { $options+=3 }
        do {
            $choice=Read-Choice $options
            if ($choice -eq 3) { Show-ClipboardResult $launch }
        } while ($choice -eq 3)
        switch ($choice) {
            0 { return }; 9 { $script:ExitRequested=$true; return }
            2 { Show-Console $profile; return }
        }
    }
    }
}
function Read-ProfileName {
    while ($true) {
        $name=Read-Host 'Profile name (0 to go back)'
        if ($name -eq '0') { return '' }
        $name=$name.Trim()
        if (-not $name -or $name.Length -gt 100 -or $name -match '[\x00-\x1f]') { Write-Host 'Enter a profile name (1-100 characters).'; continue }
        if (@($script:Pack.profiles | Where-Object {$_.name -eq $name}).Count) { Write-Host 'A profile with this name already exists.'; continue }
        return $name
    }
}
function Export-WithRetry($Pack,$Destination) {
    while ($true) {
        try { Export-Pack $Pack $Destination; return $true }
        catch {
            # The JSON may have been saved before a derived CMD failed. Keep memory
            # consistent with that source of truth, including after returning to menu.
            if (Test-Path -LiteralPath (Join-Path $Destination 'profiles.json')) {
                try { $script:Pack=Read-Pack $Destination ''; $script:Root=$Destination } catch { }
            }
            Show-Header 'Config files could not all be updated'
            Write-Host ('Folder: '+$Destination)
            Write-Host 'Check folder permissions and close programs using these files, then retry.'
            Write-Host "`n  [1] Retry"; Write-Host '  [0] Back to main menu'
            if ((Read-Choice @(0,1)) -eq 0) { return $false }
        }
    }
}
function Invoke-SaveScreen($Update) {
    :ChooseSource while ($true) {
    $existing=$null
    if ($Update) { $existing=Select-Profile 'update'; if ($null -eq $existing) { return }; $name=$existing.name }
    else { Show-Header 'Create profile'; $name=Read-ProfileName; if (-not $name) { return } }
    $context=Get-Context; if ($null -eq $context) { return }
    $id=if ($existing) {$existing.id} else {''}
    $profile=New-CapturedProfile $context $name $id
    $destination=$script:Root
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'profiles.json')) -and -not $script:Pack.profiles.Count) { $destination=Join-Path $destination 'cs2-config' }
    while ($true) {
        if ($Update) {
            Show-Header 'Review profile changes'; Write-Host ('Profile: '+$name)
            $changes=Show-Changes $existing $profile
            if (-not $changes) { Write-Host 'Profile is already up to date.'; Wait-Back; return }
            Write-Host "`n  [1] Save changes"; Write-Host '  [2] View all settings'
        } else {
            Show-Header 'Review new profile'; Show-Profile $profile
            Write-Host "`nSave to: $destination"
            Write-Host '  [1] Create profile'; Write-Host '  [2] Change destination'
        }
        Write-Host '  [0] Back'
        switch (Read-Choice @(0,1,2)) {
            0 { continue ChooseSource }
            2 {
                if ($Update) { Show-Header 'Current settings on this PC'; Show-Profile $profile; Wait-Back }
                else {
                    Show-Header 'Change destination'
                    Write-Host ('Current folder: ' + $destination)
                    $path=(Read-Host 'Folder (0 to go back)').Trim().Trim('"')
                    if ($path -ne '0' -and $path) {
                        $candidate=[IO.Path]::GetFullPath($path)
                        if ($candidate -ne $script:Root -and (Test-Path -LiteralPath (Join-Path $candidate 'profiles.json'))) { Write-Host 'That folder already contains a config. Open its setup.cmd to add a profile.'; Wait-Back }
                        else { $destination=$candidate }
                    }
                }
            }
            1 {
                $next=Copy-Data $script:Pack
                if ($Update) {
                    for ($i=0;$i -lt $next.profiles.Count;$i++) { if ($next.profiles[$i].id -eq $profile.id) { $next.profiles[$i]=$profile } }
                } else { $next.profiles=@($next.profiles)+@($profile) }
                if (-not $script:Pack.profiles.Count) { $next.name=Split-Path -Leaf $destination }
                if (-not (Export-WithRetry $next $destination)) { return }
                $script:Pack=$next; $script:Root=$destination
                Show-Header $(if ($Update) {'Profile updated'} else {'Profile created'})
                Write-Host ('Profile: '+$name); Write-Host ('Folder: '+$destination)
                Write-Host 'Open apply-config.cmd to apply a profile.'
                Write-Host 'Open update-config.cmd to update it.'
                Write-Host "`n  [1] Publishing instructions"; Write-Host '  [0] Back to main menu'; Write-Host '  [9] Exit'
                switch (Read-Choice @(0,1,9)) {
                    1 { Show-Header 'Update your config on GitHub'; Write-Host '1. Open your config repository on GitHub.'; Write-Host '2. Choose Add file > Upload files.'; Write-Host '3. Upload the updated config folder contents.'; Write-Host '4. Choose Commit changes.'; Wait-Back }
                    9 { $script:ExitRequested=$true }
                }
                return
            }
        }
    }
    }
}
function Start-ConfigTool($Mode,$Root,$Embedded) {
    $script:Root=[IO.Path]::GetFullPath($Root)
    $script:Pack=Read-Pack $script:Root $Embedded
    $script:ExitRequested=$false
    Initialize-Terminal
    if (-not $script:Pack.profiles.Count -and (Test-Path -LiteralPath (Join-Path $Root 'cfg'))) {
        Show-Header 'Name your existing profile'
        $name=Read-ProfileName; if (-not $name) { return }
        $script:Pack.name=Split-Path -Leaf $script:Root.TrimEnd('\')
        $script:Pack.profiles=@(Import-LegacyProfile $Root $name)
        Export-Pack $script:Pack $Root
    }
    :MenuLoop while (-not $script:ExitRequested) {
        try {
            switch ($Mode) {
                'apply' { Invoke-ApplyScreen }
                'create' { Invoke-SaveScreen $false }
                'update' { Invoke-SaveScreen $true }
                default {
                    Show-Header '' -MainMenu
                    Write-Host '  [1] Apply profile'; Write-Host '  [2] Update profile'; Write-Host '  [3] Create profile'; Write-Host '  [0] Exit'; Write-Host ''
                    switch (Read-Choice @(0,1,2,3)) {
                        0 { $script:ExitRequested=$true }
                        1 { $Mode='apply' }; 2 { $Mode='update' }; 3 { $Mode='create' }
                    }
                    continue MenuLoop
                }
            }
        } catch { Show-Header 'Could not continue'; Write-Host $_.Exception.Message -ForegroundColor Yellow; Wait-Back }
        $Mode='menu'
    }
}
# END CORE
$script:CoreSource = [IO.File]::ReadAllText($PSCommandPath)
$script:CoreSource = [regex]::Match($script:CoreSource,'(?ms)^# BEGIN CORE\r?\n(.*?)^# END CORE\r?$').Groups[1].Value.Trim()
try { Start-ConfigTool $Mode $env:CS2_PACK_ROOT 'eyJzY2hlbWFWZXJzaW9uIjoxLCJuYW1lIjoiY3MyLWNvbmZpZyIsInByb2ZpbGVzIjpbXX0=' }
catch { Write-Host ''; Write-Host $_.Exception.Message -ForegroundColor Yellow; [void](Read-Host 'Press Enter to close'); exit 1 }
