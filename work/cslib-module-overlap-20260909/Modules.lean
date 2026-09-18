import Lean
open Lean

def main (args : List String) : IO Unit := do
  let [output] := args | throw <| IO.userError "expected output path"
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Cslib }] {}
  let mut rows : Array Json := #[]
  for i in [:env.header.moduleNames.size] do
    let n := env.header.moduleNames[i]!
    let data := env.header.moduleData[i]!
    rows := rows.push <| Json.arr #[toJson n.toString,
      toJson (data.imports.map (·.module.toString))]
  IO.FS.writeFile output (Json.arr rows).compress
