@echo off
rem ===================================================================
rem  cs2-config setup - saves your CS2 settings into a portable folder.
rem
rem  Double-click this file. Nothing else is needed: the PowerShell
rem  script is stored in plain text below the marker at the bottom of
rem  this header, and you can read it in Notepad or on GitHub.
rem
rem  cmd stops reading at the exit below, so the marker and everything
rem  after it are never parsed as batch. PowerShell re-reads this same
rem  file as UTF-8, which is why the Russian text in it survives.
rem
rem  https://github.com/oceanvievv/cs2-config
rem ===================================================================

setlocal
title cs2-config setup

rem  Russian output needs a console codepage that can render Cyrillic; a stock
rem  Russian Windows console is 866. Switch to UTF-8 and put the old one back on
rem  the way out, so running this from an existing terminal leaves no trace.
set "CP="
for /f "tokens=2 delims=:" %%c in ('chcp') do set "CP=%%c"
chcp 65001 >nul

rem  Delete first. Otherwise a copy left by an earlier run stands in for the extraction
rem  when the extraction fails, and a corrupted download quietly runs the previous version
rem  instead of saying it is corrupted.
set "PS1=%TEMP%\cs2-config-setup.ps1"
if exist "%PS1%" del "%PS1%"

rem  The script writes the finished pack's path here; only it knows where that is.
set "OUTF=%TEMP%\cs2-config-outdir.txt"
if exist "%OUTF%" del "%OUTF%"

rem  Handed over as environment variables rather than pasted into the command line:
rem  an apostrophe in the path would otherwise break the PowerShell string. SELFDIR is
rem  where the pack gets built, so that this file placed inside a pack updates it.
set "SELF=%~f0"
set "SELFDIR=%~dp0"
powershell -NoProfile -Command "$m='::'+'PS1'+'::'; $t=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8); $i=$t.LastIndexOf($m); if($i -lt 0){exit 1}; [IO.File]::WriteAllText($env:TEMP+'\cs2-config-setup.ps1', $t.Substring($i+$m.Length), (New-Object Text.UTF8Encoding($true)))"
if not exist "%PS1%" goto broken

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
if errorlevel 1 goto failed
echo.
pause
call :openpack
call :restorecp
exit /b 0

rem  Both failure paths say it in both languages at once, with no detection. They run when
rem  something has already gone wrong, which is the worst place for one more moving part.
:broken
echo.
echo Could not unpack the script from this file.
echo Re-download it: some editors and chat apps corrupt .cmd files.
echo.
echo Не удалось распаковать скрипт из этого файла.
echo Скачай его заново: некоторые редакторы и мессенджеры портят .cmd.
echo.
pause
call :restorecp
exit /b 1

:failed
echo.
echo The script did not finish. Read the message above.
echo A copy of it is at %PS1% if you want to run it by hand.
echo.
echo Скрипт не доработал. Смотри сообщение выше.
echo Его копия лежит в %PS1%, если захочешь запустить вручную.
echo.
pause
call :restorecp
exit /b 1

:openpack
rem  Open the finished pack in Explorer, so nobody has to go hunting for it.
if not exist "%OUTF%" goto :eof
for /f "usebackq delims=" %%d in ("%OUTF%") do if exist "%%d" start "" "%%d"
del "%OUTF%"
goto :eof

:restorecp
if defined CP chcp %CP% >nul
goto :eof

::PS1::
<#
.SYNOPSIS
    Packs your CS2 settings into a portable bundle that restores itself on any PC.

.DESCRIPTION
    Steam Cloud syncs your sensitivity, crosshair and binds. It does not sync the .cfg
    files in the game folder, your video settings, or your launch options. Lose those and
    a borrowed PC feels wrong in ways you notice mid-round.

    This script reads all of it off your machine and writes a folder containing:

      apply-config.cmd   double-click it on the other PC; every config is
                             embedded in it, so this one file puts everything back
      apply-config-using-console.txt      fallback for locked-down PCs: paste into the console
      cfg/ video/ cloud-backup/
      README.md, README.ru.md

    Nothing is uploaded. The folder is yours; publish it or keep it on a USB stick.

    Double-clicking is the whole interface: which configs are yours, which one is the main
    one, your crosshair, your launch options, your name and your language are all detected.

    The parameters below are escape hatches for when detection gets it wrong, or for
    driving this from a script. They are deliberately left out of the README, because a
    flag you cannot pass by double-clicking is not something to put in front of everyone.

.PARAMETER Name
    Pack name. Defaults to your in-game name.

.PARAMETER OutDir
    Where to write the pack. Defaults to your Desktop: cs2-config-<name>

.PARAMETER Main
    Your main config, the one autoexec should run (e.g. myconfig.cfg). Auto-detected when
    unambiguous: the config that no other config or bind already execs.

.PARAMETER Include
    Extra filenames from the game cfg folder to pack that detection skipped.

.PARAMETER Exclude
    Filenames to leave out.

.PARAMETER RepoUrl
    Your GitHub repo URL, if you plan to publish. Makes the download link in the generated
    README point at your apply-config.cmd instead of leaving <you> and <repo> to fill in.

.PARAMETER Anonymize
    Strip your in-game name from the packed settings.

.PARAMETER Force
    Skip the notice about overwriting an existing pack folder.

.EXAMPLE
    setup.cmd

.EXAMPLE
    setup.cmd -Main myconfig.cfg -RepoUrl https://github.com/me/cs2-config-me
#>
param(
    [string]   $Name,
    [string]   $OutDir,
    [string]   $Main,
    [string[]] $Include = @(),
    [string[]] $Exclude = @(),
    [string]   $RepoUrl,
    [switch]   $Anonymize,
    [switch]   $Force
)

$ErrorActionPreference = 'Stop'
$TOOL_VERSION = '1.2.0'
$TOOL_URL     = 'https://github.com/oceanvievv/cs2-config'

# The Windows display language decides, and nothing else. Keyboard layouts are
# deliberately not consulted: having a Russian layout says nothing about which language
# you want your tools in.
$Lang = 'en'
try {
    if ((Get-UICulture).TwoLetterISOLanguageName -eq 'ru') { $Lang = 'ru' }
} catch { }

# Every message carries both languages at the call site. Passing only English is fine
# and means "same in both", which is what you want for paths and file names.
function L($en, $ru) {
    if ($Lang -eq 'ru' -and $ru) { return $ru }
    return $en
}
function Info($en, $ru) { Write-Host "     $(L $en $ru)" }
function Ok  ($en, $ru) { Write-Host "OK   $(L $en $ru)" -ForegroundColor Green }
function Warn($en, $ru) { Write-Host "WARN $(L $en $ru)" -ForegroundColor Yellow }
function Die ($en, $ru) { Write-Host "FAIL $(L $en $ru)" -ForegroundColor Red; exit 1 }
function Head($en, $ru) { Write-Host ''; Write-Host (L $en $ru) -ForegroundColor Cyan }

# Pad a label to a fixed column so the two languages line up the same way.
function Lbl($en, $ru) { return (L $en $ru).PadRight(18) }

$UTF8 = New-Object System.Text.UTF8Encoding($false)   # no BOM: everything this writes

# ==================================================================================
#  Detection
# ==================================================================================

