// ============================================================================
// panels.cpp - the six tabs of the GUI
// ----------------------------------------------------------------------------
// Layout helpers at the top are shared by all panels; every panel then follows
// the same pattern:  inputs -> button -> callback -> engine call -> show text.
// ============================================================================
#include <FL/Fl.H>
#include <FL/Fl_Group.H>
#include <FL/Fl_Input.H>
#include <FL/Fl_Multiline_Input.H>
#include <FL/Fl_Button.H>
#include <FL/Fl_Box.H>
#include <FL/Fl_Text_Display.H>
#include <FL/Fl_Text_Buffer.H>
#include <FL/Fl_Native_File_Chooser.H>
#include <FL/fl_ask.H>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>

#include "stego_api.h"
#include "panels.h"

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

// printf-style formatting into a std::string
static std::string fmt(const char* format, ...) {
    char buf[512];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    return std::string(buf);
}

// "Error 8: No hidden message found ..." (text comes from the MASM engine)
static std::string error_line(unsigned int rc) {
    return fmt("Error %u: %s\n", rc, Stego_ErrorText(rc));
}

// Opens the file dialog and puts the chosen path into the input box
static void browse_open_cb(Fl_Widget*, void* data) {
    Fl_Input* in = static_cast<Fl_Input*>(data);
    Fl_Native_File_Chooser dlg;
    dlg.title("Select a 24-bit BMP image");
    dlg.type(Fl_Native_File_Chooser::BROWSE_FILE);
    dlg.filter("BMP images\t*.bmp\nAll files\t*");
    if (dlg.show() == 0) in->value(dlg.filename());
}

static void browse_save_cb(Fl_Widget*, void* data) {
    Fl_Input* in = static_cast<Fl_Input*>(data);
    Fl_Native_File_Chooser dlg;
    dlg.title("Save the encoded image as");
    dlg.type(Fl_Native_File_Chooser::BROWSE_SAVE_FILE);
    dlg.filter("BMP images\t*.bmp");
    dlg.options(Fl_Native_File_Chooser::SAVEAS_CONFIRM);
    if (dlg.show() == 0) in->value(dlg.filename());
}

// A row "Label [ path.......... ] [Browse...]"; returns the input box
static Fl_Input* path_row(int x, int y, int w, const char* label, bool save) {
    Fl_Input* in = new Fl_Input(x + 150, y, w - 260, 26, label);
    Fl_Button* b = new Fl_Button(x + w - 100, y, 100, 26, "Browse...");
    b->callback(save ? browse_save_cb : browse_open_cb, in);
    return in;
}

// A read-only text area with its own buffer
struct TextArea {
    Fl_Text_Display* display;
    Fl_Text_Buffer*  buffer;
    TextArea(int x, int y, int w, int h) {
        buffer  = new Fl_Text_Buffer();
        display = new Fl_Text_Display(x, y, w, h);
        display->buffer(buffer);
        display->textfont(FL_COURIER);
    }
    void set(const std::string& text) { buffer->text(text.c_str()); }
};

// ---------------------------------------------------------------------------
// Hide Message
// ---------------------------------------------------------------------------
static Fl_Input*           hide_cover;
static Fl_Input*           hide_out;
static Fl_Multiline_Input* hide_msg;
static TextArea*           hide_result;

static void hide_cb(Fl_Widget*, void*) {
    const char* msg = hide_msg->value();
    unsigned int len = static_cast<unsigned int>(std::strlen(msg));
    if (len > MSG_MAX) {
        fl_alert("The message is longer than %u characters.", MSG_MAX);
        return;
    }
    unsigned int rc = Op_Hide(hide_cover->value(), hide_out->value(), msg, len);
    if (rc == ERR_OK)
        hide_result->set(fmt("Message hidden (%u bytes).\nEncoded image saved as:\n%s\n",
                             len, hide_out->value()));
    else
        hide_result->set(error_line(rc));
}

void build_hide_panel(int x, int y, int w, int h) {
    Fl_Group* g = new Fl_Group(x, y, w, h, "Hide Message");
    hide_cover = path_row(x + 10, y + 15, w - 20, "Cover image:", false);
    hide_out   = path_row(x + 10, y + 50, w - 20, "Save encoded as:", true);
    hide_msg   = new Fl_Multiline_Input(x + 160, y + 90, w - 180, 150, "Secret message:");
    hide_msg->wrap(1);
    Fl_Button* b = new Fl_Button(x + 160, y + 255, 160, 32, "Hide Message");
    b->callback(hide_cb);
    hide_result = new TextArea(x + 10, y + 305, w - 20, h - 320);
    g->end();
}

