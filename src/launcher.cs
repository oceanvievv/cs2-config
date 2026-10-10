using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;

// One portable executable. Windows PowerShell remains the embedded settings engine.
// The launcher exits after handoff so profile updates can replace this executable.
static class Launcher {
    [STAThread] static int Main(string[] args) {
        string scriptPath=null;
        try {
            string mode="menu";
            if(args.Length>0) {
                if(args.Length!=2 || !String.Equals(args[0],"-Mode",StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Use -Mode menu, create, update or apply.");
                mode=args[1].ToLowerInvariant();
                if(mode!="menu" && mode!="create" && mode!="update" && mode!="apply") throw new ArgumentException("Unknown mode.");
            }
            string path=Assembly.GetExecutingAssembly().Location;
            byte[] bytes=File.ReadAllBytes(path);
            if(bytes.Length<16 || Encoding.ASCII.GetString(bytes,bytes.Length-8,8)!="CS2PACK1") throw new InvalidDataException("This download is incomplete. Download the executable again.");
            long count=BitConverter.ToInt64(bytes,bytes.Length-16);
            if(count<1 || count>bytes.Length-16) throw new InvalidDataException("This download is incomplete.");
            string script;
            using(var input=new MemoryStream(bytes,bytes.Length-16-(int)count,(int)count))
            using(var gzip=new GZipStream(input,CompressionMode.Decompress))
            using(var reader=new StreamReader(gzip,Encoding.UTF8)) script=reader.ReadToEnd();
            scriptPath=Path.Combine(Path.GetTempPath(),"cs2-config-"+Guid.NewGuid().ToString("N")+".ps1");
            File.WriteAllText(scriptPath,script,new UTF8Encoding(true));
            var info=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe"));
            info.UseShellExecute=false;
            info.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -File \""+scriptPath+"\" -Mode "+mode;
            info.EnvironmentVariables["CS2_PACK_ROOT"]=Path.GetDirectoryName(path);
            info.EnvironmentVariables["CS2_ENGINE_TEMP"]=scriptPath;
            Process.Start(info);
            return 0;
        } catch(Exception error) {
            if(scriptPath!=null) try { File.Delete(scriptPath); } catch { }
            Console.WriteLine(error.Message);
            if(!Console.IsInputRedirected) { Console.WriteLine("Press Enter to close."); Console.ReadLine(); }
            return 1;
        }
    }
}
