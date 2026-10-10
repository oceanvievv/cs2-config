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
powershell -NoProfile -ExecutionPolicy Bypass -File "%CS2_RUN_FILE%" %*
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
