open Constr
open CClosure

let check = Reviewed_conversion.small_reification
let allowance = Reviewed_conversion.application_quotation_budget

let tree depth =
  let term = ref (mkRel 1) in
  for _ = 1 to depth do
    term := mkApp (mkRel 2, [|!term; !term|])
  done;
  mk_clos (Esubst.subs_id 2, UVars.Instance.empty) !term

let () =
  (* Prefixes can legitimately exceed the type-query allowance. Budget the
     expanded occurrences, even though the input is a tiny shared DAG. *)
  let prefix = tree 12 in
  assert (not (check (ref 4096) prefix));
  let remaining = ref allowance in
  assert (check remaining prefix);
  let consumed = allowance - !remaining in
  assert (consumed > 4096);
  assert (check remaining prefix);
  assert (allowance - !remaining = 2 * consumed);
  (* Exact boundaries and a small negative budget are non-accepting. *)
  assert (check (ref consumed) prefix);
  assert (not (check (ref (consumed - 1)) prefix));
  assert (not (check (ref (-1)) prefix));
  let huge = tree 50 in
  let before = Gc.allocated_bytes () in
  assert (not (check (ref allowance) huge));
  assert (Gc.allocated_bytes () -. before < 8_000_000.);
  Printf.printf "Expanded quotation budgets passed (prefix=%d nodes).\n%!" consumed