# Windows does not care how a path is spelled, but whoever reads the output does. Steam
# writes SteamPath into the registry all lower case and with forward slashes, like
# c:/program files (x86)/steam. The slashes are a substitution; how the folders are really
# spelled only the filesystem knows, so every segment is looked up in its parent.
function Get-TruePath($path) {
    $dir = New-Object IO.DirectoryInfo $path
    if (-not $dir.Exists) { return $path }
    $parts = New-Object System.Collections.Generic.List[string]
    while ($dir.Parent) {
        $hit = $dir.Parent.GetDirectories($dir.Name)
        if ($hit.Count -lt 1) { return $path }
        $parts.Insert(0, $hit[0].Name)
        $dir = $dir.Parent
    }
    # Only a drive letter is worth upper-casing. A UNC root is spelled by its server.
    $root = $dir.Name.TrimEnd('\')
    if ($root -match '^[a-z]:$') { $root = $root.ToUpper() }
    if ($parts.Count -eq 0) { return "$root\" }
    return $root + '\' + ($parts -join '\')
}

function Get-SteamPath {
    foreach ($k in @('HKCU:\Software\Valve\Steam',
                     'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
                     'HKLM:\SOFTWARE\Valve\Steam')) {
        if (Test-Path $k) {
            $p = Get-ItemProperty $k
            $raw = $p.SteamPath
            if (-not $raw) { $raw = $p.InstallPath }
            if ($raw) { return Get-TruePath (($raw -replace '/', '\').TrimEnd('\')) }
        }
    }
    return $null
}

function Get-CS2CfgPath($steam) {
    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($line in Get-Content $vdf) {
            if ($line -match '"path"\s+"(.+?)"') { $roots.Add(($matches[1] -replace '\\\\', '\')) }
        }
    }
    foreach ($r in $roots) {
        $p = Join-Path $r 'steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg'
        if (Test-Path $p) { return Get-TruePath $p }
    }
    return $null
}

function Get-SteamAccountId($steam) {
    if (Test-Path 'HKCU:\Software\Valve\Steam\ActiveProcess') {
        $id = (Get-ItemProperty 'HKCU:\Software\Valve\Steam\ActiveProcess').ActiveUser
        if ($id -and $id -ne 0 -and (Test-Path (Join-Path $steam "userdata\$id\730"))) { return "$id" }
    }
    $ud = Join-Path $steam 'userdata'
    if (-not (Test-Path $ud)) { return $null }
    $best = Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName '730\local\cfg') } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($best) { return $best.Name }
    return $null
}

# Launch options live in the 730 block of localconfig.vdf. Other apps have their own
# "LaunchOptions" lines, so walk back to the nearest app id and check it.
function Get-LaunchOptions($steam, $accountId) {
    $lc = Join-Path $steam "userdata\$accountId\config\localconfig.vdf"
    if (-not (Test-Path $lc)) { return $null }
    $lines = Get-Content $lc
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '"LaunchOptions"\s+"(.*)"\s*$') {
            $value = $matches[1]
            for ($j = $i; $j -ge 0 -and $j -gt $i - 60; $j--) {
                if ($lines[$j] -match '^\s*"(\d{3,7})"\s*$') {
                    if ($matches[1] -eq '730') { return $value }
                    break
                }
            }
        }
    }
    return $null
}

# Parse a VDF-ish "key"  "value" file into an ordered map.
function Read-VdfPairs($path) {
    $map = [ordered]@{}
    if (-not (Test-Path $path)) { return $map }
    foreach ($line in Get-Content $path) {
        if ($line -match '^\s*"([^"]+)"\s+"(.*)"\s*$') { $map[$matches[1]] = $matches[2] }
    }
    return $map
}

# ==================================================================================
#  Which .cfg files are actually yours
# ==================================================================================

$StockPrefixes = @('gamemode_', 'valve_', 'subscribed_', 'banned_', 'default_',
                   '360', 'joystick', 'undo_', 'config_default')
$StockExact    = @('server.cfg', 'server_default.cfg', 'perftest.cfg', 'default.cfg',
                   'config.cfg', 'video.cfg', 'videodefaults.cfg')

function Get-UserCfgFiles($cfgDir) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($f in (Get-ChildItem $cfgDir -Filter *.cfg -File | Sort-Object Name)) {
        if ($Exclude -contains $f.Name) { continue }
        $isStock = $false
        if ($StockExact -contains $f.Name.ToLower()) { $isStock = $true }
        foreach ($p in $StockPrefixes) {
            if ($f.Name.ToLower().StartsWith($p)) { $isStock = $true; break }
        }
        if ($isStock -and -not ($Include -contains $f.Name)) { continue }
        $out.Add($f)
    }
    return $out
}

# The main config is the one nothing else runs. Anything reached by `exec x` from another
# config or from a keybind is a sub-mode (practice, knife, ...) and must not autoexec.
function Find-MainCfg($files, $keysPath) {
    # An existing autoexec is the most direct evidence: whatever it execs is the main one.
    $auto = @($files | Where-Object { $_.Name.ToLower() -eq 'autoexec.cfg' })
    if ($auto.Count -gt 0) {
        $atext = [IO.File]::ReadAllText($auto[0].FullName)
        foreach ($m in [regex]::Matches($atext, '(?i)\bexec\s+"?([A-Za-z0-9_\-\.]+)"?')) {
            $n = $m.Groups[1].Value
            if (-not $n.ToLower().EndsWith('.cfg')) { $n = "$n.cfg" }
            if ($n.ToLower() -eq 'crosshair.cfg') { continue }
            $hit = @($files | Where-Object { $_.Name.ToLower() -eq $n.ToLower() })
            if ($hit.Count -eq 1) { return $hit[0].Name }
        }
    }
    $referenced = New-Object System.Collections.Generic.HashSet[string]
    $sources = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) { $sources.Add([IO.File]::ReadAllText($f.FullName)) }
    if ($keysPath -and (Test-Path $keysPath)) { $sources.Add([IO.File]::ReadAllText($keysPath)) }
    foreach ($text in $sources) {
        foreach ($m in [regex]::Matches($text, '(?i)\bexec\s+"?([A-Za-z0-9_\-\.]+)"?')) {
            $n = $m.Groups[1].Value
            if (-not $n.ToLower().EndsWith('.cfg')) { $n = "$n.cfg" }
            [void]$referenced.Add($n.ToLower())
        }
    }
    $candidates = @($files | Where-Object {
        $_.Name.ToLower() -ne 'autoexec.cfg' -and -not $referenced.Contains($_.Name.ToLower())
    })
    if ($candidates.Count -eq 1) { return $candidates[0].Name }
    return $null
}

# ==================================================================================
#  Launch option portability
# ==================================================================================

# Flags that take a following value token.
$ValueFlags = @('-threads', '-w', '-width', '-h', '-height', '-refresh', '-freq',
                '-language', '-dxlevel', '-tickrate', '-maxplayers')

# Flags worth dropping when the pack lands on unknown hardware.
$NotPortable = @{
    '-threads'                     = 'thread count is specific to this CPU'
    '-high'                        = 'high priority can starve audio and input on a faster CPU'
    '-refresh'                     = 'refresh rate differs on another monitor'
    '-freq'                        = 'refresh rate differs on another monitor'
    '-softparticlesdefaultoff'     = 'lowers quality to gain fps you may not need'
    '-low'                         = 'lowers quality to gain fps you may not need'
    '-lowmemory'                   = 'lowers quality to gain fps you may not need'
    '-nod3d9ex'                    = 'legacy workaround, not needed'
    '-disable_d3d9ex'              = 'legacy workaround, not needed'
    '-dxlevel'                     = 'legacy, forces a renderer level'
    '-processheap'                 = 'legacy workaround, not needed'
    '+mat_disable_fancy_blending'  = 'lowers quality to gain fps you may not need'
}

$NotPortableRu = @{
    '-threads'                     = 'число потоков подобрано под этот процессор'
    '-high'                        = 'высокий приоритет на быстром процессоре мешает звуку и вводу'
    '-refresh'                     = 'на другом мониторе другая частота обновления'
    '-freq'                        = 'на другом мониторе другая частота обновления'
    '-softparticlesdefaultoff'     = 'жертвует качеством ради кадров, которых там хватит'
    '-low'                         = 'жертвует качеством ради кадров, которых там хватит'
    '-lowmemory'                   = 'жертвует качеством ради кадров, которых там хватит'
    '-nod3d9ex'                    = 'устаревший костыль, больше не нужен'
    '-disable_d3d9ex'              = 'устаревший костыль, больше не нужен'
    '-dxlevel'                     = 'устаревший флаг, жёстко задаёт уровень рендера'
    '-processheap'                 = 'устаревший костыль, больше не нужен'
    '+mat_disable_fancy_blending'  = 'жертвует качеством ради кадров, которых там хватит'
}

function Split-LaunchOptions($raw) {
    $tokens = @($raw -split '\s+' | Where-Object { $_ -ne '' })
    $items = New-Object System.Collections.Generic.List[object]
    $i = 0
    while ($i -lt $tokens.Count) {
        $t = $tokens[$i]
        $val = $null
        # every +convar takes one value; -flags only when known to
        if ($t.StartsWith('+') -or ($ValueFlags -contains $t.ToLower())) {
            if ($i + 1 -lt $tokens.Count -and -not ($tokens[$i + 1] -match '^[+\-]')) {
                $val = $tokens[$i + 1]; $i++
            }
        }
        $items.Add([pscustomobject]@{ Flag = $t; Value = $val })
        $i++
    }
    return $items
}

# cs2_machine_convars.vcfg is not carried by Steam Cloud - the name is literal, these
# belong to the machine - so on another PC they are that machine's defaults. The radar
# lives here, and so do fov, every volume, HUD scale and gamma.
#
# An allowlist rather than a denylist, because a pack gets published: the same file holds
# "password", the direct-challenge key, cached ids and saved map lists. Anything Valve adds
# later stays out until someone puts it in, which is the right way round for a file that
# ends up in a public repository.
$MachineKeep = @(
    'cl_radar_', 'cl_hud_radar_', 'cl_hud_telemetry_', 'cl_teamid_overhead_',
    'cl_radial_', 'cl_quickinventory_', 'cl_scoreboard_', 'cl_predict_',
    'snd_', 'voice_', 'spec_', 'r_'
)
$MachineKeepExact = @(
    'cl_hud_color', 'hud_scaling', 'hud_fastswitch', 'safezonex', 'safezoney',
    'cl_teammate_colors_show', 'cl_force_spec_hud_color_to_team',
    'cl_crosshair_friendly_warning', 'cl_show_observer_crosshair',
    'cl_observed_bot_crosshair', 'cl_deathcampanel_position_dynamic',
    'cl_sniper_show_inaccuracy', 'cl_sniper_delay_unscope',
    'cl_show_clan_in_death_notice', 'cl_weapon_selection_rarity_color',
    'cl_use_last_selected_weapon_slot_position', 'cl_color', 'cl_autohelp',
    'cl_mute_enemy_team', 'cl_mute_all_but_friends_and_party', 'cl_enable_party_voice',
    'cl_net_buffer_ticks', 'cl_timeout', 'cl_player_ping_mute',
    'cl_ping_fade_deadzone', 'cl_ping_fade_distance', 'cl_versus_intro',
    'cl_disable_round_end_report', 'cl_dm_buyrandomweapons', 'cl_hide_avatar_images',
    'cl_allow_animated_avatars', 'cl_sanitize_player_names', 'mouse_inverty',
    'fov_desired', 'viewmodel_presetpos', 'rate', 'volume', 'dsp_volume',
    'fps_max', 'fps_max_ui', 'speaker_config', 'closecaption', 'sv_voiceenable',
    'mapoverview_icon_scale', 'csgo_map_preview_scale'
)
# Beats both lists above, in case a prefix ever grows into something it should not reach.
$MachineNever = @('password', 'ui_playsettings_directchallengekey')

# Filtered line by line rather than parsed and written back out, so what survives keeps
# the exact bytes CS2 wrote. Split-screen convars carry a $1..$4 suffix that is not part
# of the name.
function Select-MachineConvars($path) {
    $out  = New-Object System.Text.StringBuilder
    $kept = 0
    foreach ($line in (Get-Content $path)) {
        $m = [regex]::Match($line, '^\s*"([^"]+)"\s+"')
        if (-not $m.Success) { [void]$out.AppendLine($line); continue }
        $name = $m.Groups[1].Value
        $base = $name -replace '\$\d+$', ''
        if ($MachineNever -contains $base) { continue }
        $keep = $false
        foreach ($p in $MachineKeep) { if ($name.StartsWith($p)) { $keep = $true; break } }
        if (-not $keep -and ($MachineKeepExact -contains $base)) { $keep = $true }
        if ($keep) { [void]$out.AppendLine($line); $kept++ }
    }
    return [pscustomobject]@{ Text = $out.ToString(); Count = $kept }
}

function Get-PortableLaunchOptions($raw) {
    $kept    = New-Object System.Collections.Generic.List[string]
    $dropped = New-Object System.Collections.Generic.List[object]
    foreach ($item in (Split-LaunchOptions $raw)) {
        $key = $item.Flag.ToLower()
        $text = $item.Flag
        if ($null -ne $item.Value) { $text = "$($item.Flag) $($item.Value)" }
        if ($NotPortable.ContainsKey($key)) {
            $dropped.Add([pscustomobject]@{
                Text  = $text
                Why   = $NotPortable[$key]
                WhyRu = $NotPortableRu[$key]
            })
        } else {
            $kept.Add($text)
        }
    }
    return [pscustomobject]@{ Portable = ($kept -join ' '); Dropped = $dropped }
}

# ==================================================================================
#  Go
# ==================================================================================

Head '=== cs2-config setup ======================================='

$steam = Get-SteamPath
if (-not $steam) {
    Die 'Steam not found in the registry. Is Steam installed?' `
        'Steam не найден в реестре. Он вообще установлен?'
}
Ok "$(Lbl 'Steam' 'Steam')$steam"

$cfgDir = Get-CS2CfgPath $steam
if (-not $cfgDir) {
    Die 'CS2 not found in any Steam library.' `
        'CS2 не найдена ни в одной библиотеке Steam.'
}
Ok "$(Lbl 'CS2 cfg folder' 'Папка cfg')$cfgDir"

$accountId = Get-SteamAccountId $steam
$userCfgDir = $null
if ($accountId) {
    $userCfgDir = Join-Path $steam "userdata\$accountId\730\local\cfg"
    Ok "$(Lbl 'Steam account' 'Аккаунт Steam')$accountId"
} else {
    Warn 'No CS2 userdata folder found. Video settings and cloud backup will be skipped.' `
         'Папка userdata для CS2 не найдена. Настройки видео и копию Steam Cloud пропускаю.'
}

$convarsPath = $null
$keysPath    = $null
$videoPath   = $null
$machinePath = $null
if ($userCfgDir -and (Test-Path $userCfgDir)) {
    $c = Join-Path $userCfgDir 'cs2_user_convars_0_slot0.vcfg'
    $k = Join-Path $userCfgDir 'cs2_user_keys_0_slot0.vcfg'
    $v = Join-Path $userCfgDir 'cs2_video.txt'
    $m = Join-Path $userCfgDir 'cs2_machine_convars.vcfg'
    if (Test-Path $c) { $convarsPath = $c }
    if (Test-Path $k) { $keysPath    = $k }
    if (Test-Path $v) { $videoPath   = $v }
    if (Test-Path $m) { $machinePath = $m }
}

$convars = Read-VdfPairs $convarsPath

# --- name -------------------------------------------------------------------------
$playerName = $null
if ($convars.Contains('name')) { $playerName = $convars['name'] }
if (-not $Name) {
    if ($playerName) { $Name = $playerName } else { $Name = 'me' }
}
$slug = ($Name -replace '[^A-Za-z0-9_\-]', '').ToLower()
if ($slug -eq '') { $slug = 'me' }
Ok "$(Lbl 'Pack name' 'Название')$Name"

# The pack lands next to the launcher that made it. Two cases, and telling them apart
# is what makes update-config.cmd work: launched from inside a pack, it rebuilds that
# pack in place; launched from anywhere else, it creates cs2-config alongside itself.
if (-not $OutDir) {
    $here = $env:SELFDIR
    if (-not $here) { $here = (Get-Location).Path }
    $here = $here.TrimEnd('\')
    if (Test-Path (Join-Path $here 'apply-config.cmd')) {
        $OutDir = $here
    } else {
        $OutDir = Join-Path $here 'cs2-config'
    }
}

if ((Test-Path $OutDir) -and -not $Force) {
    $existing = @(Get-ChildItem $OutDir -Force -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Warn "$OutDir already exists and is not empty." `
             "Папка $OutDir уже есть и не пуста."
        Info 'Its cfg/, video/, cloud-backup/ and generated files will be replaced.' `
             'Папки cfg/, video/, cloud-backup/ и созданные файлы будут перезаписаны.'
        Info 'Anything else in the folder is left alone.' `
             'Остальное в папке не трогается.'
    }
}

