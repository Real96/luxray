#!/usr/bin/env bash
#
# package.sh — builds Luxray and assembles the two release archives, in the
# same layout as the r0.1.0 assets.
#
# Produces:
#   dist/luxray-<VERSION>.zip
#       LICENSE
#       atmosphere/contents/0100000000000195/exefs.nsp
#       atmosphere/contents/0100000000000195/toolbox.json
#       atmosphere/contents/0100000000000195/flags/boot2.flag   (BOOT2=1 only)
#       switch/<LAUNCHER_DIR>/<LAUNCHER_NRO>                    (if launcher/ builds)
#
#   dist/luxray-<VERSION>-ovlloader.zip
#       LICENSE
#       switch/.overlays/luxray.ovl
#
# Run inside a devkitPro environment, or with no local toolchain at all:
#
#   docker run --rm -v "$PWD:/src" -w /src devkitpro/devkita64:latest \
#     bash -lc 'git config --global --add safe.directory /src && ./package.sh'
#
set -euo pipefail

VERSION="${VERSION:-r0.2.0}"
TITLE_ID="${TITLE_ID:-0100000000000195}"
BOOT2="${BOOT2:-0}"

# Match whatever path your existing 0.1.0 archive used — unzip the old release
# and mirror it, so users upgrading in place don't end up with two launchers.
LAUNCHER_DIR="${LAUNCHER_DIR:-luxray}"
LAUNCHER_NRO="${LAUNCHER_NRO:-luxray-launcher.nro}"

DIST="dist"
STAGE_SYS="$DIST/.stage-sys"
STAGE_OVL="$DIST/.stage-ovl"

sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }
say()    { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ -n "${DEVKITPRO:-}" ] || { echo "DEVKITPRO is not set — not in a devkitPro environment."; exit 1; }

say "Toolchain"
aarch64-none-elf-gcc --version | head -n1
grep -rqs "HidNpadButton_A" "$DEVKITPRO/libnx/include" || {
    echo "ERROR: libnx is pre-4.0. Luxray needs >= 4.10.0 for Atmosphere 1.10+ / HOS 21+."
    echo "Run: dkp-pacman -Syu switch-dev switch-tools"
    exit 1
}

say "Submodules"
git config --global url."https://github.com/".insteadOf "git@github.com:" || true
git submodule update --init --recursive

say "Building sysmodule + overlay"
make clean >/dev/null 2>&1 || true
make -j"$(getconf _NPROCESSORS_ONLN)"

[ -f luxray.nsp ] || { echo "luxray.nsp missing — the sysmodule build failed."; exit 1; }
[ -f luxray.nro ] || { echo "luxray.nro missing — the overlay build failed."; exit 1; }

say "Building launcher"
if [ -d launcher ] && [ -f launcher/Makefile ]; then
    make -C launcher -j"$(getconf _NPROCESSORS_ONLN)"
    LAUNCHER_BUILT="$(find launcher -maxdepth 2 -name '*.nro' -print -quit || true)"
else
    LAUNCHER_BUILT=""
    echo "no launcher/Makefile — skipping (the sysmodule then needs boot2.flag to start)"
fi

say "Staging"
rm -rf "$STAGE_SYS" "$STAGE_OVL"
mkdir -p "$STAGE_SYS/atmosphere/contents/$TITLE_ID"
mkdir -p "$STAGE_OVL/switch/.overlays"

cp luxray.nsp "$STAGE_SYS/atmosphere/contents/$TITLE_ID/exefs.nsp"
[ -f toolbox.json ] && cp toolbox.json "$STAGE_SYS/atmosphere/contents/$TITLE_ID/"
cp LICENSE "$STAGE_SYS/"

if [ "$BOOT2" = "1" ]; then
    mkdir -p "$STAGE_SYS/atmosphere/contents/$TITLE_ID/flags"
    : > "$STAGE_SYS/atmosphere/contents/$TITLE_ID/flags/boot2.flag"
fi

if [ -n "$LAUNCHER_BUILT" ]; then
    mkdir -p "$STAGE_SYS/switch/$LAUNCHER_DIR"
    cp "$LAUNCHER_BUILT" "$STAGE_SYS/switch/$LAUNCHER_DIR/$LAUNCHER_NRO"
fi

cp luxray.nro "$STAGE_OVL/switch/.overlays/luxray.ovl"
cp LICENSE "$STAGE_OVL/"

say "Zipping"
( cd "$STAGE_SYS" && zip -r -q "../luxray-$VERSION.zip" . )
( cd "$STAGE_OVL" && zip -r -q "../luxray-$VERSION-ovlloader.zip" . )
rm -rf "$STAGE_SYS" "$STAGE_OVL"

say "Contents"
unzip -l "$DIST/luxray-$VERSION.zip"
unzip -l "$DIST/luxray-$VERSION-ovlloader.zip"

say "Checksums (paste into the release notes)"
( cd "$DIST" && sha256 "luxray-$VERSION.zip" "luxray-$VERSION-ovlloader.zip" )
