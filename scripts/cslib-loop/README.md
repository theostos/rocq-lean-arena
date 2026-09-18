# cslib compile / repair loop

Archived workflow: `start` and `worker` are disabled. Use
[manual checking from line 1](../../docs/cslib-manual-method.md), without
checkpoint reuse or automatic repairs. The instructions below are historical.

A local supervisor waits for compilation to finish. It invokes **GPT-6 Astra,
extra-high reasoning** only after a declaration-checking failure. No model
requests are made during the full compilation or the supervisor's validation
suite. Repairs and their context still consume normal Codex usage.

```sh
python3 scripts/cslib_loop.py start --repair-access full
python3 scripts/cslib_loop.py status
python3 scripts/cslib_loop.py pause
python3 scripts/cslib_loop.py stop
```

To retry a diagnosed failure after changing the repair policy, without replaying
the full failed compilation:

```sh
python3 scripts/cslib_loop.py start --retry-repair --repair-access full
```

This resumes the previous dedicated Astra session with the stored failure.

If the repair is already installed and reviewed, but validation was blocked by
a harness or resource problem, fix that problem and retry the gate locally:

```sh
python3 scripts/cslib_loop.py start --retry-validation --repair-access full
```

This makes no model call and preserves the repair count and original agent
result, including a `blocked` result. It pins the installed candidate, reruns
the complete validation gate and resumes compilation only on success. A changed
importer/foundation starts a fresh checkpoint chain; old checkpoints are not
relabelled. Do not use this option for an unfinished importer/kernel repair.

`start` adopts the active `rocq-cslib-15m-*` service, if present; otherwise it
runs the chunked continuation from the newest valid checkpoint. The original
15M checkpoint is the seed. Historical launch scripts and producer seals are
unchanged. Do not start a manual continuation while the loop is active.

Full repair access was authorized for this local experiment. Without that
authorization, use the default workspace sandbox and expect a pause if the
repair needs unavailable systemd access.

`pause` prevents the next phase from starting; an owned chunk (including its
save/reload) or repair already in progress finishes first. While waiting on an adopted run, it leaves
that run immediately (within the 15-second local polling interval).
`stop` cancels the supervisor and jobs it owns. **Neither command kills a run
that was already running before adoption.** Existing guards/checkpoints remain
responsible for safe cleanup and atomic saves.

## Control flow

Compile -> on declaration failure, repair -> fixed regression/checkpoint gates
-> compile again. Stop after a verified full continuation, save and fresh reload.

- One loop lock; existing launcher/global heavyweight locks and memory guards.
- Original 16 GiB hard limit, 15 GiB RSS, 3 GiB reserve and no workload swap.
- Default maximum **3 repair turns**, **2 hours per repair**, 1 hour per fixed
  validation suite. A second failure on the same declaration pauses the loop.
  Limits are adjustable explicitly with `start --max-repairs N --repair-seconds N`.
  These are turn/time limits, not a precise token or subscription-credit cap.
- No automatic retry on resource refusals, signals, checkpoint/provenance
  errors, authentication/model errors, invalid agent output or failed validation.
- The agent uses the CLI's existing ChatGPT login, no approval escalation,
  and network access. By default it uses the workspace-write sandbox. This
  host's sandbox cannot access the user systemd bus required by the memory
  guard. **Only with explicit authorization**, `start --repair-access full`
  gives the agent unrestricted local access, like the interactive session.
  Resource guards remain enforced; this is not filesystem isolation.
  API-key environment variables
  are removed. No model fallback, API billing setup or account-config edits.
- A dedicated CLI session is resumed by its exact ID across repairs. This is
  separate from the conversation that installed the loop.
- Repair instructions forbid proof rewrites, new axioms, weakening checks,
  memory-limit changes, unguarded heavy jobs and automatic publication.
- Before/after hashes protect the control scripts and historical checkpoints.
  Fixed validation checks the pinned toolchain, 45 regression checks, the
  checkpoint-runner/chunk-planner unit tests and the unchanged 15M checkpoint reload.
  This is a regression gate, not a soundness proof or a security boundary
  against an agent deliberately modifying its own workspace.
- Importer/foundation fixes are allowed. The agent tests them and reports
  `checkpoint_action: restart` when they change the stored representation.
  It builds a changed foundation in a new directory, preserving the old one.
  The supervisor also compares importer/foundation identities: a changed
  representation forces a fresh chain even if the agent requested reuse.

## Repair versus waiting

The agent may build, run the original failing declaration and run regression
suites, including broader tests when useful. It must check its own fix before
reporting success. It must not launch or watch the full-library pass or sit in
a monitoring loop. After its result is returned, its process exits.

The Python supervisor then performs independent validation, checkpoint work
and compilation. None of these phases invokes a model. A new agent turn is
started only for another actionable declaration failure, within the repair
budget. Resource errors and failed validation pause rather than invoking an
agent repeatedly.

## Representation changes

