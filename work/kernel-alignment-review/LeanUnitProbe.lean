import Lean

open Lean

structure ProofBox (P : Prop) : Type where
  proof : P

structure Box (A : Type) : Type where
  value : A

axiom expected : ∀ (P : Prop) (x y : Box (ProofBox P)), x = y
def reflexiveProof (P : Prop) (x y : Box (ProofBox P)) : x = x := rfl

axiom expectedUnit : ∀ (x y : Unit), x = y
def reflexiveUnit (x y : Unit) : x = x := rfl

set_option debug.skipKernelTC false

run_elab do
  for (expectedName, proofName, probeName) in
      [(`expected, `reflexiveProof, `kernelProbe), (`expectedUnit, `reflexiveUnit, `kernelUnitProbe)] do
    let type := (← getConstInfo expectedName).type
    let value := (← getConstInfo proofName).value!
    let decl := Declaration.thmDecl { name := probeName, levelParams := [], type, value }
    try
      match (← getEnv).toKernelEnv.addDecl (← getOptions) decl with
      | .ok _ => logInfo m!"KERNEL ACCEPTED {probeName}"
      | .error ex => throwKernelException ex
    catch ex =>
      logInfo m!"KERNEL REJECTED {probeName}: {ex.toMessageData}"
