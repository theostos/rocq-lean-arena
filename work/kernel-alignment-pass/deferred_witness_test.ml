let () =
  let exception Ineligible in
  let calls = ref [] in
  let inspect remember = remember 1; remember 2; raise Ineligible in
  let matches value = calls := value :: !calls; true in
  let rejected = try
      ignore (Reviewed_conversion.witness_after_complete_inspection inspect matches);
      false
    with Ineligible -> true in
  assert (rejected && !calls = []);
  let completed = ref false in
  let inspect remember = List.iter remember [1; 1; 2; 3]; completed := true in
  let matches value =
    assert !completed;
    calls := value :: !calls;
    value = 2 in
  assert (Reviewed_conversion.witness_after_complete_inspection inspect matches);
  assert (List.rev !calls = [1; 1; 2]);
  assert (not (Reviewed_conversion.witness_after_complete_inspection (fun _ -> ())
    (fun _ -> assert false)));
  print_endline "deferred eligibility witness: PASS"
