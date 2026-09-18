open Coq_checklib
open Analyze
open Values

let () =
  let samples = [Obj.repr (); Obj.repr 0; Obj.repr (-1); Obj.repr 3;
    Obj.repr "hello"; Obj.repr 1L; Obj.repr 2.5; Obj.repr [1;2;3];
    Obj.repr ["a";"b"]; Obj.repr (1,"a"); Obj.repr [|1;2|];
    Obj.repr [|"x";"y"|]; Obj.repr (Some 7); Obj.repr (Some "x");
    Obj.repr ([1;2],[1;2]); Obj.repr [|[|1|];[|2|]|]] in
  let tree = fix (fun v -> v_sum "tree" 1 [|[|v;v|]|]) in
  let validators = [v_any; v_fail "forbidden"; v_int; v_string; v_int64;
    v_float64; v_list v_int; v_list v_string; v_opt v_int; v_opt v_string;
    v_array v_int; v_array v_string; v_tuple "pair" [|v_int;v_string|];
    v_annot "note" (v_list v_int); v_array (v_array v_int); tree;
    v_tuple "shared" [|v_list v_int; v_list v_int|]] in
  let baseline v (o,mem) =
    try Baseline_validate.val_gen v mem [] o; None with
    | Baseline_validate.ValidObjError (msg,ctx,o) ->
      Some (msg,List.map Baseline_validate.print_frame ctx,o) in
  let candidate v (o,mem) =
    try Reviewed_validate.val_gen v mem [] o; None with
    | Reviewed_validate.ValidObjError (msg,ctx,o) ->
      Some (msg,List.map Reviewed_validate.print_frame ctx,o) in
  List.iter (fun obj ->
    let data = parse_string (Marshal.to_string obj []) in
    List.iter (fun v -> assert (baseline v data = candidate v data)) validators
  ) samples;
  (* Same object checked against two different validators cannot be skipped. *)
  let mem = LargeArray.make 2 (Struct (0,[||])) in
  LargeArray.set mem 0 (Struct (0,[|Ptr 1;Ptr 1|]));
  LargeArray.set mem 1 (String "shared");
  let v = v_tuple "two-types" [|v_string;v_int|] in
  assert (candidate v (Ptr 0,mem) <> None);
  assert (baseline v (Ptr 0,mem) = candidate v (Ptr 0,mem));
  (* Preserve the existing policy on cycles; this change does not silently
     tighten or weaken which graph shapes the standalone validator accepts. *)
  let cycle = LargeArray.make 1 (Struct (0,[|Int 0;Ptr 0|])) in
  assert (baseline (v_list v_int) (Ptr 0,cycle) = None);
  assert (candidate (v_list v_int) (Ptr 0,cycle) = None);
  Printf.printf "PASS %d validator acceptance/error-context differential cases, shared validators and cycles\n%!"
    (List.length samples * List.length validators);
  let depth = 3_000_000 in
  let mem = LargeArray.make depth (Struct (0,[||])) in
  for i = 0 to depth - 1 do
    let next = if i = depth-1 then Analyze.Int 0 else Ptr (i+1) in
    LargeArray.set mem i (Struct (0,[|Int i;next|]))
  done;
  let start = Sys.time () in
  assert (candidate (v_list v_int) (Ptr 0,mem) = None);
  Printf.printf "PASS depth-%d standalone value validation, CPU %.3f\n%!"
    depth (Sys.time () -. start)