// ---------------------------------------------------------------------------
// Extract Message
// ---------------------------------------------------------------------------
static Fl_Input* ext_in;
static TextArea* ext_result;

static void extract_cb(Fl_Widget*, void*) {
    static char out[MSG_MAX + 1];
    unsigned int len = 0;
    unsigned int rc = Op_Extract(ext_in->value(), out, MSG_MAX + 1, &len);
    if (rc == ERR_OK)
        ext_result->set(fmt("Hidden message (%u bytes):\n\n%s\n", len, out));
    else
        ext_result->set(error_line(rc));
}

void build_extract_panel(int x, int y, int w, int h) {
    Fl_Group* g = new Fl_Group(x, y, w, h, "Extract Message");
    ext_in = path_row(x + 10, y + 15, w - 20, "Encoded image:", false);
    Fl_Button* b = new Fl_Button(x + 160, y + 55, 160, 32, "Extract Message");
    b->callback(extract_cb);
    ext_result = new TextArea(x + 10, y + 105, w - 20, h - 120);
    g->end();
}

// ---------------------------------------------------------------------------
// Analyze Image
// ---------------------------------------------------------------------------
static Fl_Input* an_in;
static TextArea* an_result;

static void analyze_cb(Fl_Widget*, void*) {
    ANALYSISINFO ai;
    unsigned int rc = Op_Analyze(an_in->value(), &ai);
    if (rc != ERR_OK) { an_result->set(error_line(rc)); return; }
    double pct = ai.aiColourBytes ? 100.0 * ai.aiLsbOnes / ai.aiColourBytes : 0.0;
    std::string t;
    t += fmt("Width x height        : %u x %u pixels\n", ai.aiWidth, ai.aiHeight);
    t += fmt("Bits per pixel        : %u\n", ai.aiBitCount);
    t += fmt("File size             : %u bytes\n", ai.aiFileSize);
    t += fmt("Pixel data offset     : %u\n", ai.aiDataOffset);
    t += fmt("Row stride            : %u bytes\n", ai.aiRowStride);
    t += fmt("Pixel count           : %u\n", ai.aiPixelCount);
    t += fmt("Colour bytes          : %u\n", ai.aiColourBytes);
    t += fmt("Capacity              : %u message bytes\n", ai.aiCapacity);
    t += fmt("Average blue/green/red: %u / %u / %u\n", ai.aiAvgB, ai.aiAvgG, ai.aiAvgR);
    t += fmt("Lowest bit = 1        : %u bytes (%.2f %%)\n", ai.aiLsbOnes, pct);
    if (ai.aiHasMessage)
        t += fmt("Hidden message        : yes, %u bytes\n", ai.aiMsgLen);
    else
        t += "Hidden message        : no\n";
    an_result->set(t);
}

void build_analyze_panel(int x, int y, int w, int h) {
    Fl_Group* g = new Fl_Group(x, y, w, h, "Analyze Image");
    an_in = path_row(x + 10, y + 15, w - 20, "Image:", false);
    Fl_Button* b = new Fl_Button(x + 160, y + 55, 160, 32, "Analyze Image");
    b->callback(analyze_cb);
    an_result = new TextArea(x + 10, y + 105, w - 20, h - 120);
    g->end();
}

// ---------------------------------------------------------------------------
// Verify Integrity
// ---------------------------------------------------------------------------
static Fl_Input* ver_in;
static Fl_Box*   ver_status;
static TextArea* ver_result;

static void verify_cb(Fl_Widget*, void*) {
    VERIFYINFO vi = {0, 0, 0};
    unsigned int rc = Op_Verify(ver_in->value(), &vi);
    if (rc == ERR_OK || rc == ERR_CRC_BAD) {
        bool valid = (rc == ERR_OK);
        ver_status->label(valid ? "VALID" : "CORRUPTED");
        ver_status->labelcolor(valid ? FL_DARK_GREEN : FL_RED);
        ver_result->set(fmt("Message length  : %u bytes\n"
                            "Stored CRC-32   : %08X\n"
                            "Calculated CRC-32: %08X\n",
                            vi.viMsgLen, vi.viStoredCrc, vi.viCalcCrc));
    } else {
        ver_status->label("ERROR");
        ver_status->labelcolor(FL_RED);
        ver_result->set(error_line(rc));
    }
    ver_status->redraw();
}

