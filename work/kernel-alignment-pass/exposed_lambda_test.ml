(* A real reduction-machine path: opening the first binder of a multi-binder
   lambda produces a fresh FLambda, with no original FCLOS view. *)
open Names
open Constr
open CClosure
open Reviewed_conversion
open Projected_major_test

let () =
  let identity, safe = add_definition "exposed_identity"
    (mkProd (binder, ind atom, ind atom)) (mkLambda (binder, ind atom, mkRel 1)) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let env = Environ.set_typing_flags
    {(Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true} env in
  let infos = { (conversion_infos env) with
    cnv_memoize_successful_conversions = true;
    cnv_successful_conversions = make_successful_conversion_cache 32768 } in
  let cu = Environ.universes env, checked_universes_gen Sorts.Quality.equal in
  let lambda body = mkLambda (binder, ind atom, mkLambda (binder, ind atom, body)) in
  let left = lambda (app (constant boolean_not)
    [|app (constant boolean_not) [|mkRel 3|]|]) in
  let right = lambda (app (constant identity) [|mkRel 3|]) in
  let expose template value =
    let subst = usubs_cons (inject value) (Esubst.subs_id 0, instance) in
    let head, stack = whd_stack infos.cnv_inf (create_tab ()) (mk_clos subst template) [] in
    assert (is_empty_stack stack);
    let _, _, tail = destFLambda mk_clos head in
    assert (match fterm_of tail with FLambda _ -> true | _ -> false);
    assert (Option.is_empty (symbolic_view tail));
    ignore (Typeops.infer env (term_of_fconstr tail));
    tail in
  let pair a b = expose left a, expose right b in
  let check a b = ignore (ccnv CONV false infos Esubst.el_id Esubst.el_id a b cu) in
  let computed = app (constant boolean_not) [|hi|] in
  let a, b = pair computed computed in
  check a b;
  let c, d = pair computed computed in
  assert (a != c && b != d);
  let key = suspended_key infos c d in
  assert (Option.has_some key);
  assert (suspended_cached infos CONV Esubst.el_id Esubst.el_id key);
  check c d;
  let c, d = pair computed hi in
  assert (not (suspended_cached infos CONV Esubst.el_id Esubst.el_id
    (suspended_key infos c d)));
  assert (try check c d; false with NotConvertible | NotConvertibleTrace _ -> true);
  assert (not (suspended_cached infos CUMUL Esubst.el_id Esubst.el_id key));
  assert (not (suspended_cached infos CONV (Esubst.el_shft 1 Esubst.el_id) Esubst.el_id key));
  let other = push_relevance infos binder in
  assert (not (suspended_cached other CONV Esubst.el_id Esubst.el_id key));
  print_endline "PASS: exposed lambda cache, captured values, negative conversion, contexts, lifts, direction"

