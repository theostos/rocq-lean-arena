open Reviewed_closure
open Constr

let env sharing heuristic =
  let base = Environ.empty_env in
  Environ.set_typing_flags
    { (Environ.typing_flags base) with
      share_reduction = sharing; unfold_dep_heuristic = heuristic } base

let () =
  let infos = create_conv_infos RedFlags.betaiotazeta (env false true) in
  let table = create_tab () in
  let binder = Context.make_annot Names.Anonymous Sorts.Relevant in
  let term = mkApp (mkLambda (binder, mkProp, mkRel 1), [|mkSProp|]) in
  let original = inject term in
  let before = fterm_of original in
  let result = whd_stack infos table original [] in
  assert (Constr.equal (term_of_process (fst result) (snd result)) mkSProp);
  assert (fterm_of original == before);
  for _ = 1 to 100 do
    let again = whd_stack infos table original [] in
    assert (fst again == fst result && snd again == snd result);
    assert (fterm_of original == before)
  done;
  let unreduced = whd_stack (infos_with_reds infos RedFlags.no_red) table original [] in
  assert (Constr.equal (term_of_process (fst unreduced) (snd unreduced)) term);

  let name = Names.Id.of_string "symbolic_identity" in
  let definition = Context.Named.Declaration.LocalDef
    (Context.make_annot name Sorts.Relevant,
     mkLambda (binder, mkProp, mkRel 1), mkProd (binder, mkProp, mkProp)) in
  let named sharing heuristic =
    Environ.push_named Environ.ProofVar definition (env sharing heuristic) in
  let symbolic = mkApp (mkVar name, [|mkSProp|]) in
  List.iter (fun heuristic ->
    let info = create_conv_infos RedFlags.all (named true heuristic) in
    let tab = create_tab () in
    let source = inject symbolic in
    let before = fterm_of source in
    let reduced = whd_stack info tab source [] in
    assert (Constr.equal (term_of_process (fst reduced) (snd reduced)) mkSProp);
    assert (fterm_of source != before);
    if heuristic then begin
      assert (Constr.equal (term_of_fconstr source) symbolic);
      let symbolic_view = fterm_of source in
      (* The first traversal materializes the application and reduces the
         definition body. Its mutations deliberately prevent a cache entry.
         A stable traversal installs the reusable result. *)
      let stable = whd_stack info tab source [] in
      for _ = 1 to 4 do
        let serial = !closure_mutation_serial in
        let repeated = whd_stack info tab source [] in
        assert (!closure_mutation_serial = serial);
        assert (fst repeated == fst stable && snd repeated == snd stable);
        assert (fterm_of source == symbolic_view)
      done
    end;
    (* Beta-only nodes retain ordinary destructive reduction reuse. *)
    let beta = inject term in
    let beta_before = fterm_of beta in
    ignore (whd_stack info tab beta []);
    assert (fterm_of beta != beta_before)
  ) [false; true];

  let calls = ref 0 in
  let compute () = incr calls; inject mkProp, [] in
  let head = inject term in
  let arg = inject mkSProp in
  let get infos table stack = Table.memo_whnf infos table head stack compute in
  let stack = [Zapp [|arg|]] in
  let first = get infos table stack in
  assert (!calls = 1);
  assert (fst (get infos table [Zapp [|arg|]]) == fst first);
  assert (!calls = 1);
  ignore (get infos table [Zapp [|inject mkSProp|]]);
  assert (!calls = 2);
  ignore (get infos table [Zshift 1; Zapp [|arg|]]);
  assert (!calls = 3);
  ignore (get (push_relevance infos binder) table stack);
  assert (!calls = 4);
  ignore (get (infos_with_reds infos RedFlags.no_red) table stack);
  assert (!calls = 5);
  ignore (get (create_conv_infos RedFlags.betaiotazeta (env false true)) table stack);
  assert (!calls = 6);
  ignore (get infos (create_tab ()) stack);
  assert (!calls = 7);
  (* Conservatively invalidate even when an indirectly reachable cell changes. *)
  update arg Ntrl (FAtom mkProp);
  ignore (get infos table stack);
  assert (!calls = 8);
  ignore (get infos table stack);
  assert (!calls = 8);
  closure_mutation_serial := max_int;
  note_closure_mutation ();
  ignore (get infos table stack);
  assert (!calls = 9);
  (* Caller-owned update frames, oversized keys, inspection budgets, shared
     reduction and ordinary non-import conversion do not use this memo. *)
  List.iter (fun (info, frames) ->
    let start = !calls in
    ignore (get info table frames);
    ignore (get info table frames);
    assert (!calls = start + 2)
  ) [infos, [Zupdate arg]; infos, [Zapp (Array.make 65 arg)];
     { infos with i_inspection = Some (ref 4096) }, stack;
     create_conv_infos RedFlags.betaiotazeta (env true true), stack;
     create_conv_infos RedFlags.betaiotazeta (env false false), stack];
  (* No result is installed when computation throws or rewrites a closure. *)
  let exception Interrupted in
  let fresh = inject term in
  assert (try ignore (Table.memo_whnf infos table fresh []
      (fun () -> raise Interrupted)); false with Interrupted -> true);
  let start = !calls in
  ignore (Table.memo_whnf infos table fresh [] compute);
  assert (!calls = start + 1);
  let mutating = inject term in
  let compute_mutating () = note_closure_mutation (); compute () in
  let start = !calls in
  ignore (Table.memo_whnf infos table mutating [] compute_mutating);
  ignore (Table.memo_whnf infos table mutating [] compute_mutating);
  assert (!calls = start + 2);
  (* Exercise bounded eviction without depending on table internals. *)
  for _ = 1 to 5000 do
    ignore (Table.memo_whnf infos table (inject term) [] compute)
  done;
  print_endline "non-destructive WHNF memo: PASS (reuse, contexts, mutations, scopes, exceptions, eviction)"