void build_verify_panel(int x, int y, int w, int h) {
    Fl_Group* g = new Fl_Group(x, y, w, h, "Verify Integrity");
    ver_in = path_row(x + 10, y + 15, w - 20, "Encoded image:", false);
    Fl_Button* b = new Fl_Button(x + 160, y + 55, 160, 32, "Verify Integrity");
    b->callback(verify_cb);
    ver_status = new Fl_Box(x + 340, y + 55, 200, 32, "");
    ver_status->labelfont(FL_BOLD);
    ver_status->labelsize(22);
    ver_result = new TextArea(x + 10, y + 105, w - 20, h - 120);
    g->end();
}

// ---------------------------------------------------------------------------
// Compare Images
// ---------------------------------------------------------------------------
static Fl_Input* cmp_orig;
static Fl_Input* cmp_enc;
static TextArea* cmp_result;

static void compare_cb(Fl_Widget*, void*) {
    COMPAREINFO ci;
    unsigned int rc = Op_Compare(cmp_orig->value(), cmp_enc->value(), &ci);
    if (rc != ERR_OK) { cmp_result->set(error_line(rc)); return; }
    std::string t;
    t += fmt("Image size       : %u x %u pixels\n", ci.ciWidth, ci.ciHeight);
    t += fmt("Changed bytes    : %u of %u\n", ci.ciChangedBytes, ci.ciColourBytes);
    t += fmt("Changed bits     : %u\n", ci.ciChangedBits);
    t += fmt("Largest difference: %u\n", ci.ciMaxDiff);
    if (ci.ciIdentical)
        t += "The images are identical (MSE = 0, PSNR is infinite).\n";
    else {
        t += fmt("MSE              : %.4f\n", ci.ciMse);
        t += fmt("PSNR             : %.4f dB\n", ci.ciPsnr);
    }
    cmp_result->set(t);
}

void build_compare_panel(int x, int y, int w, int h) {
    Fl_Group* g = new Fl_Group(x, y, w, h, "Compare Images");
    cmp_orig = path_row(x + 10, y + 15, w - 20, "Original image:", false);
    cmp_enc  = path_row(x + 10, y + 50, w - 20, "Encoded image:", false);
    Fl_Button* b = new Fl_Button(x + 160, y + 90, 160, 32, "Compare Images");
    b->callback(compare_cb);
    cmp_result = new TextArea(x + 10, y + 140, w - 20, h - 155);
    g->end();
}

// ---------------------------------------------------------------------------
// Handle Report (log file)
// ---------------------------------------------------------------------------
static TextArea* rep_result;

static void report_view_cb(Fl_Widget*, void*) {
    static char text[LOG_BUF_SIZE + 1];
    unsigned int len = 0;
    unsigned int rc = Log_Read(text, LOG_BUF_SIZE + 1, &len);
    if (rc != ERR_OK)  rep_result->set(error_line(rc));
    else if (len == 0) rep_result->set("(the log is empty)\n");
    else               rep_result->set(text);
}

static void report_clear_cb(Fl_Widget*, void*) {
    if (fl_choice("Delete all log entries?", "Cancel", "Clear log", nullptr) != 1) return;
    unsigned int rc = Log_Clear();
    rep_result->set(rc == ERR_OK ? "The log was cleared.\n" : error_line(rc));
}

static void report_backup_cb(Fl_Widget*, void*) {
    char name[260] = {0};                       // empty = the engine picks a name
    unsigned int rc = Log_Backup(name);
    if (rc == ERR_OK)
        rep_result->set(fmt("The log was saved as:\n%s\nA new log has been started.\n", name));
    else
        rep_result->set(error_line(rc));
}

void build_report_panel(int x, int y, int w, int h) {
    Fl_Group* g = new Fl_Group(x, y, w, h, "Handle Report");
    Fl_Button* v = new Fl_Button(x + 10,  y + 15, 150, 32, "View log");
    Fl_Button* c = new Fl_Button(x + 170, y + 15, 150, 32, "Clear log");
    Fl_Button* b = new Fl_Button(x + 330, y + 15, 200, 32, "Back up log + start new");
    v->callback(report_view_cb);
    c->callback(report_clear_cb);
    b->callback(report_backup_cb);
    rep_result = new TextArea(x + 10, y + 65, w - 20, h - 80);
    g->end();
}
