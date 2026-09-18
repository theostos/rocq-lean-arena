(* Preserve both the result priority and the effects of constructor inspection. *)
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
              assert (List.rev !calls = ["constructor"; "dependency"]);
              let expected = match dependency, constructor with
                | Some left, _ | None, Some left -> left
                | None, None -> fallback in
              assert (result = expected)
            ) [None; Some false; Some true]
          ) [None; Some false; Some true]
        ) [false; true]
      ) [false; true]
    ) [false; true]
  ) [Conv_oracle.Left; Right; Same];
  print_endline "unfolding order: PASS (validated result priority and probe evaluation order)"
