open Reviewed_closure
open Constr

let env sharing heuristic =
  let base = Environ.empty_env in
  Environ.set_typing_flags
    { (Environ.typing_flags base) with
      share_reduction = sharing; unfold_dep_heuristic = heuristic } base

let () =
  let binder = Context.make_annot Names.Anonymous Sorts.Relevant in
  let name = Names.Id.of_string "symbolic_identity" in
  let identity_definition = Context.Named.Declaration.LocalDef
    (Context.make_annot name Sorts.Relevant,
     mkLambda (binder, mkProp, mkRel 1), mkProd (binder, mkProp, mkProp)) in
  let symbolic = mkApp (mkVar name, [|mkSProp|]) in
  List.iter (fun core_first ->
    let env = Environ.push_named Environ.ProofVar identity_definition (env true true) in
    let full = create_conv_infos RedFlags.all env in
    let core = infos_with_reds full RedFlags.betaiotazeta in
    let tab = create_tab () in
    let source = inject symbolic in
    if core_first then ignore (whd_stack core tab source []);
    let reduced = whd_stack full tab source [] in
    assert (Constr.equal (term_of_process (fst reduced) (snd reduced)) mkSProp);
    assert (Constr.equal (term_of_fconstr source) mkSProp);
    let view = match source.symbolic with
      | SymbolicView view -> view | _ -> assert false in
    assert (view.symbolic = SymbolicCopy);
    let ordinary = whd_stack core tab source [] in
    assert (Constr.equal (term_of_process (fst ordinary) (snd ordinary)) mkSProp);
    let recovered = whd_stack (infos_with_symbolic_views core) tab source [] in
    assert (Constr.equal (term_of_process (fst recovered) (snd recovered)) symbolic);
    let still_full = whd_stack (infos_with_symbolic_views full) tab source [] in
    assert (Constr.equal (term_of_process (fst still_full) (snd still_full)) mkSProp);
    let cheap = whd_stack core tab (Option.get (symbolic_view source)) [] in
    assert (Constr.equal (term_of_process (fst cheap) (snd cheap)) symbolic);
    let head = fst cheap in
    let reduced = whd_stack full tab source [] in
    for _ = 1 to 1000 do
      let again = whd_stack full tab source [] in
      assert (fst again == fst reduced);
      let cheap = whd_stack core tab (Option.get (symbolic_view source)) [] in
      assert (fst cheap == head);
      assert (Constr.equal (term_of_process (fst cheap) (snd cheap)) symbolic);
      assert (Constr.equal (term_of_fconstr source) mkSProp);
      assert (match source.symbolic with SymbolicView v -> v == view | _ -> false)
    done
  ) [false; true];
  (* A neutral reduced cell can retain a symbolic beta-redex. The neutral
     fast path is only valid for its reduced view, not the restored syntax. *)
  let test_env = env true true in
  let full = create_conv_infos RedFlags.all test_env in
  let term = mkApp (mkLambda (binder, mkSort Sorts.type1, mkRel 1), [|mkProp|]) in
  ignore (Typeops.infer test_env term);
  let source = inject term in
  let tab = create_tab () in
  ignore (whd_stack full tab source []);
  assert (Constr.equal (term_of_fconstr source) mkProp);
  let recovered = whd_stack
      (infos_with_symbolic_views (infos_with_reds full RedFlags.betaiotazeta))
      tab source [] in
  assert (Constr.equal (term_of_process (fst recovered) (snd recovered)) mkProp);
  (* A reduced closed value can hide an OPEN symbolic application. Lifting
     must relocate that view too, even though the reduced value needs no lift. *)
  let name = Names.Id.of_string "symbolic_ignore" in
  let atom = Names.Id.of_string "symbolic_atom" in
  let definition = Context.Named.Declaration.LocalDef
    (Context.make_annot name Sorts.Relevant,
     mkLambda (binder, mkProp, mkVar atom), mkProd (binder, mkProp, mkProp)) in
  let open_env = Environ.push_named Environ.ProofVar
    (Context.Named.Declaration.LocalAssum
      (Context.make_annot atom Sorts.Relevant, mkProp)) (env true true) in
  let open_env = Environ.push_named Environ.ProofVar definition open_env in
  let full = create_conv_infos RedFlags.all open_env in
  let core = infos_with_reds full RedFlags.betaiotazeta in
  let tab = create_tab () in
  let source = inject (mkApp (mkVar name, [|mkRel 1|])) in
  ignore (whd_stack full tab source []);
  let lifted = lift_fconstr 3 source in
  let cheap = whd_stack core tab (Option.get (symbolic_view lifted)) [] in
  assert (Constr.equal (term_of_process (fst cheap) (snd cheap))
    (mkApp (mkVar name, [|mkRel 4|])));
  let path = Names.ModPath.MPfile
    (Names.DirPath.make [Names.Id.of_string "SymbolicViews"]) in
  let ind = Names.MutInd.make2 path (Names.Id.of_string "Node"), 0 in
  let ctor = inject (mkConstructU ((ind, 1), UVars.Instance.empty)) in
  let node = inject (mkVar (Names.Id.of_string "node")) in
  let tree = ref (mk_clos (Esubst.subs_id 1, UVars.Instance.empty) (mkRel 1)) in
  for _ = 1 to 20 do
    let children = [|!tree; !tree|] in
    let reduced = zip ctor [Zapp children] in
    let view = zip node [Zapp children] in
    view.symbolic <- SymbolicCopy;
    reduced.symbolic <- SymbolicView view;
    tree := reduced
  done;
  let before = Gc.allocated_bytes () in
  let lifted = lift_fconstr 3 !tree in
  let allocated = Gc.allocated_bytes () -. before in
  let rec check depth tree = match fterm_of tree with
    | FConstruct (_, args) when depth > 0 ->
      assert (args.(0) == args.(1));
      check (depth - 1) args.(0)
    | FRel 4 when depth = 0 -> ()
    | _ -> assert false in
  check 20 lifted;
  assert (allocated < 100_000.);
  let head, _ = strip_update_shift_absorb_app !tree [Zshift 3] in
  check 20 head;
  List.iter (fun (sharing, heuristic, conversion) ->
    let env = Environ.push_named Environ.ProofVar identity_definition (env sharing heuristic) in
    let infos = if conversion then create_conv_infos RedFlags.all env
      else create_clos_infos RedFlags.all env in
    let source = inject symbolic in
    ignore (whd_stack infos (create_tab ()) source []);
    assert (source.symbolic = NoSymbolicView)
  ) [false, true, true; true, false, true; true, true, false];
  print_endline "symbolic/reduced views: PASS (both visit orders, stable reuse, scoping)"
