// FakeDemoOverlay - the FakeMimic menu (H) in a window over CS2 instead of the in-game HUD (prototype).
// A borderless always-on-top window that never takes the focus (CS2 keeps the keyboard) with the
// Windows acrylic blur behind it; menu.html draws the screens. The plugin prints each screen to the
// console as JSON (fm_overlay 1), read here over netcon; clicks go back as console commands.
// CS2 must run "Fullscreen windowed" or windowed: nothing is drawn over exclusive fullscreen.
using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--portraits") { Portraits.Extract(args[1]); return; }   // check without the game UI
        Application.EnableVisualStyles();
        Application.Run(new OverlayForm());
    }
}

class OverlayForm : Form
{
    readonly WebView2 _web = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.Transparent };
    readonly Netcon _nc = new();
    readonly System.Windows.Forms.Timer _drag = new() { Interval = 8 };
    Point _dragFrom, _dragWin;
    bool _open;

    public OverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.Black;          // GDI black has alpha 0: the acrylic shows through
        StartPosition = FormStartPosition.Manual;
        Location = new Point(-4000, -4000);
        Size = new Size(330, 420);
        Controls.Add(_web);
        _drag.Tick += (_, _) => DragTick();
        _focus.Tick += (_, _) => FollowGame();
        Load += async (_, _) => await Init();
    }

    // shown only while the game is the active window (alt-tab, minimized: hidden)
    readonly System.Windows.Forms.Timer _focus = new() { Interval = 100 };
    static readonly bool Always = Environment.GetEnvironmentVariable("FAKEDEMO_OVERLAY_ALWAYS") == "1";   // screenshots in development

    void FollowGame()
    {
        var fg = Native.GetForegroundWindow();
        var want = _open && (fg == Handle || fg == _glass.Handle || Native.IsGame(fg) || Always);
        if (want == Visible) return;
        if (want)
        {
            Native.ShowWindow(_glass.Handle, Native.SW_SHOWNOACTIVATE);
            Native.ShowWindow(Handle, Native.SW_SHOWNOACTIVATE);
        }
        else { Hide(); _glass.Hide(); }
    }

    // the page window holds the menu plus a margin for its shadow; the menu's place inside it
    readonly GlassForm _glass = new();
    Rectangle _menu = new(17, 17, 322, 400);
    int _radius = 14;

    Point MenuAt => new(Left + _menu.X, Top + _menu.Y);
    void PlaceMenu(Point p) => Location = new Point(p.X - _menu.X, p.Y - _menu.Y);

    protected override void OnLocationChanged(EventArgs e) { base.OnLocationChanged(e); FitGlass(); }
    protected override void OnSizeChanged(EventArgs e) { base.OnSizeChanged(e); FitGlass(); }

    void FitGlass()
    {
        if (!_glass.IsHandleCreated) return;
        _glass.Fit(new Rectangle(Left + _menu.X, Top + _menu.Y, _menu.Width, _menu.Height), _radius);
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW | Native.WS_EX_TOPMOST;
            return cp;
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Native.Accent(Handle, Native.AccentTransparent);   // per-pixel alpha, no blur: smooth corners, shadow
    }

    // a click on the window must not take the focus from the game
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_MOUSEACTIVATE) { m.Result = (IntPtr)Native.MA_NOACTIVATE; return; }
        base.WndProc(ref m);
    }

    async Task Init()
    {
        var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FakeDemo", "overlay");
        var env = await CoreWebView2Environment.CreateAsync(null, data);
        await _web.EnsureCoreWebView2Async(env);
        var s = _web.CoreWebView2.Settings;
        s.AreDefaultContextMenusEnabled = false;
        s.IsZoomControlEnabled = false;
        s.IsStatusBarEnabled = false;
        _web.CoreWebView2.WebMessageReceived += (_, a) => FromPage(a.TryGetWebMessageAsString());
        var portraits = Path.Combine(data, "portraits");
        Directory.CreateDirectory(portraits);
        _web.CoreWebView2.SetVirtualHostNameToFolderMapping("fm.portraits", portraits, CoreWebView2HostResourceAccessKind.Allow);
        _ = Task.Run(() => Portraits.Extract(portraits));
        _web.CoreWebView2.Navigate(new Uri(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "menu.html")).AbsoluteUri);
        _glass.Show();
        Owner = _glass;   // an owned window stays above its owner: the page over the blur
        Hide();
        _glass.Hide();
        _nc.Line += l => BeginInvoke((Action)(() => FromGame(l)));
        _nc.Gone += () => BeginInvoke((Action)Close);
        _nc.Start("fm_overlay 1");
        _focus.Start();
    }

    // ---- game -> page ----
    readonly StringBuilder _json = new();

    void FromGame(string line)
    {
        var at = line.IndexOf("FMUI", StringComparison.Ordinal);
        if (at < 0 || line.Length < at + 6) return;
        _json.Append(line.Substring(at + 6));
        if (line[at + 4] != '.') return;
        var json = _json.ToString();
        _json.Clear();
        if (json.Contains("\"closed\":true")) { _open = false; Hide(); _glass.Hide(); CenterCursor(); return; }
        var x = Int(json, "x"); var y = Int(json, "y");
        if (!_open)
        {
            var g = Native.GameRect();
            PlaceMenu(new Point(g.Left + g.Width * x / 200, g.Top + g.Height * y / 200));
            _open = true;
            FollowGame();
        }
        _web.CoreWebView2?.PostWebMessageAsJson(json);
    }

    // the game takes the mouse back a moment after the menu closes (FakeMimic waits for this); a cursor
    // away from the middle (after an alt-tab) turned the view by that distance
    static void CenterCursor()
    {
        if (!Native.IsGame(Native.GetForegroundWindow())) return;
        var g = Native.GameRect();
        Cursor.Position = new Point(g.Left + g.Width / 2, g.Top + g.Height / 2);
    }

    static int Int(string json, string key)
    {
        var m = Regex.Match(json, "\"" + key + "\":(-?\\d+)");
        return m.Success ? int.Parse(m.Groups[1].Value) : 100;
    }

    // ---- page -> game ----
    void FromPage(string msg)
    {
        if (msg.StartsWith("cmd ")) _nc.Send(msg.Substring(4));
        else if (msg.StartsWith("size "))
        {
            // size <page w h> <menu x y w h> <corner radius>, CSS pixels; the menu keeps its place on screen
            var dpi = DeviceDpi / 96.0;
            var v = msg.Split(' ').Skip(1).Select(s => (int)Math.Round(double.Parse(s, System.Globalization.CultureInfo.InvariantCulture) * dpi)).ToArray();
            var at = MenuAt;
            _menu = new Rectangle(v[2], v[3], v[4], v[5]);
            _radius = v[6];
            SetBounds(at.X - _menu.X, at.Y - _menu.Y, v[0], v[1]);
            FitGlass();
        }
        else if (msg == "drag")
        {
            _dragFrom = Cursor.Position; _dragWin = MenuAt;
            _drag.Start();
        }
    }

    // the page only says the drag began: the window follows the real cursor until the button is up
    void DragTick()
    {
        if ((MouseButtons & MouseButtons.Left) == 0)
        {
            _drag.Stop();
            var g = Native.GameRect();
            var m = MenuAt;
            if (g.Width > 0)
                _nc.Send($"fm_menupos {Clamp((m.X - g.Left) * 200 / g.Width)} {Clamp((m.Y - g.Top) * 200 / g.Height)}");
            return;
        }
        var c = Cursor.Position;
        PlaceMenu(new Point(_dragWin.X + c.X - _dragFrom.X, _dragWin.Y + c.Y - _dragFrom.Y));
    }

    static int Clamp(int v) => Math.Max(0, Math.Min(200, v));

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _nc.Stop();
        base.OnFormClosed(e);
    }
}

