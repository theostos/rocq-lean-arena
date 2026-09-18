(* Lazy source unfolding must stop at constructors and select the field.
   Unequal discarded fields are not an obligation of projected equality. *)
open Names
open Constr
open Reviewed_conversion
open Projected_major_test

let () =
  let record_type, (field, relevance), safe = add_record "LazyProjectionRecord"
    ["selected", ind atom; "discarded", ind atom] safe in
  let typ = mkProd (binder, ind atom, ind record_type) in
  let wrapper name selected safe = add_definition name typ
    (mkLambda (binder, ind atom,
      app (ctor record_type 1) [|selected; mkRel 1|])) safe in
  let left, safe = wrapper "lazy_source_left" lo safe in
  let right, safe = wrapper "lazy_source_right" lo safe in
  let wrong, safe = wrapper "lazy_source_wrong" hi safe in
  let forward, safe = add_definition "lazy_forwarding_source"
    (mkProd (binder, ind atom, mkProd (binder, ind record_type, ind record_type)))
    (mkLambda (binder, ind atom, mkLambda (binder, ind record_type,
      app (ctor record_type 1)
        [|mkProj (field, relevance, mkRel 1); mkRel 2|]))) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let env = Environ.set_typing_flags
    {(Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true} env in
  let project c arg = mkProj (field, relevance, app (constant c) [|arg|]) in
  let expensive = ref hi in
  for _ = 1 to 1024 do expensive := app (constant boolean_not) [|!expensive|] done;
  (* Exercise the lazy helper directly as well as the ordinary stack route.
     The source's first argument is computationally expensive and irrelevant
     to the forwarded field, but is NOT a proof and must not be masked. *)
  let original = app (ctor record_type 1) [|lo; hi|] in
  let forwarded argument = app (constant forward) [|argument; original|] in
  (* These explicit stack/lift cases test scheduling, not proof acceptance. *)
  let ref_ = ConstKey (forward, instance) in
  let frame = CClosure.Zproj (Projection.repr field, relevance) in
  let stack ignored source = [CClosure.Zapp [|CClosure.inject ignored; source|]; frame] in
  let probe = same_forwarded_projection_source (conversion_infos env) in
  let original_closure = CClosure.inject original in
  assert (probe Esubst.el_id ref_ (stack !expensive original_closure)
    Esubst.el_id ref_ (stack lo original_closure));
  assert (not (probe Esubst.el_id ref_ (stack lo original_closure)
    Esubst.el_id ref_ (stack lo (CClosure.inject (app (ctor record_type 1) [|hi; hi|])))));
  (* [inject] makes environment references (RelKey), not local binders.
     Bind the first two variables explicitly to exercise FRel relocation. *)
  let local n = CClosure.mk_clos (Esubst.subs_id 2, instance) (mkRel n) in
  let rel1 = local 1 and rel2 = local 2 in
  assert (match CClosure.fterm_of rel1, CClosure.fterm_of rel2 with
    | CClosure.FRel 1, CClosure.FRel 2 -> true | _ -> false);
  assert (probe (Esubst.el_shft 1 Esubst.el_id) ref_ (stack lo rel1)
    Esubst.el_id ref_ (stack lo rel2));
  assert (probe Esubst.el_id ref_ (stack lo rel1 @ [CClosure.Zshift 1])
    Esubst.el_id ref_ (stack lo rel2));
  assert (not (probe Esubst.el_id ref_ (CClosure.Zshift 1 :: stack lo rel1)
    Esubst.el_id ref_ (stack lo rel2)));
  assert (not (probe (Esubst.el_shft 1 Esubst.el_id) ref_
    (stack lo (CClosure.inject (mkRel 1))) Esubst.el_id ref_
    (stack lo (CClosure.inject (mkRel 2)))));
  assert (not (probe Esubst.el_id ref_ [CClosure.Zapp [|original_closure|]; frame]
    Esubst.el_id ref_ [CClosure.Zapp [|original_closure|]; frame]));
  let blocked = RedFlags.red_sub RedFlags.all (RedFlags.fCONST forward) in
  assert (not (same_forwarded_projection_source (conversion_infos ~reds:blocked env)
    Esubst.el_id ref_ (stack lo original_closure)
    Esubst.el_id ref_ (stack lo original_closure)));
  List.iter (fun typed -> List.iter (fun (a, b) ->
    ignore (Typeops.infer env a); ignore (Typeops.infer env b);
    let infos = conversion_infos ~typed env in
    let before = Gc.allocated_bytes () in
    let result = lazy_projection_sources CONV false infos
      Esubst.el_id field relevance (CClosure.inject a)
      Esubst.el_id field relevance (CClosure.inject b)
      (Environ.universes env, checked_universes_gen Sorts.Quality.equal) in
    assert (Option.has_some result);
    let allocated = Gc.allocated_bytes () -. before in
    Printf.printf "lazy forwarding source: typed=%b allocated=%.0f\n%!" typed allocated;
    assert (allocated < 4. *. 1024. *. 1024.))
      [forwarded !expensive, forwarded lo; forwarded lo, forwarded !expensive])
    [false; true];
  let pairs = [project left !expensive, project right lo;
               mkLambda (binder, ind atom, project left (mkRel 1)),
               mkLambda (binder, ind atom, project right lo)] in
  List.iter (fun (a, b) ->
    ignore (Typeops.infer env a); ignore (Typeops.infer env b);
    List.iter (fun (a, b) ->
      let before = Gc.allocated_bytes () in
      assert (default_conv CONV env a b = Ok ());
      let allocated = Gc.allocated_bytes () -. before in
      Printf.printf "lazy projection: allocated=%.0f\n%!" allocated;
      assert (allocated < 4. *. 1024. *. 1024.);
      (* Conservative conversion also checks the full well-typed pair. *)
      assert (conv env a b = Ok ())) [a, b; b, a]) pairs;
  let a = project left lo and b = project wrong lo in
  ignore (Typeops.infer env a); ignore (Typeops.infer env b);
  List.iter (fun (a, b) ->
    assert (default_conv CONV env a b <> Ok ());
    assert (conv env a b <> Ok ())) [a, b; b, a];
  let blocked_source = {TransparentState.full with tr_cst =
    Cpred.remove left (Cpred.remove right TransparentState.full.tr_cst)} in
  let blocked_projection = {TransparentState.full with tr_prj =
    PRpred.remove (Projection.repr field) TransparentState.full.tr_prj} in
  let a = project left hi and b = project right lo in
  List.iter (fun reds -> List.iter (fun typed ->
    assert (gen_conv ~typed CONV ~reds env a b <> Ok ());
    assert (gen_conv ~typed CONV ~reds env b a <> Ok ())) [false; true])
    [blocked_source; blocked_projection];
  (* A selected-field equality must not turn into equality of entire sources.
     The selected fields are equal but the discarded fields differ. *)
  let a = app (constant left) [|hi|] and b = app (constant right) [|lo|] in
  assert (default_conv CONV env a b <> Ok ());
  assert (conv env a b <> Ok ());
  print_endline "lazy projection: PASS selected/unused fields, binders, transparency, negative cases"
