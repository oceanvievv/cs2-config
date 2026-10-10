param([switch]$Probe, [string]$ResultPath)
$ErrorActionPreference='Stop'
if (-not $Probe) {
    $result=Join-Path $env:TEMP ('cs2-terminal-test-'+[guid]::NewGuid().ToString('N')+'.json')
    try {
        $child=Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Probe -ResultPath "'+$result+'"')
        if (-not $child.WaitForExit(30000)) { $child.Kill(); throw 'Terminal test timed out.' }
        if (-not (Test-Path -LiteralPath $result)) { throw 'Terminal test returned no result.' }
        $report=Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
        if (-not $report.success) { throw $report.error }
        Write-Output 'PASS: pinned menu options and prompt, native scrolling, section return, Unicode editing, resize and console restoration.'
    } finally { if (Test-Path -LiteralPath $result) { Remove-Item -LiteralPath $result -Force } }
    exit
}
try {
    . (Join-Path $PSScriptRoot '..\src\terminal.ps1')
    Initialize-TerminalViewApi
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class TerminalProbe {
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h,out uint mode);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool ReadConsoleOutputCharacterW(IntPtr h,[Out] char[] text,uint n,uint coord,out uint read);
    [StructLayout(LayoutKind.Explicit,Size=20,CharSet=CharSet.Unicode)] public struct Input {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(4)] public int Down;
        [FieldOffset(8)] public uint RepeatOrButtons;
        [FieldOffset(10)] public ushort Key;
        [FieldOffset(14)] public char Character;
        [FieldOffset(16)] public uint Flags;
    }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool WriteConsoleInputW(IntPtr h,Input[] records,uint n,out uint written);
    public static uint Mode() { uint mode; GetConsoleMode(GetStdHandle(-10),out mode); return mode; }
    public static string Row(int row) { var text=new char[Console.WindowWidth]; uint read; ReadConsoleOutputCharacterW(GetStdHandle(-11),text,(uint)Console.WindowWidth,(uint)(row<<16),out read); return new String(text,0,(int)read).TrimEnd(); }
    public static void QueueInput() {
        var records=new [] {
            new Input { Type=2,RepeatOrButtons=unchecked((uint)(-120<<16)),Flags=4 },
            new Input { Type=1,Down=1,RepeatOrButtons=1,Character='\u0416' },
            new Input { Type=1,Down=1,RepeatOrButtons=1,Character='x' },
            new Input { Type=1,Down=1,RepeatOrButtons=1,Key=8 },
            new Input { Type=1,Down=1,RepeatOrButtons=1,Character='1' },
            new Input { Type=1,Down=1,RepeatOrButtons=1,Key=13 }
        };
        uint written; WriteConsoleInputW(GetStdHandle(-10),records,(uint)records.Length,out written);
    }
    public static void QueueTab() {
        var records=new [] {
            new Input { Type=1,Down=1,RepeatOrButtons=1,Key=9 },
            new Input { Type=1,Down=1,RepeatOrButtons=1,Key=13 }
        };
        uint written; WriteConsoleInputW(GetStdHandle(-10),records,(uint)records.Length,out written);
    }
}
'@
    function Assert($Value,$Message) { if (-not $Value) { throw $Message } }
    $mode=[TerminalProbe]::Mode(); $buffer=[Console]::BufferHeight
    Assert ([CS2TerminalView]::Start()) 'Native terminal did not start.'
    [CS2TerminalView]::Begin('Settings')
    for ($i=0;$i -lt 100;$i++) { [CS2TerminalView]::Add("Setting $i",-1) }
    [CS2TerminalView]::AddOption('  [1] Apply')
    [CS2TerminalView]::AddOption('  [0] Back')
    [CS2TerminalView]::Render('Enter an option','',0)
    $bottom=[Console]::WindowHeight-1
    Assert ([TerminalProbe]::Row($bottom) -eq 'Enter an option:') ('Prompt is not on the bottom row: ['+[TerminalProbe]::Row($bottom)+'] at '+$bottom+' cursor '+[Console]::CursorTop)
    Assert ([Console]::CursorTop -eq $bottom) 'Input cursor is not anchored.'
    Assert ([TerminalProbe]::Row($bottom-3) -eq '  [1] Apply') 'Apply option is not visible above input.'
    Assert ([TerminalProbe]::Row($bottom-2) -eq '  [0] Back') 'Back option is not visible above input.'
    [CS2TerminalView]::Scroll(10); [CS2TerminalView]::Render('Enter an option','',0)
    Assert ([TerminalProbe]::Row(0) -like 'Setting 10 *') 'Content did not scroll independently.'
    Assert ([TerminalProbe]::Row($bottom) -eq 'Enter an option:') 'Scrolling displaced prompt.'
    Assert ([TerminalProbe]::Row($bottom-3) -eq '  [1] Apply') 'Scrolling displaced Apply option.'
    Assert ([TerminalProbe]::Row($bottom-2) -eq '  [0] Back') 'Scrolling displaced Back option.'
    [CS2TerminalView]::Begin('Menu'); [CS2TerminalView]::AddOption('[0] Exit')
    [CS2TerminalView]::Render('Enter an option','',0)
    Assert ([TerminalProbe]::Row(1) -eq '') 'Old content was not cleared.'
    Assert ([TerminalProbe]::Row($bottom-3) -eq '') 'Previous menu options were not cleared.'
    Assert ([TerminalProbe]::Row($bottom-2) -eq '[0] Exit') 'New menu option is not visible.'
    [CS2TerminalView]::Begin('Settings')
    for ($i=0;$i -lt 100;$i++) { [CS2TerminalView]::Add("Setting $i",-1) }
    [CS2TerminalView]::AddOption('  [1] Apply')
    [CS2TerminalView]::AddOption('  [0] Back')
    [CS2TerminalView]::Render('Enter an option','',0)
    Assert ([TerminalProbe]::Row(0) -like 'Setting 10 *') 'Returning to section lost scroll position.'
    [TerminalProbe]::QueueInput()
    $value=[CS2TerminalView]::ReadLine('Enter an option')
    Assert ($value -eq ([string][char]0x416+'1')) 'Unicode input or backspace failed.'
    Assert ([CS2TerminalView]::ScrollOffset -eq 13) 'Mouse wheel did not scroll content.'
    [CS2TerminalView]::Add('Invalid option',14)
    [CS2TerminalView]::Render('Enter an option','',0)
    Assert ([TerminalProbe]::Row([Console]::WindowHeight-6) -like 'Invalid option *') 'Input feedback is not visible.'
    Assert ([TerminalProbe]::Row($bottom-3) -eq '  [1] Apply') 'Feedback displaced menu options.'
    [Console]::SetWindowSize([Console]::WindowWidth,[Console]::WindowHeight-2)
    [CS2TerminalView]::Render('Enter an option','',0)
    Assert ([TerminalProbe]::Row([Console]::WindowHeight-1) -eq 'Enter an option:') 'Resize displaced prompt.'
    Assert ([TerminalProbe]::Row([Console]::WindowHeight-4) -eq '  [1] Apply') 'Resize displaced Apply option.'
    Assert ([TerminalProbe]::Row([Console]::WindowHeight-3) -eq '  [0] Back') 'Resize displaced Back option.'
    [CS2TerminalView]::Begin('Many profiles')
    for ($i=1;$i -le [Console]::WindowHeight;$i++) { [CS2TerminalView]::AddOption("  [$i] Profile $i") }
    [CS2TerminalView]::AddOption('  [0] Back')
    [CS2TerminalView]::Render('Enter an option','',0)
    Assert ([TerminalProbe]::Row([Console]::WindowHeight-3) -like 'More options: *1/2') 'Overflow options have no page indicator.'
    [TerminalProbe]::QueueTab()
    [void][CS2TerminalView]::ReadLine('Enter an option')
    Assert ([TerminalProbe]::Row([Console]::WindowHeight-3) -like 'More options: *2/2') 'Tab does not reveal remaining options.'
    Assert ([TerminalProbe]::Row([Console]::WindowHeight-4) -eq '  [0] Back') 'Last option was lost during pagination.'
    [CS2TerminalView]::Stop()
    Assert ([TerminalProbe]::Mode() -eq $mode) 'Console input mode was not restored.'
    Assert ([Console]::BufferHeight -eq $buffer) 'Console scrollback size was not restored.'
    @{success=$true} | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
} catch {
    @{success=$false;error=$_.Exception.ToString()} | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
} finally { if ('CS2TerminalView' -as [type]) { [CS2TerminalView]::Stop() } }
