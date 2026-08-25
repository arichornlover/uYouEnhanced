#!/usr/bin/env python3
"""
uYouEnhanced static crash analyzer — no dependencies, runs anywhere Python 3 runs
(GitHub macOS runners AND Windows locally).

What it does with a built IPA (or its extracted binaries):
  info           – segments/sections overview of a Mach-O
  selectors      – dump every Objective-C selector a binary implements
  syms           – dump the symbol table (survives FINALPACKAGE=1 only partially)
  funcstarts     – decoded LC_FUNCTION_STARTS function boundaries
  symbolicate    – map .ips imageOffset(s) to the nearest preceding symbol /
                   function start (this names the crashing function!)
  audit          – cross-reference: which selectors does the tweak reference
                   that YouTube's own classes do NOT implement anywhere?
                   (unrecognized-selector crashes come from exactly this set)

Typical usage on an extracted IPA:
  python3 crash_analyzer.py symbolicate Frameworks/uYouEnhanced.dylib 81012
  python3 crash_analyzer.py audit Payload/YouTube.app/YouTube Frameworks/uYouEnhanced.dylib
"""

import argparse
import bisect
import os
import re
import struct
import sys

CPU_TYPE_ARM64 = 0x0100000C
LC_SYMTAB = 0x02
LC_SEGMENT_64 = 0x19
LC_FUNCTION_STARTS = 0x26

MACHO_64_MAGIC = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE

def read_uleb128(buf, pos):
    result = 0
    shift = 0
    while True:
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, pos
        shift += 7

class MachO:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as f:
            data = f.read()
        self.data = data
        self.slice_off = 0

        if len(data) < 4:
            raise SystemExit(f"{path}: too small")
        first = struct.unpack(">I", data[:4])[0]
        if first == FAT_MAGIC:
            nfat = struct.unpack(">I", data[4:8])[0]
            for i in range(nfat):
                off = 8 + i * 20
                cputype, _sub, poff, _psize, _align = struct.unpack(">IIIII", data[off:off + 20])
                if cputype == CPU_TYPE_ARM64:
                    self.slice_off = poff
                    break
            else:
                raise SystemExit(f"{path}: fat binary without arm64 slice")

        magic = struct.unpack_from("<I", data, self.slice_off)[0]
        if magic != MACHO_64_MAGIC:
            raise SystemExit(f"{path}: not a 64-bit arm64 Mach-O (magic={magic:#x})")

        self.ncmds = struct.unpack_from("<I", data, self.slice_off + 16)[0]

        self.segments = []
        self.sections = {}
        self.symbols = []
        self.func_starts = []

        pos = self.slice_off + 32
        for _ in range(self.ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, pos)
            if cmd == LC_SEGMENT_64:
                segname = data[pos + 8:pos + 24].rstrip(b"\0").decode("latin1")
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, pos + 24)
                nsects = struct.unpack_from("<I", data, pos + 64)[0]
                self.segments.append((segname, vmaddr, fileoff, filesize))
                sp = pos + 72
                for _s in range(nsects):
                    sect = data[sp:sp + 16].rstrip(b"\0").decode("latin1")
                    sseg = data[sp + 16:sp + 32].rstrip(b"\0").decode("latin1")
                    addr, size = struct.unpack_from("<QQ", data, sp + 32)
                    soff = struct.unpack_from("<I", data, sp + 48)[0]
                    self.sections[(sseg, sect)] = {"offset": soff, "size": size, "addr": addr}
                    sp += 80
            elif cmd == LC_SYMTAB:
                symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, pos + 8)
                strbase = self.slice_off + stroff
                strtab = data[strbase:strbase + strsize]
                for i in range(nsyms):
                    e = self.slice_off + symoff + i * 16
                    n_strx, n_type, _sec, _desc = struct.unpack_from("<IBBH", data, e)
                    n_value = struct.unpack_from("<Q", data, e + 8)[0]
                    if 0 <= n_strx < len(strtab):
                        end = strtab.find(b"\0", n_strx)
                        name = strtab[n_strx:end].decode("utf-8", "replace")
                        if name:
                            self.symbols.append((n_value, n_type, name))
            elif cmd == LC_FUNCTION_STARTS:
                dataoff, datasize = struct.unpack_from("<II", data, pos + 8)
                blob = data[self.slice_off + dataoff:self.slice_off + dataoff + datasize]
                p = 0
                cur = 0
                while p < len(blob):
                    delta, p = read_uleb128(blob, p)
                    cur += delta
                    self.func_starts.append(cur)
            pos += cmdsize

        self.symbols.sort(key=lambda t: t[0])
        self.func_starts.sort()

    def section_bytes(self, seg, sect):
        info = self.sections.get((seg, sect))
        if not info or info["size"] == 0:
            return b""
        o, s = info["offset"], info["size"]
        return self.data[self.slice_off + o:self.slice_off + o + s]

    def selector_set(self):
        out = set()
        for seg, sect in (("__TEXT", "__objc_methname"), ("__OBJC", "__methname")):
            blob = self.section_bytes(seg, sect)
            for tok in blob.split(b"\0"):
                if tok:
                    out.add(tok.decode("latin1"))
        return out

    def cstrings(self):
        blob = self.section_bytes("__TEXT", "__cstring")
        out = set()
        for tok in blob.split(b"\0"):
            if tok:
                out.add(tok.decode("latin1"))
        return out

    def _nearest(self, sorted_values, offset):
        i = bisect.bisect_right(sorted_values, offset)
        prev = sorted_values[i - 1] if i > 0 else None
        nxt = sorted_values[i] if i < len(sorted_values) else None
        return prev, nxt

