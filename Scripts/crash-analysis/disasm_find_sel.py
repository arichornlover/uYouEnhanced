"""Disassemble a function in uYouEnhanced.dylib and resolve selector references.
Usage: python Scripts/disasm_find_sel.py <dylib> <start> <end>
"""
import struct
import sys

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN


def sections(data):
    ncmds = struct.unpack_from("<I", data, 16)[0]
    pos = 32
    out = {}
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
                out[(sseg, sect)] = (addr, size, soff)
                sp += 80
        pos += cmdsize
    return out


def main():
    path, start, end = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0)
    data = open(path, "rb").read()
    secs = sections(data)

    methnames = secs[("__TEXT", "__objc_methname")]
    selrefs = secs.get(("__DATA_CONST", "__objc_selrefs")) or secs[("__DATA", "__objc_selrefs")]

    md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
    code_off = start
    code = data[code_off:end]

    adrp_reg = {}
    print(f"disassembling {path} {start:#x}..{end:#x}")
    for ins in md.disasm(code, code_off):
        line = f"{ins.address:#x}: {ins.mnemonic} {ins.op_str}"
        if ins.mnemonic == "adrp":
            parts = ins.op_str.split(", ")
            adrp_reg[parts[0]] = int(parts[1].split("#")[1], 0)
        elif ins.mnemonic == "add" and "#" in ins.op_str:
            parts = ins.op_str.split(", ")
            if len(parts) == 3 and parts[0] in adrp_reg and parts[2].startswith("#"):
                addr = adrp_reg[parts[0]] + int(parts[2][1:], 0)
                sr = selrefs
                if sr[0] <= addr < sr[0] + sr[1]:
                    p = sr[2] + (addr - sr[0])
                    target = struct.unpack_from("<Q", data, p)[0]
                    mn = methnames
                    so = mn[2] + (target - mn[0])
                    e = data.index(b"\0", so)
                    name = data[so:e].decode()
                    line += f"   ; SELREF -> \"{name}\""
        print(line)


if __name__ == "__main__":
    main()
