(* Different outer fields must reject source congruence before its arguments. *)
open Names
open Constr
open Reviewed_conversion
open Projected_major_test

let () =
  let function_type = mkProd (binder, ind atom, ind atom) in
  let ci = { ci_ind = atom, 0; ci_npar = 0;
    ci_cstr_ndecls = [|0; 0|]; ci_cstr_nargs = [|0; 0|];
    ci_pp_info = {style = MatchStyle} } in
  let method_, safe = add_definition "computed_method_for_fields"
    (mkProd (binder, ind atom, function_type))
    (mkLambda (binder, ind atom,
      mkCase (ci, instance, [||], (([|binder|], function_type), Sorts.Relevant),
        NoInvert, mkRel 1,
        [|[||], mkLambda (binder, ind atom, lo);
          [||], mkLambda (binder, ind atom, lo)|]))) safe in
  let methods, (first, relevance), safe = add_record "TwoMethods"
    ["first", function_type; "second", function_type] safe in
  let mib = Environ.lookup_mind methods (Safe_typing.env_of_safe_env safe) in
  let second, _ = Declareops.inductive_make_projection (methods, 0) mib ~proj_arg:1 in
  let second = Projection.make second false in
  let outer, (parent, parent_relevance), safe = add_record "NestedMethods"
    ["methods", ind methods; "unused", ind atom] safe in
  let selected = app (constant method_) [|lo|] in
  let wrapper, safe = add_definition "nested_methods_wrapper"
    (mkProd (binder, ind atom, ind outer))
    (mkLambda (binder, ind atom,
      app (ctor outer 1) [|app (ctor methods 1) [|selected; selected|]; mkRel 1|])) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let env = Environ.set_typing_flags
    {(Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true} env in
  let source arg = mkProj (parent, parent_relevance, app (constant wrapper) [|arg|]) in
  let expensive = ref hi in
  for _ = 1 to 1024 do expensive := app (constant boolean_not) [|!expensive|] done;
  let left = app (mkProj (first, relevance, source !expensive)) [|hi|] in
  let right = app (mkProj (second, relevance, source (app (constant boolean_not) [|lo|]))) [|hi|] in
  ignore (Typeops.infer env left);
  ignore (Typeops.infer env right);
  let before = Gc.allocated_bytes () in
  let started = Sys.time () in
  assert (default_conv CONV env left right = Ok ());
  let allocated = Gc.allocated_bytes () -. before in
  Printf.printf "projection mismatch: allocated=%.0f cpu=%.6f\n%!"
    allocated (Sys.time () -. started);
  assert (allocated < 4. *. 1024. *. 1024.)
