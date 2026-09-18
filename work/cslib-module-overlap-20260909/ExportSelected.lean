import Export
open Lean

def nameKey : Name → String
  | .anonymous => ""
  | .str p s => nameKey p ++ "s" ++ toString s.utf8ByteSize ++ ":" ++ s
  | .num p n => nameKey p ++ "n" ++ toString n ++ ":"

-- Pass original Name values to the existing exporter: some generated names
-- cannot round-trip through its command-line Name-literal parser.
def main (args : List String) : IO Unit := do
  let [input] := args | throw <| IO.userError "expected selected-name keys file"
  let data ← IO.ofExcept <| Json.parse (← IO.FS.readFile input)
  let rows ← IO.ofExcept data.getArr?
  let mut selected : Std.HashSet String := {}
  for row in rows do selected := selected.insert (← IO.ofExcept row.getStr?)
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Cslib }] {}
  let mut constants : Array Name := #[]
  for (n, _) in env.constants do
    if selected.contains (nameKey n) then constants := constants.push n
  unless constants.size == selected.size do
    throw <| IO.userError s!"found {constants.size} names, expected {selected.size}"
  M.run env do
    initState env
    dumpMetadata
    for n in constants do
      modify fun st => { st with noMDataExprs := {} }
      dumpConstant n
