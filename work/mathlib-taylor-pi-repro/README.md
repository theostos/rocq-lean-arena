# hasFTaylorSeriesUpToOn_pi

Canonical line 19,571,205. The 20260911T211358885314Z attempt was stopped by
the 15 GiB aggregate RSS guard (exit 125), not a theorem timeout. The 19M main
checkpoint is sealed and intact. The sampled stack is dominated by reification
through `to_constr`, `subst_constr`, and `Vars.lift_substituend`; the initiating
caller was outside the canonical 80-frame diagnostic.

Repair implemented and validated. `run.py` reuses the prior guarded harness with the
target and read-only checkpoint verification extended through 19M. The prefix
keeps the canonical logical name MathlibTo20000000 and stops immediately before
the theorem. `trace.gdb` samples both ends of the stack and all conversion frames.
No proof, timeout, importer, memory-policy or checkpoint-chain changes.

The baseline prefix passed and saved in 890.20 seconds; SHA256
`8d22a0dc4c6878cae9270b37f23291acec841c56ad6af52a552d4bc1b33f8e45`.
The isolated target reproduced rapid memory growth in conversion call 500
(LinearIsometryEquiv, constructor relevance enabled). Its stack identifies
`transparent_inductive_after_applying.fresh_args` at baseline conversion.ml:966:
the optional eta type query was reifying a huge shared argument.

The diagnostic target was deliberately interrupted with SIGALRM after 160.62
seconds to capture the complete stack. Its exit 1 is **not** a natural timeout.
GDB's `noprint` setting had implicitly disabled stopping on SIGUSR1; the script
now uses `stop print nopass`. The untouched canonical run's exit 125 remains
the evidence of the original memory-guard failure.

Candidate: a read-only 4,096-node expanded-occurrence preflight shared across
the type and all arguments of this optional query. Oversized/unquotable inputs
return None, leaving ordinary conversion responsible for equality. No other
quotation caller, public interface, or serialization representation is changed.

Candidate worker: `0531151b6f83a927b0c3caad2fa56190f21defa5409cd7cf4933eedf30a4248d`.
`bounded-quotation-target` checked the theorem: declaration CPU 84.931 to
122.617 seconds (37.686 seconds including new dependency instances; quickdef
started at 87.915). The source helper's focused unit
test passes, including a 50-level binary closure DAG, captured versus bound
variables, unused substitutions, shifts, shared budgets and no mutation.
The unit harness compiles the actual private helper extracted from conversion.ml,
not a separately maintained implementation; no public CMI change is needed.

The target saved successfully in 413.16 seconds total, with guarded peak
8,498,380 KiB; artifact SHA256
`2eb36b69b222afd68477a07bbaac2fd15b789bcae4290e62a0b6f2476661de0f`.
Full validation passed in `validation-s_r9myrw`, after a successful target save
and worker/artifact hash check. Validation includes the original 19M-to-20M
module/order, fresh reload, the earlier 18M-to-19M MvPolynomial replay,
28 kernel fixtures (eight focused and twenty broader), both closure unit tests,
44 importer fixtures and the runner tests (199 passed, two skipped).
`resume.sh --check` passed and continues to require this exact batch, worker,
sources and saved artifacts. The previous fix's resume gate intentionally
no longer matches the new worker.

The full replay passed the reported theorem in its original declaration order:
CPU 446.548 to 479.044 (32.496 seconds). The complete 19M-to-20M replay and save
also passed, exit 0, in 1,182.42 seconds, with guarded peak 10,653,352 KiB;
artifact SHA256 `197c20689c5e9a12e0a154f732656fef2453af9e1f3d95a645a15ba67eaa8c98`.
Fresh reload/save passed in 373.39 seconds; artifact SHA256
`fd4714e7fe3293c6683e683248d6d577ab1ef33a7ec8406a2785cfa5f88d5860`.
The previous 18M-to-19M replay and save passed in 1,043.59 seconds, including
`MvPolynomial.mem_image_comap_C_basicOpen`; artifact SHA256
`d5f3d3bdd4969a0e65a462bbf75d3b5aae78860053f7c0f8dc00988c5e9ab43d`.
All 19 canonical checkpoint seals were verified read-only, together with the
export and generation inputs. `passed.json` was written only after all checks.

The main loop was launched with the validated worker under
`rocq-mathlib-ndjson-quotation-guard.service`. Its supervisor log is
`work/mathlib-ndjson/quotation-guard-resume.supervisor.log`.
At handoff, attempt `20260912T100206892784Z` is active in checkpoint preflight;
the canonical sealed frontier is still 19M.
It resumes from the existing 19M chain, including a fresh reload before
rebuilding the canonical 20M checkpoint. No isolated validation artifact was
promoted into the canonical chain. The 1,800-second declaration timeout,
15 GiB RSS / 16 GiB cgroup limits, no-swap policy, and one-worker guard remain
unchanged. No commits or pushes were made.
