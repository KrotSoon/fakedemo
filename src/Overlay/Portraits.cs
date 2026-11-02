// Agent portraits for the model cards: the same pictures the HUD shows (panorama/images/econ/characters
// in the game's pak01), unpacked once into PNG files <name>.png that the page loads from fm.portraits.
// A portrait is a compiled texture (vtex_c): resource blocks, then the mips smallest first, each one
// BGRA and LZ4-compressed when the COMPRESSED_MIP_SIZE extra data lists a smaller size.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;

static class Portraits
{
    const string Folder = "panorama/images/econ/characters";

    public static void Extract(string dir)
    {
        Fill(dir);
        try
        {
            var pak = PakFile();
            if (pak == null) return;
            var entries = Vpk.Entries(pak, "vtex_c", Folder);
            // the square picture when there is one (the HUD's choice), else the wide one
            foreach (var name in entries.Keys.Where(n => n.StartsWith("customplayer_") && n.EndsWith("_png")))
            {
                var square = name.EndsWith("_square_png");
                var p = name.Substring(13, name.Length - 13 - (square ? 11 : 4));
                var file = Path.Combine(dir, p + ".png");
                if (File.Exists(file) || (!square && entries.ContainsKey($"customplayer_{p}_square_png"))) continue;
                try { Save(Vpk.Read(pak, entries[name]), file); }
                catch (Exception) { /* a format this does not know: the card shows no picture */ }
            }
        }
        catch (Exception) { /* no game files */ }
        Fill(dir);
    }

    // before the game's files are read too: the pictures from an earlier run are there already
    static void Fill(string dir)
    {
        try { FillOutline(Path.Combine(dir, "ct_map_based.png")); }
        catch (Exception) { /* the outline stays */ }
    }

    // The game's CT "map-based agent" is a thin dark outline on a wide transparent picture: on the dark card it
    // looked empty. Made a square filled silhouette in the tone of the T one (which is filled), once: a picture
    // whose centre is already opaque is left alone
    static void FillOutline(string file)
    {
        if (!File.Exists(file)) return;
        Bitmap src;
        using (var f = new Bitmap(file)) src = new Bitmap(f);
        using (src)
        {
            int w = src.Width, h = src.Height;
            if (src.GetPixel(w / 2, h / 2).A >= 128) return;
            // transparent pixels reachable from the edge are outside the figure, the rest is the figure
            var outside = new bool[w, h];
            var queue = new Queue<Point>();
            void Push(int x, int y)
            {
                if (x < 0 || y < 0 || x >= w || y >= h || outside[x, y] || src.GetPixel(x, y).A >= 128) return;
                outside[x, y] = true;
                queue.Enqueue(new Point(x, y));
            }
            for (int x = 0; x < w; x++) { Push(x, 0); Push(x, h - 1); }
            for (int y = 0; y < h; y++) { Push(0, y); Push(w - 1, y); }
            while (queue.Count > 0)
            {
                var p = queue.Dequeue();
                Push(p.X + 1, p.Y); Push(p.X - 1, p.Y); Push(p.X, p.Y + 1); Push(p.X, p.Y - 1);
            }
            var side = Math.Min(w, h);
            int left = (w - side) / 2, top = (h - side) / 2;
            var fill = Color.FromArgb(255, 52, 62, 78);
            using var square = new Bitmap(side, side, PixelFormat.Format32bppArgb);
            for (int y = 0; y < side; y++)
                for (int x = 0; x < side; x++)
                {
                    var a = outside[left + x, top + y] ? src.GetPixel(left + x, top + y).A : 255;   // keeps the edge smooth
                    square.SetPixel(x, y, Color.FromArgb(a, fill));
                }
            square.Save(file, ImageFormat.Png);
        }
    }