// The blur under the menu: a window of its own cut to the menu's rounded shape. A window region has no
// anti-aliasing, so this one is 1 px inside the menu's edge and its stepped corners stay under the
// page's border; the page window above it is not cut and draws the smooth corners and the shadow.
// (Acrylic turned flat grey whenever the window shrank on Windows 10: the plain blur.)
class GlassForm : Form
{
    public GlassForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.Black;          // GDI black has alpha 0: the blur shows through
        StartPosition = FormStartPosition.Manual;
        Location = new Point(-4000, -4000);
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW | Native.WS_EX_TOPMOST;
            return cp;
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Native.Accent(Handle, Native.AccentBlur);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_MOUSEACTIVATE) { m.Result = (IntPtr)Native.MA_NOACTIVATE; return; }
        base.WndProc(ref m);
    }

    public void Fit(Rectangle menu, int radius)
    {
        var r = Rectangle.Inflate(menu, -1, -1);
        Bounds = r;
        var d = Math.Max(0, radius - 1) * 2;
        Native.SetWindowRgn(Handle, Native.CreateRoundRectRgn(0, 0, r.Width + 1, r.Height + 1, d, d), true);
    }
}

// the game's console over netcon: port and password from the running cs2's command line
class Netcon
{
    public event Action<string>? Line;
    public event Action? Gone;
    TcpClient? _client;
    NetworkStream? _st;
    volatile bool _stop;

    public void Start(string hello) => new Thread(() => Run(hello)) { IsBackground = true }.Start();
    public void Stop() { _stop = true; _client?.Close(); }

