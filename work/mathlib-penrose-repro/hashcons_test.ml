open Constr
module H = Reviewed_hConstr

let name = Context.make_annot Names.Name.Anonymous Sorts.Relevant
let f = mkVar (Names.Id.of_string "some_repeated_constructor_name")
let app a b = mkApp (f, [|a; b|])
let rec dag n leaf = if n = 0 then leaf else
  let c = dag (n-1) leaf in app c c

let () =
  (* Physically different, identical syntax deliberately shares one hash. *)
  let cache = H.PhysicalTbl.create 1 in
  let a = app mkSet mkSet and b = app mkSet mkSet in
  let r = Range.empty in
  assert (a != b);
  assert (H.PhysicalTbl.hash (a,r) = H.PhysicalTbl.hash (b,r));
  H.PhysicalTbl.add cache (a,r) 1;
  assert (H.PhysicalTbl.find_opt cache (a,r) = Some 1);
  assert (H.PhysicalTbl.find_opt cache (b,r) = None);
  H.PhysicalTbl.add cache (b,r) 2;
  assert (H.PhysicalTbl.find_opt cache (a,r) = Some 1);
  assert (H.PhysicalTbl.find_opt cache (b,r) = Some 2);
  let r1 = Range.cons 1 r and r2 = Range.cons 2 r in
  H.PhysicalTbl.add cache (a,r1) 3;
  assert (H.PhysicalTbl.find_opt cache (a,r2) = None);
  Gc.full_major (); Gc.compact ();
  assert (H.PhysicalTbl.find_opt cache (a,r1) = Some 3);
  for i = 1 to 100_000 do
    let c = app mkSet mkSet in
    assert (H.PhysicalTbl.find_opt ~depth:i cache (c,r) = None);
    H.PhysicalTbl.add ~depth:i cache (c,r) i;
    assert (H.PhysicalTbl.find_opt ~depth:i cache (c,r) = Some i)
  done;
  assert (H.PhysicalTbl.Table.length cache = 100003);
  print_endline "PASS colliding identities, contexts, compaction, depth-partitioned retention";
  let input = dag 60 mkSet in
  let result = H.of_constr Environ.empty_env input in
  let rec check n t = if n > 0 then match H.kind t with
    | App (_, args) -> assert (args.(0) == args.(1)); check (n-1) args.(0)
    | _ -> assert false in
  check 60 result;
  ignore (Vars.sort_and_universes_of_constr input);
  let shared = app (mkRel 1) mkSet in
  let input = app (mkLambda (name,mkSet,shared)) (mkLambda (name,mkProp,shared)) in
  let result = H.of_constr Environ.empty_env input in
  (match H.kind result with
   | App (_,args) -> (match H.kind args.(0), H.kind args.(1) with
       | Lambda (_,_,x), Lambda (_,_,y) -> assert (x != y)
       | _ -> assert false)
   | _ -> assert false);
  print_endline "PASS depth-60 DAG sharing and binder-context separation"

let () =
  let node = H.of_constr Environ.empty_env (mkApp (f,[|f|])) in
  (match H.kind node with
   | App (head,args) -> assert (head == args.(0)); assert (H.refcount head >= 2)
   | _ -> assert false);
  print_endline "PASS repeated atomic heads remain eligible for inference caching"

let () =
  (* Collection is a set union: memoization must preserve sorts, instance
     universes, binder relevance variables, and the caller's initial sets. *)
  let q n = Sorts.Quality.var n and u n = Univ.Level.var n in
  let binder = Context.make_annot Names.Anonymous
    (Sorts.RelevanceVar (Sorts.QVar.make_var 2)) in
  let inst = UVars.Instance.of_array ([|q 1|], [|u 1|]) in
  let sort = mkSort (Sorts.make (q 0) (Univ.Universe.make (u 0))) in
  let shared = mkProd (binder, mkArray (inst,[|sort;sort|],sort,sort), mkRel 1) in
  let term = app (app shared shared) shared in
  let init = Sorts.Quality.Set.singleton (q 9), Univ.Level.Set.singleton (u 9) in
  let qs, us = Vars.sort_and_universes_of_constr ~init term in
  let quality_set = List.fold_left (fun s n -> Sorts.Quality.Set.add (q n) s)
    Sorts.Quality.Set.empty [0;1;2;9] in
  let level_set = List.fold_left (fun s n -> Univ.Level.Set.add (u n) s)
    Univ.Level.Set.empty [0;1;9] in
  assert (Sorts.Quality.Set.equal qs quality_set);
  assert (Univ.Level.Set.equal us level_set);
  let roots = Array.init 100 (fun i ->
    let t = ref (mkSort (Sorts.sort_of_univ (Univ.Universe.make (u i)))) in
    for _ = 1 to 200 do t := app mkSet !t done;
    !t) in
  let _, us = Vars.sort_and_universes_of_constr (mkApp (f,roots)) in
  assert (Univ.Level.Set.cardinal us = 100);
  for i = 0 to 99 do assert (Univ.Level.Set.mem (u i) us) done;
  print_endline "PASS universe collection: initial sets, qualities, relevance, instances, collision tails"

let () =
  (* Exact reconstructed syntax, including names/relevance, against the saved
     pre-fix implementation on small terms. No conversion oracle is changed. *)
  let relevant = Context.make_annot (Names.Name.Name (Names.Id.of_string "x")) Sorts.Relevant in
  let irrelevant = Context.make_annot Names.Name.Anonymous Sorts.Irrelevant in
  let rec terms depth = if depth = 0 then [mkSet; mkProp; mkInt (Uint63.of_int 17); f] else
    List.concat_map (fun t -> [app t t; app (app t mkSet) (app mkProp t);
      mkLambda (relevant,t,mkRel 1); mkLambda (irrelevant,t,mkRel 1);
      mkProd (relevant,t,mkRel 1); mkLetIn (relevant,t,mkSet,mkRel 1);
      mkCast (t,DEFAULTcast,mkSet);
      mkArray (UVars.Instance.empty,[|t;t|],t,mkSet);
      mkFix (([|0|],0),([|relevant|],[|mkSet|],[|app t (mkRel 1)|]));
      mkCoFix (0,([|relevant|],[|mkSet|],[|app t (mkRel 1)|]))]) (terms (depth-1)) in
  let examples = terms 3 in
  List.iter (fun t ->
    let old = Baseline_hConstr.of_constr Environ.empty_env t in
    let fresh = H.of_constr Environ.empty_env t in
    assert (Baseline_hConstr.self old = H.self fresh)) examples;
  Printf.printf "PASS %d exact-syntax differential checks\n%!" (List.length examples);
  List.iter (fun n ->
    let old = Baseline_hConstr.PhysicalTbl.create 251 in
    let start = Sys.time () in
    for i = 1 to n do
      let key = app mkSet mkSet, Range.empty in
      assert (Baseline_hConstr.PhysicalTbl.find_opt old key = None);
      Baseline_hConstr.PhysicalTbl.add old key i
    done;
    Printf.printf "baseline collision memo n=%d cpu=%.6f\n%!" n (Sys.time () -. start);
    let fresh = H.PhysicalTbl.create 251 in
    let start = Sys.time () in
    for i = 1 to n do
      let key = app mkSet mkSet, Range.empty in
      assert (H.PhysicalTbl.find_opt ~depth:i fresh key = None);
      H.PhysicalTbl.add ~depth:i fresh key i
    done;
    Printf.printf "candidate collision memo n=%d cpu=%.6f retained=%d\n%!"
      n (Sys.time () -. start) (H.PhysicalTbl.Table.length fresh)
  ) [5000;10000;20000]
