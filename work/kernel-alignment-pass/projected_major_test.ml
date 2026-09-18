(* Demanded reduction/representation tests. The record declarations and small
   terms below are checked by Safe_typing/Typeops. Synthetic stack suffixes and
   resource-limit inputs test the helpers, not acceptance of any proof. *)
open Names
open Constr
open Entries
open CClosure
open Esubst
open Reviewed_conversion

let id = Id.of_string
let binder = Context.make_annot Anonymous Sorts.Relevant
let named s = Context.make_annot (Name (id s)) Sorts.Relevant
let instance = UVars.Instance.empty
let identity = subs_id 0, instance
let app f args = mkApp (f, args)
let ind mind = mkIndU ((mind, 0), instance)
let ctor mind number = mkConstructU (((mind, 0), number), instance)
let constant c = mkConstU (c, instance)
let expect condition message = if not condition then failwith message
let get = function Some value -> value | None -> failwith "unexpected None"
let none = function None -> true | Some _ -> false

let checked_fixture name f =
  try
    let value = f () in
    Printf.printf "projected major: checked fixture %s\n%!" name;
    value
  with exn ->
    Printf.eprintf "projected major: fixture %s failed: %s\n%!"
      name (Printexc.to_string exn);
    raise exn

let mind_entry ?(record = false) name constructors = {
  mind_entry_record = if record then Some (Some [|id "self"|]) else None;
  mind_entry_finite = Declarations.BiFinite;
  mind_entry_params = [];
  mind_entry_inds = [{
    mind_entry_typename = id name;
    mind_entry_arity = mkSet;
    mind_entry_consnames = List.map (fun (name, _) -> id name) constructors;
    mind_entry_lc = List.map snd constructors;
  }];
  mind_entry_universes = Monomorphic_ind_entry;
  mind_entry_variance = None;
  mind_entry_private = None;
}

let add_record name fields safe =
  (* All field types here are closed; the final Rel crosses the fields back
     to the inductive binder, as required by the add_mind entry format. *)
  let result = mkRel (List.length fields + 1) in
  let typ = List.fold_right (fun (name, typ) body ->
    mkProd (named name, typ, body)) fields result in
  let (mind, _), safe = checked_fixture name (fun () ->
    Safe_typing.add_mind (id name)
      (mind_entry ~record:true name ["make_" ^ name, typ]) safe) in
  let mib = Environ.lookup_mind mind (Safe_typing.env_of_safe_env safe) in
  expect (match mib.Declarations.mind_packets.(0).mind_record with
    | Declarations.PrimRecord _ -> true | _ -> false) "not a primitive record";
  let projection, relevance = Declareops.inductive_make_projection (mind, 0) mib
    ~proj_arg:0 in
  mind, (Projection.make projection false, relevance), safe

let add_definition name typ body safe =
  checked_fixture name (fun () -> Safe_typing.add_constant (id name) (DefinitionEntry {
    definition_entry_body = body;
    definition_entry_secctx = None;
    definition_entry_type = Some typ;
    definition_entry_universes = Monomorphic_entry;
    definition_entry_inline_code = false;
  }) safe)