# --- configs ----------------------------------------------------------------------
$userCfgs = Get-UserCfgFiles $cfgDir
if ($userCfgs.Count -eq 0) {
    Warn 'No user configs found in the game cfg folder.' `
         'В папке cfg не нашлось ни одного твоего конфига.'
    Info 'If you keep configs elsewhere, copy them into that folder and run this again.' `
         'Если держишь их в другом месте — перенеси их туда и запусти снова.'
} else {
    Ok "$(Lbl 'Configs found' 'Найдено конфигов')$($userCfgs.Count)"
    foreach ($f in $userCfgs) { Info "  $($f.Name)" }
}

if (-not $Main) { $Main = Find-MainCfg $userCfgs $keysPath }
$hasOwnAutoexec = @($userCfgs | Where-Object { $_.Name.ToLower() -eq 'autoexec.cfg' }).Count -gt 0
if ($Main) {
    Ok "$(Lbl 'Main config' 'Главный конфиг')$Main"
} elseif (-not $hasOwnAutoexec) {
    Warn 'Could not tell which config is your main one.' `
         'Не понял, какой из конфигов главный.'
    Info 'autoexec will only load the crosshair. Point your own autoexec.cfg at it instead.' `
         'autoexec подтянет только прицел. Пропиши нужный exec в своём autoexec.cfg.'
}

# --- crosshair ---------------------------------------------------------------------
# CS2 packs a whole crosshair into 18 bytes and prints them as base-57. Rebuilding that
# code here means the summary shows something you can paste into any client or send to
# someone, instead of a count of convars that tells you nothing. Byte layout follows the
# maintained reference implementation, github.com/akiver/csgo-sharecode.
$XH_DICT = 'ABCDEFGHJKLMNOPQRSTUVWXYZabcdefhijkmnopqrstuvwxyz23456789'

# Convars are strings, and CS2 writes booleans as true/false. Anything unreadable falls
# back to 0, which is what the game itself would show for a convar it never wrote.
function Cv-Num($map, $key) {
    if (-not $map.Contains($key)) { return 0.0 }
    $v = ([string]$map[$key]).Trim()
    if ($v -eq 'true')  { return 1.0 }
    if ($v -eq 'false') { return 0.0 }
    $out = 0.0
    if ([double]::TryParse($v, [Globalization.NumberStyles]::Float,
                           [Globalization.CultureInfo]::InvariantCulture, [ref]$out)) { return $out }
    return 0.0
}
# The format stores tenths and halves as whole bytes, so every field is scaled then
# rounded. A slider set to 1.875223 comes back as 1.9, exactly as the game encodes it.
function Cv-Scaled($map, $key, $scale) {
    return [int][math]::Round((Cv-Num $map $key) * $scale, [MidpointRounding]::AwayFromZero)
}
function Cv-Flag($map, $key) {
    if ((Cv-Num $map $key) -ne 0) { return 1 }
    return 0
}

function Get-CrosshairShareCode($map) {
    $b = New-Object byte[] 18
    $b[1]  = 1                                                    # format version
    $b[2]  = (Cv-Scaled $map 'cl_crosshairgap' 10) -band 0xff      # signed, wraps
    $b[3]  = (Cv-Scaled $map 'cl_crosshair_outlinethickness' 2) -band 0xff
    $b[4]  = (Cv-Scaled $map 'cl_crosshaircolor_r' 1) -band 0xff
    $b[5]  = (Cv-Scaled $map 'cl_crosshaircolor_g' 1) -band 0xff
    $b[6]  = (Cv-Scaled $map 'cl_crosshaircolor_b' 1) -band 0xff
    $b[7]  = (Cv-Scaled $map 'cl_crosshairalpha' 1) -band 0xff
    $b[8]  = ((Cv-Scaled $map 'cl_crosshair_dynamic_splitdist' 1) -band 7) -bor
             ((Cv-Flag $map 'cl_crosshair_recoil') -shl 7)
    $b[9]  = (Cv-Scaled $map 'cl_fixedcrosshairgap' 10) -band 0xff # signed, wraps
    $b[10] = ((Cv-Scaled $map 'cl_crosshaircolor' 1) -band 7) -bor
             ((Cv-Flag $map 'cl_crosshair_drawoutline') -shl 3) -bor
             (((Cv-Scaled $map 'cl_crosshair_dynamic_splitalpha_innermod' 10) -band 0xF) -shl 4)
    $b[11] = ((Cv-Scaled $map 'cl_crosshair_dynamic_splitalpha_outermod' 10) -band 0xF) -bor
             (((Cv-Scaled $map 'cl_crosshair_dynamic_maxdist_splitratio' 10) -band 0xF) -shl 4)
    $b[12] = (Cv-Scaled $map 'cl_crosshairthickness' 10) -band 0xff
    $b[13] = (((Cv-Scaled $map 'cl_crosshairstyle' 1) -band 7) -shl 1) -bor
             ((Cv-Flag $map 'cl_crosshairdot') -shl 4) -bor
             ((Cv-Flag $map 'cl_crosshairgap_useweaponvalue') -shl 5) -bor
             ((Cv-Flag $map 'cl_crosshairusealpha') -shl 6) -bor
             ((Cv-Flag $map 'cl_crosshair_t') -shl 7)
    $b[14] = (Cv-Scaled $map 'cl_crosshairsize' 10) -band 0xff

    # Byte 0 is a checksum over the rest; CS2 refuses the code without it.
    $sum = 0
    for ($i = 1; $i -lt 18; $i++) { $sum += $b[$i] }
    $b[0] = $sum -band 0xff

    $total = [System.Numerics.BigInteger]::Zero
    foreach ($x in $b) { $total = $total * 256 + [int]$x }
    $out = ''
    for ($i = 0; $i -lt 25; $i++) {
        $out += $XH_DICT[[int]($total % 57)]
        $total = [System.Numerics.BigInteger]::Divide($total, 57)
    }
    return "CSGO-$($out.Substring(0,5))-$($out.Substring(5,5))-$($out.Substring(10,5))-" +
           "$($out.Substring(15,5))-$($out.Substring(20,5))"
}

