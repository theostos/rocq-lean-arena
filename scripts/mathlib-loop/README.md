# Mathlib queue and repair loop

Mathlib waits for a verified, successful cslib completion. Waiting is a small
local Python service: no agent or model request runs during that time.

```sh
python3 scripts/mathlib_loop.py start --repair-access full
python3 scripts/mathlib_loop.py status
python3 scripts/mathlib_loop.py pause
python3 scripts/mathlib_loop.py stop
```

Full local repair access was authorized for this experiment. It retains all
memory/worker guards. `pause` acts at the next phase boundary; `stop` stops only
Mathlib and its owned jobs. Neither command stops cslib. Do not start a manual
full import while either loop owns the shared worker lock.

## Handoff

1. Wait for cslib to finish and verify its recorded full-pass artifacts. A paused
   cslib run leaves Mathlib waiting; an explicitly started replacement cslib run
   is followed automatically. Mathlib cannot overlap a cslib supervisor.
2. Freeze the validated foundation and record the importer/kernel inputs in a
   separate Mathlib toolchain manifest.
3. Export the pinned Mathlib and a small original theorem (`nontrivial_iff`) for
   the save/reload test. Stream NDJSON directly into the hint-preserving converter;
   check both processes' exit statuses. A partial export is never reusable.
4. Run the Mathlib save/reload smoke test, then the full import from line 1,
   with sealed checkpoints every 2M lines. No cslib `.vo` or parser cursor is used.
5. For a declaration failure, call **GPT-6 Astra / xhigh** in a separate Mathlib
   session. The agent fixes the importer/kernel generically and runs regressions.
   After it returns, the supervisor runs independent validation and resumes the
   newest compatible checkpoint. Representation changes create a fresh chain.

The shared checking code is `run_chunked_import.py`, `checkpoint_generation.py`
and the repair/service machinery in `cslib_loop.py`. `mathlib_loop.py` supplies
the Mathlib task, handoff, preparation and separate state. It does not modify the
live cslib controller or reuse its agent session.

## Inputs and storage

- Lean: `leanprover/lean4:v4.27.0-rc1`.
- Mathlib: `32d24245c7a12ded17325299fd41d412022cd3fe`, already cached as cslib's
  dependency. All dependency revisions and actual `.olean` hashes are recorded.
- The older Arena Mathlib cache uses Lean 4.29 and is not used here.
- Bundles: `work/library-exports/mathlib-4.27/{full,smoke}`.
- Initial toolchain/plans: `work/library-checkpoints/mathlib/`.
- Later representation generations live under their repair directories.

Preparation does not rebuild, update or delete the Lean source checkout. Missing
compiled modules or changed pins cause a clear refusal. The full export requires
12 GiB free at admission; streaming also checks the disk reserve. Each checkpoint
has its own reserve/staging check. These checks do **not** guarantee enough disk
for the entire cumulative chain; storage exhaustion pauses without a model call.
No useful checkpoints are automatically pruned.

Full checking/export stays within 16 GiB hard / 15 GiB RSS / 3 GiB available
reserve, with no workload swap. Smaller smoke exports use 4 GiB; smoke checking
uses 2 GiB. The single-heavy-workload guard covers every build/export/check.
Default repair limits are three turns, two hours each. Authentication, resource,
validation and repeated-declaration failures pause without automatic retries.

## Inspect and resume

```sh
tail -F work/mathlib-loop/latest/supervisor.log
cat work/mathlib-loop/latest/state.json
```

The state identifies the active plan and compilation attempt. Each attempt has
per-checkpoint `.run.log` and `.guard.log` files. Export logs are in the same run
directory. After resolving a resource refusal, `start` resumes the existing chain.
To explicitly retry a paused declaration repair without replaying the full pass:

```sh
python3 scripts/mathlib_loop.py start --retry-repair --repair-access full
```

The queue is not configured to restart on reboot. Run `start` again explicitly.
Checkpoint reload is a compatibility check, not rechecking every stored proof.
This remains an experimental modified-kernel validation, not a soundness result.

Tests (no Lean/Rocq worker or model calls):

```sh
python3 -m unittest discover -s scripts/tests -p 'test_*mathlib*.py'
```

The CLI handoff retains the documented
[non-interactive interface](https://learn.chatgpt.com/docs/non-interactive-mode).
The actual Mathlib export and Rocq smoke test run only after the cslib handoff;
unit tests of orchestration are not a claim that Mathlib already checks.
