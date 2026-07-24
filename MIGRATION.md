# Luxray → Atmosphère 1.11.2 / HOS 22.5.0 port

Engineering notes and drop-in files for bringing `3096/luxray` (last touched ~mid-2020,
libnx 2.x/3.x era) up to the current CFW + SDK.

---

## 0. Scope note — what I could and could not read

GitHub serves blob pages to automated fetches but blocks directory listings, so I was able to
read **`Makefile`, `luxray.json`, `.gitmodules`, `README.md`** verbatim, but **not** the contents
of `source/`, `launcher/`, or the `libs/libluxio` submodule (which vendors LVGL).

Everything in §1–§3 is verified against the files I read and against upstream release notes.
Everything in §4 is keyed to `grep` patterns instead of line numbers — run the greps, and each
hit maps to an exact before/after. Paste any file that comes up and I'll produce a literal patch.

---

## 1. Target versions (verified 2026-07-24)

| Component | Version | Notes |
|---|---|---|
| Atmosphère | **1.11.2** (16 Jun 2026, 92nd release) | Basic support for HOS **22.5.0**; built with GCC 16/newlib |
| fusée | bundled with 1.11.2 | `fusee-primary` is gone — update the payload or you won't boot |
| hbl / hbmenu | 2.4.5 / 3.6.1 | bundled |
| devkitA64 | latest (`dkp-pacman -Syu switch-dev`) | GCC 16 toolchain |
| libnx | **≥ 4.10.0 — hard requirement** | see §2.1 |
| switch-tools | latest | `elf2nso`, `npdmtool`, `elf2nro` |

```bash
sudo dkp-pacman -Syu
sudo dkp-pacman -S --needed switch-dev switch-tools
```

---

## 2. Why the current build is broken — four independent root causes

### 2.1 The HOS 21.0.0 TLS ABI break (this one is fatal, and silent)

Nintendo started writing into TLS space that libnx had been using for its TLS slots. Atmosphère's
release notes are unambiguous: **all homebrew must be recompiled against libnx ≥ 4.10.0** or it
will crash or silently corrupt memory. C++ exceptions are implemented on top of TLS slots, so a
C++ project like Luxray is squarely in the blast radius. A binary built in 2020 is not "probably
fine" here — it is expected to fail, usually on exit or at the first throw.

There is no source workaround. Rebuild is the fix.

### 2.2 The libnx 4.0 HID rewrite

`hidScanInput()`, `hidKeysDown()`, `hidKeysHeld()`, `HidControllerID`, every `KEY_*` constant,
`JoystickPosition`, `hidJoystickRead()`, `touchPosition`, `hidTouchRead()` — all removed.
This is almost certainly the largest source-level diff in the port. See §4.1.

### 2.3 The system-module memory cliff (the interesting one)

- HOS **20.0.0**: the applet pool steal dropped from **40 MB → 14 MB**. `ams.mitm` gave back 20 MB
  of its own heap to compensate.
- HOS **21.0.0**: roughly **10 MB less again** for custom system modules. SciresM's own note is that
  he has no fix in mind.

Luxray's `Makefile` builds **one ELF** and emits both `luxray.nsp` (system module) and `luxray.nro`
(renamed to `.ovl`), with `libs/libluxio` + LVGL linked into both. So the sysmodule build carries a
full LVGL UI and a `vi` framebuffer.

Budget check for a 720p double-buffered framebuffer:

| Format | Buffers | Cost |
|---|---|---|
| RGBA8888 1280×720 | 2 | **≈ 7.4 MB** |
| RGBA4444 1280×720 | 2 | **≈ 3.6 MB** |
| RGBA4444 1280×720 | 1 | **≈ 1.8 MB** |

`framebufferCreate()` takes that out of the process heap. On 2020 firmware that was comfortable.
On HOS 22 it is at or past the ceiling for *all* custom sysmodules combined — so even if it links
and loads, it will be the thing that breaks somebody's sys-clk/sys-con setup. See §5 for the
architectural fix.

### 2.4 The HOS 22.0.0 applet lifespan change