def cmd_info(m):
    print(f"== {m.path}")
    for seg, vmaddr, fileoff, filesize in m.segments:
        print(f"  segment {seg:<14} vmaddr={vmaddr:#x} fileoff={fileoff:#x} size={filesize:#x}")
    print(f"  symbols: {len(m.symbols)}   function-starts: {len(m.func_starts)}")

def cmd_selectors(m):
    for sel in sorted(m.selector_set()):
        print(sel)

def cmd_syms(m):
    for value, ntype, name in m.symbols:
        print(f"{value:#011x} {ntype:#04x} {name}")

def cmd_funcstarts(m):
    for v in m.func_starts:
        print(f"{v:#x}")

def parse_offset(tok):
    return int(tok, 0)

def cmd_symbolicate(m, offsets):
    sym_vals = [v for v, _t, _n in m.symbols]
    for off in offsets:
        target = parse_offset(off)
        print(f"--- offset {target} ({target:#x}) in {os.path.basename(m.path)}")
        prev, nxt = m._nearest(sym_vals, target)
        if prev is not None:
            matches = [(v, n) for v, t, n in m.symbols if v == prev]
            for v, name in matches[:3]:
                print(f"  symbol  : {name}  @ {v:#x}  (+{target - v:#x} bytes into it)")
        else:
            print("  symbol  : (none before offset)")
        fprev, fnxt = m._nearest(m.func_starts, target)
        if fprev is not None:
            size = (fnxt - fprev) if fnxt is not None else 0
            print(f"  function: starts {fprev:#x}, ~{target - fprev:#x} bytes in"
                  + (f", ends {fnxt:#x} (~{size:#x} total)" if size else ""))
        else:
            print("  function: (no function-starts data)")
        if not m.symbols and not m.func_starts:
            print("  NOTE: binary fully stripped — no symbols, no function starts.")

SELECTOR_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(:[A-Za-z_][A-Za-z0-9_]*)*:?$")

