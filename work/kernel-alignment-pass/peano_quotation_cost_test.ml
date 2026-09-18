(* Exercise the private bit representation without exposing it in the kernel API. *)
open Reviewed_closure

let () =
  let path = Names.ModPath.MPfile (Names.DirPath.make [Names.Id.of_string "Cost"]) in
  let ind = Names.MutInd.make2 path (Names.Id.of_string "Nat"), 0 in
  let number bits = {
    peano_ind = ind; peano_zero = ind, 1; peano_succ = ind, 2;
    peano_double = Names.Constant.make2 path (Names.Id.of_string "double");
    peano_value = bits;
  } in
  let rec nodes term = 1 + Constr.fold (fun n t -> n + nodes t) 0 term in
  List.iter (fun bits ->
    let n = number bits in
    let expected = nodes (term_of_fconstr (make_fconstr Cstr (FPeanoNat n))) in
    assert (peano_quotation_cost ~limit:expected n = Some expected);
    assert (peano_quotation_cost ~limit:(expected - 1) n = None);
    assert (peano_quotation_cost ~limit:10000 n = Some expected))
    [[]; [true]; [false; true]; [true; true]; List.init 100 (fun i -> i mod 2 = 0)];
  let huge = number (List.init 200000 (fun _ -> true)) in
  let before = Gc.allocated_bytes () in
  for _ = 1 to 10000 do assert (peano_quotation_cost ~limit:10 huge = None) done;
  assert (Gc.allocated_bytes () -. before < 2_000_000.);
  assert (peano_quotation_cost ~limit:(-1) (number []) = None);
  print_endline "compact quotation cost: PASS (exact boundaries and bounded oversized queries)"
