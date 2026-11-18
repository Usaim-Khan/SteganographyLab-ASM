# ASM Stego Lab
Image steganography (LSB) and analysis utility in x86 MASM (Irvine32) with an FLTK GUI.
COAL Lab, FAST NUCES Karachi, Fall 2026. Group BCS-3J

## Build
1. Visual Studio 2026, MASM + C++ desktop workloads, Irvine32 configured.
2. Open `StegoLab.slnx`, set configuration to Debug / x86.
3. Build StegoEngine, then StegoCLI and StegoGUI (FLTK restores through vcpkg).

## Run self-test
`StegoCLI.exe --selftest tests`

## Structure
- `engine/` shared MASM logic (BMP, LSB, CRC-32, analysis, log)
- `cli/` console front end
- `gui/` FLTK front end
- `tests/` sample BMPs (`tools/make_test_bmps.py` regenerates them)