$crosshair = [ordered]@{}
foreach ($k in $convars.Keys) {
    if ($k -match '^(cl_crosshair|cl_fixedcrosshairgap)') { $crosshair[$k] = $convars[$k] }
}
if ($crosshair.Count -gt 0) {
    $shareCode = $null
    try { $shareCode = Get-CrosshairShareCode $convars } catch { $shareCode = $null }
    if ($shareCode) {
        Ok "$(Lbl 'Crosshair' 'Прицел')$shareCode"
    } else {
        Ok "$(Lbl 'Crosshair' 'Прицел')$($crosshair.Count) convars captured" `
           "$(Lbl 'Crosshair' 'Прицел')переменных снято: $($crosshair.Count)"
    }
} else {
    Warn 'No crosshair convars found. Launch CS2 once so it writes its settings.' `
         'Переменные прицела не найдены. Зайди в CS2 один раз, чтобы она их записала.'
}

# --- launch options ------------------------------------------------------------------
$launchRaw = $null
if ($accountId) { $launchRaw = Get-LaunchOptions $steam $accountId }
$launch = $null
if ($launchRaw) {
    $launch = Get-PortableLaunchOptions $launchRaw
    Ok "$(Lbl 'Launch options' 'Параметры запуска')captured" `
       "$(Lbl 'Launch options' 'Параметры запуска')считаны"
    # Said here rather than in the pack README, which is read by whoever receives the
    # pack; this concerns whoever builds it, and only once.
    if ($launch.Dropped.Count -gt 0) {
        Info '  left out of the portable line, they do not travel well:' `
             '  не вошли в переносимый вариант, плохо переносятся:'
        foreach ($d in $launch.Dropped) {
            Info "    $($d.Text) — $($d.Why)" "    $($d.Text) — $($d.WhyRu)"
        }
    }
} else {
    Warn 'No launch options set for CS2 (or none found).' `
         'Параметры запуска у CS2 не заданы, либо найти их не вышло.'
}

# ==================================================================================
#  Assemble
# ==================================================================================

Head '--- building pack ---' '--- собираю набор ---'

foreach ($sub in @('cfg', 'video', 'cloud-backup', 'machine')) {
    $p = Join-Path $OutDir $sub
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    New-Item -ItemType Directory -Force $p | Out-Null
}

$packCfg = Join-Path $OutDir 'cfg'
foreach ($f in $userCfgs) {
    if ($f.Name.ToLower() -eq 'autoexec.cfg') { continue }   # rebuilt below
    Copy-Item $f.FullName $packCfg -Force
}

# crosshair.cfg
if ($crosshair.Count -gt 0) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('// Crosshair, read from your CS2 settings by cs2-config.')
    [void]$sb.AppendLine('// Applying this needs no share code.')
    [void]$sb.AppendLine('')
    foreach ($k in $crosshair.Keys) { [void]$sb.AppendLine("$k `"$($crosshair[$k])`"") }
    [IO.File]::WriteAllText((Join-Path $packCfg 'crosshair.cfg'), $sb.ToString(), $UTF8)
}

# autoexec.cfg: keep the user's own content, then add what is missing
$autoBody = ''
$ownAutoexec = @($userCfgs | Where-Object { $_.Name.ToLower() -eq 'autoexec.cfg' })
if ($ownAutoexec.Count -gt 0) { $autoBody = [IO.File]::ReadAllText($ownAutoexec[0].FullName).TrimEnd() }