A restart creates a separate generation under the repair directory:
`generation/{toolchain.json,foundation,full,smoke}`. The new chain starts at line
1 and checkpoints every 2M lines. Old `.vo` files, plans and producer seals are
not rewritten, deleted or used by that chain. Its manifest binds the new
importer, frozen foundation, supporting Rocq libraries and checking scripts.

Before starting it, the supervisor reruns the 45 existing regression cases,
their six dependency prefixes and seven source-comparison checks, all in a
fresh directory with the new foundation. Relative `Load` sources are staged
and hashed too. It never loads old regression `.vo` files. The three-chunk
save/reload smoke test follows. Failure in either gate prevents the full run.

The same fresh regression harness is available to the agent during repair:

```sh
python3 scripts/checkpoint_generation.py \
  --foundation /absolute/path/under/work/Lean.vo \
  --directory /absolute/new/path/under/work/regressions
```

Each compiler runs through the existing memory guard. This does not create or
monitor a full-library checkpoint chain. Kernel-only migrations of a generation
remain possible after a tested handoff; importer/foundation hashes must match.
These are compatibility/regression gates, not a soundness result.

## Every 2M lines

The original seeded plan is `work/library-checkpoints/cslib/plan.json`:

```text
15,001,015 (existing seed)
 -> 17,001,015 -> 19,001,015 -> 21,001,015 -> 22,828,731 (EOF)
```

After a representation restart, `state.json` identifies the new active plan.
`status` follows that plan and its progress, not the historical 15M cursor.

Each chunk saves a separate sealed `.vo`, then reloads it in a fresh process.
An empty import also forces the packed importer state to unpack. Only after
that succeeds is `progress.json` advanced. Intervals are end-exclusive,
contiguous and avoid splitting a pending mutual-inductive block.

Resume verifies the existing chain and reloads its newest checkpoint; already
saved chunks are not recompiled. Corrupt/unsealed checkpoints fail closed.
A kernel-only migration records old/new worker hashes without rewriting old
seals; all other proof inputs still have to match and the current worker must
pass its pin and regression gates. Reload is a compatibility check, not a
fresh recheck of every stored proof.

Before the first chunked continuation, the supervisor runs a three-chunk
save/reload test on the unchanged `UInt32.toUInt64_shiftLeft_of_lt` export under
a 2 GiB guard. This test waits until the existing full compilation exits.
Subsequent runs also reload that smoke chain with the current worker.

The ongoing legacy full pass cannot gain checkpoints mid-process. It is left
running; chunking applies to its next continuation. If it finishes successfully,
there is no need to replay it just to create intermediate checkpoints.

Before each save/reload, the runner requires 3 GiB of free disk reserve plus
a staging estimate (at least 2 GiB, scaled with checkpoint size). This is an
admission check, not a disk quota. Checkpoints are never deleted automatically.

## Mathlib next

Mathlib is recorded as the next target, but is not launched by the cslib loop.
After cslib succeeds, prepare a separate full Mathlib export and chain starting
at line 1. Never reuse cslib's parser cursor or `.vo` chain for a different export.

For the first run, use the Mathlib revision already pinned by this cslib checkout:
`32d24245c7a12ded17325299fd41d412022cd3fe`, with Lean `4.27.0-rc1`.
That keeps the Lean version fixed while expanding library coverage. The Arena
Mathlib fixture instead pins `8a178386ffc0f5fef0b77738bb5449d50efeea95` and its
existing export metadata reports Lean `4.29.0`; treat that as a later compatibility
target. Do not assume the old cached `.lean-export` has current reducibility hints.

After exporting the full `Mathlib` module and converting with preserved hints,
record source/exporter/converter revisions and hashes, check disk capacity, then:

```sh
python3 scripts/run_chunked_import.py prepare \
  --library Mathlib --export /absolute/path/to/mathlib-hints.lean-export \
  --directory work/library-checkpoints/mathlib --interval 2000000
```

The chunk engine is library-independent. The repair supervisor and its focused
regressions remain cslib-specific until that handoff is configured. Mathlib's
many cumulative parser snapshots will need substantially more disk space than
the four remaining cslib chunks; assess storage before starting it.

Each start creates `work/cslib-loop/TIMESTAMP/`; `latest` points to it:

```sh
tail -F work/cslib-loop/latest/supervisor.log
cat work/cslib-loop/latest/state.json
tail -n 5 -F work/cslib-full-fresh/runs/cslib-unit-fix/latest/*.log
```

Repair subdirectories retain the compact failure report, exact protected-input
hashes, Codex JSON events/usage, structured result and validation output.
While waiting, there is no Codex process for this loop. Logs stay on disk;
the model receives only a bounded error extract when called.

The supervisor is not configured to restart on login or reboot. After a pause,
inspect its reason and any partial changes, then run `start` explicitly for a
new repair budget. Do not restart blindly after a resource/checkpoint failure.

Tests (no Rocq compilation or model invocation):

```sh
python3 -m unittest discover -s scripts/tests -p test_cslib_loop.py
```

The handoff uses the documented [non-interactive Codex interface](https://learn.chatgpt.com/docs/non-interactive-mode),
with `--model gpt-6-astra` and `model_reasoning_effort="xhigh"` on every turn.
