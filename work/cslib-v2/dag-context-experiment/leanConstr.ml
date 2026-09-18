(* Diagnostic prototype, not linked into the importer.
   Normalized translation contexts can contain large shared terms. Comparing
   their tree unfoldings repeatedly is exponential in the size of the DAG.
   Delegate all structural decisions to Rocq's ordinary syntactic comparison;
   remember only pairs whose comparison has already completed successfully. *)
let equal left right =
  let slots = ref [||] in
  let visits = ref 0 in
  let rec equal nargs left right =
    left == right ||
    begin
      incr visits;
      (* Small comparisons need no table. A direct-mapped table bounds both
         memory and lookup cost even when deep terms have identical hashes.
         Collisions merely discard an optimization, never an equality check. *)
      if !visits = 64 then slots := Array.make 4096 None;
      let table = !slots in
      let index =
        if Array.length table = 0 then 0
        else Hashtbl.hash_param 16 128 (nargs, left, right) land 4095
      in
      let cached =
        Array.length table <> 0 &&
        match table.(index) with
        | Some (nargs', left', right') ->
          nargs = nargs' && left == left' && right == right'
        | None -> false
      in
      cached ||
      (Constr.compare_head equal_evar equal nargs left right &&
       begin
         (* A recursive call may have allocated the initially absent table. *)
         let current = !slots in
         if Array.length current <> 0 then begin
           let index = if current == table then index
             else Hashtbl.hash_param 16 128 (nargs, left, right) land 4095 in
           current.(index) <- Some (nargs, left, right)
         end;
         true
       end)
    end
  and equal_evar (key1, args1) (key2, args2) =
    Evar.equal key1 key2 && SList.equal (equal 0) args1 args2
  in
  equal 0 left right

(* Substituting context IDs with [Vars.substl] unfolds the source DAG whenever
   a shared subterm contains a replaced variable. Memoize by both physical
   term and binder depth; context IDs are closed Meta nodes, so need no lift. *)
let abstract_context ids term =
  let substitution = Array.of_list (List.map Constr.mkMeta ids) in
  let length = Array.length substitution in
  if length = 0 then term else
  let slots = ref [||] in
  let visits = ref 0 in
  let rec subst depth term =
    incr visits;
    if !visits = 64 then slots := Array.make 4096 None;
    let table = !slots in
    let index =
      if Array.length table = 0 then 0
      else Hashtbl.hash_param 16 128 (depth, term) land 4095
    in
    let cached =
      if Array.length table = 0 then None
      else match table.(index) with
      | Some (depth', term', result) when depth = depth' && term == term' ->
        Some result
      | _ -> None
    in
    match cached with
    | Some result -> result
    | None ->
      let result = match Constr.kind term with
        | Constr.Rel index ->
          if index <= depth then term
          else if index - depth <= length then substitution.(index - depth - 1)
          else Constr.mkRel (index - length)
        | _ -> Constr.map_with_binders succ subst depth term
      in
      let current = !slots in
      if Array.length current <> 0 then begin
        let index = if current == table then index
          else Hashtbl.hash_param 16 128 (depth, term) land 4095 in
        current.(index) <- Some (depth, term, result)
      end;
      result
  in
  subst 0 term