$needed = New-Object System.Collections.Generic.List[string]
if ($crosshair.Count -gt 0 -and $autoBody -notmatch '(?i)\bexec\s+"?crosshair') { $needed.Add('exec crosshair') }
if ($Main) {
    $mainBare = [IO.Path]::GetFileNameWithoutExtension($Main)
    if ($autoBody -notmatch "(?i)\bexec\s+`"?$([regex]::Escape($mainBare))") { $needed.Add("exec $mainBare") }
}

$auto = New-Object System.Text.StringBuilder
if ($autoBody -ne '') {
    [void]$auto.AppendLine($autoBody)
    # Only when there is something to put under it. Otherwise applying the pack and then
    # rebuilding it leaves a marker with nothing beneath, and another one every round.
    if ($needed.Count -gt 0) {
        [void]$auto.AppendLine('')
        [void]$auto.AppendLine('// ---- added by cs2-config ----')
    }
} else {
    [void]$auto.AppendLine('// CS2 runs this file automatically on startup.')
    [void]$auto.AppendLine('// Generated by cs2-config.')
    [void]$auto.AppendLine('')
}
foreach ($line in $needed) { [void]$auto.AppendLine($line) }
if ($autoBody -eq '') {
    [void]$auto.AppendLine('')
    [void]$auto.AppendLine('host_writeconfig')
} elseif ($needed.Count -gt 0 -and $autoBody -match '(?i)\bhost_writeconfig\b') {
    # Their own host_writeconfig ran before the lines we just appended, so it would not
    # persist them. Run it once more at the end.
    [void]$auto.AppendLine('host_writeconfig')
}
[IO.File]::WriteAllText((Join-Path $packCfg 'autoexec.cfg'), $auto.ToString(), $UTF8)

# video + cloud backup
$hasVideo = $false
if ($videoPath) {
    Copy-Item $videoPath (Join-Path $OutDir 'video') -Force
    $hasVideo = $true
}
$cloudFiles = @()
foreach ($p in @($convarsPath, $keysPath)) {
    if (-not $p) { continue }
    $dest = Join-Path (Join-Path $OutDir 'cloud-backup') (Split-Path -Leaf $p)
    if ($Anonymize -and $p -eq $convarsPath) {
        $text = [IO.File]::ReadAllText($p) -replace '(?m)^(\s*"name"\s+")[^"]*(")', '${1}player${2}'
        [IO.File]::WriteAllText($dest, $text, $UTF8)
    } else {
        Copy-Item $p $dest -Force
    }
    $cloudFiles += (Split-Path -Leaf $p)
}
$machineCount = 0
if ($machinePath) {
    $sel = Select-MachineConvars $machinePath
    if ($sel.Count -gt 0) {
        [IO.File]::WriteAllText((Join-Path (Join-Path $OutDir 'machine') 'cs2_machine_convars.vcfg'), $sel.Text, $UTF8)
        $machineCount = $sel.Count
    }
}
if ($Anonymize) {
    Ok "$(Lbl 'Anonymized' 'Обезличено')in-game name stripped" `
       "$(Lbl 'Anonymized' 'Обезличено')игровой ник убран"
}

$packedCfgs = @(Get-ChildItem $packCfg -Filter *.cfg | Sort-Object Name)
Ok "$(Lbl 'cfg/' 'cfg/')$($packedCfgs.Count) files" "$(Lbl 'cfg/' 'cfg/')файлов: $($packedCfgs.Count)"
if ($hasVideo)         { Ok "$(Lbl 'video/' 'video/')cs2_video.txt" }
if ($machineCount -gt 0) {
    Ok "$(Lbl 'machine/' 'machine/')$machineCount convars Steam Cloud does not carry" `
       "$(Lbl 'machine/' 'machine/')переменных, которые не возит Steam Cloud: $machineCount"
}
if ($cloudFiles.Count) {
    Ok "$(Lbl 'cloud-backup/' 'cloud-backup/')$($cloudFiles.Count) files" `
       "$(Lbl 'cloud-backup/' 'cloud-backup/')файлов: $($cloudFiles.Count)"
}

# ==================================================================================
#  Generate apply-config.ps1
# ==================================================================================

function Read-Payload($path) {
    $text = [IO.File]::ReadAllText($path)
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match "^\s*'@") { Die "$path has a line starting with '@ and cannot be embedded" }
    }
    return $text.TrimEnd("`r", "`n")
}

function Emit-Map($varName, $dir, $filter) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("`$$varName = [ordered]@{}")
    if (Test-Path $dir) {
        foreach ($f in (Get-ChildItem $dir -Filter $filter -File | Sort-Object Name)) {
            [void]$sb.AppendLine("`$$varName['$($f.Name)'] = @'")
            [void]$sb.AppendLine((Read-Payload $f.FullName))
            [void]$sb.AppendLine("'@")
        }
    }
    return $sb.ToString()
}

$payload  = Emit-Map 'GameCfg'  $packCfg                               '*.cfg'
$payload += Emit-Map 'VideoCfg'   (Join-Path $OutDir 'video')          '*.txt'
$payload += Emit-Map 'CloudCfg'   (Join-Path $OutDir 'cloud-backup')   '*.vcfg'
$payload += Emit-Map 'MachineCfg' (Join-Path $OutDir 'machine')        '*.vcfg'

$launchPortable = ''
if ($launch) { $launchPortable = $launch.Portable }

# A video config records the GPU it came from - VendorID, DeviceID, knowndevice - and on
# other hardware CS2 decides the file is not its own, re-detects and rewrites it, taking
# the resolution with it. -w/-h are read before any of that happens and do not care what
# card is in the machine, which is why they are not in $NotPortable: on a foreign PC they
# are the only thing that holds the resolution. Added here when Steam has none set.
if ($videoPath -and ($launchPortable -notmatch '(^|\s)-(w|width|h|height)(\s|$)')) {
    $vset = Read-VdfPairs $videoPath
    $vw = $vset['setting.defaultres']
    $vh = $vset['setting.defaultresheight']
    if ($vw -and $vh) {
        $res = "-w $vw -h $vh"
        if ($vset['setting.fullscreen'] -eq '1') { $res += ' -fullscreen' }
        $launchPortable = ("$launchPortable $res").Trim()
        Ok "$(Lbl 'Resolution' 'Разрешение')${vw}x${vh}, added to the launch options" `
           "$(Lbl 'Resolution' 'Разрешение')${vw}x${vh}, добавлено в параметры запуска"
    }
}

# CS2 is supposed to run autoexec.cfg by itself, and mostly does. Everything in a pack
# hangs off that one file, so on a PC you get for an hour it is worth not depending on
# "mostly": +exec autoexec costs nothing and runs it a second time at worst.
if ($launchPortable -notmatch '(?i)(^|\s)\+exec\s+autoexec(\s|$)') {
    $launchPortable = ("$launchPortable +exec autoexec").Trim()
}

$restoreConsts =
    "`$PackName      = '$($Name -replace "'", "''")'`r`n" +
    "`$LaunchOptions = '$($launchPortable -replace "'", "''")'`r`n" +
    "`$ToolUrl       = '$TOOL_URL'`r`n"

$restoreHead = @'
<#
    CS2 settings pack. SELF-CONTAINED - every config is embedded below, so this one
    file is all you need on another PC. No git, no ZIP, no internet.

    Double-click apply-config.cmd and pick from the menu, or pass a switch to it
    and the menu is skipped:

      apply-config.cmd            configs only
      apply-config.cmd -Video     also apply resolution and quality
      apply-config.cmd -Convars   also restore sensitivity and binds (if Steam Cloud failed)
      apply-config.cmd -Check     show what differs, write nothing
      apply-config.cmd -Undo      put this PC back the way you found it

    GENERATED FILE. Rebuild it with update-config.cmd instead of editing it.
#>
param(
    [switch]$Video,
    [switch]$Convars,
    [switch]$Check,
    [switch]$Undo
)

$ErrorActionPreference = 'Stop'
$BackupRoot = Join-Path $env:TEMP 'cs2-config-apply-backup'
$Backup     = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')

# The Windows display language decides, and nothing else. Keyboard layouts are not
# consulted. Every message carries both languages at the call site; passing only English
# means "same in both", which is what you want for paths and file names.
$Lang = 'en'
try {
    if ((Get-UICulture).TwoLetterISOLanguageName -eq 'ru') { $Lang = 'ru' }
} catch { }

function L($en, $ru) {
    if ($Lang -eq 'ru' -and $ru) { return $ru }
    return $en
}
function Info($en, $ru) { Write-Host "     $(L $en $ru)" }
function Ok  ($en, $ru) { Write-Host "OK   $(L $en $ru)" -ForegroundColor Green }
function Warn($en, $ru) { Write-Host "WARN $(L $en $ru)" -ForegroundColor Yellow }
function Die ($en, $ru) { Write-Host "FAIL $(L $en $ru)" -ForegroundColor Red; exit 1 }

# Status words sit in a fixed column, and the Russian ones are longer. Pad, do not count.
function Mark($en, $ru) { return (L $en $ru).PadRight(11) }

# Windows does not care how a path is spelled, but whoever reads the output does. Steam
# writes SteamPath into the registry all lower case and with forward slashes, like
# c:/program files (x86)/steam. The slashes are a substitution; how the folders are really
# spelled only the filesystem knows, so every segment is looked up in its parent.
function Get-TruePath($path) {
    $dir = New-Object IO.DirectoryInfo $path
    if (-not $dir.Exists) { return $path }
    $parts = New-Object System.Collections.Generic.List[string]
    while ($dir.Parent) {
        $hit = $dir.Parent.GetDirectories($dir.Name)
        if ($hit.Count -lt 1) { return $path }
        $parts.Insert(0, $hit[0].Name)
        $dir = $dir.Parent
    }
    # Only a drive letter is worth upper-casing. A UNC root is spelled by its server.
    $root = $dir.Name.TrimEnd('\')
    if ($root -match '^[a-z]:$') { $root = $root.ToUpper() }
    if ($parts.Count -eq 0) { return "$root\" }
    return $root + '\' + ($parts -join '\')
}

function Get-SteamPath {
    foreach ($k in @('HKCU:\Software\Valve\Steam',
                     'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
                     'HKLM:\SOFTWARE\Valve\Steam')) {
        if (Test-Path $k) {
            $p = Get-ItemProperty $k
            $raw = $p.SteamPath
            if (-not $raw) { $raw = $p.InstallPath }
            if ($raw) { return Get-TruePath (($raw -replace '/', '\').TrimEnd('\')) }
        }
    }
    return $null
}

function Get-CS2CfgPath($steam) {
    $roots = New-Object System.Collections.Generic.List[string]
    $roots.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($line in Get-Content $vdf) {
            if ($line -match '"path"\s+"(.+?)"') { $roots.Add(($matches[1] -replace '\\\\', '\')) }
        }
    }
    foreach ($r in $roots) {
        $p = Join-Path $r 'steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg'
        if (Test-Path $p) { return Get-TruePath $p }
    }
    return $null
}

function Get-UserCfgPath($steam) {
    if (Test-Path 'HKCU:\Software\Valve\Steam\ActiveProcess') {
        $id = (Get-ItemProperty 'HKCU:\Software\Valve\Steam\ActiveProcess').ActiveUser
        if ($id -and $id -ne 0) {
            $p = Join-Path $steam "userdata\$id\730\local\cfg"
            if (Test-Path $p) { return $p }
        }
    }
    $ud = Join-Path $steam 'userdata'
    if (-not (Test-Path $ud)) { return $null }
    $best = Get-ChildItem $ud -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName '730\local\cfg') } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($best) { return (Join-Path $best.FullName '730\local\cfg') }
    return $null
}

$UTF8 = New-Object System.Text.UTF8Encoding($false)

function Normalize($text) { return ($text -replace "`r`n", "`n").TrimEnd("`n", " ", "`t") }

function Compare-Payload($map, $destDir, $label) {
    if (-not $destDir) { return }
    foreach ($name in $map.Keys) {
        $dest = Join-Path $destDir $name
        if (-not (Test-Path $dest)) { Write-Host "     $(Mark 'MISSING' 'НЕТ ВОВСЕ')$label/$name" -ForegroundColor Yellow }
        elseif ((Normalize ([IO.File]::ReadAllText($dest))) -eq (Normalize $map[$name])) {
            Info "$(Mark 'same' 'совпадает')$label/$name"
        }
        else { Write-Host "     $(Mark 'DIFFERENT' 'ОТЛИЧАЕТСЯ')$label/$name" -ForegroundColor Yellow }
    }
}

function Write-Payload($map, $destDir, $tag) {
    $bdir  = Join-Path $Backup $tag
    $added = New-Object System.Collections.Generic.List[string]
    foreach ($name in $map.Keys) {
        $dest = Join-Path $destDir $name
        if (Test-Path $dest) {
            New-Item -ItemType Directory -Force $bdir | Out-Null
            Copy-Item $dest $bdir -Force
        } else {
            # Nothing to back up: remember it so -Undo can delete it again.
            $added.Add($name)
        }
        [IO.File]::WriteAllText($dest, ($map[$name] -replace "`r?`n", "`r`n") + "`r`n", $UTF8)
        Info $name
    }
    if ($added.Count -gt 0) {
        New-Item -ItemType Directory -Force $bdir | Out-Null
        [IO.File]::WriteAllLines((Join-Path $bdir '_added.txt'), $added)
    }
}

'@

$restoreBody = @'

# No switch on the command line means somebody double-clicked the launcher, so ask. The
# menu lives here and not in the .cmd above it: this half already knows the display
# language, and cmd would need its own detection to say the same thing in Russian.
if (-not ($Video -or $Convars -or $Check -or $Undo)) {
    Write-Host ''
    Write-Host (L '  CS2 CONFIG' '  КОНФИГ CS2') -ForegroundColor Cyan
    Write-Host ''
    Write-Host (L '    [1]  Apply everything     configs, crosshair, resolution and quality' `
                  '    [1]  Применить всё        конфиги, прицел, разрешение и качество')
    Write-Host (L '    [2]  Apply configs only   the video settings of this PC stay as they are' `
                  '    [2]  Только конфиги       настройки видео этого ПК останутся как есть')
    Write-Host (L '    [3]  Check                show what differs, change nothing' `
                  '    [3]  Проверить            показать различия, ничего не менять')
    Write-Host (L '    [4]  Undo                 put this PC back the way you found it' `
                  '    [4]  Откатить             вернуть ПК в то состояние, в котором застал')
    Write-Host ''
    $pick = Read-Host (L '  Choose 1-4, or just press Enter for 1' `
                         '  Выбери 1-4 или просто нажми Enter для 1')
    # "$pick", not $pick: with no console to read from, Read-Host hands back null, and
    # calling .Trim() on that would end the run with a stack trace instead of a default.
    switch ("$pick".Trim()) {
        '2'     { }
        '3'     { $Check = $true }
        '4'     { $Undo  = $true }
        default { $Video = $true }
    }
}

Write-Host ''
Write-Host (('=== ' + (L 'CS2 settings' 'Конфиг CS2') + ": $PackName ").PadRight(60, '=')) -ForegroundColor Cyan

$steam = Get-SteamPath
if (-not $steam) { Die 'Steam not found in the registry. Is Steam installed?' `
                       'Steam не найден в реестре. Он вообще установлен?' }
$cfgDir = Get-CS2CfgPath $steam
if (-not $cfgDir) { Die 'CS2 not found in any Steam library. Install CS2 first.' `
                        'CS2 не найдена ни в одной библиотеке Steam. Сначала установи игру.' }
$userCfg = Get-UserCfgPath $steam
Ok ((L 'CS2 cfg folder' 'Папка cfg').PadRight(17) + $cfgDir)

# --- undo -------------------------------------------------------------------------
if ($Undo) {
    if (-not (Test-Path $BackupRoot)) { Die 'No backup found on this PC. Nothing to undo.' `
                                            'На этом ПК нет резервной копии. Откатывать нечего.' }
    $last = Get-ChildItem $BackupRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $last) { Die 'No backup found on this PC. Nothing to undo.' `
                          'На этом ПК нет резервной копии. Откатывать нечего.' }
    Write-Host ''
    Write-Host (L "Restoring the files this PC had before, from $($last.Name)" `
                  "Возвращаю файлы, которые были на этом ПК, из копии $($last.Name)")
    $map = @{ 'cfg' = $cfgDir; 'video' = $userCfg; 'cloud' = $userCfg; 'machine' = $userCfg }
    foreach ($tag in $map.Keys) {
        $dir = Join-Path $last.FullName $tag
        if (-not (Test-Path $dir) -or -not $map[$tag]) { continue }
        foreach ($f in Get-ChildItem $dir -File) {
            if ($f.Name -eq '_added.txt') { continue }
            Copy-Item $f.FullName (Join-Path $map[$tag] $f.Name) -Force
            Info "$(Mark 'restored' 'возвращён')$tag/$($f.Name)"
        }
        $addedList = Join-Path $dir '_added.txt'
        if (Test-Path $addedList) {
            foreach ($n in (Get-Content $addedList)) {
                if ($n.Trim() -eq '') { continue }
                $victim = Join-Path $map[$tag] $n
                if (Test-Path $victim) { Remove-Item $victim -Force; Info "$(Mark 'removed' 'удалён')$tag/$n" }
            }
        }
    }
    Ok 'Undo complete. This PC is back to how you found it.' `
       'Откат выполнен. ПК в том состоянии, в котором ты его застал.'
    exit 0
}

# --- check ------------------------------------------------------------------------
if ($Check) {
    Write-Host ''
    Write-Host (L 'Comparing this pack against the PC (nothing will be written):' `
                  'Сравниваю набор с тем, что на ПК (ничего не записывается):')
    Compare-Payload $GameCfg  $cfgDir  'cfg'
    if ($userCfg) {
        Compare-Payload $VideoCfg   $userCfg 'video'
        Compare-Payload $MachineCfg $userCfg 'machine'
        Compare-Payload $CloudCfg   $userCfg 'cloud'
    }
    Write-Host ''
    Info 'Run without -Check to apply.' 'Запусти без -Check, чтобы применить.'
    exit 0
}

# --- apply ------------------------------------------------------------------------
Write-Host ''
Write-Host (L 'Writing configs:' 'Пишу конфиги:')
Write-Payload $GameCfg $cfgDir 'cfg'
Ok 'Configs in place. Crosshair included, no share code needed.' `
   'Конфиги на месте. Прицел внутри, код обмена не нужен.'

# Radar, fov, volumes, HUD scale. Steam Cloud does not carry these, so on any PC but the
# one they came from they are that machine's defaults unless this writes them. Applied
# with the configs rather than behind -Convars: nothing here belongs to Steam, so nothing
# overwrites it on the way out - only CS2 itself does, which is why it has to be closed.
if ($userCfg -and $MachineCfg.Count -gt 0) {
    Write-Host ''
    Write-Host (L 'Writing the settings Steam Cloud does not carry:' `
                  'Пишу настройки, которые не возит Steam Cloud:')
    Write-Payload $MachineCfg $userCfg 'machine'
    Warn 'CS2 must be closed for these: it rewrites this file when it exits.' `
         'Для них CS2 должна быть закрыта: при выходе она перезаписывает этот файл.'
}

if ($Video) {
    if (-not $userCfg) { Warn 'No CS2 userdata folder. Log into Steam, run CS2 once, retry.' `
                              'Нет папки userdata для CS2. Войди в Steam, запусти игру один раз и повтори.' }
    elseif ($VideoCfg.Count -eq 0) { Warn 'This pack has no video settings.' `
                                          'В этом наборе нет настроек видео.' }
    else {
        Write-Host ''
        Write-Host (L 'Writing video settings:' 'Пишу настройки видео:')
        Write-Payload $VideoCfg $userCfg 'video'
        Warn 'On a different GPU, CS2 re-detects and overrides some of this. The resolution is in the launch options for that reason.' `
             'На другой видеокарте CS2 определит её заново и часть этого перепишет. Поэтому разрешение продублировано в параметрах запуска.'
    }
} else {
    Info ''
    Info 'Video settings not touched. Pass -Video to apply them.' `
         'Настройки видео не тронуты. Передай -Video, чтобы применить и их.'
}

if ($Convars) {
    if (-not $userCfg) { Warn 'No CS2 userdata folder. Cannot restore the cloud backup.' `
                              'Нет папки userdata для CS2. Вернуть копию из облака не получится.' }
    else {
        Write-Host ''
        Write-Host (L 'Restoring Steam Cloud settings:' 'Возвращаю настройки из Steam Cloud:')
        Warn 'Close CS2 AND Steam first, or Steam overwrites these when it exits.' `
             'Сначала закрой и CS2, и Steam: иначе Steam перезапишет их при выходе.'
        Write-Payload $CloudCfg $userCfg 'cloud'
    }
}

if (Test-Path $Backup) {
    Write-Host ''
    Info "$(L 'Original files of this PC' 'Исходные файлы этого ПК'): $Backup"
    Info 'Run with -Undo to put them back.' 'Запусти с -Undo, чтобы вернуть их на место.'
}

Write-Host ''
Write-Host ((L '=== BY HAND ' '=== ВРУЧНУЮ ').PadRight(60, '=')) -ForegroundColor Cyan
if ($LaunchOptions -ne '') {
    Write-Host ''
    Write-Host (L 'Launch options (Steam > CS2 > Properties > General):' `
                  'Параметры запуска (Steam > CS2 > Свойства > Общие):') -ForegroundColor White
    Write-Host ''
    Write-Host "   $LaunchOptions" -ForegroundColor Yellow
    try {
        Set-Clipboard -Value $LaunchOptions
        Write-Host ''
        Info 'Copied to your clipboard. Just paste.' 'Скопировано в буфер обмена. Просто вставь.'
    } catch { }
}
Write-Host ''
Write-Host (L 'If you play a stretched 4:3 resolution, set GPU scaling too:' `
              'Если играешь в растянутом 4:3, настрой ещё и масштабирование:') -ForegroundColor White
Write-Host (L 'NVIDIA Control Panel > Adjust desktop size and position > Full-screen,' `
              'Панель управления NVIDIA > Регулировка размера и положения > Во весь экран,') -ForegroundColor White
Write-Host (L 'scaling on GPU, tick Override the scaling mode set by games.' `
              'масштабирование на GPU, галочка «Замещение режима масштабирования, заданного играми».') -ForegroundColor White
Write-Host ''
Write-Host (L 'Then start CS2 and check your crosshair, sensitivity and binds.' `
              'Дальше запусти CS2 и проверь прицел, чувствительность и бинды.') -ForegroundColor White
Write-Host ''
Write-Host (L "Made with cs2-config: $ToolUrl" "Собрано утилитой cs2-config: $ToolUrl") -ForegroundColor DarkGray
Write-Host ''
'@

$applyPs = $restoreHead + $payload + "`r`n" + $restoreConsts + $restoreBody

$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($applyPs, [ref]$null, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    Write-Host 'FAIL the generated apply-config has syntax errors:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "     $($_.Message) (line $($_.Extent.StartLineNumber))" -ForegroundColor Red }
    exit 1
}

# One file, not two. The PowerShell rides below a marker inside the .cmd, where cmd
# never reads, and the launcher unpacks it to TEMP before running it: the same trick
# this file uses on itself. A loose .ps1 is only a thing to lose, to leave behind on
# someone else's PC, or to open in Notepad by accident.
#
# Its marker is ::CFG::, deliberately different from the one this file carries for
# itself, so neither extractor can ever find the other's payload. For that same reason
# this file's own marker is never spelled out again anywhere below it: extraction takes
# the LAST match, so a second mention would silently become the marker.
$applyCmdHead = @'
@echo off
rem  Double-click this to apply the settings in this folder.
rem
rem  Generated by cs2-config. Everything is in this one file: the PowerShell below
rem  the marker is plain text, and cmd stops reading at the exit above it.

setlocal
title CS2 config

rem  Cyrillic needs a console codepage that can render it; a stock Russian console is 866.
rem  Switch to UTF-8 and put the old one back on the way out, so running this from an
rem  existing terminal leaves no trace.
set "CP="
for /f "tokens=2 delims=:" %%c in ('chcp') do set "CP=%%c"
chcp 65001 >nul

set "PS1=%TEMP%\apply-config.ps1"
if exist "%PS1%" del "%PS1%"

rem  Via an environment variable, so an apostrophe in the path cannot break the string.
set "SELF=%~f0"
powershell -NoProfile -Command "$m='::'+'CFG::'; $t=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8); $i=$t.LastIndexOf($m); if($i -lt 0){exit 1}; [IO.File]::WriteAllText($env:TEMP+'\apply-config.ps1', $t.Substring($i+$m.Length), (New-Object Text.UTF8Encoding($true)))"
if not exist "%PS1%" goto broken

rem  Switches go straight through. With none the script shows its own menu: that lives on
rem  the PowerShell side, which already knows the display language, while cmd would need a
rem  second way to work it out.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*

rem  Leave nothing behind on a machine you borrowed.
if exist "%PS1%" del "%PS1%"
echo.
pause
call :restorecp
exit /b 0

:broken
rem  Both languages at once, no detection. This runs when the file itself is damaged,
rem  which is the worst possible place for one more thing that can go wrong.
echo.
echo Could not unpack the script from this file.
echo Re-download it: some editors and chat apps corrupt .cmd files.
echo.
echo If PowerShell is blocked here, copy cfg\*.cfg into the game folder by hand,
echo or paste apply-config-using-console.txt into the CS2 console instead.
echo.
echo Не удалось распаковать скрипт из этого файла.
echo Скачай его заново: некоторые редакторы и мессенджеры портят .cmd.
echo.
echo Если тут закрыт PowerShell, скопируй cfg\*.cfg в папку игры вручную
echo или вставь содержимое apply-config-using-console.txt в консоль CS2.
echo.
pause
call :restorecp
exit /b 1

:restorecp
if defined CP chcp %CP% >nul
goto :eof

::CFG::
'@

$applyCmdText = ($applyCmdHead -replace "`r?`n", "`r`n") + $applyPs
$applyMarker  = '::' + 'CFG::'
$markerHits   = ([regex]::Matches($applyCmdText, [regex]::Escape($applyMarker))).Count
if ($markerHits -ne 1) {
    Die "One of your configs contains the text $applyMarker, which the launcher uses as its own marker. Remove it and run this again." `
        "В одном из твоих конфигов есть текст $applyMarker — этой меткой лаунчер отделяет свой скрипт. Убери её и запусти снова."
}

$applyPath = Join-Path $OutDir 'apply-config.cmd'
[IO.File]::WriteAllText($applyPath, $applyCmdText, $UTF8)
$applyKb = [math]::Round((Get-Item $applyPath).Length / 1KB, 1)
Ok "apply-config.cmd  $applyKb KB, parses clean" `
   "apply-config.cmd  $applyKb КБ, синтаксис в порядке"

# update-config.cmd is this launcher, copied in. Started from inside a pack it rebuilds
# that pack, so updating never means hunting down the original download again.
#
# Skipped when it would land on the file currently running: cmd re-reads a batch file
# after each command returns, so overwriting it mid-run wrecks the rest of the run.
$updatePath = Join-Path $OutDir 'update-config.cmd'
if ($env:SELF -and (Test-Path $env:SELF)) {
    $sameFile = $false
    try { $sameFile = ([IO.Path]::GetFullPath($env:SELF) -eq [IO.Path]::GetFullPath($updatePath)) } catch { }
    if ($sameFile) {
        Ok 'update-config.cmd  already in place' 'update-config.cmd  уже на месте'
    } else {
        Copy-Item $env:SELF $updatePath -Force
        Ok 'update-config.cmd'
    }
} else {
    Warn 'Could not copy myself in as update-config.cmd.' `
         'Не смог положить себя в набор как update-config.cmd.'
    Info 'Updating means running this setup again by hand.' `
         'Обновлять придётся, запуская этот скрипт вручную.'
}

# The one-line install downloads apply-config.cmd straight from GitHub, so the bytes
# stored in the repository are the bytes that run. cmd.exe garbles a batch file whose
# lines end in LF alone, and git normalises CRLF to LF on commit unless told otherwise.
# eol=crlf would not do: that only affects checkout, and the raw download never checks out.
$gitAttrs = @'
# apply-config.cmd is downloaded raw by the one-line install, so what is stored here is
# what runs. cmd.exe misparses a batch file with LF-only line endings, and git would
# normalise them away on commit without this line.
*.cmd -text
'@
[IO.File]::WriteAllText((Join-Path $OutDir '.gitattributes'), ($gitAttrs -replace "`r?`n", "`r`n") + "`r`n", $UTF8)
Ok '.gitattributes' '.gitattributes'

# ==================================================================================
#  Generate apply-config-using-console.txt
# ==================================================================================

# One cfg line is one command. Never split a line: semicolons also appear inside quoted
# bind bodies, and splitting there would corrupt them.
function Get-ConsoleCommands($cfgPath) {
    $cmds = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content $cfgPath)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('//')) { continue }
        $t = $t.TrimEnd(';', ' ')
        if ($t -ne '') { $cmds.Add($t) }
    }
    return $cmds
}

