param([switch]$Native,[string]$ResultPath)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($name in @('storage','capture','platform','apply','launcher-assets','executable','export','spectre-assets','terminal','ui')) { . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $repo "src/$name.ps1")))) }
function Assert($Value,$Message) { if(-not $Value){throw $Message} }
if($Native) {
 try {
  Initialize-SpectreAssemblies
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeKeys {
 [StructLayout(LayoutKind.Explicit,Size=20,CharSet=CharSet.Unicode)] public struct Input {
  [FieldOffset(0)] public ushort Type;
  [FieldOffset(4)] public int Down;
  [FieldOffset(8)] public ushort Repeat;
  [FieldOffset(10)] public ushort Key;
 }
 [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool WriteConsoleInputW(IntPtr h,Input[] records,uint n,out uint count);
 public static void Back() { var keys=new[]{new Input{Type=1,Down=1,Repeat=1,Key=40},new Input{Type=1,Down=1,Repeat=1,Key=13}}; uint count;WriteConsoleInputW(GetStdHandle(-10),keys,2,out count); }
}
'@
  Start-TerminalView
  Assert $script:TerminalViewActive 'Spectre did not activate in a native console.'
  Start-TerminalScreen 'Menu'; Write-TerminalText 'CS2 CONFIG'; Write-TerminalOption '[1] Apply'; Write-TerminalOption '[0] Back'
  [NativeKeys]::Back()
  Assert ((Read-TerminalChoice @(0,1)) -eq 0) 'Native arrow/Enter selection failed.'
  [IO.File]::WriteAllText($ResultPath,'PASS')
 } catch { [IO.File]::WriteAllText($ResultPath,$_.Exception.ToString()) }
 exit
}
Initialize-SpectreAssemblies
[void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'lib/Spectre.Console.Testing.dll')))
function New-TestConsole {
 $c=[Spectre.Console.Testing.TestConsole]::new()
 [void][Spectre.Console.Testing.TestConsoleExtensions]::Interactive($c)
 [void][Spectre.Console.Testing.TestConsoleExtensions]::Width($c,100)
 [void][Spectre.Console.Testing.TestConsoleExtensions]::Height($c,30)
 return $c
}
$c=New-TestConsole; Start-TerminalView $c
Start-TerminalScreen 'Main menu'; Write-TerminalText 'CS2 CONFIG' -ForegroundColor Cyan
Write-TerminalOption '[1] Apply profile';Write-TerminalOption '[0] Exit'
$c.Input.PushKey([ConsoleKey]::DownArrow);$c.Input.PushKey([ConsoleKey]::Enter)
Assert ((Read-TerminalChoice @(0,1)) -eq 0) 'Selection did not follow arrow keys.'
Assert ($c.Output -match 'CS2 CONFIG' -and $c.Output -match 'Apply profile') 'Menu text missing.'
Start-TerminalScreen 'Rename'
Write-TerminalText 'Current name: [red]literal[/]' -ForegroundColor Cyan
$name=([string][char]0x416)+' [green] & friends'
foreach($ch in $name.ToCharArray()) {$c.Input.PushKey([ConsoleKeyInfo]::new($ch,[ConsoleKey]::A,$false,$false,$false))}
$c.Input.PushKey([ConsoleKey]::Enter)
Assert ((Read-TerminalLine 'New profile name') -ceq $name) 'Input changed Unicode, spaces or brackets.'
Assert ($c.Output -match '\[red\]literal\[/\]') 'Profile data was interpreted as markup.'
Start-TerminalScreen 'Settings'
for($i=0;$i -lt 70;$i++){Write-TerminalText ('Setting '+$i)}
Write-TerminalOption '[1] Apply';Write-TerminalOption '[0] Back'
$c.Input.PushKey([ConsoleKey]::DownArrow);$c.Input.PushKey([ConsoleKey]::Enter)
$c.Input.PushKey([ConsoleKey]::End);$c.Input.PushKey([ConsoleKey]::Enter)
Assert ((Read-TerminalChoice @(0,1)) -eq 0) 'Page navigation invoked the wrong action.'
Assert ($script:TerminalPages['Settings'] -eq 1) 'Page position was not retained.'
Start-TerminalScreen 'Result';Write-TerminalText 'Profile Test successfully applied'
Write-TerminalText ('-novid '*80)
Write-TerminalOption '[1] Copy launch options';Write-TerminalOption '[0] Back'
$c.Input.PushKey([ConsoleKey]::Enter)
Assert ((Read-TerminalChoice @(0,1)) -eq 1) 'Long launch options hid the action.'
Start-TerminalScreen 'Many profiles'
for($i=1;$i -le 40;$i++){Write-TerminalOption "[$i] Profile $i"}
Write-TerminalOption '[0] Back'
$c.Input.PushText('Profile 37');$c.Input.PushKey([ConsoleKey]::Enter)
Assert ((Read-TerminalChoice (0..40)) -eq 37) 'Profile search selected a different profile.'
Stop-TerminalView
$result=Join-Path $env:TEMP ('cs2-spectre-native-'+[guid]::NewGuid().ToString('N')+'.txt')
try {
 $child=Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Native -ResultPath "'+$result+'"')
 if(-not $child.WaitForExit(20000)){$child.Kill();throw 'Native Spectre test timed out.'}
 Assert ((Test-Path -LiteralPath $result) -and [IO.File]::ReadAllText($result) -eq 'PASS') ('Native Spectre test failed: '+$(if(Test-Path -LiteralPath $result){[IO.File]::ReadAllText($result)}))
} finally {if(Test-Path -LiteralPath $result){Remove-Item -LiteralPath $result -Force}}
Write-Output 'Spectre checks passed: real console arrows/Enter, menus, Unicode input, literal markup, long settings, retained page and profile search.'
