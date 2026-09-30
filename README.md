# treadmill

A workspace whose only inhabitant is a shell script that takes a long time on
purpose. It reaches no model, so it costs nothing and its runtime is a number
you chose rather than a number a model happened to need.

```sh
cp -r examples/fixtures/treadmill ~/code/treadmill
cd ~/code/treadmill && git init && git add -A && git commit -m "treadmill"
bash treadmill.sh --label smoke --steps 3 --step-seconds 1 \
  --fail-at none --exit-code 1 --on-term stop
```

`examples/pipelines/testing/simulate-*.yaml` name `~/code/treadmill`. A different path
is fine; change `workspace:` to match.

## What it is for

The control plane is the thing under test — the scheduler, the pause latch,
cancellation, retries, timeouts, checkpoints, resume. A real agent exercises all
of that too, but it also introduces the two things a test does not want: money,
and variance. A run that lasted nine minutes because a model rambled is not a
measurement.

So this script does what a long-running agent does, minus the thinking:

- **It occupies a sandbox for as long as it is told.** `--steps` × `--step-seconds`
  is the node's wall-clock, near enough.
- **It writes and commits a growing tree.** Each step leaves a file under
  `work/<label>/` and commits it, so `git::write_checkpoint_bundle` has something
  to photograph, a node's patch is non-empty, and a resumed node can be seen to
  start where the frozen one stopped.
- **It prints progress.** A node that prints nothing for ten minutes is
  indistinguishable from a wedged one, and half of what you want to watch is the
  UI staying honest about a run that is alive.
- **It fails on command.** `--fail-at K --exit-code C` ends attempt after attempt
  at the same step, which is what makes `retries:` observable.
- **It can refuse to die.** `--on-term ignore` traps SIGTERM and SIGINT. Killing
  the local `sandbox exec` client leaves it running on the driver; deleting the
  sandbox is what stops it. That is the invariant in `CLAUDE.md`, executable.

## Every flag is required

There are no defaults. A simulation whose parameters are half implicit is one
nobody can read off the pipeline that started it — and the whole value here is
that the pipeline file says exactly how long the run will take and how it will
end.

| Flag | |
| --- | --- |
| `--label NAME` | the subdirectory of `work/` this invocation writes into, so concurrent nodes forked from one tree do not collide |
| `--steps N` | how many steps to take |
| `--step-seconds S` | how long each one takes |
| `--fail-at K\|none` | exit non-zero at the start of step K |
| `--exit-code C` | the code to exit with when `--fail-at` fires |
| `--on-term stop\|ignore` | whether SIGTERM and SIGINT end it |

## What it cannot test

`[harnesses.shell]` declares no `wire_format`, so a shell node has no
`inference` rule rendered for it and reaches no relay. No relay exchange means
no priced record, which means **`max_cost_usd` is not observable here at all** —
the meter tails a file that stays empty. The budget brake is tested by
`examples/pipelines/default/long-running-depot.yaml`, against a real harness and a
price override. Nothing on this treadmill will ever fire it.
