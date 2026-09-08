# Early-prefix UTF-8 timeout

Finding: resuming from 15M skipped this theorem. Older logs show it passed with
an earlier toolchain; the fresh chain exposes a real performance regression,
not an established invalid proof.

## Evidence

- Full-export declaration: `String.utf8EncodeChar.eq_def`, line **641,616**.
  It passed in `work/cslib-full-fresh/CslibFull.substitution-aware-20260907.run.log`
  (log line 6021), followed by later declarations.
- The associated `substitution-aware-20260907.audit.json` records the same
  export SHA-256, `ce6fb77ab3905e0dbbc9668dad42f3cbfee474c131b472140cc4da94f8b323ae`,
  but older worker and importer hashes.
- `work/cslib-full-fresh/runs/cslib-unit-fix/Complete15M.v` loads
  `Prefix15M` and begins at line **15,001,016**. It never rechecks line 641,616.
- The active repair's 8,452-line dependency export reproduces the timeout both
  from scratch and after a freshly saved dependency prefix. Translation
  completes; kernel conversion of the original reflexivity proof stalls.

## Likely mechanism

Conversion compares `String.utf8EncodeChar c` with its unfolded body.
The dependency probe cannot inspect some saved substitutions, and a known
positive dependency is discarded when the reverse query is unknown.
The resulting unfolding order enters conditionals and open arithmetic instead
of exposing the shared function body. The baseline trace reaches over eight
million comparison steps.

The first preference-only trial still timed out. The active repair reports a
passing diagnostic target after adding bounded substitution inspection; its
full validation is separate from this read-only investigation.

This identifies a concrete conversion bottleneck. It does **not** date its
introduction or isolate the recent source-Nat change from intervening kernel
changes: no fixed-kernel importer A/B comparison has been established.

Evidence remains under `work/utf8-encode-eq-def-repro/` in the experiment
workspace. Logs, snapshots and generated binaries are deliberately not committed.
The parallel investigation launched no compiler and changed no implementation.
