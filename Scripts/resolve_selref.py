import struct
import sys

data = open(sys.argv[1], "rb").read()
ncmds = struct.unpack_from("<I", data, 16)[0]
pos = 32
secs = {}
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from("<II", data, pos)
    if cmd == 0x19:
        nsects = struct.unpack_from("<I", data, pos + 64)[0]
        sp = pos + 72
        for _s in range(nsects):
            sect = data[sp:sp + 16].rstrip(b"\0").decode()
            sseg = data[sp + 16:sp + 32].rstrip(b"\0").decode()
            addr, size = struct.unpack_from("<QQ", data, sp + 32)
            soff = struct.unpack_from("<I", data, sp + 48)[0]
            secs[(sseg, sect)] = (addr, size, soff)
            sp += 80
    pos += cmdsize

mn = secs[("__TEXT", "__objc_methname")]
sr = secs[("__DATA", "__objc_selrefs")]


def try_resolve(vmaddr):
    p = sr[2] + (vmaddr - sr[0])
    raw = struct.unpack_from("<Q", data, p)[0]
    for mask in (0xFFFFFFFFFF, 0x7FFFFFFFFF, 0xFFFFFFFFF, 0xFFFFFFFF):
        t = raw & mask
        if mn[0] <= t < mn[0] + mn[1]:
            so = mn[2] + (t - mn[0])
            return raw, data[so:data.index(b"\0", so)].decode()
    return raw, None


for a in sys.argv[2:]:
    vmaddr = int(a, 0)
    raw, name = try_resolve(vmaddr)
    print(f"{vmaddr:#x} raw={raw:#018x} -> {name!r}")
