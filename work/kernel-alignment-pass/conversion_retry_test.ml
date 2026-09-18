open Reviewed_conversion

let () =
  List.iter (fun sharing ->
    List.iter (fun heuristic ->
      let initial = Environ.empty_env in
      let flags = { (Environ.typing_flags initial) with
        share_reduction = sharing; unfold_dep_heuristic = heuristic } in
      let env = Environ.set_typing_flags flags initial in
      let retry = conversion_retry_environment env in
      let actual = Environ.typing_flags retry in
      assert (not actual.share_reduction);
      (* Compare the complete flag record, including every trust boundary. *)
      assert ({ actual with share_reduction = sharing } = flags);
      assert (Environ.typing_flags env = flags);
      assert (Environ.universes retry = Environ.universes env);
      assert (Environ.rel_context retry == Environ.rel_context env);
      assert (conversion_retry_environment retry == retry);
      if not sharing then assert (retry == env)
    ) [false; true]
  ) [false; true];
  print_endline "conversion retry: PASS (local sharing only, flags/context preserved, idempotence)"
