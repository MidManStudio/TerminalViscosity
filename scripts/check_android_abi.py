#!/usr/bin/env python3
# ============================================================================
# NOTICE: Full documentation, design decisions, and fix history for this file
# live in docs/CI.md, section "check_android_abi.py"
# ============================================================================
"""Fails if the Odin client calls a raylib function that Odin gets wrong on 32-bit ARM Android.

Odin's 32-bit ARM backend returns small structs made only of floats (Vector2,
Vector3, Vector4, Quaternion, Rectangle, Matrix and similar) in registers. The
NDK's ABI returns them through a hidden pointer. Calling such a function from
Odin makes the C side write through a garbage pointer and crash. Those calls
must go through a C wrapper in android/entry.c.

Usage: python3 scripts/check_android_abi.py <raylib.h> <llvm-nm> <object files...>
"""
import re
import subprocess
import sys

# Return types made only of floats. Integer-only structs (Color, Shader,
# Texture) are lowered the same way on both sides and are fine.
FLOAT_STRUCTS = {
    "Vector2", "Vector3", "Vector4", "Quaternion", "Rectangle", "Matrix",
    "BoundingBox", "Ray", "Transform", "RayCollision",
}


def prototypes(header: str) -> dict:
    out = {}
    for line in open(header, encoding="utf-8"):
        m = re.match(r"RLAPI\s+(?:const\s+)?(\w+)\s*(\*?)\s*(\w+)\(", line.strip())
        if m:
            ret, star, name = m.groups()
            out[name] = ("pointer" if star else ret)
    return out


def referenced_symbols(nm: str, objects: list) -> set:
    # Undefined symbols across all objects, minus those another object defines.
    undefined, defined = set(), set()
    for obj in objects:
        text = subprocess.run([nm, obj], capture_output=True, text=True, check=True).stdout
        for line in text.splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[0] == "U":
                undefined.add(parts[1])
            elif len(parts) == 3:
                defined.add(parts[2])
    return undefined - defined


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    header, nm, objects = sys.argv[1], sys.argv[2], sys.argv[3:]
    protos = prototypes(header)
    used = sorted(s for s in referenced_symbols(nm, objects) if s in protos)
    bad = [s for s in used if protos[s] in FLOAT_STRUCTS]
    print(f"checked {len(used)} raylib functions called from Odin")
    if bad:
        print("these return a float-only struct and need a C wrapper in android/entry.c:")
        for s in bad:
            print(f"  {s} returns {protos[s]}")
        return 1
    print("ok: none of them return a float-only struct")
    return 0


if __name__ == "__main__":
    sys.exit(main())
