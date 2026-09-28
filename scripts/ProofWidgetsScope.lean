import Lean

open Lean

def uiModule (n : Name) : Bool :=
  (`ProofWidgets).isPrefixOf n || (`Mathlib.Tactic.Widget).isPrefixOf n

def parts : Name → List String
  | .anonymous => []
  | .str p s => parts p ++ [s]
  | .num p i => parts p ++ [toString i]

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output.jsonl required")
  initSearchPath (← findSysroot)
  let env ← importModules #[{module := `Mathlib}] {} 0
  let out ← IO.FS.Handle.mk output .write
  for (name, info) in env.constants.toList do
    let some idx := env.getModuleIdxFor? name | continue
    let mod := env.header.moduleNames[idx]!
    if uiModule mod then
      out.putStrLn <| (Json.mkObj [
        ("parts", toJson (parts name)), ("name", toJson name.toString),
        ("module", toJson mod.toString), ("unsafe", toJson info.isUnsafe),
        ("meta", toJson (isMarkedMeta env name))]).compress
