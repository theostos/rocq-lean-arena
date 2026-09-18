(* A hierarchy whose shared fields are computed behind let-bound wrappers. *)
open Names
open Constr
open Reviewed_conversion
open Projected_major_test

let () =
  let ci = { ci_ind = atom, 0; ci_npar = 0;
    ci_cstr_ndecls = [|0; 0|]; ci_cstr_nargs = [|0; 0|];
    ci_pp_info = {style = MatchStyle} } in
  let leaf, safe = add_definition "hierarchy_leaf"
      (mkProd (binder, ind atom, ind atom))
      (mkLambda (binder, ind atom,
        mkCase (ci, instance, [||], (([|binder|], ind atom), Sorts.Relevant),
          NoInvert, mkRel 1, [|[||], lo; [||], lo|]))) safe in
  let rec build depth previous_type previous safe =
    if depth > 12 then () else
    let name = "Hierarchy" ^ string_of_int depth in
    let current, _, safe = add_record name
      ["first", previous_type; "second", previous_type] safe in
    let result_type = ind current in
    let body = mkLambda (binder, ind atom,
        mkLetIn (binder, app (constant previous) [|mkRel 1|], previous_type,
          app (ctor current 1) [|mkRel 1; mkRel 1|])) in
    let current_function, safe = add_definition ("hierarchy" ^ string_of_int depth)
      (mkProd (binder, ind atom, result_type)) body safe in
    let env = Safe_typing.env_of_safe_env safe in
    let env = Environ.set_typing_flags
      {(Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true} env in
    let left = app (constant current_function) [|lo|] in
    let right = app (constant current_function) [|hi|] in
    ignore (Typeops.infer env left);
    ignore (Typeops.infer env right);
    diagnostic_conversion_trace := true;
    diagnostic_conversion_trace_steps := 0;
    let before = Gc.allocated_bytes () in
    let started = Sys.time () in
    assert (default_conv CONV env left right = Ok ());
    let allocated = Gc.allocated_bytes () -. before in
    let steps = !diagnostic_conversion_trace_steps in
    diagnostic_conversion_trace := false;
    Printf.printf "tied records: depth=%d steps=%d allocated=%.0f cpu=%.6f\n%!"
      depth steps allocated (Sys.time () -. started);
    build (depth + 1) result_type current_function safe
  in
  build 1 (ind atom) leaf safe
