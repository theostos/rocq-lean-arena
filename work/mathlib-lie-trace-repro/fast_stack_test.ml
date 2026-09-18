open Constr
open Names
open Esubst
open CClosure

let check = Reviewed_conversion.fast_stack_test
let rel n = mk_clos (subs_id 2, UVars.Instance.empty) (mkRel n)
let stack args = [Zapp args]
let p = Projection.Repr.make
  (MutInd.make1 (KerName.make (ModPath.MPfile (DirPath.make [Id.of_string "Test"]))
    (Id.of_string "R")), 0) ~proj_npars:0 ~proj_arg:0
let p2 = Projection.Repr.make (Projection.Repr.inductive p) ~proj_npars:0 ~proj_arg:1

let () =
  let x = rel 1 and y = rel 2 in
  assert (check el_id [Zapp [|x|]; Zapp [|y|]] el_id (stack [|x;y|]));
  assert (check el_id [Zapp [|x|]; Zshift 1] el_id (stack [|y|]));
  assert (not (check el_id [Zshift 1; Zapp [|x|]] el_id (stack [|y|])));
  assert (check (el_shft 1 el_id) (stack [|x|]) el_id (stack [|y|]));
  assert (not (check el_id (stack [|x|]) el_id (stack [|y|])));
  assert (check el_id [Zproj (p, Sorts.Relevant)] el_id [Zproj (p, Sorts.Relevant)]);
  assert (not (check el_id [Zproj (p, Sorts.Relevant)] el_id []));
  assert (not (check el_id [Zproj (p, Sorts.Relevant)] el_id [Zproj (p2, Sorts.Relevant)]));
  assert (not (check el_id (stack (Array.make 200 x)) el_id (stack (Array.make 200 x))));
  let tree n =
    let t = ref (mkRel 1) in
    for _ = 1 to n do t := mkApp (mkRel 2, [|!t;!t|]) done;
    inject !t
  in
  let a = tree 40 and b = tree 40 in
  let before = Gc.allocated_bytes () in
  (* Separately allocated but equal shared DAGs fit the node allowance. *)
  assert (check el_id (stack [|a|]) el_id (stack [|b|]));
  assert (Gc.allocated_bytes () -. before < 1_000_000.);
  let split = Reviewed_conversion.split_projection_stack in
  assert (split [Zapp [|x|]] = None);
  let source = [Zapp [|x|]; Zproj (p, Sorts.Relevant); Zshift 2] in
  let suffix = [Zapp [|y|]; Zshift 3] in
  (match split (source @ (Zproj (p2, Sorts.Relevant) :: suffix)) with
  | Some (prefix, projection, rest) ->
    assert (prefix = source && Projection.Repr.CanOrd.equal projection p2 && rest == suffix)
  | None -> assert false);
  assert (split [Zproj (p, Sorts.Relevant); Zapp (Array.make 257 x)] = None);
  let infos = create_conv_infos RedFlags.all Environ.empty_env in
  let align = Reviewed_conversion.align_projected_sources infos in
  let binder = Context.make_annot Anonymous Sorts.Relevant in
  let identity = mkLambda (binder, mkProp, mkRel 1) in
  let left = inject (mkApp (identity, [|mkProp|])) in
  let before = fterm_of left in
  assert (align el_id left [] el_id (inject mkProp) [] = Some ());
  assert (fterm_of left == before);
  let projection = Projection.make p true in
  let align = Reviewed_conversion.align_projected_sources
    (push_relevance infos binder) in
  let beta = mkApp (identity, [|mkRel 1|]) in
  let left = mk_clos (subs_id 1, UVars.Instance.empty)
    (mkProj (projection, Sorts.Relevant, beta)) in
  let right = mk_clos (subs_id 1, UVars.Instance.empty)
    (mkProj (projection, Sorts.Relevant, mkRel 1)) in
  let before = fterm_of left in
  assert (align el_id left [] el_id right [] = Some ());
  assert (fterm_of left == before);
  let omega = mkLambda (binder, mkProp, mkApp (mkRel 1, [|mkRel 1|])) in
  let divergent = inject (mkApp (omega, [|omega|])) in
  let before = fterm_of divergent in
  let allocated = Gc.allocated_bytes () in
  assert (align el_id divergent [] el_id (inject mkProp) [] = None);
  assert (Gc.allocated_bytes () -. allocated < 8_000_000.);
  assert (fterm_of divergent == before);
  print_endline "Bounded syntactic stack hint passed."
