// ============================================================================
// panels.h - one tab ("panel") per operation of ASM Stego Lab
// ----------------------------------------------------------------------------
// Each function creates an Fl_Group (one tab page) inside the Fl_Tabs that is
// currently being built. The panels contain NO image logic: they collect the
// user's input, call the MASM engine (stego_api.h) and show what it returns.
// ============================================================================
#pragma once

void build_hide_panel   (int x, int y, int w, int h);
void build_extract_panel(int x, int y, int w, int h);
void build_analyze_panel(int x, int y, int w, int h);
void build_verify_panel (int x, int y, int w, int h);
void build_compare_panel(int x, int y, int w, int h);
void build_report_panel (int x, int y, int w, int h);
