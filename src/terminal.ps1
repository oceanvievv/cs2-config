# Spectre.Console renders all interactive screens. Redirected execution stays plain text.
function Start-TerminalView($Console=$null) {
    $script:TerminalViewActive=$false
    if ($null -eq $Console -and ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected)) { return }
    Initialize-SpectreAssemblies
    $script:SpectreConsole=if ($null -ne $Console) {$Console} else {[Spectre.Console.AnsiConsole]::Console}
    $script:TerminalViewActive=$true
    $script:TerminalLines=New-Object 'Collections.Generic.List[object]'
    $script:TerminalOptions=New-Object 'Collections.Generic.List[string]'
    $script:TerminalPages=@{}
    $script:TerminalScreen=''
    $script:TerminalFeedback=$false
}
function Stop-TerminalView { $script:TerminalViewActive=$false }
function Start-TerminalScreen([string]$Title) {
    $script:TerminalScreen=$Title
    $script:TerminalLines.Clear(); $script:TerminalOptions.Clear()
    $script:TerminalFeedback=$false
    $script:TerminalBodyCount=0
    $script:TerminalShowFeedback=$false
}
function Write-TerminalText($Object='', $ForegroundColor) {
    if ($script:TerminalViewActive) {
        if ($script:TerminalFeedback -and -not [string]::IsNullOrWhiteSpace([string]$Object)) {
            while($script:TerminalLines.Count -gt $script:TerminalBodyCount) { $script:TerminalLines.RemoveAt($script:TerminalLines.Count-1) }
            $script:TerminalLines.Add([pscustomobject]@{Text='';Style=''})
            $script:TerminalFeedback=$false
            $script:TerminalShowFeedback=$true
        }
        $style=if ($null -eq $ForegroundColor) {''} else {
            switch ([string]$ForegroundColor) { 'Cyan' {'cyan'}; 'Yellow' {'yellow'}; 'Green' {'green'}; 'White' {'bold'}; default {''} }
        }
        foreach($line in ([string]$Object -replace "`r",'' -split "`n")) {
            $script:TerminalLines.Add([pscustomobject]@{Text=$line;Style=$style})
        }
    } elseif ($null -eq $ForegroundColor) { Write-Host $Object }
    else { Write-Host $Object -ForegroundColor $ForegroundColor }
}
function Write-TerminalOption([string]$Text) {
    if ($script:TerminalViewActive) { $script:TerminalOptions.Add($Text.Trim()) }
    else { Write-Host $Text }
}
function Get-TerminalPageRows {
    $width=[Math]::Max(20,$script:SpectreConsole.Profile.Width-2)
    $rows=New-Object 'Collections.Generic.List[object]'
    foreach($line in $script:TerminalLines) {
        if (-not $line.Text) { $rows.Add($line); continue }
        $rest=$line.Text.Replace("`t",'    ')
        while($rest.Length -gt $width) {
            $cut=$rest.LastIndexOf(' ',$width)
            if($cut -lt [int]($width/2)) { $cut=$width }
            $rows.Add([pscustomobject]@{Text=$rest.Substring(0,$cut);Style=$line.Style})
            $rest=$rest.Substring($cut).TrimStart()
        }
        $rows.Add([pscustomobject]@{Text=$rest;Style=$line.Style})
    }
    return ,$rows
}
function Show-TerminalPage($Rows,[int]$Page,[int]$PageSize) {
    $script:SpectreConsole.Clear($true)
    $start=$Page*$PageSize
    for($i=$start;$i -lt [Math]::Min($Rows.Count,$start+$PageSize);$i++) {
        $text=[Spectre.Console.Markup]::Escape($Rows[$i].Text)
        if($Rows[$i].Style) { $text='['+$Rows[$i].Style+']'+$text+'[/]' }
        [Spectre.Console.AnsiConsoleExtensions]::MarkupLine($script:SpectreConsole,$text)
    }
    [Spectre.Console.AnsiConsoleExtensions]::WriteLine($script:SpectreConsole)
}
function New-TerminalSelection([string[]]$Choices) {
    $prompt=[Spectre.Console.SelectionPrompt[string]]::new($null)
    $prompt.PageSize=[Math]::Max(3,[Math]::Min(10,$script:SpectreConsole.Profile.Height-6))
    $prompt.HighlightStyle=[Spectre.Console.Style]::Parse('cyan')
    $prompt.MoreChoicesText='[grey]Use arrow keys to see more options[/]'
    $prompt.SearchEnabled=$true
    $prompt.SearchPlaceholderText='Type to filter'
    $prompt.WrapAround=$false
    foreach ($choice in $Choices) { [void]$prompt.AddChoice($choice) }
    return $prompt
}
function Read-TerminalChoice([int[]]$Allowed) {
    $rows=Get-TerminalPageRows
    $pageSize=[Math]::Max(4,$script:SpectreConsole.Profile.Height-[Math]::Min(10,$script:TerminalOptions.Count+2)-6)
    $pages=[Math]::Max(1,[int][Math]::Ceiling($rows.Count/[double]$pageSize))
    $page=0
    if($script:TerminalPages.ContainsKey($script:TerminalScreen)) { $page=[Math]::Min($pages-1,$script:TerminalPages[$script:TerminalScreen]) }
    if($script:TerminalShowFeedback) { $page=$pages-1 }
    while($true) {
        Show-TerminalPage $rows $page $pageSize
        $choices=New-Object 'Collections.Generic.List[string]'
        $values=New-Object 'Collections.Generic.List[object]'
        $back=$null
        foreach($option in $script:TerminalOptions) {
            if($option -match '^\[(\d+)\]\s*(.*)$') {
                $id=[int]$matches[1]; $label=$matches[2]
                if($id -notin $Allowed) { continue }
                if($id -eq 0) { $back=$label; continue }
                $choices.Add([Spectre.Console.Markup]::Escape(('['+($choices.Count+1)+'] '+$label))); $values.Add($id)
            }
        }
        if($page -lt $pages-1) { $choices.Add('[['+($choices.Count+1)+']] Next page'); $values.Add('next') }
        if($page -gt 0) { $choices.Add('[['+($choices.Count+1)+']] Previous page'); $values.Add('previous') }
        if($null -ne $back) { $choices.Add([Spectre.Console.Markup]::Escape('[0] '+$back)); $values.Add(0) }
        if($pages -gt 1) { [Spectre.Console.AnsiConsoleExtensions]::MarkupLine($script:SpectreConsole,('[grey]Page '+($page+1)+' of '+$pages+'[/]')) }
        [Spectre.Console.AnsiConsoleExtensions]::MarkupLine($script:SpectreConsole,'[grey]Up/Down: select  Enter: confirm[/]')
        $prompt=New-TerminalSelection $choices.ToArray()
        $selected=$prompt.Show($script:SpectreConsole)
        $value=$values[$choices.IndexOf($selected)]
        if($value -eq 'next') { $page++; continue }
        if($value -eq 'previous') { $page--; continue }
        $script:TerminalPages[$script:TerminalScreen]=$page
        $script:TerminalFeedback=$true
        if(-not $script:TerminalBodyCount) { $script:TerminalBodyCount=$script:TerminalLines.Count }
        return [int]$value
    }
}
function Read-TerminalLine([string]$Prompt) {
    if ($script:TerminalViewActive) {
        $rows=Get-TerminalPageRows
        $size=[Math]::Max(4,$script:SpectreConsole.Profile.Height-5)
        $page=[Math]::Max(0,[int][Math]::Ceiling($rows.Count/[double]$size)-1)
        Show-TerminalPage $rows $page $size
        foreach($option in $script:TerminalOptions) { [Spectre.Console.AnsiConsoleExtensions]::MarkupLine($script:SpectreConsole,[Spectre.Console.Markup]::Escape($option)) }
        $field=[Spectre.Console.TextPrompt[string]]::new(([Spectre.Console.Markup]::Escape($Prompt)+':'),$null)
        $field.AllowEmpty=$true
        $field.PromptStyle=[Spectre.Console.Style]::Parse('cyan')
        $value=$field.Show($script:SpectreConsole)
        if(-not $script:TerminalBodyCount) { $script:TerminalBodyCount=$script:TerminalLines.Count }
        $script:TerminalFeedback=$true
        return $value
    }
    return Read-Host $Prompt
}
