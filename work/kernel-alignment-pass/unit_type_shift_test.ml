(* Private representation/inspection tests, not new typing rules. The native
   function-transport fixture and the proof-preserving ThinSkeleton replay
   exercise checked terms through both public conversion consumers. *)
open Constr
open CClosure
open Esubst
open Reviewed_conversion

let identity = subs_id 0, UVars.Instance.empty
let binder = Context.make_annot Names.Anonymous Sorts.Relevant
let shift = el_shft 3 el_id
let get = function Some term -> term | None -> assert false
let clos_infos = create_conv_infos RedFlags.betaiotazeta Environ.empty_env
let infos : unit conv_tab = {
  cnv_inf = clos_infos; cnv_typ = true;
  cnv_rel_types = Range.empty; cnv_rel_type_lifts = Range.empty;
  cnv_probe_budget = None; cnv_strategy_budget = None;
  cnv_symbolic_budget = None;
  cnv_symbolic_remaining = ref 16_384;
  cnv_failed_symbolic = make_projection_conversion_cache ();
  cnv_projection_conversions = make_projection_conversion_cache ();
  cnv_successful_conversions = make_successful_conversion_cache 0;
  cnv_memoize_successful_conversions = false; cnv_projection_congruence = false;
  cnv_dependency_preference = false; cnv_constructor_relevance = false;
  cnv_constructor_masks = ConstructorMasks.create 1;
  cnv_failed_congruences = make_failed_congruence_cache ();
  cnv_successful_applications = make_successful_application_cache ();
  lft_tab = create_tab (); rgt_tab = create_tab ();
  err_ret = (fun _ -> assert false);
}

let () =
  (* Deferred substitutions, their own shifts, and crossed binders must have
     exactly the same meaning as syntax relocation on a small reference term. *)
  let syntax = mkLambda (binder, mkRel 1, mkApp (mkRel 2, [|mkRel 1; mkRel 3|])) in
  let substituted = usubs_cons (inject (mkRel 2)) identity in
  List.iter (fun subst ->
    let original = mk_clos subst syntax in
    let before = fterm_of original in
    let shifted = get (delayed_unit_type_shift shift original) in
    assert (Constr.equal (term_of_fconstr shifted)
      (Vars.exliftn shift (term_of_fconstr original)));
    assert (fterm_of original == before))
    [identity; substituted; usubs_liftn 2 substituted;
     (subs_shft (4, fst substituted), snd substituted)];

  (* A linear-size closure DAG whose expanded syntax has over 2^50 leaves. *)
  let huge = ref (inject mkProp) in
  for _ = 1 to 50 do
    huge := mk_clos (usubs_cons !huge identity)
      (mkProd (binder, mkRel 1, mkRel 2))
  done;
  assert (not (small_reification (ref 4096) !huge));
  let before = fterm_of !huge in
  let allocated = Gc.allocated_bytes () in
  let shifted = get (relocate_unit_type infos (ref 4096) shift !huge) in
  assert (Gc.allocated_bytes () -. allocated < 1_000_000.);
  assert (fterm_of !huge == before);
  (match fterm_of !huge, fterm_of shifted with
   | FCLOS (body, _), FCLOS (copy, _) -> assert (body == copy)
   | _ -> assert false);
  (* No speculative general lift, constructor traversal, or budget bypass. *)
  assert (delayed_unit_type_shift (el_lift shift) !huge = None);
  assert (delayed_unit_type_shift shift (inject (mkRel 1)) = None);
  assert (with_closure_snapshot ~steps:1 clos_infos [shifted]
    (fun _ _ -> Some true) = None);
  assert (with_closure_snapshot ~steps:4096 clos_infos [shifted]
    (fun _ _ -> Some true) = Some true);

  (* Quotation can exhaust its allowance while an ignored let value stays
     delayed. That must not consume the separate argument-spine allowance. *)
  let typ = mk_clos (usubs_cons !huge identity)
    (mkLetIn (binder, mkRel 1, mkSort Sorts.type1,
      mkProd (binder, mkSort Sorts.type1, mkProp))) in
  let result = get (unit_type_after_stack infos el_id shift typ
      [Zapp [|inject mkProp|]] (inject (mkRel 1))) in
  assert (Constr.equal (term_of_fconstr result) mkProp);
  assert (unit_type_after_stack infos el_id el_id typ
      [Zapp (Array.make 4096 (inject mkProp))] (inject (mkRel 1)) = None);

  (* A raw inversion is observed but never run here. Its checked predicate
     and actual indices are interpreted by the caller, not guessed by shifting. *)
  let path = Names.ModPath.MPfile (Names.DirPath.make [Names.Id.of_string "Shift"]) in
  let ind = Names.MutInd.make2 path (Names.Id.of_string "Eq"), 0 in
  let ci = {ci_ind = ind; ci_npar = 0; ci_cstr_ndecls = [|0|];
    ci_cstr_nargs = [|0|]; ci_pp_info = {style = MatchStyle}} in
  let syntax = mkCase (ci, UVars.Instance.empty, [||],
    (([|binder|], mkProp), Sorts.Relevant), CaseInvert {indices = [||]},
    mkRel 1, [|([||], mkRel 2)|]) in
  let term = mk_clos (usubs_cons (inject (mkRel 1)) (usubs_cons !huge identity)) syntax in
  let term, stack = whd_stack (infos_with_reds clos_infos RedFlags.betazeta)
    (create_tab ()) term [] in
  let term = zip term stack in
  (match fterm_of term with FCaseInvert _ -> () | _ -> assert false);
  let before = fterm_of term in
  assert (not (small_reification (ref 4096) term));
  let shifted = get (relocate_unit_type infos (ref 4096) shift term) in
  (match fterm_of shifted with FLIFT (3, original) -> assert (original == term)
   | _ -> assert false);
  assert (fterm_of term == before);
  print_endline "unit type shifts: PASS (meaning, DAG bounds, exhausted quotation, inversion)"
