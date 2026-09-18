open Constr
open CClosure
open Esubst
open Reviewed_conversion

let infos : unit conv_tab = {
  cnv_inf = create_conv_infos RedFlags.all Environ.empty_env; cnv_typ = true;
  cnv_rel_types = Range.empty; cnv_rel_type_lifts = Range.empty;
  cnv_probe_budget = None; cnv_strategy_budget = None;
  cnv_symbolic_budget = None;
  cnv_symbolic_remaining = ref 16_384;
  cnv_failed_symbolic = make_projection_conversion_cache ();
  cnv_projection_conversions = make_projection_conversion_cache ();
  cnv_successful_conversions = make_successful_conversion_cache 0;
  cnv_memoize_successful_conversions = true; cnv_projection_congruence = false;
  cnv_dependency_preference = false; cnv_constructor_relevance = false;
  cnv_constructor_masks = ConstructorMasks.create 1;
  cnv_failed_congruences = make_failed_congruence_cache ();
  cnv_successful_applications = make_successful_application_cache ();
  lft_tab = create_tab (); rgt_tab = create_tab ();
  err_ret = (fun _ -> assert false);
}

let () =
  let path = Names.ModPath.MPfile
    (Names.DirPath.make [Names.Id.of_string "Applications"]) in
  let const label = Names.ConstKey
    (Names.Constant.make2 path (Names.Id.of_string label), UVars.Instance.empty) in
  let head = const "f" in
  let left = inject mkProp and right = inject mkSProp in
  let left_stack = [Zapp [|left|]] and right_stack = [Zapp [|right|]] in
  let key info lift = application_key info lift el_id head left_stack head right_stack in
  let original = key infos el_id in
  assert (not (completed_application infos CONV original));
  remember_application infos CONV original;
  assert (completed_application infos CONV (key infos el_id));
  assert (not (completed_application infos CUMUL original));
  assert (not (completed_application infos CONV (key infos (el_shft 1 el_id))));
  let changed = { infos with cnv_rel_types = Range.cons (Some left) Range.empty } in
  assert (not (completed_application changed CONV (key changed el_id)));
  assert (not (completed_application infos CONV
    (application_key infos el_id el_id head [Zapp [|inject mkProp|]] head right_stack)));
  assert (not (completed_application infos CONV
    (application_key infos el_id el_id (const "g") left_stack head right_stack)));
  assert (key { infos with cnv_typ = false } el_id = None);
  assert (congruence_frames [Zapp (Array.make 128 left)] = None);
  (* Arrays may be rebuilt: membership is copied and compared by cell identity. *)
  assert (completed_application infos CONV
    (application_key infos el_id el_id head [Zapp [|left|]] head [Zapp [|right|]]));
  let calls = ref 0 in
  let failed _ = incr calls; raise NotConvertible in
  for _ = 1 to 10 do
    assert (try ignore (try_congruence infos el_id el_id head left_stack
      head right_stack failed); false with NotConvertible -> true)
  done;
  assert (!calls = 1);
  (* A failed shortcut did not install a successful result. *)
  assert (not (completed_application infos CUMUL original));
  let exception Interrupted in
  let other = const "interrupted" in
  assert (try ignore (try_congruence infos el_id el_id other left_stack
    other right_stack (fun _ -> raise Interrupted)); false with Interrupted -> true);
  assert (try ignore (try_congruence infos el_id el_id other left_stack
    other right_stack failed); false with NotConvertible -> true);
  assert (!calls = 2);
  (* A whole-strategy or symbolic-recovery cutoff belongs to its owner, not
     the failed-congruence cache. It must propagate without installing a hint. *)
  List.iteri (fun index error ->
    let bounded = const ("bounded" ^ string_of_int index) in
    let size = infos.cnv_failed_congruences.failed_size in
    assert (try ignore (try_congruence infos el_id el_id bounded left_stack
      bounded right_stack (fun _ -> raise error)); false
      with caught -> caught == error);
    assert (infos.cnv_failed_congruences.failed_size = size);
    let executed = ref false in
    ignore (try_congruence infos el_id el_id bounded left_stack
      bounded right_stack (fun _ -> executed := true));
    assert !executed
  ) [Strategy_budget_exhausted; Symbolic_budget_exhausted];
  (* Common heads must retain more than eight distinct argument pairs without
     continually evicting one another. Their identities belong in the key. *)
  let variants = Array.init 128 (fun _ -> [Zapp [|inject mkProp|]]) in
  let before = !calls in
  for _ = 1 to 3 do
    Array.iter (fun stack ->
      assert (try ignore (try_congruence infos el_id el_id head stack
        head right_stack failed); false with NotConvertible -> true)) variants
  done;
  assert (!calls - before = 128);
  Array.iter (fun stack ->
    let key = application_key infos el_id el_id head stack head right_stack in
    remember_application infos CONV key) variants;
  let size = infos.cnv_successful_applications.applications_size in
  Array.iter (fun stack ->
    let key = application_key infos el_id el_id head stack head right_stack in
    assert (completed_application infos CONV key);
    remember_application infos CONV key) variants;
  assert (size = infos.cnv_successful_applications.applications_size);
  (* Destructive beta reduction must not change a stored key's hash. *)
  let binder = Context.make_annot Names.Anonymous Sorts.Relevant in
  let argument = inject (mkApp (mkLambda (binder, mkProp, mkRel 1), [|mkSProp|])) in
  let key = application_key infos el_id el_id head [Zapp [|argument|]] head right_stack in
  remember_application infos CONV key;
  ignore (whd_stack infos.cnv_inf (create_tab ()) argument []);
  assert (completed_application infos CONV key);
  for index = 1 to 5000 do
    let head = const ("f" ^ string_of_int index) in
    assert (try ignore (try_congruence infos el_id el_id head left_stack
      head right_stack failed); false with NotConvertible -> true)
  done;
  assert (infos.cnv_failed_congruences.failed_size <= 4096);
  print_endline "application caches: PASS (identity, lifts, contexts, problems, bounds, exceptions)"
