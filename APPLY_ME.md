# Apply this to your fork

## Read this first — do not replace every file

This archive is an **overlay**, not a complete repository. It contains the files
I could rewrite safely. It does **not** contain, and cannot contain:

- `source/` — the actual Luxray application code
- `launcher/` — the launcher NRO project
- `libs/libluxio` — the submodule (LVGL, rendering, IO)
- `docs/`, `LICENSE`, `.gitignore`

GitHub blocks automated directory listings, so I was never able to read those.
If you delete your fork's files and drop this in, you will have deleted the
program and kept the build system. **Extract this over the top of your fork and
let it overwrite only what it touches.**

## What's in here

| File | Status |
|---|---|
| `Makefile` | replaces the root one |
| `luxray.json` | replaces the NPDM descriptor |
| `.gitmodules` | replaces (SSH → https, so CI can fetch the submodule) |
| `toolbox.json` | new |
| `package.sh` | new |
| `include/lx_compat.h` | new |
| `source/lx_compat.c` | new |
| `source/lx_sysmodule.c` | new, inert until you define `LUXRAY_NEW_INIT` |
| `.github/workflows/build.yml` | new — builds on every push |
| `.github/workflows/release.yml` | new — builds and attaches zips when you push a tag |

Nothing here deletes or rewrites a line of your application code.

## Steps

```bash
# 1. fork on github, then
git clone https://github.com/<you>/luxray.git
cd luxray

# 2. extract this archive over the working tree
unzip -o ~/Downloads/luxray-port-2026.zip

# 3. the submodule now fetches over https
git submodule sync --recursive
git submodule update --init --recursive

# 4. one manual edit: launcher/Makefile
#    I don't have that file, so add this line next to its CFLAGS definition:
#        CFLAGS += -include $(TOPDIR)/../include/lx_compat.h
#    That gives the launcher the pmshellLaunchProcess shim. If the launcher
#    also reads controller input, copy source/lx_compat.c into its source dir.

# 5. commit and push
git add -A
git commit -m "port to Atmosphere 1.11.x / HOS 22.x, libnx 4.10+"
git push

# 6. Actions tab -> watch the build. For release zips:
git tag r0.2.0 && git push origin r0.2.0
```

## Socket init (main.cpp) — now handled for you, no edit needed

Earlier this needed a hand-edit: current libnx removed `SocketInitConfig::bsdsockets_version`
(the BSD protocol version is auto-selected from firmware now) and added
`num_bsd_sessions` + `bsd_service_type`, so the 2020-era initializer that sets
`.bsdsockets_version` wouldn't compile.

The shim now absorbs this. `include/lx_compat.h` defines a drop-in config type
that still carries `.bsdsockets_version` and a wrapper that maps it onto the real
libnx call, filling in `num_bsd_sessions = 3` and `bsd_service_type = User` when
your initializer leaves them unset. Two `#define`s point the source's
`SocketInitConfig` / `socketInitialize` at the shim. `socketInitializeDefault()`
and `socketExit()` are deliberately left alone.

You don't need to touch `main.cpp`. If you ever want the real type back (e.g.
after porting the call site by hand), build with `-DLX_NO_SOCKET_SHIM` or set
`COMPAT_SHIM=0`.

## Getting the release zip (matches the upstream r0.1.0 layout exactly)

The upstream release archive is not one sysmodule — it is three files:

```
atmosphere/contents/0100000000000195/exefs.nsp   sysmodule, "docked" program ID
atmosphere/contents/0100000000000405/exefs.nsp   same code, "handheld" program ID
switch/luxray_launcher.nro                        pmshell launcher (separate subproject)
```

Both `.nsp` are the same compiled code wrapped with different NPDMs
(`luxray.json` -> 0195, `luxray_405.json` -> 0405). The launcher offers "Launch
docked mode" / "Launch handheld mode" and pmshell-launches the matching ID — the
LVGL overlay needs a framebuffer sized to the display, hence two variants.

`package.sh` reproduces this exactly: it builds the sysmodule twice (once per
NPDM), builds `launcher/`, and zips the three files into the upstream layout. You
do not run it locally — CI does:

- **Every push:** `build.yml` runs `package.sh` and uploads `dist/luxray-ci-<sha>.zip`
  as an artifact. Download it from the Actions run.
- **Tagged release:** `git tag r0.2.0 && git push origin r0.2.0` runs `release.yml`,
  which attaches `luxray-r0.2.0.zip` to the GitHub release.

The archive name differs (`luxray-r0.2.0.zip`), but unzip it and the internal
structure is byte-for-byte the same paths as `luxray-r0.1.0-0.zip`.

## The launcher must build too — one line in launcher/Makefile

Your first green build only compiled the sysmodule (`source/` + `libluxio`). The
launcher is a separate subproject that CI wasn't building, and `package.sh` now
does. It uses the same removed-in-libnx-4.x calls (`pmshellLaunchProcess`,
`pmshellTerminateProcessByTitleId`), so it needs the same shim. Add this next to
the `CFLAGS` definition in **`launcher/Makefile`**:

```make
CFLAGS += -include $(TOPDIR)/../include/lx_compat.h
```

(Adjust the `../` depth if `launcher/`'s Makefile computes `TOPDIR` differently —
the target is `include/lx_compat.h` at the repo root.) If the launcher's first
build surfaces its own libnx errors, paste them — it's console/pmshell code, so
likely small.

## The trick that makes this build without touching your source

`Makefile` force-includes `include/lx_compat.h` into every translation unit
(`COMPAT_SHIM=1`, on by default). So existing code like

```c
hidScanInput();
if (hidKeysDown(CONTROLLER_P1_AUTO) & KEY_A) { ... }
```

compiles and runs against libnx 4.x unmodified — the shim routes it onto the
npad API, reading shared memory directly so it also works from inside the
system module, where `padUpdate()` would read as permanently idle.

Covered: `KEY_*`, `HidControllerID`, `CONTROLLER_*`, `hidScanInput`,
`hidKeysDown/Held/Up`, `JoystickPosition`, `hidJoystickRead`, `touchPosition`,
`hidTouchRead`, `hidTouchCount`, `pmshellLaunchProcess`, `FsStorageId_*`,
`fatalSimple`, `kernelAboveX`, `ApmPerformanceMode_Docked/_Handheld` (the libnx
4.0 rename to `_Boost`/`_Normal`), and `SocketInitConfig` / `socketInitialize`
(the `.bsdsockets_version` removal).

This is scaffolding. It gets you a green build now; port the call sites properly
later, then build with `COMPAT_SHIM=0` and delete the header.

## What the shim does not cover

If the build still fails, it will almost certainly be one of these — all three
live in code I couldn't read:

1. **Raw IPC.** `IpcCommand`, `ipcInitialize`, `ipcPrepareHeader`,
   `serviceIpcDispatch` were deleted in libnx 4.0 with no drop-in replacement.
   They map onto `serviceDispatch*`. See MIGRATION.md §4.2.
2. **A custom IPC server** between the launcher and the sysmodule, if one
   exists. Needs a real rewrite.
3. **LVGL** doing something GCC 16 rejects beyond what `-fcommon` covers.

Paste the failing compiler output and I'll work through it with you.

## Expectation setting

A green build is not a working build. The memory problem in MIGRATION.md §2.3
is a runtime issue: HOS 20 cut the sysmodule pool from 40 MB to 14 MB and HOS 21
took ~10 MB more, while this sysmodule carries LVGL and a framebuffer. It may
link fine and then fail to launch, or launch and starve whatever else the user
has installed. Test with another sysmodule present, not solo.