    public void Send(string cmd)
    {
        try { var b = Encoding.UTF8.GetBytes(cmd + "\n"); lock (this) _st?.Write(b, 0, b.Length); }
        catch (Exception) { /* reconnects */ }
    }

    // The hello goes every few seconds for as long as this runs: the console answers long before a map is
    // loaded (FakeMimic, which knows the command, loads with the first map), and FakeMimic takes the menu
    // back into the game's HUD when the hellos stop (this window closed or crashed).
    void Hello(string hello)
    {
        new Thread(() =>
        {
            var client = _client;
            while (!_stop && client == _client)
            {
                Send(hello);
                Thread.Sleep(3000);
            }
        }) { IsBackground = true }.Start();
    }

    void Run(string hello)
    {
        var seen = false;
        var waited = System.Diagnostics.Stopwatch.StartNew();
        while (!_stop)
        {
            var cl = CommandLine();
            // the game closed, or never came (the launcher gave up)
            if (cl == null)
            {
                if (seen || waited.Elapsed.TotalMinutes > 6) { Gone?.Invoke(); return; }
                Thread.Sleep(2000);
                continue;
            }
            seen = true;
            var m = Regex.Match(cl, @"-netconport\s+(\d+)(?:.*?-netconpassword\s+(\S+))?");
            if (!m.Success) { Thread.Sleep(2000); continue; }
            try
            {
                _client = new TcpClient();
                _client.Connect("127.0.0.1", int.Parse(m.Groups[1].Value));
                _st = _client.GetStream();
                if (m.Groups[2].Success) Send("PASS " + m.Groups[2].Value);
                Hello(hello);
                var buf = new byte[65536];
                var pending = new StringBuilder();
                int n;
                while (!_stop && (n = _st.Read(buf, 0, buf.Length)) > 0)
                {
                    pending.Append(Encoding.UTF8.GetString(buf, 0, n));
                    var text = pending.ToString();
                    var end = text.LastIndexOf('\n');
                    if (end < 0) continue;
                    foreach (var l in text.Substring(0, end).Split('\n')) Line?.Invoke(l.TrimEnd('\r'));
                    pending.Clear().Append(text.Substring(end + 1));
                }
            }
            catch (Exception) { /* game not ready or closed */ }
            _client?.Close();
            Thread.Sleep(1000);
        }
    }

    static string? CommandLine()
    {
        using var q = new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE Name='cs2.exe'");
        return q.Get().Cast<ManagementObject>().Select(o => o["CommandLine"] as string).FirstOrDefault(c => c != null);
    }
}

static class Native
{
    public const int WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOOLWINDOW = 0x80, WS_EX_TOPMOST = 0x8;
    public const int WM_MOUSEACTIVATE = 0x21, MA_NOACTIVATE = 3, SW_SHOWNOACTIVATE = 4;

    [StructLayout(LayoutKind.Sequential)] struct AccentPolicy { public int State, Flags, Color, Anim; }
    [StructLayout(LayoutKind.Sequential)] struct CompositionData { public int Attribute; public IntPtr Data; public int Size; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }

    [DllImport("user32.dll")] static extern int SetWindowCompositionAttribute(IntPtr h, ref CompositionData d);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateRoundRectRgn(int l, int t, int r, int b, int w, int h);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);

    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);

    static int _gamePid;

    public static bool IsGame(IntPtr h)
    {
        if (h == IntPtr.Zero) return false;
        GetWindowThreadProcessId(h, out var pid);
        if (pid == _gamePid) return true;
        try { if (System.Diagnostics.Process.GetProcessById(pid).ProcessName != "cs2") return false; }
        catch (Exception) { return false; }
        _gamePid = pid;
        return true;
    }

    public const int AccentTransparent = 2, AccentBlur = 3;

    // DWM composition of the window: 2 = per-pixel alpha only, 3 = blur behind (the page draws the tint)
    public static void Accent(IntPtr h, int state)
    {
        var accent = new AccentPolicy { State = state, Flags = 2, Color = 0 };
        var size = Marshal.SizeOf(accent);
        var ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(accent, ptr, false);
            var data = new CompositionData { Attribute = 19, Data = ptr, Size = size };
            SetWindowCompositionAttribute(h, ref data);
        }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    // the game's picture on screen (its client area)
    public static Rectangle GameRect()
    {
        var p = System.Diagnostics.Process.GetProcessesByName("cs2").FirstOrDefault(x => x.MainWindowHandle != IntPtr.Zero);
        if (p == null) return Screen.PrimaryScreen.Bounds;
        GetClientRect(p.MainWindowHandle, out var r);
        var o = new POINT();
        ClientToScreen(p.MainWindowHandle, ref o);
        return new Rectangle(o.X, o.Y, r.R - r.L, r.B - r.T);
    }
}
