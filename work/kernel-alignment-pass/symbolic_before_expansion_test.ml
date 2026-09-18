(* The original expression must be considered before a large expanded value
   can consume the syntactic lookup budget. All declarations/terms are checked;
   this test inspects cache lookup, not acceptance of a supplied proof. *)
open Names
open Constr
open CClosure
open Reviewed_conversion
open Projected_major_test

let () =
  let width = 1200 in
  let constructor_type = ref (mkRel (width + 1)) in
  for _ = 1 to width do
    constructor_type := mkProd (binder, ind atom, !constructor_type)
  done;
  let (wide, _), safe = Safe_typing.add_mind (id "Wide")
    (mind_entry "Wide" ["wide", !constructor_type]) safe in
  let term = app (ctor wide 1) (Array.make width lo) in
  let wrapper, safe = add_definition "wide_wrapper"
    (mkProd (binder, ind atom, ind wide))
    (mkLambda (binder, ind atom, term)) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let env = Environ.set_typing_flags
    {(Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true} env in
  let expression = app (constant wrapper) [|lo|] in
  ignore (Typeops.infer env expression);
  let infos = create_conv_infos RedFlags.all env in
  let expand () =
    let root = inject expression in
    ignore (whd_stack infos (create_tab ()) root []);
    root in
  let left, right = expand (), expand () in
  let before_left, before_right = fterm_of left, fterm_of right in
  let budget = ref 1024 in
  assert (fast_test_under ~symbolic:true budget Esubst.el_id left Esubst.el_id right);
  assert (!budget > 0);
  assert (fterm_of left == before_left && fterm_of right == before_right);
  assert (not (fast_test_under (ref 1024) Esubst.el_id left Esubst.el_id right));
  print_endline "symbolic lookup: PASS original checked expression before 1200-field expansion; ordinary bounded probe unchanged"