ALLOWLIST = {
    "init", "dealloc", "class", "self", "superclass", "isKindOfClass:", "respondsToSelector:",
    "description", "debugDescription", "hash", "copy", "retain", "release", "autorelease",
    "backgroundColor", "setBackgroundColor:", "backgroundEffects", "setBackgroundEffects:",
    "superview", "subviews", "frame", "setFrame:", "bounds", "setBounds:",
    "hidden", "setHidden:", "removeFromSuperview", "addSubview:", "insertSubview:atIndex:",
    "nextResponder", "window", "traitCollection", "userInterfaceStyle",
    "layoutSubviews", "layoutIfNeeded", "setNeedsLayout", "layoutSublayersOfLayer:",
    "didMoveToWindow", "willMoveToWindow:", "loadView", "viewDidLoad", "viewWillAppear:",
    "viewDidAppear:", "viewWillDisappear:", "viewDidDisappear:", "viewIsAppearing:",
    "viewDidLayoutSubviews", "viewWillLayoutSubviews", "updateViewConstraints",
    "touchesBegan:withEvent:", "touchesMoved:withEvent:", "touchesEnded:withEvent:",
    "touchesCancelled:withEvent:", "displayLayer:", "drawRect:", "sizeThatFits:",
    "contentMode", "setContentMode:", "translatesAutoresizingMaskIntoConstraints",
    "leftAnchor", "rightAnchor", "topAnchor", "bottomAnchor", "widthAnchor", "heightAnchor",
    "leadingAnchor", "trailingAnchor", "centerXAnchor", "centerYAnchor",
    "constraintEqualToAnchor:", "constraintGreaterThanOrEqualToAnchor:", "active",
    "setActive:", "text", "setText:", "textColor", "setTextColor:", "font", "setFont:",
    "titleLabel", "imageView", "tableView", "visibleCells", "cellForRowAtIndex:",
    "valueForKey:", "setValue:forKey:", "valueForKeyPath:", "objectsForKeys:",
    "accessibilityIdentifier", "setAccessibilityIdentifier:",
    "sharedInstance", "sharedApplication", "connectedScenes", "keyWindow",
    "rootViewController", "presentedViewController", "presentViewController:animated:completion:",
    "dismissViewControllerAnimated:completion:", "generalPasteboard", "string", "setString:",
    "standardUserDefaults", "objectForKey:", "setObject:forKey:", "boolForKey:",
    "integerForKey:", "floatForKey:", "stringForKey:", "removeObjectForKey:",
    "dataForKey:", "arrayForKey:", "dictionaryForKey:", "synchronize",
    "componentsJoinedByString:", "componentsSeparatedByString:", "hasPrefix:", "hasSuffix:",
    "containsString:", "stringByAppendingString:", "isEqualToString:", "length",
    "UTF8String", "count", "countByEnumeratingWithState:objects:count:",
    "objectAtIndex:", "objectForKeyedSubscript:", "firstObject", "lastObject",
    "addObject:", "removeAllObjects", "mutableCopy", "copyWithZone:", "alloc",
    "new", "bundleWithPath:", "pathForResource:ofType:", "imageWithContentsOfFile:",
    "imageNamed:", "UIImage", "colorWithRed:green:blue:alpha:", "blackColor", "clearColor",
    "whiteColor", "systemVersion", "currentDevice", "mainBundle", "infoDictionary",
    "objectForInfoDictionaryKey:", "callStackSymbols", "name", "reason", "userInfo",
    "writeToFile:atomically:encoding:error:", "stringWithFormat:",
    "dispatch_async", "dispatch_after", "isnan", "progress", "pause", "play", "close",
}

def cmd_audit(yt_path, tweak_path):
    yt = MachO(yt_path)
    tw = MachO(tweak_path)

    yt_sels = yt.selector_set()
    tw_defined = tw.selector_set()
    tw_refs = tw.cstrings() | tw_defined

    suspects = []
    for tok in tw_refs:
        if not SELECTOR_RE.match(tok):
            continue
        if tok in yt_sels or tok in tw_defined or tok in ALLOWLIST:
            continue
        interesting = (":" in tok) or (tok[:1].islower() and any(c.isupper() for c in tok))
        if interesting:
            suspects.append(tok)

    print(f"YouTube binary : {yt_path}")
    print(f"  selectors implemented anywhere: {len(yt_sels)}")
    print(f"Tweak          : {tweak_path}")
    print(f"  selectors defined by tweak    : {len(tw_defined)}")
    print(f"  selector-like strings scanned : {len(tw_refs)}")
    print()
    print(f"SUSPECTS — referenced by the tweak but implemented NOWHERE in YouTube:")
    print("(each is a candidate for 'unrecognized selector sent to instance';")
    print(" UIKit-private selectors may appear here as false positives)")
    print()
    for tok in sorted(suspects):
        print(f"  ? {tok}")
    if not suspects:
        print("  (none — tweak references look clean)")

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("info"); p.add_argument("binary")
    p = sub.add_parser("selectors"); p.add_argument("binary")
    p = sub.add_parser("syms"); p.add_argument("binary")
    p = sub.add_parser("funcstarts"); p.add_argument("binary")
    p = sub.add_parser("symbolicate"); p.add_argument("binary"); p.add_argument("offsets", nargs="+")
    p = sub.add_parser("audit"); p.add_argument("youtube_binary"); p.add_argument("tweak_dylib")

    args = ap.parse_args()

    if args.cmd == "audit":
        cmd_audit(args.youtube_binary, args.tweak_dylib)
        return

    m = MachO(args.binary)
    if args.cmd == "info":
        cmd_info(m)
    elif args.cmd == "selectors":
        cmd_selectors(m)
    elif args.cmd == "syms":
        cmd_syms(m)
    elif args.cmd == "funcstarts":
        cmd_funcstarts(m)
    elif args.cmd == "symbolicate":
        cmd_symbolicate(m, args.offsets)

if __name__ == "__main__":
    main()