let safe, atom, payload, holder, fun_holder, projection, fun_projection,
    source_constant, opaque_source, eliminator, boolean_not =
  let _, safe = Safe_typing.start_library
    (DirPath.make [id "ProjectedMajorTest"]) Safe_typing.empty_environment in
  let (atom, _), safe = Safe_typing.add_mind (id "Atom")
    (mind_entry "Atom" ["lo", mkRel 1; "hi", mkRel 1]) safe in
  (* The projected payload is an ordinary constructor with fields, so its
     checked eliminator may use Case. Rocq forbids Case on primitive records;
     Holder and FunHolder, the projection sources, are primitive records. *)
  let (payload, _), safe = checked_fixture "Payload" (fun () ->
    Safe_typing.add_mind (id "Payload")
      (mind_entry "Payload" ["make_Payload",
        mkProd (named "left", ind atom,
          mkProd (named "right", ind atom, mkRel 3))]) safe) in
  let holder, projection, safe = add_record "Holder"
    ["value", ind payload; "sentinel", ind atom] safe in
  let fun_holder, fun_projection, safe = add_record "FunHolder"
    ["run", mkProd (binder, ind atom, ind payload)] safe in
  let value = app (ctor payload 1) [|ctor atom 1; ctor atom 2|] in
  let source = app (ctor holder 1) [|value; ctor atom 2|] in
  let source_constant, safe = add_definition "record_source" (ind holder) source safe in
  (* A real opaque declaration with a checked type and no supplied proof body.
     We test only that its projection cannot be reduced. *)
  let opaque_source, safe = Safe_typing.add_constant (id "opaque_source")
    (OpaqueEntry {
      opaque_entry_body = ();
      opaque_entry_secctx = Id.Set.empty;
      opaque_entry_type = ind holder;
      opaque_entry_universes = Monomorphic_entry;
    }) safe in
  let ci = { ci_ind = payload, 0; ci_npar = 0;
    ci_cstr_ndecls = [|2|]; ci_cstr_nargs = [|2|];
    ci_pp_info = {style = MatchStyle} } in
  let case = mkCase (ci, instance, [||],
    (([|binder|], ind atom), Sorts.Relevant), NoInvert, mkRel 1,
    [|([|named "left"; named "right"|], mkRel 2)|]) in
  let typ = mkProd (binder, ind atom, mkProd (binder, ind payload, ind atom)) in
  let body = mkLambda (binder, ind atom, mkLambda (binder, ind payload, case)) in
  let eliminator, safe = add_definition "select_left" typ body safe in
  (* Atom is a two-constructor Boolean fixture; no arithmetic registration or
     fabricated metadata is required to test a computed Boolean major. *)
  let ci = { ci_ind = atom, 0; ci_npar = 0;
    ci_cstr_ndecls = [|0; 0|]; ci_cstr_nargs = [|0; 0|];
    ci_pp_info = {style = MatchStyle} } in
  let body = mkLambda (binder, ind atom,
    mkCase (ci, instance, [||], (([|binder|], ind atom), Sorts.Relevant),
      NoInvert, mkRel 1, [|([||], ctor atom 2); ([||], ctor atom 1)|])) in
  let boolean_not, safe = add_definition "boolean_not"
    (mkProd (binder, ind atom, ind atom)) body safe in
  safe, atom, payload, holder, fun_holder, projection, fun_projection,
    source_constant, opaque_source, eliminator, boolean_not

