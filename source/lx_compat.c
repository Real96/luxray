/*
 * lx_compat.c — implementation of the libnx <=3.x input shim declared in
 * include/lx_compat.h.
 *
 * State is a single process-wide instance on purpose: the old libnx API was
 * global too, so a translation unit that calls hidScanInput() and another that
 * calls hidKeysHeld() must see the same snapshot.
 */

#include <switch.h>
#include <string.h>

#include "lx_compat.h"

static u64 g_held;
static u64 g_down;
static u64 g_up;
static HidAnalogStickState g_stick_l;
static HidAnalogStickState g_stick_r;

static bool g_hid_ready;
static bool g_touch_ready;

static void lxEnsureHid(void)
{
    if (g_hid_ready)
        return;

    /* libnx refcounts service initialisation, so this is safe even if
     * __appInit already called it. */
    if (R_SUCCEEDED(hidInitialize()))
        g_hid_ready = true;
}

static void lxEnsureTouch(void)
{
    if (g_touch_ready)
        return;

    lxEnsureHid();
    hidInitializeTouchScreen();
    g_touch_ready = true;
}

static u64 lxReadButtons(void)
{
    static const HidNpadIdType ids[] = {
        HidNpadIdType_Handheld,
        HidNpadIdType_No1, HidNpadIdType_No2, HidNpadIdType_No3,
        HidNpadIdType_No4, HidNpadIdType_No5, HidNpadIdType_No6,
        HidNpadIdType_No7, HidNpadIdType_No8,
    };

    u64 buttons = 0;

    for (size_t i = 0; i < sizeof(ids) / sizeof(ids[0]); i++) {
        const HidNpadIdType id    = ids[i];
        const u32           style = hidGetNpadStyleSet(id);

        if (style & HidNpadStyleTag_NpadHandheld) {
            HidNpadHandheldState st;
            if (hidGetNpadStatesHandheld(id, &st, 1)) {
                buttons    |= st.buttons;
                g_stick_l   = st.analog_stick_l;
                g_stick_r   = st.analog_stick_r;
            }
        } else if (style & HidNpadStyleTag_NpadFullKey) {
            HidNpadFullKeyState st;
            if (hidGetNpadStatesFullKey(id, &st, 1)) {
                buttons    |= st.buttons;
                g_stick_l   = st.analog_stick_l;
                g_stick_r   = st.analog_stick_r;
            }
        } else if (style & HidNpadStyleTag_NpadJoyDual) {
            HidNpadJoyDualState st;
            if (hidGetNpadStatesJoyDual(id, &st, 1)) {
                buttons    |= st.buttons;
                g_stick_l   = st.analog_stick_l;
                g_stick_r   = st.analog_stick_r;
            }
        } else if (style & HidNpadStyleTag_NpadJoyLeft) {
            HidNpadJoyLeftState st;
            if (hidGetNpadStatesJoyLeft(id, &st, 1)) {
                buttons  |= st.buttons;
                g_stick_l = st.analog_stick_l;
            }
        } else if (style & HidNpadStyleTag_NpadJoyRight) {
            HidNpadJoyRightState st;
            if (hidGetNpadStatesJoyRight(id, &st, 1)) {
                buttons  |= st.buttons;
                g_stick_r = st.analog_stick_r;
            }
        }
    }

    return buttons;
}

void hidScanInput(void)
{
    lxEnsureHid();

    const u64 prev = g_held;
    g_held = lxReadButtons();
    g_down = g_held & ~prev;
    g_up   = prev & ~g_held;
}

u64 hidKeysHeld(HidControllerID id) { (void)id; return g_held; }
u64 hidKeysDown(HidControllerID id) { (void)id; return g_down; }
u64 hidKeysUp  (HidControllerID id) { (void)id; return g_up;   }

u64 lxKeysHeld(void) { return g_held; }
u64 lxKeysDown(void) { return g_down; }
u64 lxKeysUp  (void) { return g_up;   }

void hidJoystickRead(JoystickPosition *pos, HidControllerID id,
                     HidControllerJoystick stick)
{
    (void)id;
    if (!pos)
        return;

    const HidAnalogStickState *src = (stick == JOYSTICK_RIGHT) ? &g_stick_r
                                                               : &g_stick_l;
    pos->dx = src->x;
    pos->dy = src->y;
}

u32 hidTouchCount(void)
{
    lxEnsureTouch();

    HidTouchScreenState st;
    memset(&st, 0, sizeof(st));

    if (!hidGetTouchScreenStates(&st, 1))
        return 0;

    return (st.count > 0) ? (u32)st.count : 0;
}

u32 lxTouchCount(void) { return hidTouchCount(); }

void hidTouchRead(touchPosition *pos, u32 point_id)
{
    if (!pos)
        return;

    memset(pos, 0, sizeof(*pos));
    lxEnsureTouch();

    HidTouchScreenState st;
    memset(&st, 0, sizeof(st));

    if (!hidGetTouchScreenStates(&st, 1))
        return;
    if (st.count <= 0 || point_id >= (u32)st.count)
        return;

    const HidTouchState *t = &st.touches[point_id];
    pos->id    = t->finger_id;
    pos->px    = t->x;
    pos->py    = t->y;
    pos->dx    = t->diameter_x;
    pos->dy    = t->diameter_y;
    pos->angle = t->rotation_angle;
}
