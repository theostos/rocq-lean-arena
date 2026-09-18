open Names
open Constr

let check name expected left right =
  let ordinary = Constr.equal left right in
  let memoized = LeanConstr.equal left right in
  if ordinary <> expected || memoized <> ordinary then
    failwith (Printf.sprintf "%s: expected=%b ordinary=%b memoized=%b"
      name expected ordinary memoized)

let copy term = Marshal.from_string (Marshal.to_string term []) 0
let annot name = Context.make_annot (Name.Name (Id.of_string name)) Sorts.Relevant
let x = annot "x"
let y = annot "y"
let app left right = mkApp (mkMeta 0, [|left; right|])
let rec dag depth leaf =
  if depth = 0 then leaf else let child = dag (depth - 1) leaf in app child child

let check_context ids term =
  let ordinary = Vars.substl (List.map mkMeta ids) term in
  let memoized = LeanConstr.abstract_context ids term in
  check "context abstraction" true ordinary memoized

let () =
  check "physical identity" true mkProp mkProp;
  check "different sorts" false mkProp mkSet;
  check "alpha" true (mkLambda (x, mkSet, mkRel 1))
    (mkLambda (y, mkSet, mkRel 1));
  check "cast" true (mkCast (mkRel 1, DEFAULTcast, mkSet)) (mkRel 1);
  check "cast type ignored" true (mkCast (mkRel 1, VMcast, mkProp))
    (mkCast (mkRel 1, DEFAULTcast, mkSet));
  check "different indices" false (mkRel 1) (mkRel 2);
  check "no beta reduction" false
    (mkApp (mkLambda (x, mkSet, mkRel 1), [|mkProp|])) mkProp;
  let ev key args = mkEvar (Evar.unsafe_of_int key, args) in
  let args = SList.cons (mkRel 1) (SList.default SList.empty) in
  check "evar copy" true (ev 1 args) (copy (ev 1 args));
  check "evar key" false (ev 1 args) (ev 2 args);
  check "evar argument" false (ev 1 args)
    (ev 1 (SList.cons (mkRel 2) (SList.default SList.empty)));
  check "evar default" false (ev 1 args)
    (ev 1 (SList.of_full_list [mkRel 1; mkRel 2]));
  let level n = Univ.Level.make (Univ.UGlobal.make DirPath.empty "test" n) in
  let instance n = UVars.Instance.of_array ([||], [|level n|]) in
  let constant = Constant.make2 (ModPath.MPfile DirPath.empty) (Id.of_string "c") in
  let c n = mkConstU (constant, instance n) in
  check "universe copy" true (c 0) (copy (c 0));
  check "universe mismatch" false (c 0) (c 1);
  check "applied universe mismatch" false
    (mkApp (c 0, [|mkProp|])) (mkApp (c 1, [|mkProp|]));
  let fix = mkFix (([|0|], 0), ([|x|], [|mkSet|], [|mkRel 1|])) in
  check "fix copy" true fix (copy fix);
  check_context [11; 29] fix;
  check "fix body mismatch" false fix
    (mkFix (([|0|], 0), ([|y|], [|mkSet|], [|mkRel 2|])));
  let cofix = mkCoFix (0, ([|x|], [|mkSet|], [|mkRel 1|])) in
  check "cofix copy" true cofix (copy cofix);
  check_context [11; 29] cofix;
  let array = mkArray (instance 0, [|mkRel 1; mkRel 2|], mkRel 3, mkSet) in
  check "array copy" true array (copy array);
  check "array default mismatch" false array
    (mkArray (instance 0, [|mkRel 1; mkRel 2|], mkRel 4, mkSet));
  let rng = Random.State.make [|2026; 9; 6|] in
  let rec term depth =
    if depth = 0 then match Random.State.int rng 4 with
      | 0 -> mkRel (1 + Random.State.int rng 4)
      | 1 -> mkMeta (Random.State.int rng 4)
      | 2 -> mkProp
      | _ -> mkSet
    else
      let a = term (depth - 1) in
      let b = term (depth - 1) in
      match Random.State.int rng 7 with
      | 0 -> app a b
      | 1 -> app a a
      | 2 -> mkLambda (x, a, b)
      | 3 -> mkProd (y, a, b)
      | 4 -> mkCast (a, DEFAULTcast, b)
      | 5 -> mkLetIn (x, a, mkSet, b)
      | _ -> ev 1 (SList.of_full_list [a; b])
  in
  for _ = 1 to 500 do
    let left = term 5 and right = term 5 in
    check "generated copy" true left (copy left);
    check "generated pair" (Constr.equal left right) left right;
    List.iter (fun ids -> check_context ids left) [[]; [11]; [11; 29; 37]]
  done;
  let shared = dag 18 (mkRel 1) in
  check_context [11; 29] (app shared (mkLambda (x, mkSet, shared)));
  check_context [11; 29] (dag 18 (mkRel 4));
  let original = Vars.substl [mkMeta 11] shared in
  let preserved = LeanConstr.abstract_context [11] shared in
  let shared_children term = match kind term with
    | App (_, args) -> args.(0) == args.(1)
    | _ -> assert false
  in
  assert (not (shared_children original));
  assert (shared_children preserved);
  let left = dag 20 (mkRel 1) and right = dag 20 (mkRel 1) in
  let start = Sys.time () in
  check "shared DAG" true left right;
  Printf.printf "depth-20 oracle + memoized: %.6fs\n%!" (Sys.time () -. start);
  check "late mismatch after shared DAG" false (app left (mkRel 1))
    (app right (mkRel 2));
  (* The ordinary tree traversal at depth 45 would take impractically long.
     The depth-20 cases above provide the paired oracle checks. *)
  let left = dag 45 (mkRel 1) and right = dag 45 (mkRel 1) in
  let start = Sys.time () in
  assert (LeanConstr.equal left right);
  assert (not (LeanConstr.equal (app left (mkRel 1)) (app right (mkRel 2))));
  let normalized1 = LeanConstr.abstract_context [11] left in
  let normalized2 = LeanConstr.abstract_context [11] right in
  assert (LeanConstr.equal normalized1 normalized2);
  assert (not (LeanConstr.equal normalized1 (LeanConstr.abstract_context [29] right)));
  Printf.printf "depth-45 memoized equality + abstraction controls: %.6fs\n%!"
    (Sys.time () -. start);
  print_endline "Constr equality: all checks passed"
