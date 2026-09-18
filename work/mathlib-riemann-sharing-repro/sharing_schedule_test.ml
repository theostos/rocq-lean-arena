open Reviewed_conversion

let () =
  (* Work counts below model scheduling overhead, not Mathlib timings. *)
  List.iter (fun winner_symbolic ->
    List.iter (fun needed ->
      let spent = ref 0 and calls = ref [] in
      let result = retry_sharing_modes ~initial_work_limit:8
        (fun ~preserve_symbols budget ->
          let limit = Option.get budget in
          calls := (preserve_symbols, limit) :: !calls;
          let cost = if preserve_symbols = winner_symbolic then needed else max_int in
          spent := !spent + min cost limit;
          if cost <= limit then Ok (preserve_symbols, needed)
          else raise Strategy_budget_exhausted) in
      assert (result = Ok (winner_symbolic, needed));
      assert (!spent <= 8 * max 8 needed);
      assert (List.length !calls < 32)
    ) [1; 7; 8; 9; 31; 257; 4096; 100000]
  ) [false; true];
  (* A completed failed mode is retired, while an exhausted mode is retried. *)
  List.iter (fun failed_symbolic ->
    let failures = ref 0 and attempts = ref 0 in
    let result = retry_sharing_modes ~initial_work_limit:1
      (fun ~preserve_symbols budget ->
        if preserve_symbols = failed_symbolic then
          (incr failures; Error None)
        else begin
          incr attempts;
          if Option.get budget >= 8 then Ok 42
          else raise Strategy_budget_exhausted
        end) in
    assert (result = Ok 42 && !failures = 1 && !attempts = 4)
  ) [false; true];
  let calls = ref 0 in
  assert (retry_sharing_modes (fun ~preserve_symbols:_ _ ->
    incr calls; Error None) = Error None);
  assert (!calls = 2);
  let calls = ref 0 in
  assert (retry_sharing_modes (fun ~preserve_symbols:_ _ ->
    incr calls; Error (Some "universe-error")) = Error (Some "universe-error"));
  assert (!calls = 1);
  let exception Interrupt in
  assert (try ignore (retry_sharing_modes (fun ~preserve_symbols:_ _ -> raise Interrupt));
    false with Interrupt -> true);
  (* No budget overflow and no success manufactured by saturation. *)
  let budgets = ref [] in
  assert (retry_sharing_modes ~initial_work_limit:max_int
    (fun ~preserve_symbols:_ budget ->
      budgets := budget :: !budgets;
      match budget with Some _ -> raise Strategy_budget_exhausted | None -> Ok 17) = Ok 17);
  assert (List.rev !budgets = [Some max_int; Some max_int; None]);
  assert (try ignore (retry_sharing_modes ~initial_work_limit:max_int
    (fun ~preserve_symbols:_ _ -> raise Strategy_budget_exhausted)); false
    with Strategy_budget_exhausted -> true);
  assert (try ignore (retry_sharing_modes ~initial_work_limit:0
    (fun ~preserve_symbols:_ _ -> Ok ())); false with Invalid_argument _ -> true);
  print_endline "sharing scheduler: PASS (both winners, geometric work, failures, exceptions, overflow)"
