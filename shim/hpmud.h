/*
 * Stub for HP's hpmud.h.
 *
 * dbuscomm.h includes <hpmud.h> unconditionally, but no hpcups translation
 * unit actually references any HPMUD_* type or hpmud_* function -- the
 * include is vestigial.  hpmud is HP's Linux USB/parallel I/O layer and does
 * not build on macOS, where CUPS' own usb backend performs the same job.
 *
 * With HAVE_DBUS undefined, the DBusCommunicator methods in dbuscomm.cpp
 * compile to no-ops, so status reporting is simply absent rather than broken.
 */
#ifndef __HPMUD_STUB_H__
#define __HPMUD_STUB_H__
#endif
