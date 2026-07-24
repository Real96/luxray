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

## The one source edit you still have to make: source/main.cpp

`SocketInitConfig` lost its `.bsdsockets_version` field in libnx 3.x+ (libnx now
picks the BSD protocol version itself from the running firmware). No build-system
shim can add a struct member back, so this is a genuine two-minute edit.

In the `SocketInitConfig` initializer inside `__appInit()`:

1. **Delete** the `.bsdsockets_version = <n>,` line (it's the first designator).
2. **Change** the closing `.sb_efficiency = 1};` to also set the two fields that
   replaced it:

```cpp
        .sb_efficiency    = 1,
        .num_bsd_sessions = 3,
        .bsd_service_type = BsdServiceType_User,
    };
```

Order matters in C++ designated initializers: those two go last, after
`sb_efficiency`, which is where they sit in the struct. Leaving them unset makes
`num_bsd_sessions` default to 0, which is not a valid session count.

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
`fatalSimple`, `kernelAboveX`.

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
