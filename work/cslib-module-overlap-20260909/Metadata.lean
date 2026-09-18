import Lean

open Lean

-- Unambiguous keys, shared with analyze.py (including numeric name components).
def nameKey : Name → String
  | .anonymous => ""
  | .str p s => nameKey p ++ "s" ++ toString s.utf8ByteSize ++ ":" ++ s
  | .num p n => nameKey p ++ "n" ++ toString n ++ ":"

unsafe structure VisitState where
  visited : PtrSet Expr := mkPtrSet
  deps : NameHashSet := {}

-- Mirror lean4export's constant traversal and implicit literal dependencies.
unsafe def visitExpr (e : Expr) : StateM VisitState Unit := do
  if (← get).visited.contains e then return
  modify fun s => { s with visited := s.visited.insert e }
  match e with
  | .const n _ => modify fun s => { s with deps := s.deps.insert n }
  | .lit (.natVal _) => modify fun s => { s with deps := s.deps.insert ``Nat }
  | .lit (.strVal _) =>
    modify fun s => { s with deps := s.deps.insert ``Char.ofNat |>.insert ``String.ofList }
  | .app f a => visitExpr f; visitExpr a
  | .lam _ t b _ | .forallE _ t b _ => visitExpr t; visitExpr b
  | .letE _ t v b _ => visitExpr t; visitExpr v; visitExpr b
  | .proj _ _ b | .mdata _ b => visitExpr b
  | _ => pure ()

unsafe def dependencies (ci : ConstantInfo) (recs : NameMap NameSet) : NameHashSet := Id.run do
  let action : StateM VisitState Unit := do
    visitExpr ci.type
    if let some v := ci.value? (allowOpaque := true) then visitExpr v
    let add (n : Name) : StateM VisitState Unit :=
      modify fun s => { s with deps := s.deps.insert n }
    match ci with
    | .inductInfo v =>
      for n in v.all do add n
      for n in v.ctors do add n
      for n in recs.getD v.name {} do add n
    | .ctorInfo v => add v.induct
    | .recInfo v =>
      for n in v.all do add n
      for r in v.rules do visitExpr r.rhs
    | .quotInfo _ =>
      for n in [`Quot, ``Quot.mk, ``Quot.lift, ``Quot.ind, ``Eq] do add n
    | _ => pure ()
  return (action.run {}).2.deps

def kind : ConstantInfo → String
  | .defnInfo _ => "def"
  | .thmInfo _ => "thm"
  | .opaqueInfo _ => "opaque"
  | .axiomInfo _ => "axiom"
  | .inductInfo _ => "inductive"
  | .ctorInfo _ => "ctor"
  | .recInfo _ => "rec"
  | .quotInfo _ => "quot"

unsafe def main (args : List String) : IO Unit := do
  let [output] := args | throw <| IO.userError "expected metadata output path"
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Cslib }] {}
  let constants := env.constants.toList.toArray
  let mut ids : Std.HashMap Name Nat := Std.HashMap.emptyWithCapacity constants.size
  let mut recs : NameMap NameSet := {}
  for i in [:constants.size] do
    let (n, ci) := constants[i]!
    ids := ids.insert n i
    if let .recInfo v := ci then
      for ind in v.all do
        recs := recs.insert ind ((recs.getD ind {}).insert n)
  IO.FS.withFile output .write fun out => do
    out.putStrLn <| (Json.mkObj [
      ("modules", toJson (env.header.moduleNames.map (·.toString))),
      ("constants", toJson constants.size)
    ]).compress
    for i in [:constants.size] do
      let (n, ci) := constants[i]!
      let moduleId := (env.getModuleIdxFor? n).map (·.toNat)
      let mut deps : Array Nat := #[]
      if !ci.isUnsafe then
        for dep in (dependencies ci recs).toArray do
          let some depId := ids[dep]? | throw <| IO.userError s!"missing dependency: {dep}"
          deps := deps.push depId
      let row := Json.arr #[toJson (nameKey n), toJson moduleId, toJson (kind ci),
        toJson ci.isUnsafe, toJson n.isInternal, toJson deps, toJson n.toString]
      out.putStrLn row.compress
      if i % 50000 == 0 then
        (← IO.getStderr).putStrLn s!"metadata {i}/{constants.size}"