# A config another one binds a key to, like bind f1 "exec training", is meant to run when
# that key is pressed, not now. training.cfg on its own would flip sv_cheats and kick the
# bots on whatever server you happen to be on, so those files stay out of the paste.
function Get-OnDemandCfgs($cfgs) {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($f in $cfgs) {
        foreach ($line in (Get-Content $f.FullName)) {
            foreach ($m in [regex]::Matches($line, '(?i)bind\s+"?[^"\s]+"?\s+"[^"]*\bexec\s+([\w.-]+)')) {
                $n = $m.Groups[1].Value.ToLower()
                if (-not $n.EndsWith('.cfg')) { $n = "$n.cfg" }
                if (-not $names.Contains($n)) { $names.Add($n) }
            }
        }
    }
    return $names
}

# The file is opened, selected whole, copied and pasted into the console once. So it holds
# one line of commands and nothing else: a heading or a note would be pasted along with
# them. What the file cannot say, the pack README says instead.
#
# autoexec.cfg stays out as well. It only chains to the other configs with exec and calls
# host_writeconfig, and neither means anything on a PC that does not have those files.
$onDemand    = Get-OnDemandCfgs $packedCfgs
$consoleCmds = New-Object System.Collections.Generic.List[string]
$consoleLeft = New-Object System.Collections.Generic.List[string]

