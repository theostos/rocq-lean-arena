(* Direct witnesses precede hints, without graph search. Ties preserve effects. *)
open Reviewed_conversion

let forbidden () = failwith "disabled unfolding-order probe"
let () =
  List.iter (fun order ->
    List.iter (fun l2r ->
      List.iter (fun compact1 ->
        List.iter (fun compact2 ->
          let fallback = if compact1 <> compact2 then compact2 else
            match order with Conv_oracle.Left -> true | Right -> false | Same -> l2r in
          assert (choose_unfolding_action ~order ~l2r ~heuristic:false
            ~compact1 ~compact2 ~constructor:forbidden ~dependency:forbidden
            ~direct_dependency:forbidden = unfolding_side fallback);
          List.iter (fun constructor ->
            List.iter (fun dependency ->
              List.iter (fun direct ->
              let calls = ref [] in
              let result = choose_unfolding_action ~order ~l2r ~heuristic:true
                  ~compact1 ~compact2
                  ~direct_dependency:(fun () -> calls := "direct" :: !calls; direct)
                  ~constructor:(fun () -> calls := "constructor" :: !calls; constructor)
                  ~dependency:(fun () -> calls := "dependency" :: !calls; dependency) in
              let expected_calls, expected = match order with
                | Conv_oracle.Left | Conv_oracle.Right ->
                  ["direct"], unfolding_side (Option.default (order = Conv_oracle.Left) direct)
                | Conv_oracle.Same ->
                  ["constructor"; "dependency"],
                  (match dependency, constructor with
                   | Some left, _ | None, Some left -> unfolding_side left
                   | None, None -> if compact1 <> compact2 then unfolding_side compact2 else Unfold_both) in
              assert (List.rev !calls = expected_calls);
              assert (result = expected)
              ) [None; Some false; Some true]
            ) [None; Some false; Some true]
          ) [None; Some false; Some true]
        ) [false; true]
      ) [false; true]
    ) [false; true]
  ) [Conv_oracle.Left; Right; Same];
  List.iter (fun order ->
    ignore (choose_unfolding_action ~order ~l2r:false ~heuristic:true
      ~compact1:false ~compact2:false ~constructor:forbidden ~dependency:forbidden
      ~direct_dependency:(fun () -> None))
  ) [Conv_oracle.Left; Right];
  print_endline "unfolding order: PASS (direct witnesses, hints skip graph search, tied probe order, both sides on an unpreferred tie)"
