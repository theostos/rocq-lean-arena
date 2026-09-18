open Names
open Constr
open CClosure
open Esubst
open Reviewed_conversion

let () =
  let path = ModPath.MPfile (DirPath.make [Id.of_string "Segments"]) in
  let ind = MutInd.make2 path (Id.of_string "R"), 0 in
  let proj i = Zlproj (Projection.Repr.make ind ~proj_npars:0 ~proj_arg:i, el_id) in
  let arg i = Zlapp [|el_id, inject (mkRel i)|] in
  let stacks = [arg 1; arg 2; proj 0; arg 3; proj 1; arg 4] in
  let calls = ref [] in
  let compare compared nargs left right count =
    assert (List.length left = List.length right);
    calls := (!calls @ [Array.length compared, nargs, List.length left]);
    count + List.length left
  in
  assert (compare_projection_segments compare [|true|] 0 stacks stacks 0 = 4);
  assert (!calls = [1, 0, 2; 0, -1, 1; 0, -1, 1]);
  (* No projection means exactly the original callback, including its mask. *)
  calls := [];
  assert (compare_projection_segments compare [|false|] 8 [arg 1] [arg 1] 0 = 1);
  assert (!calls = [1, 8, 1]);
  (* A source mismatch stops before any expensive outer comparison. *)
  let calls = ref 0 in
  assert (try ignore (compare_projection_segments
    (fun _ _ _ _ _ -> incr calls; raise NotConvertible)
    [||] 0 stacks stacks 0); false with NotConvertible -> true);
  assert (!calls = 1);
  (* Do not silently ignore mismatched projection fields. *)
  let calls = ref 0 in
  assert (try ignore (compare_projection_segments compare [||] 0
    [arg 1; proj 0; arg 4] [arg 1; proj 1; arg 4] 0); false
    with NotConvertible -> true);
  assert (try ignore (compare_projection_segments
    (fun _ _ _ _ cu -> incr calls; cu) [||] 0
    [arg 1; proj 0; arg 4] [arg 1; proj 1; arg 4] 0); false
    with NotConvertible -> true);
  assert (!calls = 0);
  print_endline "projection segments: PASS (prefixes, continuations, masks, failure, field identity)"
