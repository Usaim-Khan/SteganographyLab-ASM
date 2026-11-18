// ============================================================================
// stego_api.h - C++ view of the MASM engine (Irvine32 logic layer)
// ----------------------------------------------------------------------------
// Every engine procedure is STDCALL, so the assembler exports it as
// _Name@<bytes of arguments>.  "extern C" + __stdcall makes C++ look for that
// same name.  Keep this header in sync with engine/stego.inc.
// The structures are packed to 1 byte because MASM does not add padding;
// the two doubles in COMPAREINFO sit at offset 40, which is 8-aligned anyway.
// ============================================================================
#pragma once

// ---- error codes (mirror engine/stego.inc) ----
enum StegoError {
    ERR_OK = 0, ERR_FILE_OPEN = 1, ERR_NOT_BMP = 2, ERR_NOT_24BIT = 3,
    ERR_COMPRESSED = 4, ERR_BAD_SIZE = 5, ERR_TOO_BIG = 6, ERR_MSG_TOO_BIG = 7,
    ERR_NO_SIG = 8, ERR_BAD_LENGTH = 9, ERR_CRC_BAD = 10, ERR_FILE_WRITE = 11,
    ERR_FILE_READ = 12, ERR_BAD_SLOT = 13, ERR_NOT_LOADED = 14, ERR_EMPTY_MSG = 15,
    ERR_BUF_SMALL = 16, ERR_SIZE_MISMATCH = 17, ERR_LOG_EMPTY = 18,
    ERR_LOG_FULL = 19, ERR_SAME_FILE = 20
};

const unsigned int MSG_MAX      = 4096;     // longest message the GUI accepts
const unsigned int LOG_BUF_SIZE = 65536;    // the log file is limited to 64 KB

#pragma pack(push, 1)
struct VERIFYINFO {
    unsigned int viMsgLen;
    unsigned int viStoredCrc;
    unsigned int viCalcCrc;
};

struct ANALYSISINFO {
    unsigned int aiWidth, aiHeight, aiBitCount, aiFileSize, aiDataOffset,
                 aiRowStride, aiPixelCount, aiColourBytes, aiCapacity,
                 aiAvgB, aiAvgG, aiAvgR, aiLsbOnes, aiHasMessage, aiMsgLen;
};

struct COMPAREINFO {
    unsigned int ciWidth, ciHeight, ciColourBytes, ciChangedBytes, ciChangedBits,
                 ciMaxDiff, ciSumSqLo, ciSumSqHi, ciIdentical, ciReserved;
    double       ciMse;
    double       ciPsnr;
};
#pragma pack(pop)

static_assert(sizeof(VERIFYINFO)   == 12, "VERIFYINFO must match the MASM structure");
static_assert(sizeof(ANALYSISINFO) == 60, "ANALYSISINFO must match the MASM structure");
static_assert(sizeof(COMPAREINFO)  == 56, "COMPAREINFO must match the MASM structure");

#ifdef __cplusplus
extern "C" {
#endif

// ---- the five user operations (each one also writes a log line) ----
unsigned int __stdcall Op_Hide   (const char* cover, const char* out,
                                  const char* msg, unsigned int msgLen);
unsigned int __stdcall Op_Extract(const char* stego, char* out,
                                  unsigned int maxOut, unsigned int* outLen);
unsigned int __stdcall Op_Verify (const char* stego, VERIFYINFO* vi);
unsigned int __stdcall Op_Analyze(const char* image, ANALYSISINFO* ai);
unsigned int __stdcall Op_Compare(const char* orig, const char* enc, COMPAREINFO* ci);

// ---- log file ("Handle Report") ----
unsigned int __stdcall Log_Read  (char* out, unsigned int maxOut, unsigned int* outLen);
unsigned int __stdcall Log_Clear (void);
unsigned int __stdcall Log_Backup(char* nameInOut);   // buffer >= 64 bytes; "" = auto name

// ---- text for an error code ----
const char*  __stdcall Stego_ErrorText(unsigned int errCode);

#ifdef __cplusplus
}
#endif
