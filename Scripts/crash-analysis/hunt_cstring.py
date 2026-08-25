"""Dump __cstring strings from a Mach-O matching a pattern.
Usage: python Scripts/hunt_cstring.py <dylib> <regex>
"""
import re
import struct
import sys

data = open(sys.argv[1], "rb").read()
slice_off = 0
first = struct.unpack(">I", data[:4])[0]
if first == 0xCAFEBABE:
    nfat = struct.unpack(">I", data[4:8])[0]
    for i in range(nfat):
        off = 8 + i * 20
        cputype, _sub, poff, _psize, _align = struct.unpack(">IIIII", data[off:off + 20])
        if cputype == 0x0100000C:
            slice_off = poff
            break
ncmds = struct.unpack_from("<I", data, slice_off + 16)[0]
pos = slice_off + 32
pat = re.compile(sys.argv[2].encode())
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
            if sect == "__cstring":
                blob = data[slice_off + soff:slice_off + soff + size]
                seen = set()
                for tok in blob.split(b"\0"):
                    if tok and pat.search(tok) and tok not in seen:
                        seen.add(tok)
                        print(tok.decode("latin1"))
            sp += 80
    pos += cmdsize
