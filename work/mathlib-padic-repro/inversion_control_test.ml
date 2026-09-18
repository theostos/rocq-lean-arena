(* Checked declarations and a checked inverted-case term. These tests exercise
   the reduction boundary directly, including retrying the same closure. *)
open Names
open Constr
open Entries
open CClosure
open Reviewed_conversion
open Projected_major_test

let safe = Safe_typing.set_typing_flags
  { (Environ.typing_flags (Safe_typing.env_of_safe_env safe)) with
    Declarations.allow_uip = true; sprop_allowed = true;
    unfold_dep_heuristic = true; indices_matter = false } safe

let witness, safe =
  let entry = mind_entry "AtLo" ["at_lo", app (mkRel 1) [|lo|]] in
  let decl = List.hd entry.mind_entry_inds in
  let entry = {entry with mind_entry_inds = [{decl with
    mind_entry_arity = mkProd (binder, ind atom, mkSProp)}]} in
  let (witness, _), safe = Safe_typing.add_mind (id "AtLo") entry safe in
  witness, safe

let alias, safe = add_definition "inversion_alias" (ind atom) lo safe
let family, safe = add_definition "inversion_family"
  (mkProd (binder, ind atom, mkSet))
  (mkLambda (binder, ind atom, ind atom)) safe
let env = Safe_typing.env_of_safe_env safe
let proof_binder = Context.make_annot Anonymous Sorts.Irrelevant
let case =
  let ci = {ci_ind = witness, 0; ci_npar = 0;
    ci_cstr_ndecls = [|0|]; ci_cstr_nargs = [|0|];
    ci_pp_info = {style = MatchStyle}} in
  mkCase (ci, instance, [||],
    (([|binder; proof_binder|], app (constant family) [|mkRel 2|]), Sorts.Relevant),
    CaseInvert {indices = [|constant alias|]}, ctor witness 1,
    [|[||], lo|])

let () = try ignore (Typeops.infer env case) with Type_errors.TypeError (_, error) as exn ->
  let label = match error with
    | Type_errors.BadInvert -> "BadInvert"
    | Type_errors.BadBinderRelevance _ -> "BadBinderRelevance"
    | Type_errors.BadCaseRelevance _ -> "BadCaseRelevance"
    | Type_errors.ElimArity (_, _, None) -> "ElimArity (not a sort)"
    | Type_errors.ElimArity (_, _, Some _) -> "ElimArity (squashed)"
    | Type_errors.IllFormedBranch _ -> "IllFormedBranch"
    | Type_errors.ActualType _ -> "ActualType"
    | Type_errors.WrongCaseInfo _ -> "WrongCaseInfo"
    | Type_errors.CantApplyBadType _ -> "CantApplyBadType"
    | Type_errors.UnboundRel n -> "UnboundRel " ^ string_of_int n
    | _ -> "other" in
  Printf.eprintf "inversion fixture: %s\n%!" label; raise exn
let base = create_conv_infos RedFlags.all env
let reduce infos term = whd_stack infos (create_tab ()) term []
let is_lo (head, stack) = Constr.equal (term_of_process head stack) lo

let () =
  expect (is_lo (reduce base (inject case))) "ordinary inversion did not reduce";
  let budget = ref 64 in
  let bounded = infos_with_conversion_work base (Some budget) in
  expect (is_lo (reduce bounded (inject case))) "bounded inversion failed";
  expect (!budget < 64) "nested inversion bypassed its caller's counter";
  let exhausted = infos_with_conversion_work base (Some (ref 0)) in
  let exhausted_as_exception () =
    try ignore (reduce exhausted (inject case)); false
    with Strategy_budget_exhausted -> true in
  expect (exhausted_as_exception ()) "exhaustion was swallowed or ignored";
  let symbolic = infos_with_symbolic_views exhausted in
  let head, stack = reduce symbolic (inject case) in
  let head = zip head stack in
  expect (match fterm_of head with FCaseInvert _ -> true | _ -> false)
    "symbolic recovery evaluated an inverted case";
  expect (is_lo (reduce base head)) "symbolic view poisoned an ordinary retry";
  expect (info_conversion_work base = None) "allowance leaked into another query";
  Printf.printf "inversion control: checked term, inherited work, exhaustion, symbolic deferral and same-cell retry passed\n%!"
