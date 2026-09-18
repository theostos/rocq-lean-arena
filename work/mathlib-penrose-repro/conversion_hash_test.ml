open Constr
module Cache = Reviewed_typeops.ApplicationConversions

let () =
  let env = Environ.empty_env in
  let head = mkVar (Names.Id.of_string "computed_character_type") in
  let left i =
    let term = ref (mkInt (Uint63.of_int i)) in
    for _ = 1 to 40 do term := mkApp (head, [|!term; mkSet|]) done;
    !term
  in
  let terms = Array.init 100 left in
  let shallow = Hashtbl.hash_param 8 32 terms.(0) in
  assert (Array.for_all (fun t -> Hashtbl.hash_param 8 32 t = shallow) terms);
  let hashes = Array.map Cache.syntax_hash terms in
  assert (List.length (List.sort_uniq compare (Array.to_list hashes)) = 100);
  Gc.full_major (); Gc.compact ();
  assert (Array.map Cache.syntax_hash terms = hashes);
  let checks = ref 0 in
  let check _ _ _ = incr checks; Ok () in
  let cache = Cache.create () in
  for _ = 1 to 5 do
    Array.iter (fun t -> assert (Cache.convert cache check env t mkSet = Ok ())) terms
  done;
  assert (!checks = 100 && cache.hits = 400);
  (* The structural fingerprint does not recursively expand large shared DAGs
     or long chains; exhaustion only declines memoization. *)
  let dag = ref mkSet in
  for _ = 1 to 60 do dag := mkApp (head, [|!dag; !dag|]) done;
  assert (Cache.syntax_hash !dag = None);
  let calls = ref 0 in
  let reject _ _ _ = incr calls; Error () in
  assert (Cache.convert cache reject env !dag mkProp = Error ());
  assert (!calls = 1);
  print_endline "PASS structural conversion fingerprints: hidden literals, GC, hits, bounded DAG fallback";
  let binder = Context.make_annot Names.Anonymous Sorts.Relevant in
  let make_type leaf =
    let typ = ref leaf in
    for _ = 1 to 2000 do typ := mkProd (binder, mkSet, !typ) done;
    !typ in
  let left = make_type (mkRel 1) and right = make_type (mkRel 1) in
  assert (Cache.compare_syntax left right = None);
  assert (Reviewed_typeops.shared_type_syntax env left right);
  assert (not (Reviewed_typeops.shared_type_syntax env left (make_type (mkRel 2))));
  let env = Environ.set_typing_flags
    { (Environ.typing_flags env) with unfold_dep_heuristic = true } env in
  ignore (Typeops.infer_type env left);
  ignore (Typeops.infer_type env right);
  assert (Reviewed_typeops.conv_leq env left right = Ok ());
  assert (Reviewed_typeops.conv_leq env mkSet (mkSort Sorts.type1) = Ok ());
  assert (Reviewed_typeops.conv_leq env (mkSort Sorts.type1) mkSet = Error ());
  let other = ref mkSet in
  for _ = 1 to 60 do other := mkApp (head, [|!other; !other|]) done;
  assert (Reviewed_typeops.shared_type_syntax env !dag !other);
  print_endline "PASS shared type syntax: large reflexivity, distinct bound variables, directed sorts, independent DAGs"
