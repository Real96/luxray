#!/usr/bin/env bash
#
# package.sh — builds Luxray and assembles the release archive in the EXACT
# layout of the upstream r0.1.0 release:
#
#   atmosphere/contents/0100000000000195/exefs.nsp   (sysmodule, "docked" ID)
#   atmosphere/contents/0100000000000405/exefs.nsp   (same code, "handheld" ID)
#   switch/luxray_launcher.nro                        (pmshell launcher subproject)
#
# The two .nsp are the same compiled code wrapped with two different NPDMs
# (luxray.json -> 0195, luxray_405.json -> 0405). The launcher picks which
# program ID to launch based on docked vs handheld.
#
# Run inside a devkitPro environment, or with no local toolchain:
#   docker run --rm -v "$PWD:/src" -w /src devkitpro/devkita64:latest \
#     bash -lc 'git config --global --add safe.directory /src && ./package.sh'
#
set -euo pipefail

VERSION="${VERSION:-r0.2.0}"
ID_DOCKED="0100000000000195"
ID_HANDHELD="0100000000000405"
LAUNCHER_NRO_NAME="luxray_launcher.nro"   # exact name from the upstream release

DIST="dist"
STAGE="$DIST/.stage"

sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }
say()    { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ -n "${DEVKITPRO:-}" ] || { echo "DEVKITPRO is not set — not in a devkitPro environment."; exit 1; }

say "Toolchain"
aarch64-none-elf-gcc --version | head -n1
grep -rqs "HidNpadButton_A" "$DEVKITPRO/libnx/include" || {
    echo "ERROR: libnx is pre-4.0. Luxray needs >= 4.10.0 for Atmosphere 1.10+ / HOS 21+."
    exit 1
}
command -v npdmtool  >/dev/null || { echo "ERROR: npdmtool not found (dkp-pacman -S switch-tools)"; exit 1; }
command -v build_pfs0 >/dev/null || { echo "ERROR: build_pfs0 not found (dkp-pacman -S switch-tools)"; exit 1; }

say "Submodules"
git config --global url."https://github.com/".insteadOf "git@github.com:" || true
git submodule update --init --recursive

# ---------------------------------------------------------------------------
# Sysmodule, program ID 0100000000000195 (uses luxray.json)
# ---------------------------------------------------------------------------
say "Building sysmodule -> $ID_DOCKED (luxray.json)"
make clean >/dev/null 2>&1 || true
make -j"$(getconf _NPROCESSORS_ONLN)"
[ -f luxray.nsp ] || { echo "luxray.nsp missing — sysmodule build failed."; exit 1; }
mkdir -p "$STAGE/atmosphere/contents/$ID_DOCKED"
cp luxray.nsp "$STAGE/atmosphere/contents/$ID_DOCKED/exefs.nsp"

# ---------------------------------------------------------------------------
# Sysmodule, program ID 0100000000000405 (same code, luxray_405.json)
# Full clean between builds so the NPDM is regenerated cleanly and there is no
# stale-target ambiguity — costs a second compile, buys reliability in CI.
# ---------------------------------------------------------------------------
say "Building sysmodule -> $ID_HANDHELD (luxray_405.json)"
make clean >/dev/null 2>&1 || true
make -j"$(getconf _NPROCESSORS_ONLN)" CONFIG_JSON=luxray_405.json
[ -f luxray.nsp ] || { echo "luxray.nsp missing — 0405 build failed."; exit 1; }
mkdir -p "$STAGE/atmosphere/contents/$ID_HANDHELD"
cp luxray.nsp "$STAGE/atmosphere/contents/$ID_HANDHELD/exefs.nsp"

# ---------------------------------------------------------------------------
# Launcher subproject -> switch/luxray_launcher.nro
# ---------------------------------------------------------------------------
say "Building launcher"
if [ -d launcher ] && [ -f launcher/Makefile ]; then
    make -C launcher clean >/dev/null 2>&1 || true
    make -C launcher -j"$(getconf _NPROCESSORS_ONLN)"
    LAUNCHER_BUILT="$(find launcher -maxdepth 2 -name '*.nro' -print -quit || true)"
    if [ -z "$LAUNCHER_BUILT" ]; then
        echo "ERROR: launcher built but no .nro found — check launcher/Makefile output."
        exit 1
    fi
    mkdir -p "$STAGE/switch"
    cp "$LAUNCHER_BUILT" "$STAGE/switch/$LAUNCHER_NRO_NAME"
else
    echo ""
    echo "  WARNING: no launcher/Makefile found. The release NEEDS the launcher"
    echo "  (switch/$LAUNCHER_NRO_NAME) — without it there is no way to start the"
    echo "  sysmodule short of a boot2 flag. The archive will be built without it;"
    echo "  add the launcher subproject and re-run."
    echo ""
fi

# ---------------------------------------------------------------------------
# Zip, matching the upstream archive's internal structure
# ---------------------------------------------------------------------------
say "Zipping"
ARCHIVE="luxray-$VERSION.zip"
( cd "$STAGE" && zip -r -q "../$ARCHIVE" atmosphere switch 2>/dev/null || zip -r -q "../$ARCHIVE" . )
rm -rf "$STAGE"

say "Contents"
unzip -l "$DIST/$ARCHIVE"

say "Checksum"
( cd "$DIST" && sha256 "$ARCHIVE" )

say "Done -> $DIST/$ARCHIVE"
