open Names
open Constr
open CClosure
open Reviewed_conversion
open Projected_major_test

let () =
  let record, (field0, relevance0), safe = add_record "SourceCacheRecord"
    ["first", ind atom; "second", ind atom] safe in
  let typ = mkProd (binder, ind atom, ind record) in
  let wrap, safe = add_definition "source_cache_wrap" typ
    (mkLambda (binder, ind atom,
      app (ctor record 1) [|app (constant boolean_not) [|mkRel 1|];
        app (constant boolean_not) [|app (constant boolean_not) [|mkRel 1|]|]|])) safe in
  let left, safe = add_definition "source_cache_left" typ
    (mkLambda (binder, ind atom, app (ctor record 1) [|lo; mkRel 1|])) safe in
  let right, safe = add_definition "source_cache_right" typ
    (mkLambda (binder, ind atom, app (ctor record 1) [|lo; mkRel 1|])) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let env = Environ.set_typing_flags
    {(Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true} env in
  let mib = Environ.lookup_mind record env in
  let field1, relevance1 = Declareops.inductive_make_projection (record, 0) mib ~proj_arg:1 in
  let field1 = Projection.make field1 false in
  let infos () = { (conversion_infos env) with cnv_memoize_successful_conversions = true } in
  let cu = Environ.universes env, checked_universes_gen Sorts.Quality.equal in
  let a = inject (app (constant boolean_not) [|app (constant boolean_not) [|lo|]|]) in
  let b = inject lo in
  let source c x = zip (inject (constant c)) [Zapp [|x|]] in
  let run infos field relevance c a d b =
    let a, b = source c a, source d b in
    ignore (Typeops.infer env (term_of_fconstr a));
    ignore (Typeops.infer env (term_of_fconstr b));
    lazy_projection_sources CONV false infos Esubst.el_id field relevance a
      Esubst.el_id field relevance b cu in
  let state = infos () in
  assert (Option.has_some (run state field0 relevance0 wrap a wrap b));
  assert (state.cnv_successful_applications.applications_size > 0);
  let hits = state.cnv_successful_applications.applications_hits in
  assert (Option.has_some (run state field1 relevance1 wrap a wrap b));
  assert (state.cnv_successful_applications.applications_hits > hits);
  (* Equal first fields cannot prove the sources or their second fields equal. *)
  let state = infos () in
  assert (Option.has_some (run state field0 relevance0 left (inject lo) right (inject hi)));
  assert (state.cnv_successful_applications.applications_size = 0);
  let rejected = try
    Option.is_empty (run state field1 relevance1 left (inject lo) right (inject hi))
    with NotConvertible | NotConvertibleTrace _ -> true in
  assert rejected;
  print_endline "source cache: PASS reuse across fields; selected-field equality never certifies sources"
