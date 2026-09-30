#!/usr/bin/env bash
#
# A long-running agent that is not an agent.
#
# It reaches no model, so a run of it costs nothing and takes exactly as long as
# it is told to. What it does do is everything the control plane watches for:
# it occupies a sandbox for minutes at a time, writes and commits a growing tree
# so a checkpoint bundle has something to photograph, prints progress so a run
# reads as alive rather than wedged, and fails on command.
#
# Every flag is required. A simulation whose parameters are half implicit is a
# simulation nobody can read off the pipeline that started it.
#
#   --label NAME        subdirectory of work/ this invocation writes into, so
#                       concurrent nodes sharing a forked tree do not collide
#   --steps N           how many steps to take
#   --step-seconds S    how long each one takes
#   --fail-at K|none    exit non-zero at the start of step K
#   --exit-code C       the code to exit with when --fail-at fires
#   --on-term stop|ignore
#                       whether SIGTERM and SIGINT end it. `ignore` is the
#                       interesting one: it is what proves that killing the
#                       local `sandbox exec` client does not stop the remote
#                       process, and that deleting the sandbox does.

set -u -o pipefail

label=
steps=
step_seconds=
fail_at=
exit_code=
on_term=

while [ $# -gt 0 ]; do
  case "$1" in
    --label)        label=$2;        shift 2 ;;
    --steps)        steps=$2;        shift 2 ;;
    --step-seconds) step_seconds=$2; shift 2 ;;
    --fail-at)      fail_at=$2;      shift 2 ;;
    --exit-code)    exit_code=$2;    shift 2 ;;
    --on-term)      on_term=$2;      shift 2 ;;
    *) echo "treadmill: unknown argument: $1" >&2; exit 64 ;;
  esac
done

for required in label steps step_seconds fail_at exit_code on_term; do
  if [ -z "${!required}" ]; then
    echo "treadmill: --${required//_/-} is required" >&2
    exit 64
  fi
done

# Every numeric flag is checked before anything sleeps or commits. Without this
# a non-numeric `--steps` reaches `[ "$step" -le "$steps" ]`, which bash reports
# as `integer expression expected` on stderr and then treats as false — so the
# script exits 0 having taken no steps, and a pipeline that asked for a
# ten-minute node gets a node that succeeded in a second. A simulation that
# lies about what it did is worse than one that refuses.
numeric() {
  case "$2" in
    '' | *[!0-9]*)
      echo "treadmill: --$1 takes a non-negative whole number, not '$2'" >&2
      exit 64
      ;;
  esac
}
numeric steps "$steps"
numeric step-seconds "$step_seconds"
numeric exit-code "$exit_code"
# `--fail-at` is the one that takes a word as well, and only this one.
if [ "$fail_at" != none ]; then
  numeric fail-at "$fail_at"
fi
if [ "$exit_code" -gt 255 ]; then
  echo "treadmill: --exit-code $exit_code is outside 0-255" >&2
  exit 64
fi

case "$on_term" in
  stop) ;;
  ignore)
    trap '' TERM INT
    echo "treadmill: ignoring SIGTERM and SIGINT; delete the sandbox to stop me"
    ;;
  *) echo "treadmill: --on-term takes stop or ignore, not $on_term" >&2; exit 64 ;;
esac

dir="work/$label"
mkdir -p "$dir"

commit() {
  git -c user.name=treadmill -c user.email=treadmill@invalid \
    add -A -- "$dir" >/dev/null 2>&1 || return 0
  git -c user.name=treadmill -c user.email=treadmill@invalid \
    commit -q -m "$1" >/dev/null 2>&1 || return 0
}

started=$(date +%s)
echo "treadmill: $label, $steps steps of ${step_seconds}s, failing at ${fail_at}, ${on_term} on TERM"

step=1
while [ "$step" -le "$steps" ]; do
  if [ "$fail_at" != none ] && [ "$step" -eq "$fail_at" ]; then
    echo "treadmill: $label failing at step $step as instructed"
    exit "$exit_code"
  fi

  sleep "$step_seconds"

  printf '# %s step %03d\n\nreached at %s\n' \
    "$label" "$step" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$dir/step-$(printf '%03d' "$step").md"
  commit "$label: step $step of $steps"

  elapsed=$(( $(date +%s) - started ))
  echo "treadmill: $label step $step/$steps done, ${elapsed}s elapsed"
  step=$(( step + 1 ))
done

echo "treadmill: $label finished $steps steps in $(( $(date +%s) - started ))s"
