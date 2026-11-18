#!/usr/bin/env python3
"""
run_tests.py - one-command automatic test for ASM Stego Lab (whole engine).

  python tools\\run_tests.py                (finds Debug\\StegoCLI.exe itself)
  python tools\\run_tests.py path\\to\\StegoCLI.exe

What it does
  1. Regenerates the test BMPs (tools/make_test_bmps.py) and checks them against
     a Python reference of the parser.
  2. Starts StegoCLI.exe with  --selftest <tests folder>. The exe runs all
     checks (BMP loading, Pix_Index padding, CRC-32, hide/extract/verify,
     Analyze, Compare with MSE/PSNR, log file) and prints PASS/FAIL
     lines into THIS console. Its exit code is the number of failed checks.

Run it from cmd, PowerShell or a VS Code / Visual Studio terminal. Irvine32
prints through the Windows console API, so the exe's text cannot be captured
by Python; the exit code is what Python reads.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
TESTS = os.path.join(ROOT, "tests")


def find_exe():
    if len(sys.argv) > 1:
        return os.path.abspath(sys.argv[1])
    for cfg in ("Debug", "Release"):
        cand = os.path.join(ROOT, cfg, "StegoCLI.exe")
        if os.path.isfile(cand):
            return cand
    return None


def main():
    exe = find_exe()
    if not exe or not os.path.isfile(exe):
        print("StegoCLI.exe not found. Build the solution first, or pass its path.")
        return 2

    # 1. generate the images and run the Python reference check
    gen = subprocess.run([sys.executable, os.path.join(HERE, "make_test_bmps.py")],
                         capture_output=True, text=True)
    if gen.returncode != 0 or "MISMATCH" in gen.stdout:
        print(gen.stdout, gen.stderr)
        print("Reference check failed - test images are not trustworthy.")
        return 2
    print("Test images generated; Python reference check passed.")

    # 2. run the assembly tests. The folder is passed UNQUOTED on purpose:
    #    Irvine's GetCommandTail returns the raw text after the program name.
    if len(TESTS) > 120:
        print("Warning: the tests path is longer than 120 characters; Irvine's "
              "command tail holds at most 128. Move the project to a shorter path.")
    print(f"Running {exe}\n")
    rc = subprocess.run(f'"{exe}" --selftest {TESTS}').returncode

    print()
    if rc == 0:
        print("PYTHON: ALL TESTS PASSED")
        return 0
    if 0 < rc <= 100:
        print(f"PYTHON: {rc} CHECK(S) FAILED - see the FAIL lines above")
    else:
        print(f"PYTHON: StegoCLI.exe crashed or exited abnormally (code {rc & 0xFFFFFFFF:#x})")
    n = input()
    return 1


if __name__ == "__main__":
    sys.exit(main())
