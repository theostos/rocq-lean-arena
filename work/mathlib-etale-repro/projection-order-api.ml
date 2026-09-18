(* Real typed conversion with checked inductive/record/definition fixtures. *)
open Names
open Constr
open CClosure
open Reviewed_conversion
open Projected_major_test

let () =
  let function_type = mkProd (binder, ind atom, ind atom) in
  let ops, (projection, relevance), safe = add_record "OrderOps"
      ["operation", function_type] safe in
  let ci = { ci_ind = atom, 0; ci_npar = 0;
    ci_cstr_ndecls = [|0; 0|]; ci_cstr_nargs = [|0; 0|];
    ci_pp_info = {style = MatchStyle} } in
  let method_body = mkLambda (binder, ind atom,
      mkCase (ci, instance, [||], (([|binder|], function_type), Sorts.Relevant),
        NoInvert, mkRel 1,
        [|[||], mkLambda (binder, ind atom, lo);
          [||], mkLambda (binder, ind atom, lo)|])) in
  let method_, safe = add_definition "computed_method"
      (mkProd (binder, ind atom, function_type)) method_body safe in
  let wrapper, safe = add_definition "computed_wrapper"
      (mkProd (binder, ind atom, ind ops))
      (mkLambda (binder, ind atom,
        app (ctor ops 1) [|app (constant method_) [|mkRel 1|]|])) safe in
  let identity = mkLambda (binder, ind atom, mkRel 1) in
  let identity_method, safe = add_definition "computed_identity_method"
      (mkProd (binder, ind atom, function_type))
      (mkLambda (binder, ind atom,
        mkCase (ci, instance, [||], (([|binder|], function_type), Sorts.Relevant),
          NoInvert, mkRel 1, [|[||], identity; [||], identity|]))) safe in
  let identity_wrapper, safe = add_definition "computed_identity_wrapper"
      (mkProd (binder, ind atom, ind ops))
      (mkLambda (binder, ind atom,
        app (ctor ops 1) [|app (constant identity_method) [|mkRel 1|]|])) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let env = Environ.set_typing_flags
      {(Environ.typing_flags env) with Declarations.unfold_dep_heuristic = true} env in
  let project source = mkProj (projection, relevance, source) in
  List.iter (fun depth ->
    let argument = ref hi in
    for _ = 1 to depth do argument := app (constant boolean_not) [|!argument|] done;
    let left = app (project (app (constant wrapper) [|lo|])) [|!argument|] in
    let right = app (project (app (constant wrapper) [|hi|])) [|lo|] in
    (* Type checking is not bypassed to set the typed conversion precondition. *)
    ignore (Typeops.infer env left);
    ignore (Typeops.infer env right);
    diagnostic_conversion_trace := true;
    diagnostic_conversion_trace_steps := 0;
    let allocated_before = Gc.allocated_bytes () in
    let started = Sys.time () in
    let answer = default_conv CONV env left right in
    let elapsed = Sys.time () -. started in
    let allocated = Gc.allocated_bytes () -. allocated_before in
    let steps = !diagnostic_conversion_trace_steps in
    diagnostic_conversion_trace := false;
    assert (answer = Ok ());
    Printf.printf "projection order: depth=%d steps=%d allocated=%.0f cpu=%.6f\n%!"
      depth steps allocated elapsed
  ) [0; 16; 64; 128; 1024; 8192];
  let check label equal left right =
    ignore (Typeops.infer env left);
    ignore (Typeops.infer env right);
    assert ((default_conv CONV env left right = Ok ()) = equal);
    assert ((default_conv CONV env right left = Ok ()) = equal);
    Printf.printf "projection order: PASS %s (both directions)\n%!" label
  in
  let ignore_from source arg = app (project (app (constant wrapper) [|source|])) [|arg|] in
  check "open ignored argument under binder" true
    (mkLambda (binder, ind atom, ignore_from lo (mkRel 1)))
    (mkLambda (binder, ind atom, ignore_from hi lo));
  let identity_method = mkLambda (binder, ind atom, mkRel 1) in
  let identity_record = app (ctor ops 1) [|identity_method|] in
  check "used method arguments are not discarded" false
    (app (project identity_record) [|lo|])
    (app (project identity_record) [|hi|]);
  check "different selected methods remain different" false
    (app (project identity_record) [|hi|]) (ignore_from lo hi);
  let use_from source arg =
    app (project (app (constant identity_wrapper) [|source|])) [|arg|] in
  check "matching symbolic source still checks continuation" false
    (use_from lo lo) (use_from lo hi);
  check "different source with convertible selected method" true
    (use_from lo hi) (use_from hi hi)
