/*
 * No-op stub for HP's ImageProcessor.
 *
 * In HPLIP these five entry points live in libImageProcessor, a closed-source
 * binary that HP ships for Linux only -- there is no macOS build of it.  It is
 * an optional per-line colour-processing hook: HPCupsFilter logs a debug line
 * if any call fails and continues regardless, so raster passes through
 * unmodified when it is absent.
 *
 * Returning IPE_SUCCESS (rather than an error) keeps the filter's debug log
 * clean; returning NULL from Create is what the real library does on failure
 * and the caller already tolerates it.
 */
#include "ImageProcessor.h"

image_processor_t* imageProcessorCreate(void)
{
    return NULL;
}

void imageProcessorDestroy(image_processor_t *handle)
{
    (void)handle;
}

IMAGE_PROCESSOR_ERROR imageProcessorStartPage(image_processor_t *handle,
                                              cups_page_header2_t *header)
{
    (void)handle; (void)header;
    return IPE_SUCCESS;
}

IMAGE_PROCESSOR_ERROR imageProcessorProcessLine(image_processor_t *handle,
                                                BYTE *buffer, unsigned size)
{
    (void)handle; (void)buffer; (void)size;
    return IPE_SUCCESS;
}

IMAGE_PROCESSOR_ERROR imageProcessorEndPage(image_processor_t *handle)
{
    (void)handle;
    return IPE_SUCCESS;
}