    static string? PakFile()
    {
        foreach (var p in System.Diagnostics.Process.GetProcessesByName("cs2"))
        {
            try
            {
                // game\bin\win64\cs2.exe -> game\csgo\pak01_dir.vpk
                var pak = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(p.MainModule!.FileName)!, @"..\..\csgo\pak01_dir.vpk"));
                if (File.Exists(pak)) return pak;
            }
            catch (Exception) { }
        }
        return null;
    }

    static uint U32(byte[] b, int at) => BitConverter.ToUInt32(b, at);
    static int U16(byte[] b, int at) => BitConverter.ToUInt16(b, at);

    static void Save(byte[] t, string file)
    {
        // resource header: file size (= where the pixels start), versions, block list offset and count
        var blocks = 8 + (int)U32(t, 8);
        int data = -1;
        for (var i = 0; i < (int)U32(t, 12); i++)
        {
            var at = blocks + i * 12;
            if (Encoding.ASCII.GetString(t, at, 4) == "DATA") data = at + 4 + (int)U32(t, at + 4);
        }
        if (data < 0) return;
        int w = U16(t, data + 20), h = U16(t, data + 22), format = t[data + 26], mips = t[data + 27];
        if (format != 28) return;   // BGRA8888
        var extraAt = data + 32;
        int extraCount = (int)U32(t, extraAt + 4);
        var sizes = new int[mips];
        for (var m = 0; m < mips; m++) sizes[m] = Math.Max(1, w >> m) * Math.Max(1, h >> m) * 4;
        var stored = (int[])sizes.Clone();
        var entry = extraAt + (int)U32(t, extraAt);
        for (var i = 0; i < extraCount; i++, entry += 12)
        {
            if (U32(t, entry) != 4) continue;   // COMPRESSED_MIP_SIZE
            var at = entry + 4 + (int)U32(t, entry + 4);
            var list = at + 4 + (int)U32(t, at + 4);
            var count = (int)U32(t, at + 8);
            for (var m = 0; m < Math.Min(count, mips); m++) stored[m] = (int)U32(t, list + m * 4);
        }
        // mips are stored smallest first: the full picture is the last one
        var start = (int)U32(t, 0);
        for (var m = mips - 1; m >= 1; m--) start += stored[m];
        var px = stored[0] < sizes[0] ? Lz4(t, start, stored[0], sizes[0]) : t.Skip(start).Take(sizes[0]).ToArray();

        using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        var bits = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        for (var y = 0; y < h; y++) Marshal.Copy(px, y * w * 4, bits.Scan0 + y * bits.Stride, w * 4);
        bmp.UnlockBits(bits);
        var part = file + ".part";
        bmp.Save(part, ImageFormat.Png);
        File.Move(part, file);
    }

    static byte[] Lz4(byte[] src, int at, int length, int size)
    {
        var dst = new byte[size];
        int s = at, end = at + length, d = 0;
        while (s < end)
        {
            int token = src[s++], lit = token >> 4;
            if (lit == 15) { int b; do { b = src[s++]; lit += b; } while (b == 255); }
            Buffer.BlockCopy(src, s, dst, d, lit);
            s += lit; d += lit;
            if (s >= end) break;
            var back = src[s] | src[s + 1] << 8;
            s += 2;
            var len = token & 15;
            if (len == 15) { int b; do { b = src[s++]; len += b; } while (b == 255); }
            len += 4;
            for (var i = 0; i < len; i++, d++) dst[d] = dst[d - back];
        }
        return dst;
    }
}

namespace System.Runtime.CompilerServices { static class IsExternalInit { } }   // records on .NET Framework

// files of one folder in a VPK (as fakedemo.ps1 Vpk-Entries / Vpk-Read)
static class Vpk
{
    public record Entry(int Archive, uint Offset, uint Length, byte[] Preload, long DataStart);

    public static Dictionary<string, Entry> Entries(string file, string wantExt, string wantPath)
    {
        byte[] t;
        long head = 12;
        using (var br = new BinaryReader(File.OpenRead(file)))
        {
            if (br.ReadUInt32() != 0x55AA1234) return new();
            var ver = br.ReadUInt32();
            var size = br.ReadInt32();
            if (ver == 2) { br.ReadBytes(16); head = 28; }
            t = br.ReadBytes(size);
        }
        var found = new Dictionary<string, Entry>();
        var p = 0;
        string Str() { var e = Array.IndexOf(t, (byte)0, p); var s = Encoding.UTF8.GetString(t, p, e - p); p = e + 1; return s; }
        while (true)
        {
            var ext = Str();
            if (ext.Length == 0) break;
            while (true)
            {
                var path = Str();
                if (path.Length == 0) break;
                var take = ext == wantExt && path == wantPath;
                while (true)
                {
                    var name = Str();
                    if (name.Length == 0) break;
                    var pre = BitConverter.ToUInt16(t, p + 4);
                    if (take)
                        found[name] = new Entry(BitConverter.ToUInt16(t, p + 6), BitConverter.ToUInt32(t, p + 8),
                                                BitConverter.ToUInt32(t, p + 12), t.Skip(p + 18).Take(pre).ToArray(), head + t.Length);
                    p += 18 + pre;
                }
            }
        }
        return found;
    }

    public static byte[] Read(string dirFile, Entry e)
    {
        var inDir = e.Archive == 0x7FFF;
        var src = inDir ? dirFile : dirFile.Replace("_dir.vpk", $"_{e.Archive:000}.vpk");
        var buf = new byte[e.Preload.Length + e.Length];
        Array.Copy(e.Preload, buf, e.Preload.Length);
        using var fs = File.OpenRead(src);
        fs.Seek(inDir ? e.DataStart + e.Offset : e.Offset, SeekOrigin.Begin);
        var n = e.Preload.Length;
        while (n < buf.Length) { var r = fs.Read(buf, n, buf.Length - n); if (r <= 0) break; n += r; }
        return buf;
    }
}
