# Constructor requested before its inductive instance

`ConstructorOwner.lean` is a genuine Lean 4.27.0-rc1 reproduction, with no imports
or axioms. The failing definition is:

```lean
def repro : Token := (Box.mk Token.mk).value
```

The export first declares polymorphic `Box` and `Box.value`, then uses the
constructor at universe `0`. The importer's projection fast path translates
its arguments before declaring the specialized projection. Consequently it
requests `Box.mk` before `Box` has been instantiated at that universe.

Previously, the importer looked for a source declaration named `Box.mk`, but
constructors live inside the source entry for `Box`. The fix records that
ownership and instantiates `Box` first. It does not change the proof, the
kernel, the universe translation, or the checkpoint schema.

Evidence (experimental worker `239ec13e...` in both cases):

- Lean compilation and export passed; the export contains 74 lines.
- Importer `77614c42...`: `ConstructorOwnerRepro.before.run.log` fails at line
  74 with `missing Box.mk`.
- Importer `8c1e2aee...`: `ConstructorOwnerRepro.constructor-owner.run.log`
  passes, including a wrong-type negative control.
- `ConstructorOwnerBase` / `ConstructorOwnerResume` also pass in separate
  processes: `Box_inst1` is absent before saving, then created on demand after
  loading. The owner index is reconstructed, not serialized.

Logs and Rocq drivers are in the parent directory. Regenerate the export with
`bash export.sh` **through the memory guard**, with a 1.5 GiB cap, no swap and
the existing 13.5 GiB reserve. Run Rocq drivers through `run-checkpoint-atomic.sh`
as documented in the parent README. Never run these alongside a continuation.

The real cslib-export failure is `Lean.Server.Watchdog.eraseFileWorker` at line
9,380,048 (`missing Lean.JsonRpc.ResponseError.mk`). Its replay with the fix
has now checked this declaration and the rest of the range to 9.5M without
skips. Saving exceeded the preventive RSS limit, so the usable checkpoint
remains 9M. A retry with a smaller temporary serialization index is running;
the full cslib pass is still pending.