Applications and applets are now expected to exit cleanly via the relevant IPC commands. libnx
homebrew and hbmenu deliberately don't, so Atmosphère 1.11.x ships `am` patches to restore the old
behaviour. Practical consequence for Luxray: **the launcher NRO and the overlay must return from
`main()` normally** — no `exit()`, no `svcExitProcess()`, no infinite loop that is killed by hbmenu.
Don't build on the assumption that the `am` patch will always be there.

---

## 3. Files replaced in this bundle

| File | Change |
|---|---|
| `Makefile` | GCC 16 clean, `-fcommon`, size/GC flags, libnx sanity check, portable `sha256sum`, ships `toolbox.json` |
| `luxray.json` | NPDM rewritten: no duplicate JSON keys, explicit SVC set, current-kernel SVCs added |
| `include/lx_compat.h` | `KEY_*` → `HidNpadButton_*` shim + sysmodule-safe pad reader (header-only, drop-in) |
| `source/lx_sysmodule.c` | Modern sysmodule boilerplate: inner heap, `__appInit`/`__appExit`, `time:s` init |
| `.github/workflows/build.yml` | CI on the official devkitPro container, works around the SSH submodule |
| `toolbox.json` | lets ovlmenu / sysmodule managers toggle Luxray |

---

## 4. Source migration, by grep

Run these from the repo root (include the submodule — `libluxio` is where the input and render
code most likely lives).

### 4.1 HID

```bash
grep -rn "hidScanInput\|hidKeysDown\|hidKeysHeld\|hidKeysUp\|KEY_\|HidControllerID\|CONTROLLER_P1_AUTO\|JoystickPosition\|hidJoystickRead\|touchPosition\|hidTouchRead\|hidTouchCount" source launcher libs
```

| libnx ≤ 3.x | libnx 4.x |
|---|---|
| `hidScanInput()` | `padUpdate(&pad)` (applet) / `lxPadUpdate(&pad)` (sysmodule, see below) |
| `hidKeysHeld(CONTROLLER_P1_AUTO)` | `padGetButtons(&pad)` |
| `hidKeysDown(CONTROLLER_P1_AUTO)` | `padGetButtonsDown(&pad)` |
| `hidKeysUp(...)` | `padGetButtonsUp(&pad)` |
| `KEY_A`, `KEY_ZL`, `KEY_DUP` … | `HidNpadButton_A`, `_ZL`, `_Up` … |
| `KEY_UP` (dpad+sticks) | `HidNpadButton_AnyUp` |
| `HidControllerID` | `HidNpadIdType` |
| `JoystickPosition` + `hidJoystickRead` | `HidAnalogStickState` + `padGetStickPos(&pad, 0)` |
| `touchPosition` + `hidTouchRead` | `HidTouchScreenState` + `hidGetTouchScreenStates()` |

Fastest path: `#include "lx_compat.h"` and keep the `KEY_*` names. It defines them as aliases for
the new enum, so button *constants* need no edits — only the read calls do.

**Important:** `PadState`/`padUpdate` are designed for the applet side. Inside the system module,
where there is no applet resource user ID of your own, read the npad states directly. That's what
`lxPadUpdate()` in `lx_compat.h` does — it dispatches on `hidGetNpadStyleSet()` and ORs together
Handheld / FullKey / JoyDual / JoyLeft / JoyRight, which is the same approach libtesla uses.

For the **overlay** build, the ovlloader runs you as an applet, so plain `padInitializeDefault()`
+ `padUpdate()` is correct there; also call
`hidsysEnableAppletToGetInput(true, <your aruid>)` if you need input while a game is foreground.

### 4.2 Raw IPC — removed in libnx 4.0

```bash
grep -rn "IpcCommand\|ipcInitialize\|ipcPrepareHeader\|ipcParse\|serviceIpcDispatch\|ipcAddSendBuffer\|ipcAddRecvBuffer\|ipcSendHandleCopy" source launcher libs
```

The whole `IpcCommand` layer is gone; libnx 4.x is cmif-based:

```c
/* old */
IpcCommand c; ipcInitialize(&c);
struct { u64 magic; u64 cmd_id; u32 arg; } *raw = ipcPrepareHeader(&c, sizeof(*raw));
raw->cmd_id = 3; raw->arg = value;
Result rc = serviceIpcDispatch(&srv);

/* new */
Result rc = serviceDispatchIn(&srv, 3, value);

/* with an input buffer */
Result rc = serviceDispatchIn(&srv, 3, value,
    .buffer_attrs = { SfBufferAttr_HipcMapAlias | SfBufferAttr_In },
    .buffers      = { { ptr, size } });
```

If Luxray *hosts* a service (launcher ↔ sysmodule control channel), the server side has no libnx
framework: either hand-roll it with `smRegisterService` + `svcAcceptSession` + `svcReplyAndReceive`
+ `hipcParseRequest`, or move the module to libstratosphere. Given the size of this project, a
simpler option is worth considering — a tiny state file on the SD plus a `SystemEvent`, which
removes the custom service entirely.

### 4.3 The launcher (`pmshell`) — guaranteed broken

```bash
grep -rn "pmshellLaunchProcess\|pmshellTerminateProcessByTitleId\|FsStorageId" launcher source
```

```c
/* old (libnx 2.x) */
u64 pid;
Result rc = pmshellLaunchProcess(0, LUXRAY_PROGRAM_ID, FsStorageId_None, &pid);

/* new (libnx 3.0+) */
u64 pid;
const NcmProgramLocation loc = {
    .program_id = LUXRAY_PROGRAM_ID,
    .storageID  = NcmStorageId_None,
};
Result rc = pmshellLaunchProgram(0, &loc, &pid);

/* terminate */
Result rc = pmshellTerminateProgram(LUXRAY_PROGRAM_ID);
```

Also check the launcher's exit path against §2.4 — return from `main()`, let libnx's `__appExit`
run.

### 4.4 Misc renames

```bash
grep -rn "fatalSimple\|kernelAbove\|u128 .*[Uu]ser\|hidsysEnableAppletToGetInput\|hiddbgAttachHdlsWorkBuffer" source launcher libs
```

| old | new |
|---|---|
| `fatalSimple(rc)` | `diagAbortWithResult(rc)` (or `fatalThrow(rc)`) |
| `kernelAbove400()` etc. | `hosversionAtLeast(4,0,0)` — and call `hosversionSet()` in `__appInit` |
| `u128` user IDs | `AccountUid` |
| `hiddbgAttachHdlsWorkBuffer(void)` | `hiddbgAttachHdlsWorkBuffer(HiddbgHdlsSessionId *)` |

`hiddbg` matters only if the roadmap's "game play automation" work got started — the Hdls structs
(`HiddbgHdlsDeviceInfo`, `HiddbgHdlsState`) changed shape as well as the session parameter.

### 4.5 Sysmodule entrypoint

```bash
grep -rn "__libnx_initheap\|__appInit\|__nx_applet_type\|nx_inner_heap" source
```

Replace with `source/lx_sysmodule.c` from this bundle (or merge it into your existing `main.cpp` —
the symbols must have C linkage if the file is C++). Two things in there that are easy to miss:

- `__nx_time_service_type = TimeServiceType_System;` **before** `timeInitialize()`. libnx defaults
  to `time:u`, which is read-only; date advance needs `time:s`. If your date advance quietly stopped
  working after a libnx bump, this is why.
- `hosversionSet()` from `set:sys` during init — several libnx service paths branch on HOS version
  and misbehave when it reads as 0.

### 4.6 LVGL — deliberately *not* upgraded

`libs/libluxio` vendors LVGL from 2020 (v6/v7). LVGL 8 and 9 rewrote the object, style, and
display-buffer APIs wholesale; doing that in the same change as the libnx port would make failures
impossible to bisect. **Keep the pinned LVGL.** The only thing it usually needs under GCC 16 is
`-fcommon` (GCC 10 flipped the default to `-fno-common`, which breaks tentative definitions in old
C headers) — already added to the Makefile. Treat an LVGL upgrade as a separate later branch.

---

## 5. Recommended architecture change

Right now one ELF becomes both the sysmodule and the overlay, so LVGL and the framebuffer live in
the sysmodule. Given §2.3, invert that:

- **Overlay (`.ovl`, runs as an applet under ovlloader): all UI.** That's where memory still exists.
- **Sysmodule: headless logic only** — the date-advance timer loop and the clock write. No LVGL,
  no `vi`, no framebuffer. An inner heap of 256–512 KB is then plenty.

Mechanically: add `-DLUXRAY_SYSMODULE` / `-DLUXRAY_OVERLAY`, guard every `libluxio`/LVGL include
and the `vi` init behind them, and give the sysmodule build its own (much shorter) `SOURCES` list.

If you want to keep rendering from the sysmodule in the short term, at minimum:

1. `PIXEL_FORMAT_RGBA_4444`, not 8888.
2. `viCreateManagedLayer` + `framebufferCreate` **on show**, `framebufferClose` + `viDestroyManagedLayer`
   **on hide** — do not hold the framebuffer while the overlay is invisible.
3. Size the inner heap to measured peak usage, not to a round number.

---

## 6. Release layout (unchanged paths, one addition)

```
sd:/atmosphere/contents/0100000000000195/exefs.nsp
sd:/atmosphere/contents/0100000000000195/toolbox.json      <- new
sd:/atmosphere/contents/0100000000000195/flags/boot2.flag  <- only if you want autostart
sd:/switch/.overlays/luxray.ovl
sd:/switch/Luxray/luxray-launcher.nro
```

`atmosphere/contents/` is already correct (the `atmosphere/titles/` rename happened in AMS 0.10,
before this repo's last commit).

**Program ID audit.** `0x0100000000000195` sits inside Nintendo's reserved system-program range.
It works today and it's what shipped, but the range keeps filling up as firmware adds modules, and
a future collision would be a nasty class of bug. Moving to a clearly-homebrew ID is the safer
long-term call — with the caveat that it breaks every existing install (folder name, launcher
constant, and `toolbox.json` all change), so it belongs in a major version bump with migration
notes, not in this port.

---

## 7. Build

```bash
git clone https://github.com/3096/luxray.git
cd luxray
git config --global url."https://github.com/".insteadOf "git@github.com:"   # .gitmodules uses SSH
git submodule update --init --recursive
make -j"$(nproc)"
make release
```

Fix `.gitmodules` properly while you're in there:

```ini
[submodule "libs/libluxio"]
	path = libs/libluxio
	url = https://github.com/3096/libluxio.git
```

The SSH URL is why the README says "recursive clone with SSH" — it blocks anonymous clones and CI.

---

## 8. Test plan

Order matters; each step isolates one of the four root causes.

1. **Compiles** against current devkitA64/libnx — catches §2.2 and §2.4 mechanically.
2. **Launcher starts the sysmodule.** Watch for `0x...` from `pmshellLaunchProgram`; a launch
   failure with a valid NSP usually means the NPDM was rejected.
3. **Sysmodule survives 5 minutes idle**, then check free memory. Combine with sys-clk or another
   sysmodule installed — the §2.3 ceiling is shared, and testing solo will hide the problem.
4. **Overlay opens over a game** and takes input (§4.1 handheld *and* docked/pro controller —
   the style-set dispatch is exactly where a sysmodule input reader goes wrong).
5. **Date advance actually moves the clock** with "Synchronize Clock via Internet" **off** — if it's
   on, the console re-syncs and silently undoes the write, which looks identical to a broken port.
6. **Clean exit** of launcher and overlay, twice in a row without a reboot (§2.4).
7. Crash reports land in `sd:/atmosphere/crash_reports/` — read them, they name the module now.

---

## 9. Honest risk list

| Risk | Severity | Note |
|---|---|---|
| `libluxio`/LVGL uses removed raw IPC or HID internally | high | can't see the submodule; §4.1/§4.2 greps will tell you in seconds |
| Sysmodule won't fit in the post-21.0.0 memory budget | high | §5 is the real fix, not a tuning exercise |
| Custom IPC server between launcher and sysmodule | medium | needs a rewrite, or replace with a file + event |
| LVGL v6/v7 warnings-as-errors under GCC 16 | low | `-fcommon` covers the common case |
| Program ID collision in Nintendo's range | low, non-zero | §6 |
| Pokémon RNG offsets moved | out of scope | game-version dependent, unrelated to the CFW port |
