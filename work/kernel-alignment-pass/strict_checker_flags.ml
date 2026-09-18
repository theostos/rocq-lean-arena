let () =
  let env = Environ.empty_env in
  let flags = Environ.typing_flags env in
  let changed = Declarations.[
    { flags with check_guarded = false };
    { flags with check_positive = false };
    { flags with check_universes = false };
    { flags with check_eliminations = false }] in
  (* Compatibility behavior remains unchanged until explicitly selected. *)
  List.iter (fun flags -> ignore (Reviewed_check_flags.set_local_flags flags env)) changed;
  Reviewed_check_flags.enable_strict_checks ();
  ignore (Reviewed_check_flags.set_local_flags flags env);
  let rejects flags = try
    ignore (Reviewed_check_flags.set_local_flags flags env); false
    with CErrors.UserError _ -> true in
  List.iter (fun flags -> assert (rejects flags)) changed;
  let uip = { flags with Declarations.allow_uip = true } in
  assert (rejects uip);
  Reviewed_check_flags.allow_definitional_uip ();
  ignore (Reviewed_check_flags.set_local_flags uip env);
  List.iter (fun flags -> assert (rejects { flags with Declarations.allow_uip = true })) changed;
  print_endline "strict checker flags: PASS (all four checks; explicit UIP policy)"
