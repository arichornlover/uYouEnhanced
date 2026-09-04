"""Rebrand an extracted uYou.dylib for unofficial builds.
Usage: python3 Scripts/rebrand_uyou.py <path-to-uYou.dylib>
Does: 3.0.4 -> 3.0.5 (ASCII) + credit line -> UNOFFICIAL notice (UTF-16LE).
"""
import sys

path = sys.argv[1]
data = open(path, "rb").read()
orig = data

data = data.replace(b"3.0.4", b"3.0.5")

old_credit = "Coded with ❤️ by MiRO".encode("utf-16-le") + b"\x00"
notice = "UNOFFICIAL, not MiRO".encode("utf-16-le")
new_credit = notice + b"\x00" * (len(old_credit) - len(notice))
if old_credit in data:
    data = data.replace(old_credit, new_credit)
    print("==> credit line patched: UNOFFICIAL, not MiRO")

if data != orig:
    open(path, "wb").write(data)
    print(f"==> {path} rebranded")
else:
    print(f"==> no changes written to {path}")