# Main config first. If the console does turn out to have a length limit, what falls off
# the end is then the least important thing in the file.
$ordered = @($packedCfgs | Where-Object { $Main -and $_.Name -eq $Main }) +
           @($packedCfgs | Where-Object { -not ($Main -and $_.Name -eq $Main) })
foreach ($f in $ordered) {
    $lower = $f.Name.ToLower()
    if ($lower -eq 'autoexec.cfg') { continue }
    if ($onDemand.Contains($lower)) { $consoleLeft.Add($f.Name); continue }
    foreach ($c in (Get-ConsoleCommands $f.FullName)) { $consoleCmds.Add($c) }
}

$consoleLine = ($consoleCmds -join '; ')
# No BOM. The file exists to be copied, and an editor that carries the BOM into the
# clipboard would glue it onto the first command.
[IO.File]::WriteAllText((Join-Path $OutDir 'apply-config-using-console.txt'), $consoleLine, $UTF8)
Ok "apply-config-using-console.txt  $($consoleCmds.Count) commands, $($consoleLine.Length) chars" `
   "apply-config-using-console.txt  команд: $($consoleCmds.Count), символов: $($consoleLine.Length)"
if ($consoleLeft.Count -gt 0) {
    Info "not in it: $($consoleLeft -join ', ') — run from a key, not on arrival" `
         "не вошли: $($consoleLeft -join ', ') — они запускаются с клавиши, а не при старте"
}

# ==================================================================================
#  Generate the pack instructions, English and Russian
#  Markdown, because the pack is meant to end up on GitHub, where README.md becomes the
#  landing page. That decides the formatting: single newlines collapse when rendered, so
#  anything that has to keep its line breaks - listings, commands - goes in a fence.
# ==================================================================================

# The blob page, not the raw URL: GitHub serves a .cmd as text/plain with no attachment
# header, so a raw link opens the script in the browser instead of downloading it. The
# blob page has a download button. Without -RepoUrl nobody knows the repo yet, so the
# placeholders stay in and the person filling them in can see where they go.
$downloadUrl = 'https://github.com/<you>/<repo>/blob/main/apply-config.cmd'
if ($RepoUrl) {
    $downloadUrl = $RepoUrl.TrimEnd('/') + '/blob/main/apply-config.cmd'
} elseif (Test-Path (Join-Path $OutDir 'README.md')) {
    # update-config.cmd knows nothing about where the pack was published, so without this
    # every rebuild by hand would put the placeholders back into a README that already had
    # a working link. Recover it from the README standing here.
    $prev = [regex]::Match([IO.File]::ReadAllText((Join-Path $OutDir 'README.md')),
                           'https://github\.com/[^\s)]+/blob/main/apply-config\.cmd')
    if ($prev.Success -and $prev.Value -notmatch '[<>]') { $downloadUrl = $prev.Value }
}

