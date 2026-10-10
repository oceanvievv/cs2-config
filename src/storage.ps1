# Windows PowerShell 5.1. Profiles are data, never executable PowerShell.
$TOOL_VERSION = '2.0.1'
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
