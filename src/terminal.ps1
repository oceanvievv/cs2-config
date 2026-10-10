function Initialize-TerminalViewApi {
    if ('CS2TerminalView' -as [type]) { return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CS2TerminalView {
    [StructLayout(LayoutKind.Sequential)] public struct Coord {
        public short X, Y;
        public Coord(int x, int y) { X=(short)x; Y=(short)y; }
    }
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public short Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Explicit, CharSet=CharSet.Unicode)] public struct Cell {
        [FieldOffset(0)] public char Character;
        [FieldOffset(2)] public ushort Attributes;
    }
    [StructLayout(LayoutKind.Explicit, Size=20, CharSet=CharSet.Unicode)] public struct Input {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(4)] public int KeyDown;
        [FieldOffset(8)] public ushort Repeat;
        [FieldOffset(10)] public ushort Key;
        [FieldOffset(14)] public char Character;
        [FieldOffset(16)] public uint Control;
        [FieldOffset(4)] public Coord Mouse;
        [FieldOffset(8)] public uint Buttons;
        [FieldOffset(16)] public uint MouseFlags;
    }
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int handle);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr handle, out uint mode);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr handle, uint mode);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool WriteConsoleOutputW(IntPtr handle, Cell[] cells, Coord size, Coord origin, ref Rect region);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool ReadConsoleInputW(IntPtr handle, [Out] Input[] records, uint count, out uint read);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);

    class Line {
        public string Text;
        public ushort Color;
        public Line(string text, ushort color) { Text=text; Color=color; }
    }
    static readonly List<Line> lines=new List<Line>();
    static readonly List<Line> options=new List<Line>();
    static readonly Dictionary<string,int> positions=new Dictionary<string,int>();
    static IntPtr input, output;
    static uint originalMode;
    static int originalWidth, originalHeight, offset, maximum, pageHeight;
    static string screen="";
    static ushort normalColor;
    static bool feedback;
    static int optionPage, optionPages=1;
    public static bool Active { get; private set; }
    public static bool Cancelled { get; private set; }
    public static int ScrollOffset { get { return offset; } }
    public static int PromptRow { get; private set; }

    public static bool Start() {
        if (Active) return true;
        input=GetStdHandle(-10); output=GetStdHandle(-11);
        if (!GetConsoleMode(input,out originalMode) || Console.WindowWidth<4 || Console.WindowHeight<5) return false;
        originalWidth=Console.BufferWidth; originalHeight=Console.BufferHeight;
        normalColor=(ushort)((int)Console.ForegroundColor | ((int)Console.BackgroundColor<<4));
        // Mouse events replace native scrollback; typed characters are rendered only in the footer.
        if (!SetConsoleMode(input,(originalMode | 0x0098u) & ~0x0047u)) return false;
        Active=true;
        Cancelled=false; feedback=false;
        lines.Clear(); options.Clear(); positions.Clear(); screen=""; offset=0; optionPage=0;
        try { FitBuffer(); return true; } catch { Stop(); return false; }
    }
    public static bool HasVisibleConsole() { return IsWindowVisible(GetConsoleWindow()); }
    static void FitBuffer() {
        int width=Console.WindowWidth, height=Console.WindowHeight;
        if (Console.WindowLeft!=0 || Console.WindowTop!=0) Console.SetWindowPosition(0,0);
        if (Console.BufferWidth!=width || Console.BufferHeight!=height) Console.SetBufferSize(width,height);
    }
    public static void Stop() {
        if (!Active) return;
        SetConsoleMode(input,originalMode);
        try { Console.SetBufferSize(Math.Max(originalWidth,Console.WindowWidth),Math.Max(originalHeight,Console.WindowHeight)); } catch { }
        Active=false;
    }
    public static void Begin(string key) {
        if (!feedback) positions[screen]=offset;
        screen=key ?? "";
        if (!positions.TryGetValue(screen,out offset)) offset=0;
        lines.Clear();
        options.Clear(); optionPage=0;
        feedback=false;
    }
    public static void Add(string text, int color) {
        ushort attributes=color<0 ? normalColor : (ushort)((normalColor & 0xF0) | color);
        foreach (string line in (text ?? "").Replace("\r","").Replace("\t","    ").Split('\n')) lines.Add(new Line(line,attributes));
        if (feedback && !String.IsNullOrWhiteSpace(text)) offset=Int32.MaxValue;
    }
    public static void AddOption(string text) { options.Add(new Line((text ?? "").Trim('\r','\n'),normalColor)); }
    static List<Line> Wrap(List<Line> source,int width) {
        var result=new List<Line>();
        foreach (Line line in source) {
            if (line.Text.Length==0) result.Add(line);
            else for (int start=0;start<line.Text.Length;start+=width)
                result.Add(new Line(line.Text.Substring(start,Math.Min(width,line.Text.Length-start)),line.Color));
        }
        return result;
    }
    static void Put(Cell[] cells,int width,int row,string text,ushort color) {
        for (int x=0;x<Math.Min(width,text.Length);x++) {
            cells[row*width+x].Character=text[x]; cells[row*width+x].Attributes=color;
        }
    }
    public static void Render(string prompt,string value,int caret) {
        FitBuffer();
        int width=Console.WindowWidth, height=Console.WindowHeight;
        if (width<4 || height<5) return;
        var actions=Wrap(options,width-1);
        int actionCapacity=Math.Max(1,height-6);
        optionPages=Math.Max(1,(actions.Count+actionCapacity-1)/actionCapacity);
        optionPage=Math.Min(optionPage,optionPages-1);
        int actionStart=optionPage*actionCapacity;
        int actionCount=Math.Min(actionCapacity,actions.Count-actionStart);
        int actionRows=actionCount+(optionPages>1 ? 1 : 0);
        pageHeight=height-3-actionRows; PromptRow=height-1;
        var body=Wrap(lines,width-1);
        maximum=Math.Max(0,body.Count-pageHeight);
        offset=Math.Max(0,Math.Min(offset,maximum));
        var cells=new Cell[width*height];
        for (int i=0;i<cells.Length;i++) { cells[i].Character=' '; cells[i].Attributes=normalColor; }
        for (int y=0;y<pageHeight && offset+y<body.Count;y++) Put(cells,width,y,body[offset+y].Text,body[offset+y].Color);
        if (maximum>0) {
            string hint=String.Format("Scroll: wheel / PgUp / PgDn   {0}-{1} of {2}",offset+1,Math.Min(body.Count,offset+pageHeight),body.Count);
            Put(cells,width,pageHeight,hint,(ushort)((normalColor & 0xF0) | 8));
            int thumb=(int)((long)offset*(pageHeight-1)/maximum);
            for (int y=0;y<pageHeight;y++) {
                cells[y*width+width-1].Character=y==thumb ? '\u2588' : '\u2502';
                cells[y*width+width-1].Attributes=(ushort)((normalColor & 0xF0) | 8);
            }
        }
        for (int y=0;y<actionCount;y++) Put(cells,width,pageHeight+1+y,actions[actionStart+y].Text,actions[actionStart+y].Color);
        if (optionPages>1) Put(cells,width,height-3,String.Format("More options: Tab / Shift+Tab   {0}/{1}",optionPage+1,optionPages),normalColor);
        string prefix=(prompt ?? "")+": ";
        if (prefix.Length>width/2) prefix=prefix.Substring(0,width/2);
        int room=Math.Max(1,width-prefix.Length-1);
        int start=Math.Max(0,caret-room+1);
        string shown=value.Substring(start,Math.Min(room,value.Length-start));
        Put(cells,width,PromptRow,prefix+shown,normalColor);
        var region=new Rect { Left=0,Top=0,Right=(short)(width-1),Bottom=(short)(height-1) };
        if (!WriteConsoleOutputW(output,cells,new Coord(width,height),new Coord(0,0),ref region)) throw new InvalidOperationException("The terminal could not be redrawn.");
        Console.SetCursorPosition(Math.Min(width-1,prefix.Length+caret-start),PromptRow);
    }
    public static void Scroll(int rows) { offset=Math.Max(0,Math.Min(maximum,offset+rows)); }
    public static string ReadLine(string prompt) {
        var value=new StringBuilder(); int caret=0;
        while (true) {
            Render(prompt,value.ToString(),caret);
            var records=new Input[1]; uint count;
            if (!ReadConsoleInputW(input,records,1,out count)) throw new InvalidOperationException("The terminal input could not be read.");
            if (count==0) continue;
            Input record=records[0];
            if (record.Type==2) {
                if ((record.MouseFlags & 4)!=0) Scroll(-Math.Sign((short)(record.Buttons>>16))*3);
                else if ((record.Buttons & 1)!=0 && record.Mouse.X==Console.WindowWidth-1 && record.Mouse.Y<pageHeight && maximum>0)
                    offset=(int)((long)Math.Max(0,Math.Min(pageHeight-1,(int)record.Mouse.Y))*maximum/Math.Max(1,pageHeight-1));
                continue;
            }
            if (record.Type!=1 || record.KeyDown==0) continue;
            if ((record.Control & 12)!=0 && record.Key==67) { Cancelled=true; return "0"; }
            if (record.Key==9 && optionPages>1) { optionPage=(optionPage+((record.Control & 16)!=0 ? optionPages-1 : 1))%optionPages; continue; }
            if (record.Key==13) { positions[screen]=offset; feedback=true; return value.ToString(); }
            if (((record.Control & 12)!=0 && record.Key==86) || ((record.Control & 16)!=0 && record.Key==45)) {
                try {
                    string pasted=System.Windows.Forms.Clipboard.GetText();
                    foreach (char ch in pasted) if (!Char.IsControl(ch) && value.Length<4096) value.Insert(caret++,ch);
                } catch { }
                continue;
            }
            if (record.Key==33) { Scroll(-pageHeight); continue; }
            if (record.Key==34) { Scroll(pageHeight); continue; }
            if (record.Key==38) { Scroll(-1); continue; }
            if (record.Key==40) { Scroll(1); continue; }
            if ((record.Control & 12)!=0 && record.Key==36) { offset=0; continue; }
            if ((record.Control & 12)!=0 && record.Key==35) { offset=maximum; continue; }
            if (record.Key==36) { caret=0; continue; }
            if (record.Key==35) { caret=value.Length; continue; }
            if (record.Key==37) { caret=Math.Max(0,caret-1); continue; }
            if (record.Key==39) { caret=Math.Min(value.Length,caret+1); continue; }
            if (record.Key==8) { if (caret>0) value.Remove(--caret,1); continue; }
            if (record.Key==46) { if (caret<value.Length) value.Remove(caret,1); continue; }
            if (!Char.IsControl(record.Character) && value.Length<4096) {
                for (int n=0;n<Math.Max(1,(int)record.Repeat) && value.Length<4096;n++) value.Insert(caret++,record.Character);
            }
        }
    }
}
'@
}
function Start-TerminalView {
    $script:TerminalViewActive=$false
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { return }
    try {
        Initialize-TerminalViewApi
        if ([CS2TerminalView]::HasVisibleConsole()) { $script:TerminalViewActive=[CS2TerminalView]::Start() }
    } catch { $script:TerminalViewActive=$false }
}
function Stop-TerminalView {
    if ($script:TerminalViewActive) { [CS2TerminalView]::Stop(); $script:TerminalViewActive=$false }
}
function Write-TerminalText($Object='', $ForegroundColor) {
    if ($script:TerminalViewActive) {
        $color=if ($null -eq $ForegroundColor) {-1} else {[int][ConsoleColor]$ForegroundColor}
        [CS2TerminalView]::Add([string]$Object,$color)
    } elseif ($null -eq $ForegroundColor) { Write-Host $Object }
    else { Write-Host $Object -ForegroundColor $ForegroundColor }
}
function Write-TerminalOption([string]$Text) {
    if ($script:TerminalViewActive) { [CS2TerminalView]::AddOption($Text) }
    else { Write-Host $Text }
}
function Read-TerminalLine([string]$Prompt) {
    if ($script:TerminalViewActive) {
        $value=[CS2TerminalView]::ReadLine($Prompt)
        if ([CS2TerminalView]::Cancelled) { $script:ExitRequested=$true }
        return $value
    }
    return Read-Host $Prompt
}
