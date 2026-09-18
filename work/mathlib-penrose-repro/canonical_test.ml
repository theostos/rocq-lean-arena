module C = Reviewed_constr
let binder = Context.make_annot Names.Name.Anonymous Sorts.Relevant
let head = C.mkVar (Names.Id.of_string "canonical_test_head")
let app a b = C.mkApp (head,[|a;b|])
let rec terms depth = if depth=0 then
    [C.mkSet; C.mkProp; C.mkRel 1; C.mkInt (Uint63.of_int 123)]
  else List.concat_map (fun t ->
    [app t t; app (app t C.mkSet) t; C.mkLambda (binder,C.mkSet,t);
     C.mkProd (binder,C.mkSet,t); C.mkLetIn (binder,t,C.mkSet,C.mkRel 1);
     C.mkCast (t,C.DEFAULTcast,C.mkSet);
     C.mkArray (UVars.Instance.empty,[|t;t|],t,C.mkSet)]) (terms (depth-1))
let () =
  let cases = terms 3 in
  List.iter (fun t ->
    (* The original recursive [hash_term] remains an independent definition
       of each node's hash/shape, including its old App branch. *)
    let old_hash, old_kind = C.HCons.hash_term t in
    let hash, canonical = C.hcons t in
    assert (old_hash=hash);
    assert (old_kind=C.kind canonical);
    let hash', canonical' = C.hcons canonical in
    assert (hash'=hash && canonical'==canonical)) cases;
  Printf.printf "PASS %d canonical hashes/shapes and idempotence\n%!" (List.length cases)
