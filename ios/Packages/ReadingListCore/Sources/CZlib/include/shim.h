#ifndef CZLIB_SHIM_H
#define CZLIB_SHIM_H
#include <zlib.h>

/* Swift cannot call the deflateInit2/inflateInit2 macros directly (they pass the
   zlib version string and struct size for the ABI check), so wrap them in real functions. */
static inline int CZlib_deflateInit2(z_streamp strm, int level, int method, int windowBits,
                                     int memLevel, int strategy) {
    return deflateInit2(strm, level, method, windowBits, memLevel, strategy);
}

static inline int CZlib_inflateInit2(z_streamp strm, int windowBits) {
    return inflateInit2(strm, windowBits);
}

#endif
