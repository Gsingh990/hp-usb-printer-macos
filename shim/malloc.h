/*
 * Stand-in for Linux's <malloc.h>.
 *
 * genJPEGStrips.cpp includes <malloc.h>, which does not exist on macOS (the
 * nearest equivalent is <malloc/malloc.h>).  The file only uses malloc()
 * and free(), both of which <stdlib.h> provides on every platform.
 */
#ifndef __MALLOC_SHIM_H__
#define __MALLOC_SHIM_H__
#include <stdlib.h>
#endif
