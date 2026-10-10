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
function Export-Pack($Pack,$Root,[switch]$Rename,$PreviousProfile=$null) {
    Assert-Pack $Pack
    $rootPath=[IO.Path]::GetFullPath($Root)
    if (-not $script:CoreSource) { throw 'The application source is unavailable. Run cs2-config.exe again.' }
    # Prepare every output before replacing anything. profiles.json is authoritative;
    # a failed launcher write can be retried without losing the new profile.
    $outputs=[ordered]@{}
    $outputs['profiles.json']=(ConvertTo-Json -InputObject $Pack -Depth 50) + "`r`n"
    $executable=New-ExecutableBytes $script:CoreSource $Pack
    $readme=New-Object 'Collections.Generic.List[string]'
    $readme.Add('# ' + $Pack.name)
    $readme.Add("`nRun **cs2-config.exe**, choose **Apply profile**, then choose a profile explicitly. Review the settings and select **Apply**.")
    $readme.Add("`nClose CS2 before applying or capturing settings. Sign in to Steam first. Applying a profile creates missing settings folders; no preliminary CS2 launch is required.")
    $readme.Add("`n## Profiles`n")
    foreach ($profile in $Pack.profiles) {
        $name=Get-ConsoleFilename $profile
        $outputs['console\'+$name]=Get-ConsoleCommands $profile
        $readme.Add('- **' + $profile.name + '**: [console commands](console/' + [Uri]::EscapeDataString($name) + ')')
    }
    $readme.Add("`n## Update a profile`n`nChange settings in CS2 or launch options in Steam, exit CS2, run **cs2-config.exe**, choose **Update profile**, and select the profile to update. Review the changes and choose **Save changes**. Only the selected profile is replaced. No previous versions are retained.")
    $readme.Add("`n## Create a profile`n`nRun **cs2-config.exe** and choose **Create profile** in the main menu. Enter any unique name, review the settings and destination, then choose **Create profile**.")
    $readme.Add("`n## Rename the config`n`nChoose **Rename config** in the main menu and enter a new name. This updates the config name and its executable; the folder, GitHub repository and profiles keep their names.")
    $readme.Add("`n## Rename a profile`n`nChoose **Rename profile**, select the profile, then enter its new name. Settings stay unchanged. Console file links are updated automatically.")
    $readme.Add("`n## Launch options`n`nThe profile stores the exact launch options read from Steam. After applying, paste the displayed line into **Steam > CS2 > Properties > General > Launch Options**. An empty line means clearing that field. Launch options are a manual step.")
    $readme.Add("`nIf the requested fullscreen refresh rate exceeds the maximum available at the profile's resolution, the utility uses that maximum and reports the adjustment. The saved profile is unchanged. Explicit refresh arguments in the displayed launch-options line are adjusted for this application too. Unavailable resolutions are skipped.")
    $readme.Add("`n## Console alternative`n`nOpen the command file for your profile above. Paste its commands into the CS2 console in small batches, then check your settings in CS2.`n`nSupported settings: crosshair, mouse, audio and controls.")
    $readme.Add("`n## Files and results`n`n**profiles.json** is the editable source for this config. Keep it beside the executable. The executable also contains all profiles, so a downloaded **cs2-config.exe** can run on its own. Rebuilding updates the executable and console files. Saved and checked means the values were verified on disk; check the actual result after starting CS2. Skipped settings and write failures are listed separately.")
    $readme.Add("`n## Publish or update on GitHub`n`nOpen your config repository, choose **Add file > Upload files**, upload the updated folder contents and choose **Commit changes**. Download a fresh **cs2-config.exe** on another PC; previously downloaded files keep their embedded settings.")
    if ($Pack.Contains('notes') -and $Pack.notes) {
        $readme.Add("`n## Config notes`n")
        foreach ($note in $Pack.notes) { $readme.Add([string]$note) }
    }
    $outputs['README.md']=$readme -join "`r`n"
    $renamedProfile=$null
    if ($PreviousProfile) {
        $renamedProfile=@($Pack.profiles | Where-Object {$_.id -eq $PreviousProfile.id})[0]
        if (-not $renamedProfile) { throw 'The profile to rename could not be found.' }
        $oldFile=Get-ConsoleFilename $PreviousProfile
        $newFile=Get-ConsoleFilename $renamedProfile
    }
    if ($Rename) {
        # Preserve user-written instructions and translated READMEs when renaming.
        foreach ($document in Get-ChildItem -LiteralPath $rootPath -Filter 'README*.md' -File -ErrorAction SilentlyContinue) {
            $body=[IO.File]::ReadAllText($document.FullName)
            $body=$body -replace '\A(?:\uFEFF)?# [^\r\n]*(?:\r?\n|$)', ''
            if ($renamedProfile) {
                $body=$body.Replace(('**'+$PreviousProfile.name+'**'),('**'+$renamedProfile.name+'**'))
                $body=$body.Replace(('console/'+[Uri]::EscapeDataString($oldFile)),('console/'+[Uri]::EscapeDataString($newFile)))
                $body=$body.Replace(('console/'+$oldFile),('console/'+$newFile))
            }
            $outputs[$document.Name]='# ' + $Pack.name + "`r`n" + $body
        }
    }
    $outputs['.gitattributes']="*.exe binary`r`n*.ps1 text eol=crlf`r`n"
    foreach ($name in $outputs.Keys) { Write-TextFile (Join-Path $rootPath $name) $outputs[$name] }
    Write-ExecutableFile (Join-Path $rootPath 'cs2-config.exe') $executable
    if ($renamedProfile -and $oldFile -cne $newFile) {
        $oldPath=Join-Path $rootPath ('console\'+$oldFile)
        if ($oldFile -ieq $newFile) { Rename-Item -LiteralPath $oldPath -NewName $newFile }
        elseif ((Test-Path -LiteralPath $oldPath -PathType Leaf) -and [IO.File]::ReadAllText($oldPath) -ceq (Get-ConsoleCommands $PreviousProfile)) {
            # Only remove this profile's obsolete generated file; preserve hand-edited files.
            Remove-Item -LiteralPath $oldPath
        }
    }
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
