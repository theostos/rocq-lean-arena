(* Observation only: distinguish identity reuse from reconstructed syntax. *)
open Constr
open CClosure
open Esubst
open Reviewed_conversion

let () =
  let path = Names.ModPath.MPfile
      (Names.DirPath.make [Names.Id.of_string "CacheReconstruction"]) in
  let observe label build =
    let infos = { Application_cache_test.infos with
      cnv_failed_congruences = make_failed_congruence_cache () } in
    let head = Names.ConstKey (Names.Constant.make2 path
        (Names.Id.of_string label), UVars.Instance.empty) in
    let executions = ref 0 in
    for i = 0 to 99 do
      let left, right = build i in
      try ignore (try_congruence infos el_id el_id head [Zapp [|left|]]
        head [Zapp [|right|]] (fun _ -> incr executions; raise NotConvertible))
      with NotConvertible -> ()
    done;
    Printf.printf "%s: %d comparisons, %d cache hits\n%!" label !executions
      infos.cnv_failed_congruences.failed_hits
  in
  let left = inject mkProp and right = inject mkSProp in
  observe "shared" (fun _ -> left, right);
  observe "reconstructed" (fun _ -> inject mkProp, inject mkSProp);
  observe "reversed" (fun i -> if i mod 2 = 0 then left, right else right, left)
