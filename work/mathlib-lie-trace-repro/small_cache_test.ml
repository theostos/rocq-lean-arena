open Constr
open CClosure
open Esubst
open Reviewed_conversion

let binder = Context.make_annot Names.Anonymous Sorts.Relevant
let infos : unit conv_tab = {
  cnv_inf = create_conv_infos RedFlags.betaiotazeta Environ.empty_env;
  cnv_typ = true;
  cnv_rel_types = Range.empty; cnv_rel_type_lifts = Range.empty;
  cnv_probe_budget = None; cnv_strategy_budget = None;
  cnv_projection_conversions = make_projection_conversion_cache ();
  cnv_successful_conversions = make_successful_conversion_cache 32768;
  cnv_memoize_successful_conversions = true; cnv_projection_congruence = false;
  cnv_dependency_preference = false; cnv_constructor_relevance = false;
  cnv_constructor_masks = ConstructorMasks.create 1;
  lft_tab = create_tab (); rgt_tab = create_tab ();
  err_ret = (fun _ -> assert false);
}

let get = function Some (value, _) -> value | None -> assert false
let term n = inject (mkApp (mkRel n, [|mkProp; mkRel (n + 1)|]))
let key left right = small_conversion_key infos el_id left el_id right
let same_pair (a,b) (c,d) = a == c && b == d

let () =
  let left = term 1 and right = term 2 in
  let original = key left right in
  assert (not (small_conversion_cached infos CONV original));
  (* Test cache mechanics, not a claim that these arbitrary test terms convert. *)
  remember_small_conversion infos CONV original;
  let rebuilt = key (term 1) (term 2) in
  assert (same_pair (get original) (get rebuilt));
  assert (small_conversion_cached infos CONV rebuilt);
  assert (not (small_conversion_cached infos CUMUL rebuilt));
  assert (not (small_conversion_cached infos CONV (key right left)));
  assert (not (small_conversion_cached infos CONV (key (term 3) right)));
  let shifted = small_conversion_key infos (el_shft 1 el_id) (term 1) el_id right in
  assert (same_pair (get (key (term 2) right)) (get shifted));
  List.iter (fun changed ->
    assert (not (small_conversion_cached changed CONV rebuilt))) [
    {infos with cnv_inf = CClosure.push_relevance infos.cnv_inf binder};
    {infos with cnv_rel_types = Range.cons (Some left) Range.empty};
    {infos with cnv_rel_type_lifts = Range.cons el_id Range.empty};
    {infos with cnv_successful_conversions = make_successful_conversion_cache 32768};
  ];
  assert (small_conversion_key {infos with cnv_memoize_successful_conversions = false}
    el_id left el_id right = None);

  (* Quoting an exponentially expanded closure DAG must be declined, leaving
     the source frozen term unchanged and using bounded allocation. *)
  let identity = subs_id 0, UVars.Instance.empty in
  let huge = ref (inject mkProp) in
  for _ = 1 to 50 do
    huge := mk_clos (usubs_cons !huge identity)
      (mkProd (binder, mkRel 1, mkRel 2))
  done;
  let before = fterm_of !huge in
  let allocated = Gc.allocated_bytes () in
  assert (key !huge right = None);
  assert (fterm_of !huge == before);
  assert (Gc.allocated_bytes () -. allocated < 1_000_000.);

  for i = 1 to 10000 do
    let changed = {infos with cnv_rel_type_lifts = Range.cons (el_shft i el_id) Range.empty} in
    remember_small_conversion changed CONV rebuilt;
    assert (List.length (SmallConversionPairs.find
      infos.cnv_successful_conversions.small_conversion_table (get rebuilt)) <= 8)
  done;
  assert (not (small_conversion_cached infos CONV original));
  for i = 1 to 10000 do
    let next = key (term (i + 10)) right in
    remember_small_conversion infos CONV next;
    assert (infos.cnv_successful_conversions.small_conversion_size <= 2048);
    assert (small_conversion_cached infos CONV next)
  done;
  assert (not (small_conversion_cached infos CONV original));
  remember_small_conversion infos CONV original;
  let rec extended n infos =
    if n = 0 then infos else
    extended (n - 1) (push_relevance ~typ:(Some (inject mkProp)) infos binder) in
  List.iter (fun depth ->
    let under = extended depth infos in
    let shifted term = mk_clos (subs_id depth, UVars.Instance.empty)
      (Vars.lift depth (term_of_fconstr term)) in
    let next = small_conversion_key under el_id (shifted left) el_id (shifted right) in
    assert (small_conversion_cached under CONV next);
    (* Referencing a newly introduced local must prevent dropping its context. *)
    let local = mk_clos (subs_id depth, UVars.Instance.empty)
      (term_of_fconstr left) in
    let local_key = small_conversion_key under el_id local el_id (shifted right) in
    assert (not (small_conversion_cached under CONV local_key))) [1; 2; 3; 8];
  let lambda = inject (mkLambda (binder, mkRel 1, mkRel 1)) in
  let lambda_key = key lambda right in
  remember_small_conversion infos CONV lambda_key;
  let under = extended 2 infos in
  let shifted term = mk_clos (subs_id 2, UVars.Instance.empty)
    (Vars.lift 2 (term_of_fconstr term)) in
  assert (small_conversion_cached under CONV
    (small_conversion_key under el_id (shifted lambda) el_id (shifted right)));
  print_endline "Small-expression conversion cache: bounded keys, contexts, relocation, eviction PASS"
