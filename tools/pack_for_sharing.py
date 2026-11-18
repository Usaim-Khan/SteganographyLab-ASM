#!/usr/bin/env python3
"""
pack_for_sharing.py - make StegoLab_share.zip for a project partner.

  python tools\\pack_for_sharing.py

Puts the SOURCE, the Visual Studio project files, vcpkg.json, the test images
and the tools into one zip, and leaves out everything Visual Studio can rebuild
or that belongs only to this computer:
  * build output   (Debug, Release, x64, x86, *.obj, *.exe, *.lib, *.pdb ...)
  * vcpkg_installed (vcpkg recreates it on the first build)
  * .vs folder and *.user files (per-user Visual Studio settings)
  * log / test leftovers (stego_log*.txt, selftest_*.txt, tmp_encoded.bmp)
The zip is written NEXT TO the StegoLab folder, e.g. Desktop\\StegoLab_share.zip.
"""
import fnmatch
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))          # the StegoLab folder
OUT = os.path.join(os.path.dirname(ROOT), "StegoLab_share.zip")

SKIP_DIRS = {"Debug", "Release", "x64", "x86", ".vs", "vcpkg_installed",
             "__pycache__", ".git"}
SKIP_FILES = ["*.obj", "*.exe", "*.lib", "*.pdb", "*.ilk", "*.idb", "*.recipe",
              "*.tlog", "*.user", "*.log", "stego_log*.txt", "selftest_*.txt",
              "tmp_encoded.bmp", "project_structure.txt", "StegoLab_share.zip"]


def wanted(name):
    return not any(fnmatch.fnmatch(name, pat) for pat in SKIP_FILES)


def main():
    kept, size = [], 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for folder, dirs, files in os.walk(ROOT):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)   # prune
            for name in sorted(files):
                if not wanted(name):
                    continue
                path = os.path.join(folder, name)
                arc = os.path.join(os.path.basename(ROOT), os.path.relpath(path, ROOT))
                z.write(path, arc)
                kept.append(os.path.relpath(path, ROOT))
                size += os.path.getsize(path)

    print(f"Wrote {OUT}")
    print(f"{len(kept)} files, {size / 1024:.0f} KB before compression, "
          f"{os.path.getsize(OUT) / 1024:.0f} KB zipped\n")
    for k in kept:
        if not k.startswith("tests" + os.sep):
            print("  ", k)
    print(f"   tests\\ ({sum(1 for k in kept if k.startswith('tests'))} images)")

    needed = ["StegoLab.slnx", "StegoLab.vcxproj", "vcpkg.json",
              os.path.join("StegoEngine", "StegoEngine.vcxproj"),
              os.path.join("StegoCLI", "StegoCLI.vcxproj")]
    missing = [n for n in needed if n not in kept]
    if missing:
        print("\nWARNING: these project files were not found, the zip is incomplete:")
        for m in missing:
            print("   ", m)
        return 1
    print("\nRemember to ALSO send the Irvine32 library folder (C:\\Irvine).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
