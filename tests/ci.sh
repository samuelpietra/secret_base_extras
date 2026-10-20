#!/bin/sh
# Runs the one offline test that needs no ROM — lint — as GitHub Actions does,
# with the system's LÖVE (apt).  render, engine, save and integration read the
# imported ROM's data or the player's save, which never leave the player's
# machine; they run locally with tests/run.sh.
set -eu

TESTS=$(cd "$(dirname "$0")" && pwd)
WORK=${RUNNER_TEMP:-${TMPDIR:-/tmp}}/secret_base_extras-ci
mkdir -p "$WORK"

export SBE_MOD="$(dirname "$TESTS")"
echo "== lint"
love "$TESTS/lint" > "$WORK/lint.log" 2>&1 || true
cat "$WORK/lint.log"
! grep -q -e UNEXPECTED -e "COMPILE ERROR" "$WORK/lint.log" && [ "$(grep -c '	ok$' "$WORK/lint.log")" -eq 7 ]
