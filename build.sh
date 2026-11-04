#!/usr/bin/env bash
# Build the firmware locally with the same Docker image GitHub Actions uses.
#
#   ./build.sh              build both halves
#   ./build.sh left         build one half
#   CLEAN=1 ./build.sh      full rebuild from scratch
#
# The ZMK/Zephyr checkout lives in .zmk/ (kept out of the repo root so it
# doesn't collide with zephyr/module.yml). Output goes to firmware/.
set -euo pipefail

cd "$(dirname "$0")"
REPO=$PWD
WS=.zmk
IMAGE=zmkfirmware/zmk-build-arm:stable
BOARD=nice_nano_v2

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

for side in "$@"; do
    echo "==> building dactyl_$side"
    run "west build -p $pristine -s zmk/app -d build/$side -b $BOARD -- \
        -DSHIELD=dactyl_$side \
        -DZMK_CONFIG=/repo/config \
        -DZMK_EXTRA_MODULES=/repo"
    cp "$WS/build/$side/zephyr/zmk.uf2" "firmware/dactyl_$side-$BOARD-zmk.uf2"
done

echo "==> done:"
ls -1 firmware/*.uf2
