function New-ExecutableBytes($Core,$Pack) {
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Pack -Depth 50 -Compress)))
    $entry=@'
param([ValidateSet('menu','create','update','apply')][string]$Mode='menu')
$ErrorActionPreference='Stop'
'@
    $tail=@'
$script:CoreSource=[regex]::Match([IO.File]::ReadAllText($PSCommandPath),'(?ms)^# BEGIN CORE\r?\n(.*?)^# END CORE\r?$').Groups[1].Value.Trim()
try { Start-ConfigTool $Mode $env:CS2_PACK_ROOT '__PAYLOAD__' }
catch { Stop-TerminalView; Write-Host ''; Write-Host $_.Exception.Message -ForegroundColor Yellow; Write-Host ''; if (-not [Console]::IsInputRedirected) { [void](Read-Host 'Press Enter to close') }; exit 1 }
finally { Stop-TerminalView; if ($env:CS2_ENGINE_TEMP -and $PSCommandPath -eq $env:CS2_ENGINE_TEMP) { Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue } }
'@
    $text=($entry+"`n# BEGIN CORE`n"+$Core.Trim()+"`n# END CORE`n"+$tail.Replace('__PAYLOAD__',$encoded)) -replace "`r?`n","`r`n"
    $bytes=[Text.Encoding]::UTF8.GetBytes($text)
    $compressed=New-Object IO.MemoryStream
    $gzip=New-Object IO.Compression.GZipStream($compressed,[IO.Compression.CompressionMode]::Compress,$true)
    $gzip.Write($bytes,0,$bytes.Length);$gzip.Dispose()
    $payload=$compressed.ToArray();$compressed.Dispose()
    $output=New-Object IO.MemoryStream
    $stub=[Convert]::FromBase64String($script:LauncherStub)
    $output.Write($stub,0,$stub.Length);$output.Write($payload,0,$payload.Length)
    $length=[BitConverter]::GetBytes([long]$payload.Length);$output.Write($length,0,8)
    $magic=[Text.Encoding]::ASCII.GetBytes('CS2PACK1');$output.Write($magic,0,8)
    $result=$output.ToArray();$output.Dispose();return ,$result
}
function Read-ExecutableSource($Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    if([Text.Encoding]::ASCII.GetString($bytes,$bytes.Length-8,8) -ne 'CS2PACK1') {throw 'Invalid executable package.'}
    $count=[BitConverter]::ToInt64($bytes,$bytes.Length-16)
    $inputStream=New-Object IO.MemoryStream(,$bytes)
    $inputStream.Position=$bytes.Length-16-$count
    $gzip=New-Object IO.Compression.GZipStream($inputStream,[IO.Compression.CompressionMode]::Decompress)
    $reader=New-Object IO.StreamReader($gzip,[Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally {$reader.Dispose();$inputStream.Dispose()}
}
function Write-ExecutableFile($Path,[byte[]]$Bytes) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllBytes($temp,$Bytes)
        if(Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
        if((Get-Item -LiteralPath $Path).Length -ne $Bytes.Length) {throw 'The executable could not be verified.'}
    } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
