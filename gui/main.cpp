// ============================================================================
// main.cpp - ASM Stego Lab : FLTK GUI front end
// ----------------------------------------------------------------------------
// Builds the window with one tab per operation (see panels.cpp). All image
// work is done by the shared MASM engine (Irvine32), the same code the console
// menu uses. This file only creates the window and runs the event loop.
// ============================================================================
#include <FL/Fl.H>
#include <FL/Fl_Double_Window.H>
#include <FL/Fl_Tabs.H>

#include "panels.h"

int main() {
    Fl::scheme("gtk+");                               // nicer look than the default

    Fl_Double_Window win(860, 640, "ASM Stego Lab - Image Steganography and Analysis");
    Fl_Tabs tabs(10, 10, 840, 620);

    // The panels are created while 'tabs' is the current group, so each one
    // becomes a tab page. The y offset leaves room for the tab buttons.
    build_hide_panel   (10, 40, 840, 590);
    build_extract_panel(10, 40, 840, 590);
    build_analyze_panel(10, 40, 840, 590);
    build_verify_panel (10, 40, 840, 590);
    build_compare_panel(10, 40, 840, 590);
    build_report_panel (10, 40, 840, 590);

    tabs.end();
    win.resizable(tabs);
    win.end();
    win.show();
    return Fl::run();
}
