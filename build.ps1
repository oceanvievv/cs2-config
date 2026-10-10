param([string]$OutFile = (Join-Path $PSScriptRoot 'setup.cmd'))
$ErrorActionPreference='Stop'
$names=@('storage','capture','platform','apply','export','ui')
$parts=@($names | ForEach-Object { [IO.File]::ReadAllText((Join-Path $PSScriptRoot "src\$_.ps1")) })
$script:CoreSource=$parts -join "`r`n"
foreach ($part in $parts) { . ([scriptblock]::Create($part)) }
$pack=[ordered]@{schemaVersion=1; name='cs2-config'; profiles=@()}
Write-TextFile ([IO.Path]::GetFullPath($OutFile)) (New-LauncherText $script:CoreSource $pack 'create')
Write-Output "Built $OutFile"
