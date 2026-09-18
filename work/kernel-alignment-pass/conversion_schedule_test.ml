open Reviewed_conversion

let () =
  assert (scale_conversion_budget 32 (Some 256) = Some 8192);
  assert (scale_conversion_budget 32 (Some max_int) = Some max_int);
  assert (scale_conversion_budget 32 None = None);
  assert (scale_conversion_budget 32 (Some 0) = Some 0);
  List.iter (fun factor ->
    assert (try ignore (scale_conversion_budget factor None); false
      with Invalid_argument _ -> true)
  ) [0; -1];
  assert (try ignore (scale_conversion_budget 32 (Some (-1))); false
    with Invalid_argument _ -> true);
  (* Work counts model scheduling only, not reduction time or Mathlib timing. *)
  List.iter (fun count ->
    let strategies = List.init count Fun.id in
    List.iter (fun winner ->
      List.iter (fun needed ->
        let spent = ref 0 and calls = ref 0 in
        let result = retry_conversion_strategies ~initial_work_limit:8 strategies
          (fun strategy budget ->
            let limit = Option.get budget in
            incr calls;
            let cost = if strategy = winner then needed else max_int in
            spent := !spent + min cost limit;
            if cost <= limit then Ok strategy else raise Strategy_budget_exhausted) in
        assert (result = Ok winner);
        assert (!spent <= 8 * count * max 8 needed);
        assert (!calls < 32 * count)
      ) [1; 7; 8; 9; 31; 257; 4096; 100000]
    ) strategies;
    List.iter (fun winner ->
      let calls = Array.make count 0 in
      let result = retry_conversion_strategies ~initial_work_limit:1 strategies
        (fun strategy budget ->
          calls.(strategy) <- calls.(strategy) + 1;
          if strategy <> winner then Error None
          else if Option.get budget >= 8 then Ok strategy
          else raise Strategy_budget_exhausted) in
      assert (result = Ok winner);
      Array.iteri (fun strategy attempts ->
        assert (attempts = if strategy = winner then 4 else 1)) calls
    ) strategies;
    let calls = ref 0 in
    assert (retry_conversion_strategies strategies (fun _ _ ->
      incr calls; Error None) = Error None);
    assert (!calls = count);
    let budgets = ref [] in
    assert (retry_conversion_strategies ~initial_work_limit:max_int strategies
      (fun _ budget ->
        budgets := budget :: !budgets;
        match budget with Some _ -> raise Strategy_budget_exhausted | None -> Ok 17) = Ok 17);
    assert (List.rev !budgets = List.init count (fun _ -> Some max_int) @ [None])
  ) [1; 2; 4; 12];
  let calls = ref 0 in
  assert (retry_conversion_strategies [0; 1] (fun _ _ ->
    incr calls; Error (Some "universe-error")) = Error (Some "universe-error"));
  assert (!calls = 1);
  let exception Interrupt in
  assert (try ignore (retry_conversion_strategies [0; 1] (fun _ _ -> raise Interrupt));
    false with Interrupt -> true);
  assert (try ignore (retry_conversion_strategies ~initial_work_limit:max_int [0; 1]
    (fun _ _ -> raise Strategy_budget_exhausted)); false
    with Strategy_budget_exhausted -> true);
  List.iter (fun limit ->
    assert (try ignore (retry_conversion_strategies ~initial_work_limit:limit [0]
      (fun _ _ -> Ok ())); false with Invalid_argument _ -> true)
  ) [0; -1];
  assert (try ignore (retry_conversion_strategies [] (fun _ _ -> Ok ()));
    false with Invalid_argument _ -> true);
  print_endline "conversion scheduler: PASS (all strategy winners, retries, failures, exceptions, saturation)"
