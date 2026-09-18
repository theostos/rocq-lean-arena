(* Type-head inspection must not copy environments belonging to discarded
   arguments. These representation tests supplement checked native fixtures. *)
open Constr
open CClosure
open Reviewed_conversion
open Unit_type_shift_test

let query typ stack =
  with_type_snapshot infos typ stack (fun infos typ stack ->
    let head, stack = whd_stack infos.cnv_inf (create_tab ()) typ stack in
    Some (term_of_process head stack))

let huge_substitution width =
  let value = inject (mkRel 1) in
  let subst = ref identity in
  for _ = 1 to width do subst := usubs_cons value !subst done;
  !subst

let () =
  let allocations = List.map (fun width ->
    let subst = huge_substitution width in
    let source = mk_clos subst
      (mkLetIn (binder, mkRel 1, mkProp, mkProp)) in
    let before = fterm_of source in
    let bytes = Gc.allocated_bytes () in
    assert (query source [] = Some mkProp);
    let bytes = Gc.allocated_bytes () -. bytes in
    assert (fterm_of source == before);
    bytes) [1; 256; 8192; 32768] in
  let first = List.hd allocations in
  List.iter (fun bytes -> assert (bytes <= first *. 2.)) allocations;

  (* The stack argument's environment is irrelevant to this beta redex too. *)
  let argument = mk_clos (huge_substitution 8192) (mkRel 1) in
  let original = fterm_of argument in
  let typ = inject (mkLambda (binder, mkProp, mkProp)) in
  let update = inject (mkRel 7) in
  let update_before = fterm_of update in
  assert (query typ [Zapp [|argument|]; Zupdate update] = Some mkProp);
  assert (fterm_of argument == original && fterm_of update == update_before);

  (* Demanded substitutions are reduced privately, including a shared cell. *)
  let source = inject (mkLetIn (binder, mkProp, mkSort Sorts.type1, mkRel 1)) in
  let before = fterm_of source in
  let typ = mk_clos (usubs_cons source identity) (mkRel 1) in
  assert (query typ [] = Some mkProp);
  assert (fterm_of source == before);
  assert (query typ [] = Some mkProp);
  assert (fterm_of source == before);

  (* Bounds still apply to demanded work, not to ignored closure graphs. *)
  let omega = mkLambda (binder, mkProp, mkApp (mkRel 1, [|mkRel 1|])) in
  let looping = inject (mkApp (omega, [|omega|])) in
  let before = fterm_of looping in
  assert (query looping [] = None);
  assert (fterm_of looping == before);
  assert (query (inject mkProp) [Zapp (Array.make 4096 argument)] = None);

  (* Eager snapshots remain a small-reference oracle. The private query must
     preserve binder/shift/substitution meaning on demanded open terms. *)
  let reference source = with_closure_snapshot ~steps:4096 infos.cnv_inf [source]
      (fun infos -> function
       | [copy] ->
         let head, stack = whd_stack infos (create_tab ()) copy [] in
         Some (term_of_process head stack)
       | _ -> assert false) in
  let subst = usubs_cons (inject (mkRel 3)) identity in
  List.iter (fun subst ->
    List.iter (fun syntax ->
      let source = mk_clos subst syntax in
      let before = fterm_of source in
      assert (query source [] = reference source);
      assert (fterm_of source == before))
      [mkRel 1; mkRel 2;
       mkApp (mkLambda (binder, mkProp, mkRel 2), [|mkProp|]);
       mkLetIn (binder, mkRel 1, mkProp, mkRel 1);
       mkLambda (binder, mkProp, mkRel 2)])
    [subst; usubs_liftn 2 subst;
     (Esubst.subs_shft (5, fst subst), snd subst)];

  (* Query limits are shared by repeated reductions, even of a cached atom. *)
  assert (with_private_closure_query ~steps:32 infos.cnv_inf [inject mkProp]
    (fun infos -> function
     | [copy] ->
       for _ = 1 to 100 do ignore (whd_stack infos (create_tab ()) copy []) done;
       Some true
     | _ -> assert false) = None);
  assert (with_private_closure_query ~steps:0 infos.cnv_inf [inject mkProp]
    (fun _ _ -> Some true) = None);

  (* Duplicate roots share one owned cell; neither success nor exhaustion
     may write a reduced value or leave FLOCKED in the original graph. *)
  let source = inject (mkLetIn (binder, mkProp, mkProp, mkRel 1)) in
  let before = fterm_of source in
  assert (with_private_closure_query ~steps:128 infos.cnv_inf [source; source]
    (fun infos -> function
     | [left; right] ->
       assert (left == right && left != source);
       let head, stack = whd_stack infos (create_tab ()) left [] in
       assert (term_of_process head stack = mkProp);
       assert (fterm_of source == before);
       let head, stack = whd_stack infos (create_tab ()) right [] in
       assert (term_of_process head stack = mkProp);
       Some true
     | _ -> assert false) = Some true);
  assert (fterm_of source == before);
  Printf.printf "type queries: PASS (unused environments 1/256/8192/32768: %s bytes)\n%!"
    (String.concat "/" (List.map (Printf.sprintf "%.0f") allocations))
