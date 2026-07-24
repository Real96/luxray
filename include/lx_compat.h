/*
 * lx_compat.h — libnx <=3.x source-compatibility shim for Luxray.
 *
 * The point of this header is that the 2020 codebase should compile against
 * libnx >= 4.10 *without editing call sites*. The Makefile force-includes it
 * into every translation unit (COMPAT_SHIM=1, on by default), so old code like
 *
 *     hidScanInput();
 *     if (hidKeysDown(CONTROLLER_P1_AUTO) & KEY_A) ...
 *
 * keeps working, and is routed onto the libnx 4.x npad API underneath.
 *
 * This is scaffolding, not a destination. It buys a working build now; port the
 * call sites properly over time and then drop COMPAT_SHIM.
 *
 * If any declaration here collides with your libnx (a "redefinition" error),
 * delete that block — it means libnx still provides it.
 *
 * Implementation lives in source/lx_compat.c.
 */

#pragma once

#include <switch.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------ */
/* Button names (deleted in libnx 4.0)                                       */
/* ------------------------------------------------------------------------ */

#ifndef KEY_A
#define KEY_A            HidNpadButton_A
#define KEY_B            HidNpadButton_B
#define KEY_X            HidNpadButton_X
#define KEY_Y            HidNpadButton_Y
#define KEY_LSTICK       HidNpadButton_StickL
#define KEY_RSTICK       HidNpadButton_StickR
#define KEY_L            HidNpadButton_L
#define KEY_R            HidNpadButton_R
#define KEY_ZL           HidNpadButton_ZL
#define KEY_ZR           HidNpadButton_ZR
#define KEY_PLUS         HidNpadButton_Plus
#define KEY_MINUS        HidNpadButton_Minus

#define KEY_DLEFT        HidNpadButton_Left
#define KEY_DUP          HidNpadButton_Up
#define KEY_DRIGHT       HidNpadButton_Right
#define KEY_DDOWN        HidNpadButton_Down

#define KEY_LSTICK_LEFT  HidNpadButton_StickLLeft
#define KEY_LSTICK_UP    HidNpadButton_StickLUp
#define KEY_LSTICK_RIGHT HidNpadButton_StickLRight
#define KEY_LSTICK_DOWN  HidNpadButton_StickLDown
#define KEY_RSTICK_LEFT  HidNpadButton_StickRLeft
#define KEY_RSTICK_UP    HidNpadButton_StickRUp
#define KEY_RSTICK_RIGHT HidNpadButton_StickRRight
#define KEY_RSTICK_DOWN  HidNpadButton_StickRDown

#define KEY_SL_LEFT      HidNpadButton_LeftSL
#define KEY_SR_LEFT      HidNpadButton_LeftSR
#define KEY_SL_RIGHT     HidNpadButton_RightSL
#define KEY_SR_RIGHT     HidNpadButton_RightSR
#define KEY_SL           (HidNpadButton_LeftSL | HidNpadButton_RightSL)
#define KEY_SR           (HidNpadButton_LeftSR | HidNpadButton_RightSR)

/* sideways Joy-Con: the d-pad names rotate, same as old libnx */
#define KEY_JOYCON_RIGHT HidNpadButton_Left
#define KEY_JOYCON_DOWN  HidNpadButton_Up
#define KEY_JOYCON_LEFT  HidNpadButton_Right
#define KEY_JOYCON_UP    HidNpadButton_Down

/* d-pad OR stick, as the old aliases meant */
#define KEY_LEFT         HidNpadButton_AnyLeft
#define KEY_UP           HidNpadButton_AnyUp
#define KEY_RIGHT        HidNpadButton_AnyRight
#define KEY_DOWN         HidNpadButton_AnyDown

/* Old KEY_TOUCH has no npad equivalent; use lxTouchCount() != 0 instead. */
#define KEY_TOUCH        0ULL
#endif /* KEY_A */

/* ------------------------------------------------------------------------ */
/* Controller / stick / touch types (deleted in libnx 4.0)                   */
/* ------------------------------------------------------------------------ */

#ifndef CONTROLLER_P1_AUTO
typedef enum {
    CONTROLLER_PLAYER_1 = 0,
    CONTROLLER_PLAYER_2 = 1,
    CONTROLLER_PLAYER_3 = 2,
    CONTROLLER_PLAYER_4 = 3,
    CONTROLLER_PLAYER_5 = 4,
    CONTROLLER_PLAYER_6 = 5,
    CONTROLLER_PLAYER_7 = 6,
    CONTROLLER_PLAYER_8 = 7,
    CONTROLLER_HANDHELD = 8,
    CONTROLLER_UNKNOWN  = 9,
    CONTROLLER_P1_AUTO  = 10,
} HidControllerID;

