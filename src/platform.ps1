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
        $steam = Read-TerminalLine 'Steam folder (0 to go back)'
        if ($steam -eq '0') { return $null }
        $steam = $steam.Trim().Trim('"')
    }
    $game = Find-Game $steam
    while (-not $game -or -not (Test-Path -LiteralPath (Join-Path $game 'game\csgo\cfg'))) {
        Show-Header 'CS2 installation not found'
        $game = Read-TerminalLine 'CS2 installation folder (0 to go back)'
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
        for ($i=0; $i -lt $accounts.Count; $i++) { Write-TerminalText "  [$($i+1)] $($accounts[$i].Name) (account $($accounts[$i].Id))" }
        Write-TerminalText '  [0] Back'
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
