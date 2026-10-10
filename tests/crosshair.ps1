$ErrorActionPreference = 'Stop'

# Load only the pure capture function, never run setup against the user's Steam files.
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\src\capture.ps1'))
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput(
    $source,
    [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$function = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-CurrentCrosshair'
}, $true)
. ([scriptblock]::Create($function.Extent.Text))

function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Assert-Throws($action, $message) {
    $caught = $false
    try { & $action | Out-Null } catch { $caught = $true }
    Assert $caught $message
}

# Modern saves still contain legacy hidden values. They must not replace pixel sizes
# or enter the generated CFG alongside the current settings.
$saved = [ordered]@{
    cl_crosshair_screen_height = '1080'
    cl_crosshair_length = '4'
    cl_crosshair_thickness = '1'
    cl_crosshair_gap = '2'
    cl_crosshaircolor_a = '255'
    cl_crosshaircolor_r = '50'
    cl_crosshaircolor_g = '250'
    cl_crosshaircolor_b = '250'
    cl_crosshair_drawoutline = '2'
    cl_crosshairoutline_a = '255'
    cl_crosshairstyle = '4'
    cl_crosshairsize = '1.875223'
    cl_crosshairthickness = '0.1'
    cl_crosshairalpha = '200'
    cl_crosshaircolor = '4'
    cl_crosshairgap = '-2.598061'
    cl_crosshair_outlinethickness = '0.192549'
    cl_fixedcrosshairgap = '3'
    sensitivity = '2.2'
}
$actual = Get-CurrentCrosshair $saved
foreach ($key in @('cl_crosshair_length', 'cl_crosshair_thickness', 'cl_crosshair_gap',
                   'cl_crosshaircolor_a', 'cl_crosshaircolor_r', 'cl_crosshaircolor_g',
                   'cl_crosshaircolor_b', 'cl_crosshair_drawoutline',
                   'cl_crosshairoutline_a', 'cl_crosshairstyle')) {
    Assert ($actual[$key] -eq $saved[$key]) "Current setting changed: $key"
}
foreach ($key in @('cl_crosshairsize', 'cl_crosshairthickness', 'cl_crosshairalpha',
                   'cl_crosshaircolor', 'cl_crosshairgap', 'cl_crosshair_outlinethickness',
                   'cl_fixedcrosshairgap', 'sensitivity')) {
    Assert (-not $actual.Contains($key)) "Stale/unrelated setting exported: $key"
}
Assert (@($actual.Keys)[-1] -eq 'cl_crosshair_screen_height') 'Reference height must be emitted last.'
Assert ($saved.Contains('cl_crosshairsize')) 'Capture mutated its source.'
$again = Get-CurrentCrosshair $actual
Assert (($again | ConvertTo-Json -Compress) -eq ($actual | ConvertTo-Json -Compress)) 'Current capture is not idempotent.'
Assert ((Get-CurrentCrosshair ([ordered]@{})).Count -eq 0) 'Empty capture is not empty.'
Assert-Throws { Get-CurrentCrosshair ([ordered]@{ cl_crosshairsize = '1.875223' }) } 'Legacy sizes silently accepted.'
$actual.Remove('cl_crosshair_screen_height')
Assert-Throws { Get-CurrentCrosshair $actual } 'Missing reference height silently accepted.'

Write-Output 'Crosshair capture checks passed.'
