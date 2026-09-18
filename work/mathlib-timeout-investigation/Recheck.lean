import Mathlib.RepresentationTheory.Homological.Resolution

open Lean Elab Command in
run_cmd do
  let .thmInfo thm ← getConstInfo ``Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq
    | throwError "Expected the original theorem body"
  if thm.value.hasSorry ||
      (thm.value.find? (·.isConstOf thm.name)).isSome then
    throwError "Expected a proof body without sorry or a reference to itself"
  let env := (← getEnv).unlockAsync
  let start ← IO.monoMsNow
  match env.addDeclCore 0 (.thmDecl { thm with name := `TimeoutRecheck }) none true with
  | .error error => throwError "Kernel rejected the replay: {error.toMessageData (← getOptions)}"
  | .ok _ => logInfo m!"Original proof checked by Lean in {(← IO.monoMsNow) - start} ms"
