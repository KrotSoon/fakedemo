import struct, sys
p = sys.argv[1]
PREFIX = sys.argv[2] if len(sys.argv) > 2 else 'agents/models/'
f = open(p, 'rb')
sig, ver, tree = struct.unpack('<III', f.read(12))
if ver == 2: f.read(16)
def s():
    b = bytearray()
    while True:
        c = f.read(1)
        if c == b'\0' or not c: return b.decode('utf-8', 'replace')
        b += c
out = []
while True:
    ext = s()
    if not ext: break
    while True:
        path = s()
        if not path: break
        while True:
            name = s()
            if not name: break
            crc, pre, arch, off, ln, term = struct.unpack('<IHHIIH', f.read(18))
            f.read(pre)
            if path.startswith(PREFIX) and ext == 'vmdl_c':
                out.append(f"{path}/{name}.vmdl")
for x in sorted(out): print(x)
