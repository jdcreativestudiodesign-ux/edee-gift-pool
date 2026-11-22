#!/usr/bin/env bash
# Proves the tests catch real mistakes: plants one deliberate bug at a time in a throwaway copy of the
# project and checks that `forge test` FAILS. Your working copy is never touched.
# Usage: ./negative-controls.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G=src/EdeeGiftPool.sol
B=src/BusinessDays.sol
caught=0
survived=0
broken=0

# control <file> <exact text> <planted bug> <what it breaks>
control() {
  local file="$1" find="$2" plant="$3" what="$4" tmp
  tmp="$(mktemp -d)"
  cp -r "$HERE/src" "$HERE/test" "$HERE/review" "$HERE/foundry.toml" "$tmp/"
  ln -s "$HERE/lib" "$tmp/lib"
  if ! python3 - "$tmp/$file" "$find" "$plant" <<'PY'
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
if a not in s:
    sys.exit(1)
open(p, "w").write(s.replace(a, b, 1))
PY
  then
    echo "STOP: control text not found in $file: $find"
    exit 1
  fi
  if (cd "$tmp" && forge test > out.log 2>&1); then
    echo "SURVIVED  $what"
    survived=$((survived + 1))
  elif grep -qE '[0-9]+ tests passed, [1-9][0-9]* failed' "$tmp/out.log"; then
    echo "CAUGHT    $what  ($(grep -oE '[0-9]+ tests passed, [0-9]+ failed' "$tmp/out.log" | tail -1))"
    caught=$((caught + 1))
  else
    # forge failed without any test failing (no compiler, no network, a build error): proves nothing.
    echo "BROKEN    $what  (the test run did not complete; last lines below)"
    tail -5 "$tmp/out.log"
    broken=$((broken + 1))
  fi
  rm -rf "$tmp"
}

# Baseline: the unchanged project must pass, or every "caught" below would be meaningless.
tmp="$(mktemp -d)"; cp -r "$HERE/src" "$HERE/test" "$HERE/review" "$HERE/foundry.toml" "$tmp/"; ln -s "$HERE/lib" "$tmp/lib"
if ! (cd "$tmp" && forge test > out.log 2>&1); then
  echo "STOP: the unchanged project does not pass its tests:"; tail -10 "$tmp/out.log"; exit 1
fi
echo "BASELINE  unchanged project passes ($(grep -oE '[0-9]+ tests passed' "$tmp/out.log" | tail -1))"
rm -rf "$tmp"

control "$G" "contributionOf[msg.sender] = 0; // zero first" "// (moved)" \
  "refund re-entry protection weakened (balance not zeroed)"
control "$G" "return totalRaised < GOAL || block.timestamp >= SAFETY_NET_AT;" "return totalRaised < GOAL;" \
  "safety net never opens refunds"
control "$G" "if (block.timestamp >= SAFETY_NET_AT) revert SafetyNetOpen();" "" \
  "release still allowed after the safety net opens"
control "$G" "if (msg.sender != ORGANISER && block.timestamp < DEADLINE)" \
  "if (msg.sender != ORGANISER || block.timestamp < DEADLINE)" "wrong rule for who may release"
control "$G" "if (block.timestamp >= DEADLINE) revert DeadlinePassed();" \
  "if (block.timestamp > DEADLINE) revert DeadlinePassed();" "contributions accepted at the closing second"
control "$G" "received = TOKEN.balanceOf(address(this)) - before;" "received = amount;" \
  "fee-charging tokens inflate the total"
control "$G" $'if (msg.sender != ORGANISER) revert NotOrganiser();\n        if (status != Status.Open) revert NotOpen();\n        status = Status.Cancelled;' \
  $'if (status != Status.Open) revert NotOpen();\n        status = Status.Cancelled;' "anyone can call the gift off"
control "$G" "return totalRaised < GOAL || block.timestamp >= SAFETY_NET_AT;" \
  "return totalRaised <= GOAL || block.timestamp >= SAFETY_NET_AT;" "refunds open when the goal is met exactly"
control "$G" "uint256 public constant SAFETY_NET_BUSINESS_DAYS = 5;" \
  "uint256 public constant SAFETY_NET_BUSINESS_DAYS = 4;" "safety net opens a day early"
control "$B" "if (dayOfWeek(result) < 5) {" "if (dayOfWeek(result) <= 5) {" "Saturdays counted as business days"

echo "NEGATIVE CONTROLS: $caught caught, $survived survived, $broken broken"
[ "$survived" -eq 0 ] && [ "$broken" -eq 0 ]