let env =
  let env = Safe_typing.env_of_safe_env safe in
  Environ.set_typing_flags
    { (Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true } env
let lo = ctor atom 1
let hi = ctor atom 2
let value a b = app (ctor payload 1) [|a; b|]
let record v = app (ctor holder 1) [|v; hi|]
let project source = let p, r = projection in mkProj (p, r, source)
let value0 = value lo hi
let source0 = record value0
let projected0 = project source0
let reference = ConstKey (eliminator, instance)
let clos ?(reds = RedFlags.all) env = create_conv_infos reds env

let conversion_infos ?(typed = true) ?(reds = RedFlags.all) env : unit conv_tab = {
  cnv_inf = clos ~reds env; cnv_typ = typed;
  cnv_rel_types = Range.empty; cnv_rel_type_lifts = Range.empty;
  cnv_probe_budget = None; cnv_strategy_budget = None; cnv_symbolic_budget = None;
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

let ordinary ?(reds = RedFlags.all) env term =
  norm_val (create_clos_infos reds env) (create_tab ()) (inject term)

(* Private demand must preserve the caller's closure cells and arrays.
   Deferred substitutions used in tests are supplied as extra roots. *)
let unchanged roots =
  let seen = ref [] in
  let checks = ref [] in
  let rec visit root =
    if not (List.exists (fun previous -> previous == root) !seen) then begin
      seen := root :: !seen;
      let before = fterm_of root in
      checks := (fun () -> expect (fterm_of root == before)
        "source closure mutated") :: !checks;
      match before with
      | FConstruct (_, args) -> vector args
      | FApp (head, args) -> visit head; vector args
      | FProj (_, _, source) | FLIFT (_, source) -> visit source
      | _ -> ()
    end
  and vector args =
    let before = Array.copy args in
    checks := (fun () -> Array.iteri (fun i old ->
      expect (args.(i) == old) "source array mutated") before) :: !checks;
    Array.iter visit args
  in
  List.iter visit roots;
  fun () -> List.iter (fun check -> check ()) !checks

let check_result ?(reds = RedFlags.all) ?(extra = [])
    ?(constructor = ((payload, 0), 1)) ?(field_count = 2) env input expected =
  let syntax = term_of_fconstr input in
  ignore (Typeops.infer env syntax);
  ignore (Typeops.infer env expected);
  let check = unchanged (input :: extra) in
  let result = get (reduce_constructor_major (clos ~reds env) input) in
  (match fterm_of result with
   | FConstruct ((actual, _), fields) ->
     expect (Construct.UserOrd.equal actual constructor) "wrong constructor";
     expect (Array.length fields = field_count) "lost constructor fields"
   | _ -> failwith "result is not a constructor root with fields");
  let result_term = term_of_fconstr result in
  expect (Constr.equal result_term expected) "wrong result syntax";
  expect (Constr.equal result_term (ordinary ~reds env syntax))
    "result differs from ordinary small reduction";
  check ();
  result

let check_none ?(reds = RedFlags.all) ?(extra = []) env input =
  let check = unchanged (input :: extra) in
  expect (none (reduce_constructor_major (clos ~reds env) input))
    "expected None";
  check ()

let assume typ env = Environ.push_rel
  (Context.Rel.Declaration.LocalAssum (binder, typ)) env
let define typ body env = Environ.push_rel
  (Context.Rel.Declaration.LocalDef (binder, body, typ)) env

let tests = ref 0
let failures = ref []
let test name f =
  incr tests;
  try f (); Printf.printf "projected major: PASS %s\n%!" name
  with exn ->
    let message = Printexc.to_string exn in
    failures := (name, message) :: !failures;
    Printf.printf "projected major: FAIL %s: %s\n%!" name message

let () =
  test "checked primitive projection returns both constructor fields" (fun () ->
    ignore (check_result env (inject projected0) value0));

  test "shared source remains valid for subsequent reductions" (fun () ->
    let machine = clos env in
    let source_head, source_stack = whd_stack machine (create_tab ()) (inject source0) [] in
    let source = zip source_head source_stack in
    (* The substitution deliberately shares the source with a separate caller. *)
    let input = mk_clos (usubs_cons source identity) (project (mkRel 1)) in
    let result = check_result ~extra:[source] env input value0 in
    (match fterm_of source, fterm_of result with
     | FConstruct (_, source_args), FConstruct (_, result_args) ->
       expect (source_args != result_args) "returned source argument array";
       expect (Constr.equal (term_of_fconstr source_args.(0)) value0)
         "shared payload changed meaning"
     | _ -> failwith "fixture did not expose constructor source");
    let check = unchanged [input; source] in
    ignore (norm_val (create_clos_infos RedFlags.all env) (create_tab ()) result);
    check ());

  test "FProj and FApp projected-function views" (fun () ->
    let p, r = fun_projection in
    let fn = mkLambda (binder, ind atom, value (mkRel 1) hi) in
    let source = app (ctor fun_holder 1) [|fn|] in
    let syntax = app (mkProj (p, r, source)) [|lo|] in
    (* beta/zeta alone exposes the projection but leaves it uncontracted. *)
    let head, stack = whd_stack (clos ~reds:RedFlags.betazeta env)
      (create_tab ()) (inject syntax) [] in
    let input = zip head stack in
    expect (match fterm_of input with FApp _ -> true | _ -> false)
      "fixture did not produce FApp";
    ignore (check_result env input value0));

  test "relative constructor fields" (fun () ->
    let env = env |> assume (ind atom) |> assume (ind atom) in
    let expected = value (mkRel 2) (mkRel 1) in
    ignore (check_result env (inject (project (record expected))) expected));

  test "LocalDef source beneath another binder" (fun () ->
    let env = env |> assume (ind atom)
      |> define (ind holder) (record (value (mkRel 1) hi))
      |> assume (ind atom) in
    ignore (check_result env (inject (project (mkRel 2))) (value (mkRel 3) hi)));

  test "substituted source with lifted binder" (fun () ->
    let env = env |> assume (ind atom) |> assume (ind atom) in
    let source = inject (record (value (mkRel 1) hi)) in
    let subst = usubs_lift (usubs_cons source identity) in
    let input = mk_clos subst (project (mkRel 2)) in
    ignore (check_result ~extra:[source] env input (value (mkRel 2) hi)));

  test "FLIFT preserves open fields" (fun () ->
    let env = env |> assume (ind atom) |> assume (ind atom) |> assume (ind atom) in
    let inner = inject (project (record (value (mkRel 1) hi))) in
    let input = zip inner [Zshift 2] in
    expect (match fterm_of input with FLIFT _ -> true | _ -> false)
      "fixture did not produce FLIFT";
    ignore (check_result ~extra:[inner] env input (value (mkRel 3) hi)));

  test "transparent record constant" (fun () ->
    ignore (check_result env (inject (project (constant source_constant))) value0));

  test "blocked projection" (fun () ->
    let p, _ = projection in
    let reds = RedFlags.red_sub RedFlags.all (RedFlags.fPROJ (Projection.repr p)) in
    let input = inject projected0 in
    check_none ~reds env input;
    expect (Constr.equal (ordinary ~reds env projected0) projected0)
      "ordinary reduction crossed blocked projection");

  test "blocked transparent record source" (fun () ->
    let reds = RedFlags.red_sub RedFlags.all (RedFlags.fCONST source_constant) in
    check_none ~reds env (inject (project (constant source_constant))));

  test "oracle-opaque record source with oracle transparency mask" (fun () ->
    let oracle = Conv_oracle.set_strategy (Environ.oracle env)
      (Conv_oracle.EvalConstRef source_constant) Conv_oracle.Opaque in
    let env = Environ.set_oracle env oracle in
    let reds = RedFlags.red_add_transparent RedFlags.all
      (Conv_oracle.get_transp_state oracle) in
    check_none ~reds env (inject (project (constant source_constant))));

  test "kernel-opaque source has no reducible body" (fun () ->
    let syntax = project (constant opaque_source) in
    ignore (Typeops.infer env syntax);
    check_none env (inject syntax));

  test "neutral record source" (fun () ->
    let env = assume (ind holder) env in
    check_none env (inject (project (mkRel 1))));

  test "neutral projected field" (fun () ->
    let env = assume (ind payload) env in
    check_none env (inject (project (record (mkRel 1)))));

  test "stuck demand preserves the original symbolic root" (fun () ->
    let env = assume (ind atom) env in
    let input = inject (app (constant boolean_not) [|mkRel 1|]) in
    let before = fterm_of input in
    check_none env input;
    expect (fterm_of input == before) "stuck demand overwrote its symbolic root");

  test "successful demand preserves the source expression" (fun () ->
    let input = inject projected0 in
    let before = fterm_of input in
    ignore (check_result env input value0);
    expect (fterm_of input == before) "successful demand overwrote its source");

  test "demand preserves sharing of repeated let computations" (fun () ->
    let ci = { ci_ind = atom, 0; ci_npar = 0;
      ci_cstr_ndecls = [|0; 0|]; ci_cstr_nargs = [|0; 0|];
      ci_pp_info = {style = MatchStyle} } in
    let force_twice = mkCase (ci, instance, [||],
      (([|binder|], ind atom), Sorts.Relevant), NoInvert, mkRel 1,
      [|([||], mkRel 1); ([||], mkRel 1)|]) in
    let allocation depth =
      let syntax = ref lo in
      for _ = 1 to depth do
        syntax := mkLetIn (binder, !syntax, ind atom, force_twice)
      done;
      ignore (Typeops.infer env !syntax);
      let input = inject !syntax in
      let machine = clos env in
      let before = Gc.allocated_bytes () in
      let result = get (reduce_constructor_major machine input) in
      let allocated = Gc.allocated_bytes () -. before in
      expect (Constr.equal (term_of_fconstr result) lo) "wrong shared result";
      allocated in
    let small = allocation 8 in
    let large = allocation 16 in
    Printf.printf "demanded sharing allocation: depth8=%.0f depth16=%.0f\n%!" small large;
    expect (large <= 8. *. small +. 1_000_000.)
      "demand duplicated a shared computation exponentially");

  test "already-visible constructors need no field normalization" (fun () ->
    ignore (check_result env (inject value0) value0);
    ignore (check_result ~constructor:((atom, 0), 1) ~field_count:0 env (inject lo) lo));

  test "beta demand returns a constructor with fields" (fun () ->
    let syntax = app (mkLambda (binder, ind payload, mkRel 1)) [|value0|] in
    ignore (check_result env (inject syntax) value0));

  test "let/beta demand preserves substitution" (fun () ->
    let env = assume (ind atom) env in
    let syntax = mkLetIn (binder, value (mkRel 1) hi, ind payload,
      app (mkLambda (binder, ind payload, mkRel 1)) [|mkRel 1|]) in
    ignore (check_result env (inject syntax) (value (mkRel 1) hi)));

  test "computed Boolean demand, not just projections" (fun () ->
    let syntax = app (constant boolean_not) [|lo|] in
    ignore (check_result ~constructor:((atom, 0), 2) ~field_count:0
      env (inject syntax) hi));

  test "computed Boolean neutral and blocked function decline" (fun () ->
    let env = assume (ind atom) env in
    check_none env (inject (app (constant boolean_not) [|mkRel 1|]));
    let reds = RedFlags.red_sub RedFlags.all (RedFlags.fCONST boolean_not) in
    check_none ~reds env (inject (app (constant boolean_not) [|lo|])));

  test "demanded reduction has no shallow head-step cutoff" (fun () ->
    let identity_record = mkLambda (binder, ind holder, mkRel 1) in
    List.iter (fun depth ->
      let source = ref source0 in
      for _ = 1 to depth do source := app identity_record [|!source|] done;
      let result = get (reduce_constructor_major (clos env) (inject (project !source))) in
      expect (Constr.equal (term_of_fconstr result) value0) "deep demand declined")
      [16; 256; 4096; 16384]);

  test "large unused substitution is not copied or forced" (fun () ->
    let shared = inject lo in
    let subst = ref identity in
    for _ = 1 to 5500 do subst := usubs_cons shared !subst done;
    let result = get (reduce_constructor_major (clos env) (mk_clos !subst projected0)) in
    expect (Constr.equal (term_of_fconstr result) value0) "unused environment blocked demand");

  test "expose replaces major in copied frame and agrees with ordinary iota" (fun () ->
    let major = inject projected0 and other = inject hi in
    let args = [|other; major|] in
    let stack = [Zapp args] in
    let check = unchanged [major; other] in
    let result = expose_eliminator_major (conversion_infos env) reference stack in
    (match result with
     | [Zapp copied] ->
       expect (copied != args) "application array not copied";
       expect (copied.(0) == other && args.(1) == major) "unrelated argument changed";
       expect (Constr.equal (term_of_fconstr copied.(1)) value0) "wrong exposed major"
     | _ -> failwith "application frame lost");
    let head = inject (constant eliminator) in
    let before = term_of_process head stack in
    let after = term_of_process head result in
    ignore (Typeops.infer env before); ignore (Typeops.infer env after);
    expect (Constr.equal (ordinary env before) lo) "wrong ordinary case result";
    expect (Constr.equal (ordinary env after) (ordinary env before)) "exposure changed meaning";
    check ());

  test "expose computed Boolean into another checked Boolean case" (fun () ->
    let major = inject (app (constant boolean_not) [|lo|]) in
    let args = [|major|] in
    let check = unchanged [major] in
    let result = expose_eliminator_major (conversion_infos env)
      (ConstKey (boolean_not, instance)) [Zapp args] in
    (match result with
     | [Zapp copied] ->
       expect (copied != args && args.(0) == major)
         "Boolean frame not copied";
       expect (Constr.equal (term_of_fconstr copied.(0)) hi) "Boolean not exposed"
     | _ -> failwith "Boolean frame lost");
    let head = inject (constant boolean_not) in
    let before = term_of_process head [Zapp args] in
    let after = term_of_process head result in
    ignore (Typeops.infer env before); ignore (Typeops.infer env after);
    expect (Constr.equal (ordinary env before) lo && Constr.equal (ordinary env after) lo)
      "Boolean exposure changed case result";
    check ());

  test "split frames preserve prefix/suffix, shifts and update targets" (fun () ->
    let other = inject hi and major = inject projected0 and update = inject lo in
    let first = Zapp [|other|] in
    let shift = Zshift 2 and update_frame = Zupdate update in
    let args = [|major; other|] in
    let tail = [Zshift 3; Zapp [|other|]; Zupdate update] in
    let stack = first :: shift :: update_frame :: Zapp args :: tail in
    let check = unchanged [major; other; update] in
    let result = expose_eliminator_major (conversion_infos env) reference stack in
    (match result with
     | first' :: shift' :: update' :: Zapp copied :: tail' ->
       expect (first' == first && shift' == shift && update' == update_frame && tail' == tail)
         "untouched frames not preserved";
       expect (copied != args && copied.(1) == other && args.(0) == major)
         "wrong argument replacement";
       expect (Constr.equal (term_of_fconstr copied.(0)) value0) "wrong major"
     | _ -> failwith "stack topology changed");
    check ());

  let unchanged_stack ?(infos = conversion_infos env) stack =
    expect (expose_eliminator_major infos reference stack == stack)
      "declined exposure did not return original stack" in
  test "application length does not impose a demand cutoff" (fun () ->
    List.iter (fun length ->
    let major = inject projected0 in
    let args = Array.make length (inject lo) in
    args.(1) <- major;
    let result = expose_eliminator_major (conversion_infos env) reference [Zapp args] in
    (match result with
     | [Zapp copied] ->
       expect (copied != args && args.(1) == major) "application rejected"
     | _ -> failwith "wrong accepted frame");
    ()) [1024; 1025; 8192]);

  test "frame traversal does not impose a demand cutoff" (fun () ->
    List.iter (fun length ->
    let tail = [Zapp [|inject lo; inject projected0|]] in
    let prefix n = List.init n (fun _ -> Zshift 1) in
    let accepted = prefix length @ tail in
    expect (expose_eliminator_major (conversion_infos env) reference accepted != accepted)
      "deep frame rejected") [127;128;4096]);

  test "unsupported frame before major and missing major decline" (fun () ->
    let p, r = projection in
    unchanged_stack [Zproj (Projection.repr p, r); Zapp [|inject lo; inject projected0|]];
    unchanged_stack [Zapp [|inject lo|]];
    unchanged_stack []);

  test "neutral or blocked major preserves original stack" (fun () ->
    let env = assume (ind holder) env in
    unchanged_stack ~infos:(conversion_infos env)
      [Zapp [|inject lo; inject (project (mkRel 1))|]];
    let p, _ = projection in
    let reds = RedFlags.red_sub RedFlags.all (RedFlags.fPROJ (Projection.repr p)) in
    unchanged_stack ~infos:(conversion_infos ~reds env)
      [Zapp [|inject lo; inject projected0|]]);

  test "untyped, disabled heuristic and blocked eliminator decline" (fun () ->
    let stack = [Zapp [|inject lo; inject projected0|]] in
    unchanged_stack ~infos:(conversion_infos ~typed:false env) stack;
    let no_heuristic = Environ.set_typing_flags
      { (Environ.typing_flags env) with Declarations.unfold_dep_heuristic = false } env in
    unchanged_stack ~infos:(conversion_infos no_heuristic) stack;
    let reds = RedFlags.red_sub RedFlags.all (RedFlags.fCONST eliminator) in
    unchanged_stack ~infos:(conversion_infos ~reds env) stack;
    List.iter (fun level ->
      let oracle = Conv_oracle.set_strategy (Environ.oracle env)
        (Conv_oracle.EvalConstRef eliminator) level in
      unchanged_stack ~infos:(conversion_infos (Environ.set_oracle env oracle)) stack)
      [Conv_oracle.Expand; Conv_oracle.Level (-9); Conv_oracle.Opaque]);

  Printf.printf "projected major: %d/%d tests passed\n%!"
    (!tests - List.length !failures) !tests;
  if !failures <> [] then exit 1
