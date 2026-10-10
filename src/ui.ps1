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
    Start-TerminalView
}
function Show-Header($Title, [switch]$MainMenu) {
    if (-not [Console]::IsOutputRedirected) { try { $Host.UI.RawUI.WindowTitle = 'CS2 CONFIG - ' + $script:Pack.name } catch { } }
    if ($script:TerminalViewActive) { Start-TerminalScreen ([string]$Title) }
    elseif (-not [Console]::IsOutputRedirected) { try { Clear-Host } catch { } }
    if ($MainMenu) {
        Write-TerminalText 'CS2 CONFIG' -ForegroundColor Cyan
        Write-TerminalText ''
        Write-TerminalText ('Config name: ' + $script:Pack.name)
    }
    Write-TerminalText ''
    if ($Title) { Write-TerminalText $Title -ForegroundColor White; Write-TerminalText '' }
}
function Read-Choice([int[]]$Allowed) {
    if ($script:TerminalViewActive) { return Read-TerminalChoice $Allowed }
    while ($true) {
        Write-TerminalText ''
        $value=Read-TerminalLine 'Enter an option'
        Write-TerminalText ''
        $number=-1
        if ([int]::TryParse($value,[ref]$number) -and $number -in $Allowed) { return $number }
        Write-TerminalText 'Enter one of the listed numbers.' -ForegroundColor Yellow
    }
}
function Wait-Back { Write-TerminalText ''; [void](Read-TerminalLine 'Press Enter to go back') }
function Show-ProfileDetails($Profile) {
    Show-Header 'Profile settings'
    Show-Profile $Profile
    Write-TerminalOption '  [0] Back'
    [void](Read-Choice @(0))
}
function Show-ProfileSummary($Profile) {
    Write-TerminalText ('Profile: '+$Profile.name)
    Write-TerminalText ''
    foreach ($row in (Get-ProfileRows $Profile | Where-Object {$_.Group -eq 'Display'})) {
        Write-TerminalText ('  {0,-20} {1}' -f $row.Name,$row.Value)
    }
}
function Select-Profile($Purpose) {
    Show-Header ('Choose a profile to ' + $Purpose)
    if (-not $script:Pack.profiles.Count) { Write-TerminalText 'No profiles yet. Create a profile first.'; Wait-Back; return $null }
    for ($i=0;$i -lt $script:Pack.profiles.Count;$i++) { Write-TerminalOption "  [$($i+1)] $($script:Pack.profiles[$i].name)" }
    Write-TerminalOption '  [0] Back'
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
    Write-TerminalText ('Profile: ' + $Profile.name)
    # Preserve capture order without PowerShell 7-only Sort-Object -Stable.
    $rows=Get-ProfileRows $Profile
    foreach ($groupName in ($rows.Group | Select-Object -Unique)) {
        Write-TerminalText ''; Write-TerminalText $groupName -ForegroundColor Cyan
        foreach ($row in $rows | Where-Object { $_.Group -eq $groupName }) {
            if ($row.Name -eq 'Steam Launch Options') { Write-TerminalText $row.Value }
            else { Write-TerminalText ('  {0,-39} {1}' -f $row.Name,$row.Value) }
        }
    }
}
function Show-Changes($Before,$After) {
    $old=@{}; foreach ($row in (Get-ProfileRows $Before)) { $old[$row.Group+'/'+$row.Name]=$row.Value }
    $count=0
    foreach ($row in (Get-ProfileRows $After)) {
        $key=$row.Group+'/'+$row.Name
        if (-not $old.ContainsKey($key) -or $old[$key] -cne $row.Value) { Write-TerminalText ('  {0}: {1} -> {2}' -f $row.Name,$old[$key],$row.Value); $count++ }
    }
    foreach ($section in @('user','machine','keys','gameFiles','video')) {
        if ((ConvertTo-Json -InputObject $Before[$section] -Depth 10 -Compress) -cne (ConvertTo-Json -InputObject $After[$section] -Depth 10 -Compress)) {
            $label=@{user='Player preferences';machine='Audio, HUD and radar';keys='Controls';gameFiles='Custom configs';video='Display and video'}[$section]
            Write-TerminalText "  $label includes updated settings."
            $count++
        }
    }
    return $count
}
function Show-Issues($Issues) {
    foreach ($issue in $Issues) { Write-TerminalText ("  {0}: {1} - {2}" -f $issue.Kind,$issue.Setting,$issue.Reason) -ForegroundColor Yellow }
}
function Show-ClipboardResult([string]$Text) {
    if (Copy-LaunchOptions $Text) { Write-TerminalText 'Launch options copied to clipboard. Paste into Steam > CS2 > Properties > General > Launch Options.' }
    else { Write-TerminalText 'Could not copy launch options to clipboard. Use Copy launch options to retry or copy the line above manually.' -ForegroundColor Yellow }
}
function Show-ApplyResult($Profile, $Plan, $Result) {
    $failed=@($Result.Issues | Where-Object {$_.Kind -eq 'Skipped'})
    $title=if (-not $failed.Count) { 'Profile {0} successfully applied' }
        elseif ($Result.Saved.Count) { 'Profile {0} partially applied' }
        else { 'Profile {0} could not be applied' }
    Show-Header ($title -f $Profile.name)
    Show-Issues $Result.Issues
    if ($Result.Issues.Count) { Write-TerminalText '' }
    Write-TerminalText 'Launch options:'; Write-TerminalText ''
    $launch=Get-EffectiveLaunchOptions $Profile $Plan
    Write-TerminalText $(if ($launch) {$launch} else {'(empty - clear the Launch Options field in Steam)'})
    Write-TerminalText ''
    if (@($Result.Issues | Where-Object {$_.Setting -in @('Display','Refresh Rate')}).Count) { Write-TerminalText 'Check any display parameters in this line before pasting.' -ForegroundColor Yellow; Write-TerminalText '' }
    if ($launch) { Show-ClipboardResult $launch }
    $actions=@()
    if ($failed.Count) { $actions+=@('Retry','Console alternative') }
    if ($launch) { $actions+='Copy launch options' }
    $actions+='Exit'
    Write-TerminalText ''
    for ($i=0; $i -lt $actions.Count; $i++) { Write-TerminalOption ('  [{0}] {1}' -f ($i+1),$actions[$i]) }
    Write-TerminalOption '  [0] Back to main menu'
    while ($true) {
        $choice=Read-Choice (0..$actions.Count)
        if ($choice -eq 0) { return 'Back' }
        $action=$actions[$choice-1]
        if ($action -ne 'Copy launch options') { return $action }
        Show-ClipboardResult $launch
    }
}
function Show-Console($Profile) {
    Show-Header 'Console alternative'
    Write-TerminalText ('Profile: ' + $Profile.name)
    $path=Join-Path $script:Root ('console\'+(Get-ConsoleFilename $Profile))
    Write-TextFile $path (Get-ConsoleCommands $Profile)
    Write-TerminalText "`n1. Open $path"
    Write-TerminalText '2. Copy its commands into the CS2 console in small batches and run them.'
    Write-TerminalText '3. Check your settings in CS2.'
    Write-TerminalText "`nSupported settings: crosshair, mouse, audio and controls."
    Wait-Back
}
function Invoke-ApplyScreen {
    :ChooseProfile while ($true) {
    $profile=Select-Profile 'apply'; if ($null -eq $profile) { return }
    $context=Get-Context; if ($null -eq $context) { return }
    while ($true) {
        $plan=New-ApplyPlan $profile $context
        Show-Header 'Apply profile'; Show-ProfileSummary $profile
        Write-TerminalText ''; Show-Issues $plan.Video.Issues
        $label=if (@($plan.Video.Issues | Where-Object {$_.Kind -eq 'Skipped'}).Count) {'Apply available settings'} else {'Apply'}
        Write-TerminalOption "`n  [1] $label"; Write-TerminalOption '  [2] View all settings'; Write-TerminalOption '  [0] Back'
        $choice=Read-Choice @(0,1,2)
        if ($choice -eq 0) { continue ChooseProfile }
        if ($choice -eq 2) { Show-ProfileDetails $profile; continue }
        $result=Invoke-ApplyPlan $plan
        switch (Show-ApplyResult $profile $plan $result) {
            'Back' { return }; 'Exit' { $script:ExitRequested=$true; return }
            'Console alternative' { Show-Console $profile; return }
        }
    }
    }
}
function Read-ProfileName {
    while ($true) {
        $name=Read-TerminalLine 'Profile name (0 to go back)'
        Write-TerminalText ''
        if ($name -eq '0') { return '' }
        $name=$name.Trim()
        if (-not $name -or $name.Length -gt 100 -or $name -match '[\x00-\x1f]') { Write-TerminalText 'Enter a profile name (1-100 characters).'; Write-TerminalText ''; continue }
        if (@($script:Pack.profiles | Where-Object {$_.name -eq $name}).Count) { Write-TerminalText 'A profile with this name already exists.'; Write-TerminalText ''; continue }
        return $name
    }
}
function Export-WithRetry($Pack,$Destination,[switch]$Rename,$PreviousProfile=$null) {
    while ($true) {
        try { Export-Pack $Pack $Destination -Rename:$Rename -PreviousProfile $PreviousProfile; return $true }
        catch {
            # The JSON may have been saved before a derived CMD failed. Keep memory
            # consistent with that source of truth, including after returning to menu.
            if (Test-Path -LiteralPath (Join-Path $Destination 'profiles.json')) {
                try { $script:Pack=Read-Pack $Destination ''; $script:Root=$Destination } catch { }
            }
            Show-Header 'Config files could not all be updated'
            Write-TerminalText ('Folder: '+$Destination)
            Write-TerminalText ''
            Write-TerminalText 'Check folder permissions and close programs using these files, then retry.'
            Write-TerminalOption "`n  [1] Retry"; Write-TerminalOption '  [0] Back to main menu'
            if ((Read-Choice @(0,1)) -eq 0) { return $false }
        }
    }
}
function Invoke-RenameScreen([switch]$Profile) {
    :ChooseRename while ($true) {
    $selected=$null
    $kind='config'
    $currentName=$script:Pack.name
    if ($Profile) {
        $selected=Select-Profile 'rename'; if ($null -eq $selected) { return }
        $kind='profile'; $currentName=$selected.name
    }
    Show-Header ('Rename ' + $kind)
    Write-TerminalText ('Current name: ' + $currentName)
    Write-TerminalText ''; Write-TerminalOption '  [0] Back'
    while ($true) {
        Write-TerminalText ''
        $name=(Read-TerminalLine ('New ' + $kind + ' name')).Trim()
        Write-TerminalText ''
        if ($name -eq '0') { if ($Profile) { continue ChooseRename }; return }
        if (-not $name -or $name.Length -gt 100 -or $name -match '[\x00-\x1f\x7f]') {
            Write-TerminalText ('Enter a ' + $kind + ' name (1-100 characters).') -ForegroundColor Yellow
            continue
        }
        if ($Profile -and @($script:Pack.profiles | Where-Object {$_.id -ne $selected.id -and $_.name -eq $name}).Count) {
            Write-TerminalText 'A profile with this name already exists.' -ForegroundColor Yellow
            continue
        }
        $label=if ($Profile) {'Profile'} else {'Config'}
        if ($name -ceq $currentName) { Show-Header ($label + ' name is unchanged') }
        else {
            $next=Copy-Data $script:Pack
            if ($Profile) {
                foreach ($item in $next.profiles) { if ($item.id -eq $selected.id) { $item.name=$name } }
            } else { $next.name=$name }
            if (-not (Export-WithRetry $next $script:Root -Rename -PreviousProfile $selected)) { return }
            $script:Pack=$next
            Show-Header ($label + ' renamed to ' + $name)
        }
        Write-TerminalOption '  [0] Back to main menu'
        [void](Read-Choice @(0))
        return
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
            Show-Header 'Review profile changes'; Write-TerminalText ('Profile: '+$name); Write-TerminalText ''
            $changes=Show-Changes $existing $profile
            if (-not $changes) { Write-TerminalText 'Profile is already up to date.'; Wait-Back; return }
            Write-TerminalOption "`n  [1] Save changes"; Write-TerminalOption '  [2] View all settings'
        } else {
            Show-Header 'Review new profile'; Show-ProfileSummary $profile
            Write-TerminalText "`nSave to: $destination"
            Write-TerminalText ''
            Write-TerminalOption '  [1] Create profile'; Write-TerminalOption '  [2] Change destination'; Write-TerminalOption '  [3] View all settings'
        }
        Write-TerminalOption '  [0] Back'
        $allowed=if ($Update) {@(0,1,2)} else {@(0,1,2,3)}
        switch (Read-Choice $allowed) {
            0 { continue ChooseSource }
            2 {
                if ($Update) { Show-ProfileDetails $profile }
                else {
                    Show-Header 'Change destination'
                    Write-TerminalText ('Current folder: ' + $destination)
                    Write-TerminalText ''
                    $path=(Read-TerminalLine 'Folder (0 to go back)').Trim().Trim('"')
                    Write-TerminalText ''
                    if ($path -ne '0' -and $path) {
                        $candidate=[IO.Path]::GetFullPath($path)
                        if ($candidate -ne $script:Root -and (Test-Path -LiteralPath (Join-Path $candidate 'profiles.json'))) { Write-TerminalText 'That folder already contains a config. Open its cs2-config.exe to add a profile.'; Wait-Back }
                        else { $destination=$candidate }
                    }
                }
            }
            3 { Show-ProfileDetails $profile }
            1 {
                $next=Copy-Data $script:Pack
                if ($Update) {
                    for ($i=0;$i -lt $next.profiles.Count;$i++) { if ($next.profiles[$i].id -eq $profile.id) { $next.profiles[$i]=$profile } }
                } else { $next.profiles=@($next.profiles)+@($profile) }
                if (-not $script:Pack.profiles.Count -and -not (Test-Path -LiteralPath (Join-Path $destination 'profiles.json'))) { $next.name=Split-Path -Leaf $destination }
                if (-not (Export-WithRetry $next $destination)) { return }
                $script:Pack=$next; $script:Root=$destination
                Show-Header $(if ($Update) {'Profile updated'} else {'Profile created'})
                Write-TerminalText ('Profile: '+$name); Write-TerminalText ('Folder: '+$destination)
                Write-TerminalText ''
                Write-TerminalText 'Open cs2-config.exe and choose Apply profile.'
                Write-TerminalText ''
                Write-TerminalText 'Choose Update profile to update it.'
                Write-TerminalOption "`n  [1] Publishing instructions"; Write-TerminalOption '  [2] Exit'; Write-TerminalOption '  [0] Back to main menu'
                switch (Read-Choice @(0,1,2)) {
                    1 { Show-Header 'Update your config on GitHub'; Write-TerminalText '1. Open your config repository on GitHub.'; Write-TerminalText '2. Choose Add file > Upload files.'; Write-TerminalText '3. Upload the updated config folder contents.'; Write-TerminalText '4. Choose Commit changes.'; Wait-Back }
                    2 { $script:ExitRequested=$true }
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
                'rename' { Invoke-RenameScreen }
                'rename-profile' { Invoke-RenameScreen -Profile }
                default {
                    Show-Header '' -MainMenu
                    Write-TerminalOption '  [1] Apply profile'; Write-TerminalOption '  [2] Update profile'; Write-TerminalOption '  [3] Create profile'; Write-TerminalOption '  [4] Rename config'; Write-TerminalOption '  [5] Rename profile'; Write-TerminalOption '  [0] Exit'
                    switch (Read-Choice @(0,1,2,3,4,5)) {
                        0 { $script:ExitRequested=$true }
                        1 { $Mode='apply' }; 2 { $Mode='update' }; 3 { $Mode='create' }
                        4 { $Mode='rename' }
                        5 { $Mode='rename-profile' }
                    }
                    continue MenuLoop
                }
            }
        } catch { Show-Header 'Could not continue'; Write-TerminalText $_.Exception.Message -ForegroundColor Yellow; Wait-Back }
        $Mode='menu'
    }
}
