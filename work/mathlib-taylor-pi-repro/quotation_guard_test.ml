open Constr
open CClosure

let () =
  let identity = Esubst.subs_id 0, UVars.Instance.empty in
  let node = mkVar (Names.Id.of_string "node") in
  let duplicate = mkApp (node, [|mkRel 1; mkRel 1|]) in
  let grow value = mk_clos (usubs_cons value identity) duplicate in
  let leaf = inject (mkRel 1) in
  let small = grow (grow leaf) in
  assert (Quotation_guard.small_reification (ref 1024) small);
  let expected = mkApp (node, [|mkApp (node, [|mkRel 1; mkRel 1|]);
                               mkApp (node, [|mkRel 1; mkRel 1|])|]) in
  assert (Constr.equal (term_of_fconstr small) expected);
  let huge = ref leaf in
  let snapshots = ref [] in
  for _ = 1 to 50 do
    huge := grow !huge;
    snapshots := (!huge, fterm_of !huge) :: !snapshots
  done;
  assert (not (Quotation_guard.small_reification (ref 4096) !huge));
  List.iter (fun (term, before) -> assert (fterm_of term == before)) !snapshots;
  let binder = Context.make_annot Names.Anonymous Sorts.Relevant in
  let under_binder = mk_clos (usubs_cons !huge identity)
      (mkLambda (binder, mkProp, mkRel 2)) in
  assert (not (Quotation_guard.small_reification (ref 4096) under_binder));
  let unused = mk_clos (usubs_cons !huge identity)
      (mkLambda (binder, mkProp, mkRel 1)) in
  assert (Quotation_guard.small_reification (ref 16) unused);
  let shifted = mk_clos (Esubst.subs_shft (17, fst (usubs_cons !huge identity)), snd identity)
      (mkRel 1) in
  assert (not (Quotation_guard.small_reification (ref 4096) shifted));
  assert (not (Quotation_guard.small_reification (ref 0) leaf));
  let shared = ref 2 in
  assert (Quotation_guard.small_reification shared leaf);
  assert (Quotation_guard.small_reification shared leaf);
  assert (not (Quotation_guard.small_reification shared leaf));
  print_endline "bounded quotation preflight: PASS"
