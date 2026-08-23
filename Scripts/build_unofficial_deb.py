"""Build an UNOFFICIAL patched uYou deb.

Takes the pristine com.miro.uyou_3.0.4 deb + a compiled tweak dylib, and emits
com.miro.uyou_3.0.5-unofficial_iphoneos-arm.deb containing:
  - uYou.dylib with version strings rebranded 3.0.4 -> 3.0.5
  - the tweak dylib injected under Library/MobileSubstrate/DynamicLibraries/
    plus a substrate filter plist (loads only inside YouTube)
  - control file marked Version 3.0.5-unofficial

Usage:
  python Scripts/build_unofficial_deb.py <uyou.deb> <tweak.dylib> [out.deb]

NOTE: this artifact is NOT used by uYouEnhanced IPA builds (those keep the
pristine 3.0.4 deb). It exists purely as an alternative distribution.
"""
import gzip
import io
import lzma
import os
import sys
import tarfile
import time


def decompress(name, body):
    if name.endswith(".gz"):
        return gzip.decompress(body)
    if name.endswith(".xz"):
        return lzma.decompress(body)
    if name.endswith(".lzma"):
        return lzma.decompress(body, format=lzma.FORMAT_ALONE)
    raise SystemExit(f"unsupported compression: {name}")


def compress_like(name, raw):
    if name.endswith(".gz"):
        return gzip.compress(raw)
    if name.endswith(".xz"):
        return lzma.compress(raw, format=lzma.FORMAT_XZ)
    return lzma.compress(raw, format=lzma.FORMAT_ALONE)


def read_ar(path):
    data = open(path, "rb").read()
    assert data[:8] == b"!<arch>\n", "not an ar/deb archive"
    members = []
    pos = 8
    while pos < len(data):
        hdr = data[pos:pos + 60]
        name = hdr[0:16].decode().strip().rstrip("/")
        size = int(hdr[48:58].decode().strip())
        body = data[pos + 60:pos + 60 + size]
        members.append((name, body))
        pos += 60 + size + (size % 2)
    return members


def write_ar(members, path):
    out = io.BytesIO()
    out.write(b"!<arch>\n")
    for name, body in members:
        hdr = "{:<16}{:<12}{:<6}{:<6}{:<8}{:<10}".format(
            name + "/", str(int(time.time())), "0", "0", "100644", str(len(body))).encode()
        out.write(hdr)
        out.write(b"`\n")
        out.write(body)
        if len(body) % 2:
            out.write(b"\n")
    open(path, "wb").write(out.getvalue())


def rebrand(data):
    return data.replace(b"3.0.4", b"3.0.5")


def main():
    deb, dylib = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else "com.miro.uyou-unofficial_3.0.5_iphoneos-arm.deb"
    members = {name: body for name, body in read_ar(deb)}

    control = decompress("control.tar.gz", members["control.tar.gz"])
    data_name = next(n for n in members if n.startswith("data.tar"))
    datapack = decompress(data_name, members[data_name])

    # --- control: mark unofficial ---
    c_in = tarfile.open(fileobj=io.BytesIO(control))
    c_out = tarfile.open(fileobj=io.BytesIO(), mode="w")
    for m in c_in.getmembers():
        if "md5sums" in m.name:
            continue  # hashes are stale after rebranding/injection
        f = c_in.extractfile(m)
        if m.name.lstrip("./") == "control":
            text = f.read().decode()
            lines = []
            for line in text.splitlines():
                if line.startswith("Version:"):
                    lines.append("Version: 3.0.5-unofficial")
                elif line.startswith("Description:"):
                    lines.append(line + " [UNOFFICIAL build with download/modern-YT fixes - not affiliated with MiRO92]")
                else:
                    lines.append(line)
            text = "\n".join(lines) + "\n"
            b = text.encode()
            m.size = len(b)
            c_out.addfile(m, io.BytesIO(b))
        else:
            c_out.addfile(m, f if f else io.BytesIO(b""))
    c_out.close()
    members["control.tar.gz"] = compress_like("control.tar.gz", c_out.fileobj.getvalue())

    # --- data: rebrand dylib + inject tweak ---
    d_in = tarfile.open(fileobj=io.BytesIO(datapack))
    d_out = tarfile.open(fileobj=io.BytesIO(), mode="w")
    for m in d_in.getmembers():
        if "md5sums" in m.name:
            continue
        f = d_in.extractfile(m)
        body = f.read() if f else None
        if m.name.endswith("uYou.dylib") and body:
            body = rebrand(body)
            old_credit = "Coded with ❤️ by MiRO".encode("utf-16-le")
            notice = "UNOFFICIAL, not MiRO".encode("utf-16-le")
            new_credit = notice + b"\x00" * (len(old_credit) - len(notice))
            if old_credit + b"\x00" in body:
                body = body.replace(old_credit + b"\x00", new_credit + b"\x00")
                print("patched credit line -> UNOFFICIAL notice")
            print(f"rebranded {m.name}")
        m.mtime = int(time.time())
        d_out.addfile(m, io.BytesIO(body) if body else io.BytesIO(b""))

    tweak = open(dylib, "rb").read()
    tweak_name = os.path.basename(dylib)

    def add(path, body, mode=0o755):
        ti = tarfile.TarInfo("./" + path)
        ti.size = len(body)
        ti.mode = mode
        ti.mtime = int(time.time())
        d_out.addfile(ti, io.BytesIO(body))

    add("Library/MobileSubstrate/DynamicLibraries/" + tweak_name, tweak)
    filt = ("{ Filter = { Bundles = (\"com.google.ios.youtube\"); }; }").encode()
    add("Library/MobileSubstrate/DynamicLibraries/" + tweak_name + ".plist", filt, 0o644)
    d_out.close()
    members[data_name] = compress_like(data_name, d_out.fileobj.getvalue())

    write_ar([
        ("debian-binary", b"2.0\n"),
        ("control.tar.gz", members["control.tar.gz"]),
        (data_name, members[data_name]),
    ], out)
    print(f"wrote {out} ({os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
