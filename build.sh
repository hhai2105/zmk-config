#!/usr/bin/env bash
# Build the firmware locally with the same Docker image GitHub Actions uses.
#
#   ./build.sh              build both halves
#   ./build.sh left         build one half
#   CLEAN=1 ./build.sh      full rebuild from scratch
#   LOG=1 ./build.sh left   debug build that logs over USB serial
#   KEYMAP=path/to/other.keymap ./build.sh left   use another keymap
#
# The ZMK/Zephyr checkout lives in .zmk/ (kept out of the repo root so it
# doesn't collide with zephyr/module.yml). Output goes to firmware/.
set -euo pipefail

cd "$(dirname "$0")"
REPO=$PWD
WS=.zmk
IMAGE=zmkfirmware/zmk-build-arm:stable
BOARD=nice_nano//zmk

[ $# -eq 0 ] && set -- left right

run() {
    docker run --rm \
        -v "$REPO":/repo -w "/repo/$WS" \
        -u "$(id -u):$(id -g)" -e HOME="/repo/$WS/.home" \
        "$IMAGE" sh -c "$1"
}

mkdir -p "$WS/config" "$WS/.home" firmware

# Re-fetch dependencies on first run or whenever config/west.yml changes.
need_update=0
if ! cmp -s config/west.yml "$WS/config/west.yml"; then
    cp config/west.yml "$WS/config/west.yml"
    need_update=1
fi
if [ ! -d "$WS/.west" ]; then
    run "west init -l config"
    need_update=1
fi
if [ "$need_update" -eq 1 ]; then
    run "west update && west zephyr-export"
fi

pristine=auto
[ "${CLEAN:-0}" = 1 ] && pristine=always

snippet= suffix=
if [ "${LOG:-0}" = 1 ]; then
    snippet="-S zmk-usb-logging"
    suffix=-log
fi

keymap=
if [ -n "${KEYMAP:-}" ]; then
    keymap="-DKEYMAP_FILE=/repo/$KEYMAP"
    suffix="$suffix-$(basename "$KEYMAP" .keymap)"
fi

for side in "$@"; do
    echo "==> building dactyl_$side$suffix"
    run "west build -p $pristine -s zmk/app -d build/$side$suffix -b $BOARD $snippet -- \
        -DSHIELD=dactyl_$side \
        -DZMK_CONFIG=/repo/config \
        -DZMK_EXTRA_MODULES=/repo $keymap"
    cp "$WS/build/$side$suffix/zephyr/zmk.uf2" "firmware/dactyl_$side-nice_nano-zmk$suffix.uf2"
done

echo "==> done:"
ls -1 firmware/*.uf2
