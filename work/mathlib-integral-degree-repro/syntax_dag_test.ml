(* Independently allocated, well-typed DAGs must not become exponential trees
   during the bounded read-only syntactic probe. *)
open Constr
open CClosure
open Reviewed_conversion
open Projected_major_test

let () =
  let choose, safe = add_definition "dag_choose"
    (mkProd (binder, ind atom, mkProd (binder, ind atom, ind atom)))
    (mkLambda (binder, ind atom, mkLambda (binder, ind atom, mkRel 2))) safe in
  let env = Safe_typing.env_of_safe_env safe in
  let rec dag n leaf =
    if n = 0 then leaf else
    let child = dag (n - 1) leaf in
    app (constant choose) [|child; child|] in
  let left = dag 40 lo and right = dag 40 lo in
  assert (left != right);
  ignore (Typeops.infer env left);
  ignore (Typeops.infer env right);
  let budget = ref 1024 in
  let a = inject left and b = inject right in
  let before_a = fterm_of a and before_b = fterm_of b in
  assert (fast_test_under budget Esubst.el_id a Esubst.el_id b);
  assert (!budget > 0);
  assert (fterm_of a == before_a && fterm_of b == before_b);
  Printf.printf "PASS syntax DAG: depth=40 visits=%d allowance=1024\n%!" (1024 - !budget);
  (* Captures, universes and relocation must not disappear from memo keys. *)
  let raw = dag 30 (mkRel 1) in
  let close value = mk_clos (usubs_cons (inject value) (Esubst.subs_id 0, instance)) raw in
  assert (fast_test_under (ref 1024) Esubst.el_id (close lo) Esubst.el_id (close lo));
  assert (not (fast_test_under (ref 1024) Esubst.el_id (close lo) Esubst.el_id (close hi)));
  assert (not (fast_test_under (ref 1024) Esubst.el_id (inject raw)
    (Esubst.el_shft 1 Esubst.el_id) (inject raw)));
  let distinct = dag 40 hi in
  ignore (Typeops.infer env distinct);
  assert (not (fast_test_under (ref 1024) Esubst.el_id a Esubst.el_id (inject distinct)));
  (* Memoized hits still cost a visit: a very wide spine must not bypass the
     bound by repeating the same child. This is a helper resource input. *)
  let wide () = inject (app (constant choose) (Array.make 2048 lo)) in
  assert (not (fast_test_under (ref 1024) Esubst.el_id (wide ()) Esubst.el_id (wide ())));
  print_endline "PASS syntax DAG: no reduction, unequal leaves/captures/lifts rejected, width remains bounded";
  (* A shared memo may see the same syntax at multiple universe instances or
     under different substitutions within one probe. Those are distinct keys. *)
  let sort_body = mkSort (Sorts.sort_of_univ
    (Univ.Universe.make (Univ.Level.var 0))) in
  let sort_lambda () = mkLambda (binder, sort_body, mkRel 1) in
  let universe_subst level = Esubst.subs_id 0,
    UVars.Instance.of_array ([||], [|level|]) in
  let e0 = universe_subst Univ.Level.set and e1 = universe_subst (Univ.Level.var 1) in
  let memo = lazy (SyntaxPairs.create 17) in
  let raw_left = sort_lambda () and raw_right = sort_lambda () in
  assert (compare_under ~memo (ref 1024) e0 raw_left e0 raw_right);
  assert (not (compare_under ~memo (ref 1024) e1 raw_left e0 raw_right));
  (* Expanded FApp graphs exercise the closure-pair memo, not raw templates. *)
  let rec closure_dag n leaf =
    if n = 0 then inject leaf else
    let child = closure_dag (n-1) leaf in
    zip (inject (constant choose)) [Zapp [|child; child|]] in
  let open_left = closure_dag 8 (mkRel 1)
  and open_right = closure_dag 8 (mkRel 1) in
  assert (fast_test_under ~memo (ref 1024) Esubst.el_id open_left Esubst.el_id open_right);
  assert (not (fast_test_under ~memo (ref 1024)
    (Esubst.el_shft 1 Esubst.el_id) open_left Esubst.el_id open_right));
  print_endline "PASS syntax DAG: successful memo entries do not leak across universe instances or lifts";
  List.iter (fun depth ->
    let a = closure_dag depth lo and b = closure_dag depth lo in
    let budget = ref 1024 in
    assert (fast_test_under budget Esubst.el_id a Esubst.el_id b);
    assert (1024 - !budget <= 4*depth+2);
    assert (not (fast_test_under (ref 1024) Esubst.el_id a Esubst.el_id
      (closure_dag depth hi)))
  ) [8;16;32;64];
  (* Differential checks on small well-typed terms/substitutions. A positive
     syntactic probe must also pass the integrated kernel's normal conversion. *)
  let random = Random.State.make [|4701;2026|] in
  let rec generate depth =
    if depth=0 then (if Random.State.bool random then lo else hi) else
    match Random.State.int random 3 with
    | 0 -> app (constant boolean_not) [|generate (depth-1)|]
    | 1 -> let child=generate (depth-1) in app (constant choose) [|child;child|]
    | _ -> app (constant choose) [|generate (depth-1);generate (depth-1)|] in
  let positives = ref 0 in
  for index=1 to 200 do
    let t = generate 5 in
    ignore (Typeops.infer env t);
    let u = if index mod 2=0 then t else generate 5 in
    let a=inject t and b=inject u in
    if index mod 3=0 then ignore (whd_stack (create_conv_infos RedFlags.all env) (create_tab ()) a []);
    if index mod 5=0 then ignore (whd_stack (create_conv_infos RedFlags.all env) (create_tab ()) b []);
    let before_a=fterm_of a and before_b=fterm_of b in
    if fast_test_under ~symbolic:true (ref 1024) Esubst.el_id a Esubst.el_id b then begin
      incr positives;
      assert (Conversion.default_conv Conversion.CONV env t u = Result.Ok ())
    end;
    assert (fterm_of a == before_a && fterm_of b == before_b)
  done;
  assert (!positives>0);
  Printf.printf "PASS syntax DAG: linear closure visits; 200 differential checks (%d positive), read-only\n%!" !positives
