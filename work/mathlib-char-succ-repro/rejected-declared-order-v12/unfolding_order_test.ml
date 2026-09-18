(* Decisive hints need no graph search. Ties preserve the fallback's effects. *)
open Reviewed_conversion

let forbidden () = failwith "disabled unfolding-order probe"
let () =
  List.iter (fun order ->
    List.iter (fun l2r ->
      List.iter (fun compact1 ->
        List.iter (fun compact2 ->
          let fallback = if compact1 <> compact2 then compact2 else
            match order with Conv_oracle.Left -> true | Right -> false | Same -> l2r in
          assert (choose_unfolding_side ~order ~l2r ~heuristic:false
            ~compact1 ~compact2 ~constructor:forbidden ~dependency:forbidden = fallback);
          List.iter (fun constructor ->
            List.iter (fun dependency ->
              let calls = ref [] in
              let result = choose_unfolding_side ~order ~l2r ~heuristic:true
                  ~compact1 ~compact2
                  ~constructor:(fun () -> calls := "constructor" :: !calls; constructor)
                  ~dependency:(fun () -> calls := "dependency" :: !calls; dependency) in
              let expected_calls, expected = match order with
                | Conv_oracle.Left -> [], true
                | Conv_oracle.Right -> [], false
                | Conv_oracle.Same ->
                  ["constructor"; "dependency"],
                  (match dependency, constructor with
                   | Some left, _ | None, Some left -> left
                   | None, None -> fallback) in
              assert (List.rev !calls = expected_calls);
              assert (result = expected)
            ) [None; Some false; Some true]
          ) [None; Some false; Some true]
        ) [false; true]
      ) [false; true]
    ) [false; true]
  ) [Conv_oracle.Left; Right; Same];
  List.iter (fun order ->
    ignore (choose_unfolding_side ~order ~l2r:false ~heuristic:true
      ~compact1:false ~compact2:false ~constructor:forbidden ~dependency:forbidden)
  ) [Conv_oracle.Left; Right];
  print_endline "unfolding order: PASS (decisive hints skip probes; tied probe evaluation order)"
