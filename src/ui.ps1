function Show-Header($Title) {
    Write-Host ''; Write-Host 'CS2 CONFIG' -ForegroundColor Cyan
    Write-Host ('Config name: ' + $script:Pack.name)
    Write-Host ''; Write-Host $Title -ForegroundColor White; Write-Host ''
}
function Read-Choice([int[]]$Allowed) {
    while ($true) {
        $value=Read-Host 'Choose an option'
        $number=-1
        if ([int]::TryParse($value,[ref]$number) -and $number -in $Allowed) { return $number }
        Write-Host 'Enter one of the listed numbers.' -ForegroundColor Yellow
    }
}
function Wait-Back { Write-Host ''; [void](Read-Host 'Press Enter to go back') }
function Select-Profile($Purpose) {
    if (-not $script:Pack.profiles.Count) { Write-Host 'No profiles yet. Create a profile first.'; Wait-Back; return $null }
    Show-Header ('Choose a profile to ' + $Purpose)
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
        try { Set-Clipboard -Value $launch; Write-Host 'Copied to clipboard.' } catch { }
        Write-Host "`nStart CS2 to use the saved settings."
        if ($failed.Count) { Write-Host '  [1] Retry'; Write-Host '  [2] Console alternative' }
        Write-Host '  [0] Back to main menu'; Write-Host '  [9] Exit'
        $options=if ($failed.Count) {@(0,1,2,9)} else {@(0,9)}
        switch (Read-Choice $options) {
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
                    Show-Header 'Choose option below:'
                    Write-Host '  [1] Apply profile'; Write-Host '  [2] Update profile'; Write-Host '  [3] Create profile'; Write-Host '  [0] Exit'; Write-Host ''
                    switch (Read-Choice @(0,1,2,3)) {
                        0 { $script:ExitRequested=$true }
                        1 { $Mode='apply' }; 2 { $Mode='update' }; 3 { $Mode='create' }
                    }
                    continue MenuLoop
                }
            }
        } catch { Write-Host ''; Write-Host $_.Exception.Message -ForegroundColor Yellow; Wait-Back }
        $Mode='menu'
    }
}
