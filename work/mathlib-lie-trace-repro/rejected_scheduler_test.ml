(* Historical experiment only: the scheduler was removed after it failed to
   repair this theorem. Not part of the production regression gate. *)
open Reviewed_conversion

exception Sentinel

let () =
  let calls = ref [] in
  let run budget strategy =
    calls := (budget, strategy) :: !calls;
    match strategy with
    | 0 -> raise Strategy_budget_exhausted
    | 1 -> Result.Error None
    | 2 when budget < 16 -> raise Strategy_budget_exhausted
    | 2 -> Result.Ok 42
    | _ -> assert false in
  assert (search_conversion_strategies ~initial_limit:4 [0; 1; 2] run = Result.Ok 42);
  assert (List.rev !calls = [4,0; 4,1; 4,2; 8,0; 8,2; 16,0; 16,2]);
  (* A definitive rejection is not retried. Exhaustion is not rejection. *)
  calls := [];
  assert (search_conversion_strategies ~initial_limit:4 [0; 1]
    (fun budget strategy -> calls := (budget, strategy) :: !calls;
      if strategy = 0 && budget = 4 then raise Strategy_budget_exhausted
      else Result.Error None) = Result.Error None);
  assert (List.rev !calls = [4,0; 4,1; 8,0]);
  (* Success and structured errors return unchanged and stop the search. *)
  List.iter (fun expected ->
    let calls = ref 0 in
    assert (search_conversion_strategies ~initial_limit:4 [0; 1]
      (fun _ _ -> incr calls; expected) = expected);
    assert (!calls = 1)) [Result.Ok 9; Result.Error (Some "universe-error")];
  assert (search_conversion_strategies ~initial_limit:4 []
    (fun _ _ -> assert false) = Result.Error None);
  (* Interrupts/anomalies and inner probe exhaustion must not be swallowed. *)
  List.iter (fun exn ->
    assert (try ignore (search_conversion_strategies ~initial_limit:4 [0]
      (fun _ _ -> raise exn)); false with caught -> caught == exn))
    [Sentinel; Probe_budget_exhausted; NotConvertible];
  assert (try ignore (search_conversion_strategies ~initial_limit:0 []
    (fun _ _ -> assert false)); false with Invalid_argument _ -> true);
  (* Geometric growth saturates without integer wraparound. *)
  let calls = ref [] in
  assert (search_conversion_strategies ~initial_limit:(max_int / 2 + 1) [0]
    (fun budget _ -> calls := budget :: !calls;
      if budget < max_int then raise Strategy_budget_exhausted else Result.Ok ())
    = Result.Ok ());
  assert (List.rev !calls = [max_int / 2 + 1; max_int]);
  print_endline "conversion scheduling: PASS (fair retries, rejection, errors, interruption, overflow)"
