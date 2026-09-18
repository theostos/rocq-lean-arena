(* Exercise the public checking path, including its initial alpha comparison. *)
open Constr
open Reviewed_conversion
open Projected_major_test

let () =
  let choose, safe = add_definition "conversion_dag_choose"
    (mkProd (binder, ind atom, mkProd (binder, ind atom, ind atom)))
    (mkLambda (binder, ind atom, mkLambda (binder, ind atom, mkRel 2))) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let rec dag n leaf =
    if n = 0 then leaf else
    let child = dag (n-1) leaf in
    app (constant choose) [|child; child|] in
  let left = dag 40 lo and right = dag 40 lo in
  ignore (Typeops.infer env left);
  ignore (Typeops.infer env right);
  print_endline "BEGIN public conversion on independently allocated depth40 DAGs";
  assert (default_conv CONV env left right = Result.Ok ());
  assert (default_conv CUMUL env left right = Result.Ok ());
  assert (default_conv CONV env left (dag 40 hi) = Result.Error ());
  print_endline "PASS public conversion: shared DAG equality and unequal leaves";
  List.iter (fun depth ->
    let left = dag depth lo and right = dag depth lo in
    let started = Sys.time () in
    assert (default_conv CONV env left right = Result.Ok ());
    Printf.printf "public DAG conversion depth=%d cpu_seconds=%.6f\n%!"
      depth (Sys.time () -. started)
  ) [8; 16; 32; 64; 128; 256];
  let graph = Environ.universes env in
  let types = [mkSProp; mkProp; mkSet; mkSort Sorts.type1;
    mkProd (binder, ind atom, mkSet);
    mkProd (binder, ind atom, mkSort Sorts.type1);
    mkLambda (binder, ind atom, mkRel 1);
    mkLambda (binder, ind atom, lo);
    mkCast (lo, DEFAULTcast, ind atom);
    mkLetIn (binder, lo, ind atom, mkRel 1);
    dag 4 lo; dag 4 hi] in
  List.iter (fun left -> List.iter (fun right ->
    assert (quick_constr_univs CONV graph left right = eq_constr_univs graph left right);
    assert (quick_constr_univs CUMUL graph left right = leq_constr_univs graph left right)
  ) types) types;
  assert (quick_constr_univs CUMUL graph mkSet (mkSort Sorts.type1));
  assert (not (quick_constr_univs CONV graph mkSet (mkSort Sorts.type1)));
  assert (not (quick_constr_univs CUMUL graph (mkSort Sorts.type1) mkSet));
  print_endline "PASS alpha probe: 288 differential checks; cumulativity remains directional";
  let bodies = Environ.fold_constants (fun _ declaration bodies ->
    match declaration.Declarations.const_body with
    | Declarations.Def body -> body :: bodies
    | _ -> bodies) env [] in
  (* In-memory round-trip of our own checked fixture expressions preserves
     their DAGs but removes cross-operand physical identity shortcuts. *)
  let clone term = Marshal.from_string (Marshal.to_string term []) 0 in
  let count = ref 0 in
  List.iter (fun left -> List.iter (fun source ->
    let right = clone source in
    assert (quick_constr_univs CONV graph left right = eq_constr_univs graph left right);
    assert (quick_constr_univs CUMUL graph left right = leq_constr_univs graph left right);
    count := !count + 2
  ) bodies) bodies;
  Printf.printf "PASS alpha probe: %d independent-allocation checked-body comparisons (including cases)\n%!" !count;
  (* Exhausting the shortcut must still permit ordinary kernel conversion. *)
  let width = 1200 in
  let constructor_type = ref (mkRel (width+1)) in
  for _ = 1 to width do
    constructor_type := mkProd (binder, ind atom, !constructor_type)
  done;
  let (wide, _), safe = Safe_typing.add_mind (id "AlphaWide")
    (mind_entry "AlphaWide" ["wide", !constructor_type]) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let make last = app (ctor wide 1) (Array.init width (fun index ->
    if index = width-1 then last else ctor atom 1)) in
  let left = make lo and right = make lo and wrong = make hi in
  List.iter (fun term -> ignore (Typeops.infer env term)) [left; right; wrong];
  assert (not (quick_constr_univs CONV (Environ.universes env) left right));
  assert (default_conv CONV env left right = Result.Ok ());
  assert (default_conv CONV env left wrong = Result.Error ());
  print_endline "PASS alpha probe: exhausted shortcut falls back; unequal final field rejected"
