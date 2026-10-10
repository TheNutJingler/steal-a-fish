#!/usr/bin/env bash
# verify.sh — run the pre-push verification checklist from the blueprint.
#
#   1. luau-compile syntax check on every .lua file under src/
#   2. called-but-undefined service function checker
#   3. rojo build of the whole project
#
# Run from anywhere:  ~/workspace/steal-a-fish/tools/verify.sh
# Exit code: 0 if everything passes, nonzero otherwise.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LUAU_BIN="$HOME/workspace/bin/luau-bin"
ROJO="$HOME/workspace/bin/rojo"
FAIL=0

echo "== [1/3] luau-compile syntax check =="
BAD=0
while IFS= read -r -d '' f; do
  if ! "$LUAU_BIN/luau-compile" "$f" > /dev/null 2>&1; then
    echo "  SYNTAX ERROR: $f"
    BAD=1
  fi
done < <(find "$REPO/src" -name "*.lua" -print0)
if [ "$BAD" -eq 0 ]; then
  echo "  all .lua files compile OK"
else
  FAIL=1
fi

echo "== [2/3] called-but-undefined checker =="
if python3 "$REPO/tools/check_undefined.py"; then
  :
else
  FAIL=1
fi

echo "== [3/3] rojo build =="
cd "$REPO" || exit 1
if "$ROJO" build -o /tmp/saf-verify.rbxlx > /tmp/saf-verify.log 2>&1; then
  echo "  rojo build OK"
else
  echo "  ROJO BUILD FAILED:"
  tail -20 /tmp/saf-verify.log | sed 's/^/  /'
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "VERIFY: ALL GREEN"
else
  echo "VERIFY: FAILURES ABOVE — do not push"
fi
exit "$FAIL"
