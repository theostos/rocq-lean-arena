open Constr

let () =
  let n = int_of_string Sys.argv.(1) in
  let head = mkVar (Names.Id.of_string "long_literal_cons") in
  let atom = mkInt (Uint63.of_int 65) in
  let input = ref mkSet in
  for _ = 1 to n do input := mkApp (head, [|atom; !input|]) done;
  let start = Sys.time () in
  let result = HConstr.of_constr Environ.empty_env !input in
  let node = ref result in
  for _ = 1 to n do
    match HConstr.kind !node with
    | App (_,args) -> node := args.(1)
    | _ -> assert false
  done;
  assert (match HConstr.kind !node with Sort Sorts.Set -> true | _ -> false);
  Printf.printf "PASS deep hashcons: %d nodes in %.3f CPU seconds\n%!" n (Sys.time () -. start);
  let start = Sys.time () in
  ignore (Vars.sort_and_universes_of_constr (HConstr.self result));
  Printf.printf "PASS deep universe scan: %.3f CPU seconds\n%!" (Sys.time () -. start);
  let start = Sys.time () in
  let _, canonical = HConstr.hcons result in
  let node = ref canonical in
  for _ = 1 to n do
    match Constr.kind !node with
    | App (_,args) -> node := args.(1)
    | _ -> assert false
  done;
  assert (is_Set !node);
  Printf.printf "PASS deep canonical hashcons: %.3f CPU seconds\n%!" (Sys.time () -. start)