# PadRight alone is not enough: cs2_user_convars_0_slot0.vcfg is longer than the column,
# and its description would end up glued to the file name.
function Col($name, $desc) {
    if ($desc -eq '') { return $name }
    $gap = 33 - $name.Length
    if ($gap -lt 2) { $gap = 2 }
    return $name + (' ' * $gap) + $desc
}

$fileLinesEn = New-Object System.Collections.Generic.List[string]
$fileLinesRu = New-Object System.Collections.Generic.List[string]
foreach ($f in $packedCfgs) {
    $en = ''
    $ru = ''
    if ($f.Name -eq 'autoexec.cfg')   { $en = 'Runs automatically on startup'; $ru = 'Запускается сам при старте игры' }
    if ($f.Name -eq 'crosshair.cfg')  { $en = 'Your crosshair';                $ru = 'Твой прицел' }
    if ($Main -and $f.Name -eq $Main) { $en = 'Your main config';              $ru = 'Твой главный конфиг' }
    $fileLinesEn.Add((Col "cfg\$($f.Name)" $en))
    $fileLinesRu.Add((Col "cfg\$($f.Name)" $ru))
}
if ($hasVideo) {
    $fileLinesEn.Add((Col 'video\cs2_video.txt' 'Resolution and quality'))
    $fileLinesRu.Add((Col 'video\cs2_video.txt' 'Разрешение и качество картинки'))
}
if ($machineCount -gt 0) {
    $fileLinesEn.Add((Col 'machine\cs2_machine_convars.vcfg' 'Radar, fov, volumes: what Steam Cloud does not carry'))
    $fileLinesRu.Add((Col 'machine\cs2_machine_convars.vcfg' 'Радар, fov, громкости: то, что не возит Steam Cloud'))
}
foreach ($c in $cloudFiles) {
    $fileLinesEn.Add((Col "cloud-backup\$c" 'What Steam Cloud normally brings'))
    $fileLinesRu.Add((Col "cloud-backup\$c" 'То, что обычно приносит Steam Cloud'))
}
$filesBlockEn = ($fileLinesEn -join "`r`n")
$filesBlockRu = ($fileLinesRu -join "`r`n")

$tmplEn = @'
# CS2 config

Packed by [cs2-config]({{TOOLURL}}).

## Installing the config on another PC

Any one of these three. Take the first that works on that PC — they are alternatives, not
steps.

#### Installation file
Download [apply-config.cmd]({{DOWNLOAD}}) and launch it.

#### Copy configs manually
Copy the files from `cfg\` into:

```
...\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\
```

Then restart CS2. `autoexec.cfg` runs on startup and pulls in the rest. If the game is
already open, `exec autoexec` in the console does the same thing once.

#### Use CS2 console
Open `apply-config-using-console.txt` and copy everything, then paste into the CS2 console.

For a PC where you cannot write files at all. Configs and crosshair only.

## Launch options

Steam > CS2 > Properties > General.

Portable version, safe on unknown hardware:

```
{{LAUNCHPORTABLE}}
```

Your full version, for home:

```
{{LAUNCHFULL}}
```

## What is in here

```
apply-config.cmd                 Applies the settings; your configs are embedded in it
apply-config-using-console.txt   One line to paste into the CS2 console
update-config.cmd                Re-reads your settings and rebuilds this folder
.gitattributes                   Keeps the line endings that a downloaded .cmd needs
{{FILES}}
```

The crosshair is applied as convars, so there is nothing to paste. The share code, if you
want it anyway:

```
{{CROSSHAIR}}
```

`cloud-backup\` is a copy of what Steam Cloud normally delivers. You usually never need
it: logging into Steam brings your sensitivity, crosshair and binds down by itself.
'@

$tmplRu = @'
# Конфиг CS2

Собран утилитой [cs2-config]({{TOOLURL}}).

## Установка конфига на другом компьютере

Любой из трёх способов. Бери первый, который сработает на этом ПК: это варианты, а не
шаги.

#### Файл установки
Скачай [apply-config.cmd]({{DOWNLOAD}}) и запусти его.

#### Скопировать конфиги вручную
Скопируй файлы из `cfg\` в папку:

```
...\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\
```

Потом перезапусти CS2: `autoexec.cfg` выполняется при старте и подтягивает остальное.
Если игра уже открыта, то же самое сделает `exec autoexec` в консоли.

#### Через консоль CS2
Открой `apply-config-using-console.txt`, скопируй всё и вставь в консоль CS2.

Для ПК, где записывать файлы нельзя вообще. Только конфиги и прицел.

## Параметры запуска

Steam > CS2 > «Свойства» > «Общие».

Переносимый вариант, безопасный на незнакомом железе:

```
{{LAUNCHPORTABLE}}
```

Твой полный вариант, домашний:

```
{{LAUNCHFULL}}
```

## Что лежит внутри

```
apply-config.cmd                 Применяет настройки; конфиги лежат внутри него же
apply-config-using-console.txt   Одна строка для вставки в консоль CS2
update-config.cmd                Перечитывает настройки и пересобирает эту папку
.gitattributes                   Хранит переводы строк, нужные скачанному .cmd
{{FILES}}
```

Прицел применяется через консольные переменные, вставлять ничего не нужно. Код обмена,
если он всё же нужен:

```
{{CROSSHAIR}}
```

`cloud-backup\` — копия того, что обычно приносит Steam Cloud. Обычно она не нужна:
вход в Steam сам подтянет чувствительность, прицел и бинды.
'@

function Expand-Template($t, $files, $none) {
    $launchFull = $launchRaw
    if (-not $launchFull) { $launchFull = $none }
    $lp = $launchPortable
    if ($lp -eq '') { $lp = $none }
    $xh = $shareCode
    if (-not $xh) { $xh = $none }
    return $t.Replace('{{TOOLURL}}', $TOOL_URL).
              Replace('{{DOWNLOAD}}', $downloadUrl).
              Replace('{{LAUNCHPORTABLE}}', $lp).
              Replace('{{LAUNCHFULL}}', $launchFull).
              Replace('{{CROSSHAIR}}', $xh).
              Replace('{{FILES}}', $files)
}

# CRLF and a BOM so Notepad on a stock Windows box renders them correctly.
# Names this tool used to write. A pack built by an older version keeps them forever
# otherwise, and two apply scripts side by side is worse than none.
foreach ($old in @('cs2-config-apply.cmd', 'cs2-config-apply.ps1', 'apply-config.ps1',
                   'console-paste.txt', 'README.txt', 'README.ru.txt')) {
    $stale = Join-Path $OutDir $old
    if (Test-Path $stale) { Remove-Item $stale -Force }
}
$enTxt = (Expand-Template $tmplEn $filesBlockEn '(none)') -replace "`r?`n", "`r`n"
$ruTxt = (Expand-Template $tmplRu $filesBlockRu '(нет)')  -replace "`r?`n", "`r`n"
# No BOM: markdown is read by GitHub far more often than by Notepad, and modern Notepad
# detects UTF-8 on its own anyway.
[IO.File]::WriteAllText((Join-Path $OutDir 'README.md'),    $enTxt, $UTF8)
[IO.File]::WriteAllText((Join-Path $OutDir 'README.ru.md'), $ruTxt, $UTF8)
Ok 'README.md, README.ru.md' 'README.md, README.ru.md — инструкции'
# ==================================================================================
#  Summary
# ==================================================================================

Head '=== done ===================================================' `
     '=== готово ================================================='
Write-Host ''
Info "Pack written to: $OutDir" "Набор собран здесь: $OutDir"
Write-Host ''
# Just the string worth pasting. The per-flag reasoning lives in the pack README, which
# is where someone actually goes looking for it. Said as "on the other PC" because that
# is where it matters: on this one they are already set, and this line is the trimmed
# version, so pasting it here would quietly drop flags.
if ($launchPortable -ne '') {
    Write-Host (L 'Set these on the other PC (Steam > CS2 > Properties > General):' `
                  'Поставь их на другом ПК (Steam > CS2 > «Свойства» > «Общие»):') -ForegroundColor White
    Write-Host $launchPortable -ForegroundColor Yellow
    Write-Host ''
    Write-Host (L 'The resolution is in there because a video config does not survive another GPU.' `
                  'Разрешение тут потому, что настройки видео не переживают другую видеокарту.') -ForegroundColor DarkGray
    Write-Host ''
}
Write-Host (L 'Next:' 'Дальше:') -ForegroundColor White
Info '1. Copy the whole folder to a USB stick. It is tiny, and apply-config-using-console.txt' `
     '1. Скопируй всю папку на флешку. Она крошечная, а apply-config-using-console.txt —'
Info '   is the fallback you want when a venue PC blocks PowerShell.' `
     '   тот самый запасной вариант, когда на площадке закрыт PowerShell.'
Info '2. On the other PC, double-click apply-config.cmd and pick an option.' `
     '2. На другом ПК кликни по apply-config.cmd и выбери пункт.'
Info '3. Or put the contents of the folder on GitHub, so it can be downloaded anywhere.' `
     '3. Или выложи содержимое папки на GitHub, чтобы скачать её откуда угодно.'
Info '4. Settings changed later? Run update-config.cmd from inside that folder.' `
     '4. Поменяешь настройки — запусти update-config.cmd из этой же папки.'
Write-Host ''

# Hand the path to the launcher, which opens the folder once Enter is pressed. Doing it
# from here instead would bury Explorer under the console window still waiting on pause.
try {
    [IO.File]::WriteAllText((Join-Path $env:TEMP 'cs2-config-outdir.txt'), $OutDir, $UTF8)
} catch { }