typedef enum {
    JOYSTICK_LEFT  = 0,
    JOYSTICK_RIGHT = 1,
} HidControllerJoystick;

typedef struct {
    s32 dx;
    s32 dy;
} JoystickPosition;

typedef struct {
    u32 id;
    u32 px;
    u32 py;
    u32 dx;
    u32 dy;
    u32 angle;
} touchPosition;
#endif /* CONTROLLER_P1_AUTO */

/* ------------------------------------------------------------------------ */
/* Input functions (deleted in libnx 4.0)                                    */
/* ------------------------------------------------------------------------ */
/*
 * These read the npad shared memory directly rather than going through
 * PadState. padInitializeDefault()/padUpdate() bind to the caller's applet
 * resource user id; a system module has none, so the pad would read as
 * permanently idle. Dispatching on hidGetNpadStyleSet() works from a sysmodule
 * and from an overlay applet alike — the same approach libtesla takes.
 *
 * The controller id argument is accepted and ignored: all connected pads are
 * merged, which is what CONTROLLER_P1_AUTO meant in practice for an overlay.
 * hidInitialize() is performed lazily on first use, so this is safe whether or
 * not your __appInit already did it (libnx refcounts service init).
 */
void hidScanInput(void);
u64  hidKeysHeld(HidControllerID id);
u64  hidKeysDown(HidControllerID id);
u64  hidKeysUp(HidControllerID id);
void hidJoystickRead(JoystickPosition *pos, HidControllerID id, HidControllerJoystick stick);

u32  hidTouchCount(void);
void hidTouchRead(touchPosition *pos, u32 point_id);

/* Preferred names, if you'd rather call the shim explicitly than via the
 * old libnx spelling. */
u64  lxKeysHeld(void);
u64  lxKeysDown(void);
u64  lxKeysUp(void);
u32  lxTouchCount(void);

/* ------------------------------------------------------------------------ */
/* Process management (signature changed in libnx 3.0)                       */
/* ------------------------------------------------------------------------ */

#ifndef FsStorageId_None
#define FsStorageId_None       0   /* NcmStorageId_None       */
#define FsStorageId_Host       1   /* NcmStorageId_Host       */
#define FsStorageId_GameCard   2   /* NcmStorageId_GameCard   */
#define FsStorageId_NandSystem 3   /* NcmStorageId_BuiltInSystem */
#define FsStorageId_NandUser   4   /* NcmStorageId_BuiltInUser   */
#define FsStorageId_SdCard     5   /* NcmStorageId_SdCard     */
#endif

/*
 * pmshellLaunchProcess(flags, program_id, storage_id, &pid)
 *   -> pmshellLaunchProgram(flags, &NcmProgramLocation, &pid)
 *
 * Sysmodules under atmosphere/contents are resolved by AMS's loader, so
 * NcmStorageId_None is correct regardless of what the old call passed.
 */
static inline Result pmshellLaunchProcess(u32 launch_flags, u64 program_id,
                                          u32 storage_id, u64 *out_pid)
{
    NcmProgramLocation loc;
    (void)storage_id;
    loc.program_id = program_id;
    loc.storageID  = NcmStorageId_None;
    return pmshellLaunchProgram(launch_flags, &loc, out_pid);
}

#ifndef pmshellTerminateProcessByTitleId
#define pmshellTerminateProcessByTitleId(tid) pmshellTerminateProgram(tid)
#endif

/* ------------------------------------------------------------------------ */
/* Misc renames                                                              */
/* ------------------------------------------------------------------------ */

/* fatalSimple() went away in libnx 2.x. */
static inline void fatalSimple(Result rc)
{
    diagAbortWithResult(rc);
}

/* kernelAboveX() was replaced by the hosversion API. Requires hosversionSet()
 * to have run — libnx's default __appInit does it, sysmodules must do it
 * themselves (see source/lx_sysmodule.c). */
#ifndef kernelAbove200
#define kernelAbove200() hosversionAtLeast(2, 0, 0)
#define kernelAbove300() hosversionAtLeast(3, 0, 0)
#define kernelAbove400() hosversionAtLeast(4, 0, 0)
#define kernelAbove500() hosversionAtLeast(5, 0, 0)
#define kernelAbove600() hosversionAtLeast(6, 0, 0)
#define kernelAbove700() hosversionAtLeast(7, 0, 0)
#endif

#ifdef __cplusplus
}
#endif
