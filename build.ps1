param([string]$OutFile = (Join-Path $PSScriptRoot 'cs2-config.exe'))
$ErrorActionPreference='Stop'
$launcherSource=Join-Path $PSScriptRoot 'src\launcher.cs'
$launcherAsset=Join-Path $PSScriptRoot 'src\launcher-assets.ps1'
$sourceHash=(Get-FileHash $launcherSource -Algorithm SHA256).Hash
if (-not (Test-Path -LiteralPath $launcherAsset) -or -not ([IO.File]::ReadAllText($launcherAsset).Contains('# Source SHA256: '+$sourceHash))) {
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $stub=Join-Path $env:TEMP ('cs2-launcher-'+[guid]::NewGuid().ToString('N')+'.exe')
    try {
        & $compiler /nologo /target:exe /platform:anycpu /optimize+ "/out:$stub" $launcherSource
        if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
        $encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes($stub))
        [IO.File]::WriteAllText($launcherAsset,('# Source SHA256: '+$sourceHash+"`r`n"+'$script:LauncherStub='''+$encoded+''''+"`r`n"))
    } finally {if(Test-Path -LiteralPath $stub){Remove-Item -LiteralPath $stub -Force}}
}
$names=@('storage','capture','platform','apply','launcher-assets','executable','export','spectre-assets','terminal','ui')
$parts=@($names | ForEach-Object { [IO.File]::ReadAllText((Join-Path $PSScriptRoot "src\$_.ps1")) })
$script:CoreSource=$parts -join "`r`n"
foreach ($part in $parts) { . ([scriptblock]::Create($part)) }
$pack=[ordered]@{schemaVersion=1; name='cs2-config'; profiles=@()}
Write-ExecutableFile ([IO.Path]::GetFullPath($OutFile)) (New-ExecutableBytes $script:CoreSource $pack)
Write-Output "Built $OutFile"
