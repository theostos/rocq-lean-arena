(* Well-typed terms; rebuilding their closures must not lose established
   equality, or confuse different captured values, lifts or local contexts. *)
open Names
open Constr
open CClosure
open Reviewed_conversion
open Projected_major_test

let () =
  let identity, safe = add_definition "suspended_identity"
    (mkProd (binder, ind atom, ind atom)) (mkLambda (binder, ind atom, mkRel 1)) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let env = Environ.set_typing_flags
    {(Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true} env in
  let left_body = app (constant boolean_not) [|app (constant boolean_not) [|mkRel 1|]|] in
  let right_body = app (constant identity) [|mkRel 1|] in
  let clos body value = mk_clos (usubs_cons (inject value) (Esubst.subs_id 0, instance)) body in
  let pair a b = clos left_body a, clos right_body b in
  let infos = { (conversion_infos env) with
    cnv_memoize_successful_conversions = true;
    cnv_successful_conversions = make_successful_conversion_cache 32768 } in
  let cu = Environ.universes env, checked_universes_gen Sorts.Quality.equal in
  let check a b =
    ignore (Typeops.infer env (term_of_fconstr a));
    ignore (Typeops.infer env (term_of_fconstr b));
    ignore (ccnv CONV false infos Esubst.el_id Esubst.el_id a b cu) in
  let a, b = pair lo lo in
  check a b;
  assert (infos.cnv_successful_conversions.suspended_size > 0);
  let c, d = pair lo lo in
  assert (a != c && b != d);
  let key = suspended_key infos c d in
  assert (suspended_cached infos CONV Esubst.el_id Esubst.el_id key);
  check c d;
  let c, d = pair hi hi in
  assert (not (suspended_cached infos CONV Esubst.el_id Esubst.el_id (suspended_key infos c d)));
  check c d;
  let wrong1, wrong2 = pair lo hi in
  let key = suspended_key infos wrong1 wrong2 in
  assert (not (suspended_cached infos CONV Esubst.el_id Esubst.el_id key));
  assert (try check wrong1 wrong2; false with NotConvertible | NotConvertibleTrace _ -> true);
  let c, d = pair lo lo in
  let key = suspended_key infos c d in
  assert (not (suspended_cached infos CUMUL Esubst.el_id Esubst.el_id key));
  assert (not (suspended_cached infos CONV (Esubst.el_shft 1 Esubst.el_id) Esubst.el_id key));
  let other_context = { infos with cnv_rel_types = Range.cons None infos.cnv_rel_types } in
  assert (not (suspended_cached other_context CONV Esubst.el_id Esubst.el_id key));
  let other_lifts = { infos with
    cnv_rel_type_lifts = Range.cons Esubst.el_id infos.cnv_rel_type_lifts } in
  assert (not (suspended_cached other_lifts CONV Esubst.el_id Esubst.el_id key));
  let other_relevances = { infos with
    cnv_inf = CClosure.push_relevance infos.cnv_inf
      (Context.make_annot Anonymous Sorts.Relevant) } in
  assert (not (suspended_cached other_relevances CONV Esubst.el_id Esubst.el_id key));
  (* A fresh conversion call/environment never inherits this table. *)
  let fresh = { infos with
    cnv_successful_conversions = make_successful_conversion_cache 32768 } in
  assert (not (suspended_cached fresh CONV Esubst.el_id Esubst.el_id key));
  (* Universe substitutions are part of the suspended expression, even when
     the syntax template itself is physically identical. *)
  let sort_body = mkSort (Sorts.sort_of_univ
    (Univ.Universe.make (Univ.Level.var 0))) in
  let type0 = Univ.Level.set in
  let type1 = Univ.Level.var 1 in
  let universe_subst u = Esubst.subs_id 0, UVars.Instance.of_array ([||], [|u|]) in
  let s0, s1 = universe_subst type0, universe_subst type1 in
  let universe_key = Some ((sort_body, sort_body), s0, s0) in
  (* Reflexivity establishes this entry without relying on any conversion rule. *)
  remember_suspended infos CONV Esubst.el_id Esubst.el_id universe_key;
  assert (suspended_cached infos CONV Esubst.el_id Esubst.el_id universe_key);
  assert (not (suspended_cached infos CONV Esubst.el_id Esubst.el_id
    (Some ((sort_body, sort_body), s1, s0))));
  assert (Option.is_empty (suspended_key
    { infos with cnv_memoize_successful_conversions = false } c d));
  (* The previously captured value is reduced during the successful check.
     A fresh closure of its original syntax must still find that success. *)
  let computed = app (constant boolean_not) [|hi|] in
  let before_left, before_right = pair computed computed in
  check before_left before_right;
  let fresh_left, fresh_right = pair computed computed in
  assert (suspended_cached infos CONV Esubst.el_id Esubst.el_id
    (suspended_key infos fresh_left fresh_right));
  let different = app (constant boolean_not) [|lo|] in
  let wrong_left, wrong_right = pair computed different in
  assert (not (suspended_cached infos CONV Esubst.el_id Esubst.el_id
    (suspended_key infos wrong_left wrong_right)));
  assert (try check wrong_left wrong_right; false
    with NotConvertible | NotConvertibleTrace _ -> true);
  (* Both indexes share one allowance, including repeated context variants.
     Closed operands remain well-typed under these extra fresh binders. *)
  let limit = 16 in
  let cache = make_successful_conversion_cache limit in
  for _ = 1 to 100 do
    let scoped = push_relevance { infos with cnv_successful_conversions = cache }
      (Context.make_annot Anonymous Sorts.Relevant) in
    let c, d = pair lo lo in
    ignore (ccnv CONV false scoped Esubst.el_id Esubst.el_id c d cu);
    assert (cache.suspended_size + cache.successful_conversion_size <= limit)
  done;
  print_endline "suspended cache: PASS reconstructed cells, captures, universes, fresh calls, contexts, lifts, ordered problem, disabled path, shared retention bound"
