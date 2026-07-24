/*
 * lx_sysmodule.c — libnx >= 4.10 system module boilerplate for Luxray.
 *
 * INERT BY DEFAULT. The whole file is behind LUXRAY_NEW_INIT because your
 * existing main translation unit almost certainly already defines
 * __appInit / __libnx_initheap / nx_inner_heap, and two definitions is a
 * duplicate-symbol link error rather than a helpful message.
 *
 * To adopt it:
 *   1. delete the old __libnx_initheap / __appInit / __appExit block and the
 *      __nx_applet_type / nx_inner_heap globals from your main file
 *   2. build with -DLUXRAY_NEW_INIT (add it to DEFINES in the Makefile)
 *
 * Compile as C, or paste the body into a C++ file inside extern "C" {} — these
 * symbols must have C linkage to override libnx's weak definitions.
 */

#ifdef LUXRAY_NEW_INIT

#include <switch.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------ */
/* Heap                                                                      */
/* ------------------------------------------------------------------------ */
/*
 * HOS 20.0.0 cut the applet pool steal from 40 MB to 14 MB, and 21.0.0 took
 * roughly another 10 MB away from custom system modules. This budget is shared
 * with every other sysmodule the user has installed (sys-clk, sys-con, ...),
 * so treat it as a scarce resource and measure rather than guess.
 *
 *   headless logic only (recommended)     : 0x40000  (256 KB)
 *   logic + small on-demand framebuffer   : 0x200000 (2 MB)
 *
 * Override from the Makefile with -DINNER_HEAP_SIZE=0x...
 */
#ifndef INNER_HEAP_SIZE
#define INNER_HEAP_SIZE 0x40000
#endif

u32 __nx_applet_type              = AppletType_None;
u32 __nx_fs_num_sessions          = 1;
u32 __nx_fsdev_direntry_cache_size = 1;

/*
 * libnx defaults to time:u, which cannot write the clock. Date advance needs
 * time:s. This must be set before timeInitialize() runs.
 */
TimeServiceType __nx_time_service_type = TimeServiceType_System;

size_t nx_inner_heap_size = INNER_HEAP_SIZE;
char   nx_inner_heap[INNER_HEAP_SIZE];

void __libnx_initheap(void);
void __appInit(void);
void __appExit(void);

void __libnx_initheap(void)
{
    extern char *fake_heap_start;
    extern char *fake_heap_end;

    fake_heap_start = nx_inner_heap;
    fake_heap_end   = nx_inner_heap + nx_inner_heap_size;
}

/* ------------------------------------------------------------------------ */
/* Service init                                                              */
/* ------------------------------------------------------------------------ */

static void lxAbortIfFailed(Result rc)
{
    if (R_FAILED(rc))
        diagAbortWithResult(rc);   /* fatalSimple() was removed in libnx 2.x */
}

void __appInit(void)
{
    lxAbortIfFailed(smInitialize());

    /*
     * Publish the running HOS version. Several libnx service paths branch on
     * it and behave badly when it reads as 0.0.0, which is what happens in a
     * sysmodule that never calls hosversionSet().
     */
    if (R_SUCCEEDED(setsysInitialize())) {
        SetSysFirmwareVersion fw;
        if (R_SUCCEEDED(setsysGetFirmwareVersion(&fw)))
            hosversionSet(MAKEHOSVERSION(fw.major, fw.minor, fw.micro));
        setsysExit();
    }

    lxAbortIfFailed(timeInitialize());   /* time:s, see __nx_time_service_type */
    lxAbortIfFailed(hidInitialize());    /* npad shared memory, for lx_compat.h */

#ifdef LUXRAY_NEEDS_FS
    lxAbortIfFailed(fsInitialize());
    lxAbortIfFailed(fsdevMountSdmc());
#endif

    /*
     * Close the sm session once every service handle is held. Sessions are a
     * global resource and a resident sysmodule should not sit on one.
     */
    smExit();
}

void __appExit(void)
{
#ifdef LUXRAY_NEEDS_FS
    fsdevUnmountAll();
    fsExit();
#endif
    hidExit();
    timeExit();
}

/* ------------------------------------------------------------------------ */
/* Clock helpers                                                             */
/* ------------------------------------------------------------------------ */

#define LX_SECONDS_PER_DAY 86400ULL

Result lxGetPosixTime(u64 *out)
{
    return timeGetCurrentTime(TimeType_UserSystemClock, out);
}

Result lxSetPosixTime(u64 posix_time)
{
    return timeSetCurrentTime(TimeType_UserSystemClock, posix_time);
}

/*
 * Advance (or rewind, with a negative day count) the user system clock.
 *
 * Caveat that is not a code problem: if "Synchronize Clock via Internet" is on,
 * the console will re-sync and silently undo this. That failure looks exactly
 * like a broken write, so check the setting before debugging the code.
 */
Result lxAdvanceDays(s64 days)
{
    u64    now = 0;
    Result rc  = lxGetPosixTime(&now);
    if (R_FAILED(rc))
        return rc;

    const s64 target = (s64)now + days * (s64)LX_SECONDS_PER_DAY;
    if (target < 0)
        return MAKERESULT(Module_Libnx, LibnxError_BadInput);

    return lxSetPosixTime((u64)target);
}

#ifdef __cplusplus
}
#endif

#endif /* LUXRAY_NEW_INIT */
