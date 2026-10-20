#!/bin/sh
# Runs the offline tests against the gen1recomp install this mod sits in
# (mods/secret_base_extras/tests -> the install is three levels up).
#
#   lint         every global a mod file touches; a misspelt local shows here
#   render       composes the furniture from the imported ROM into render.png
#   engine       the mod's data hooks on the real engine modules
#   save         a round trip of the real save through the save hooks
#   integration  the in-game paths on stand-ins for the wrapped engine modules
#
# The engine is read from the newest update payload, and the tests run on a
# copy of the app's LÖVE without its game.love, which would otherwise start
# the game instead of the test.  Exits non-zero on a failure.
set -eu

TESTS=$(cd "$(dirname "$0")" && pwd)
MOD=$(dirname "$TESTS")
INSTALL=$(cd "$MOD/../.." && pwd)
WORK=${TMPDIR:-/tmp}/secret_base_extras-tests
PAYLOAD=$(ls -t "$HOME/Library/Application Support/pokemon-love2d/updates/"gen1recomp-*.love 2>/dev/null | head -1 || true)
[ -n "$PAYLOAD" ] || PAYLOAD="$INSTALL/gen1recomp.app/Contents/Resources/game.love"

mkdir -p "$WORK"
# macOS empties old files under $TMPDIR, so the extracted engine is checked too
if [ ! -f "$WORK/engine/main.lua" ] || [ "$(cat "$WORK/engine.from" 2>/dev/null)" != "$PAYLOAD" ]; then
  rm -rf "$WORK/engine" && mkdir -p "$WORK/engine"
  unzip -q -o "$PAYLOAD" -d "$WORK/engine"
  echo "$PAYLOAD" > "$WORK/engine.from"
fi
if [ ! -x "$WORK/love.app/Contents/MacOS/love" ]; then
  rm -rf "$WORK/love.app"
  cp -R "$INSTALL/gen1recomp.app" "$WORK/love.app"
  rm -f "$WORK/love.app/Contents/Resources/game.love"
fi

export SBE_MOD="$MOD" SBE_INSTALL="$INSTALL" SBE_ENGINE="$WORK/engine" SBE_WORK="$WORK"
for test in lint render engine save integration; do
  echo "== $test"
  "$WORK/love.app/Contents/MacOS/love" "$TESTS/$test" > "$WORK/$test.log" 2>&1 &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
  kill "$pid" 2>/dev/null || true
  cat "$WORK/$test.log"
done
failed=0
[ "$(grep -c '	ok$' "$WORK/lint.log")" -eq 7 ] || failed=1
grep -qx "OK slots	35" "$WORK/render.log" || failed=1
for test in engine save integration; do grep -qx "ALL PASS" "$WORK/$test.log" || failed=1; done
exit "$failed"
