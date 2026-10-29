// FakeDemo.exe: runs launcher.ps1 (next to it) inside its own process, so the window, the taskbar
// button and a pinned shortcut carry this exe's icon, and no powershell.exe -ExecutionPolicy Bypass is
// started for the window. The logic stays in the scripts; this exe rarely needs a new build.
// Built by tools\build_exe.ps1 with the .NET Framework compiler that ships with Windows (C# 5).
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

static class Program
{
    [STAThread]
    static int Main()
    {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        var script = Path.Combine(dir, "launcher.ps1");
        try
        {
            if (!File.Exists(script)) throw new FileNotFoundException("launcher.ps1 is missing next to FakeDemo.exe", script);
            // scripts from a downloaded zip carry the internet mark: Bypass for this process only, as FakeDemo.cmd did
            var iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (var rs = RunspaceFactory.CreateRunspace(iss))
            {
                // the WPF window needs an STA thread: run the script on this one
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddCommand(script);
                    ps.Invoke();
                    if (ps.Streams.Error.Count > 0) Fail(ps.Streams.Error[0].ToString());
                }
            }
            return 0;
        }
        catch (Exception e)
        {
            var re = e as RuntimeException;
            Fail(re != null && re.ErrorRecord != null ? re.ErrorRecord + "\n" + re.ErrorRecord.InvocationInfo.PositionMessage : e.Message);
            return 1;
        }
    }

    // same log the launcher writes for its own crashes
    static void Fail(string text)
    {
        try
        {
            var data = Environment.GetEnvironmentVariable("FAKEDEMO_DATA");
            if (string.IsNullOrEmpty(data)) data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "FakeDemo");
            Directory.CreateDirectory(data);
            File.AppendAllText(Path.Combine(data, "launcher-error.log"), DateTime.Now.ToString("s") + " " + text + Environment.NewLine);
        }
        catch (Exception) { }
        MessageBox.Show(text, "FakeDemo", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
