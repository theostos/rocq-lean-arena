open Constr
let () =
  let f = mkVar (Names.Id.of_string "crossed_shared_dag") in
  List.iter (fun depth ->
    let a = ref mkSet and b = ref mkProp in
    for _ = 1 to depth do
      let a', b' = mkApp (f,[|!a;!b|]), mkApp (f,[|!b;!a|]) in
      a := a'; b := b'
    done;
    let start = Sys.time () in
    ignore (HConstr.of_constr Environ.empty_env !a);
    ignore (Vars.sort_and_universes_of_constr !a);
    Printf.printf "crossed DAG depth=%d CPU=%.6f\n%!" depth (Sys.time () -. start)
  ) [8;12;16;20;24;64;128;256];
  List.iter (fun depth ->
    let a = ref mkSet and b = ref mkProp in
    for _ = 1 to depth do
      let next = mkApp (f,[|!a;!b|]) in b := !a; a := next
    done;
    let start = Sys.time () in
    ignore (HConstr.of_constr Environ.empty_env !a);
    ignore (Vars.sort_and_universes_of_constr !a);
    Printf.printf "multi-depth Fibonacci DAG depth=%d CPU=%.6f\n%!" depth (Sys.time () -. start)
  ) [16;32;64;128;256]
