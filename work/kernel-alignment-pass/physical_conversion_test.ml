open Constr
open CClosure
open Esubst
open Reviewed_conversion

let () =
  let local n = mk_clos (subs_id 2, UVars.Instance.empty) (mkRel n) in
  let leaf = local 1 in
  (* The graph is shared, not an exponentially materialized syntax tree. *)
  let shared = ref leaf in
  for _ = 1 to 30 do
    shared := zip !shared [Zapp [|!shared; !shared|]]
  done;
  let budget = ref 1 in
  assert (fast_test_under budget el_id !shared el_id !shared);
  assert (!budget = 0);
  (* Physical identity without equal relocations does NOT imply equality. *)
  assert (not (fast_test_under (ref 1024) el_id leaf (el_shft 1 el_id) leaf));
  assert (not (fast_test_under (ref 1024) el_id !shared (el_shft 1 el_id) !shared));
  let different = local 2 in
  assert (not (fast_test_under (ref 1024) el_id leaf el_id different));
  (* Ordinary structural equality and relocated variables remain available. *)
  assert (fast_test_under (ref 1024) el_id leaf el_id (local 1));
  assert (fast_test_under (ref 1024) (el_shft 1 el_id) leaf el_id different);
  let same = syntactically_same_arguments in
  assert (same el_id [Zapp [|leaf; different|]] el_id
    [Zapp [|local 1|]; Zapp [|local 2|]]);
  assert (not (same el_id [Zapp [|leaf|]] el_id [Zapp [|different|]]));
  assert (not (same el_id [Zapp [|leaf|]] el_id [Zapp [|leaf; leaf|]]));
  (* A shift affects frames before it, not arguments following it. *)
  assert (same el_id [Zapp [|leaf|]; Zshift 1; Zapp [|leaf|]] el_id
    [Zapp [|different; leaf|]]);
  assert (not (same el_id [Zshift 1; Zapp [|leaf|]] el_id
    [Zapp [|different|]]));
  assert (same (el_shft 1 el_id) [Zapp [|leaf|]] el_id [Zapp [|different|]]);
  assert (same el_id [Zapp [|leaf|]; Zupdate different] el_id [Zapp [|leaf|]]);
  assert (fast_test el_id different el_id (local 2));
  (* Unsupported eliminations and oversized stacks decline the preference. *)
  assert (not (same el_id [Zfix (leaf, [])] el_id [Zfix (leaf, [])]));
  assert (not (same el_id [Zapp (Array.make 1024 leaf)] el_id
    [Zapp (Array.make 1024 leaf)]));
  assert (not (same el_id (List.init 1025 (fun _ -> Zshift 1)) el_id []));
  (* Compare the same constructor syntax before and after head exposure. *)
  let open Names in
  let path = MPfile (DirPath.make [Id.of_string "ArgumentView"]) in
  let ind = MutInd.make2 path (Id.of_string "Tag"), 0 in
  let ctor = mkConstructU ((ind, 1), UVars.Instance.empty) in
  let identity = subs_id 2, UVars.Instance.empty in
  let wrap arg = mkApp (ctor, [|arg|]) in
  let raw subst body = mk_clos subst body in
  let expose term = fst (whd_stack
    (create_conv_infos RedFlags.betaiotazeta Environ.empty_env) (create_tab ()) term []) in
  let left = expose (raw identity (wrap (mkRel 1))) in
  let right = raw identity (wrap (mkRel 1)) in
  let before_left, before_right = fterm_of left, fterm_of right in
  assert (same el_id [Zapp [|left|]] el_id [Zapp [|right|]]);
  assert (same el_id [Zapp [|right|]] el_id [Zapp [|left|]]);
  assert (not (same el_id [Zapp [|left|]] el_id
    [Zapp [|raw identity (wrap (mkRel 2))|]]));
  assert (not (same (el_shft 1 el_id) [Zapp [|left|]] el_id [Zapp [|right|]]));
  assert (same (el_shft 1 el_id) [Zapp [|left|]] el_id
    [Zapp [|raw identity (wrap (mkRel 2))|]]);
  let substituted = usubs_cons (local 1) identity in
  assert (same el_id [Zapp [|left|]] el_id [Zapp [|raw substituted (wrap (mkRel 1))|]]);
  assert (same (el_shft 1 el_id) [Zapp [|left|]] el_id
    [Zapp [|raw (usubs_lift substituted) (wrap (mkRel 2))|]]);
  let outer term = expose (mk_clos (usubs_cons term identity) (wrap (mkRel 1))) in
  assert (same el_id [Zapp [|outer left|]] el_id [Zapp [|outer right|]]);
  assert (not (same el_id [Zapp [|left|]] el_id
    [Zapp [|raw identity (mkApp (ctor, [|mkRel 1; mkRel 2|]))|]]));
  let other_ctor = mkConstructU ((ind, 2), UVars.Instance.empty) in
  assert (not (same el_id [Zapp [|left|]] el_id
    [Zapp [|raw identity (mkApp (other_ctor, [|mkRel 1|]))|]]));
  assert (fterm_of left == before_left && fterm_of right == before_right);
  print_endline "physical conversion: PASS (shared DAG, relocation, bounded stack reflexivity)"
