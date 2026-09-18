(* Compile conversion.ml as Reviewed_conversion to test this private cache
   without adding any test-only exports to the trusted kernel interface. *)
open CClosure
open Esubst
open Reviewed_conversion

let () =
  let cache = make_projection_conversion_cache () in
  let left = inject (Constr.mkRel 1) and right = inject (Constr.mkRel 2) in
  let entry = {
    projection_left_lift = el_id; projection_left_term = left;
    projection_right_lift = el_id; projection_right_term = right;
    projection_relevances = Range.empty;
    projection_rel_types = Range.empty;
    projection_rel_type_lifts = Range.empty;
  } in
  let cached ?(relevances = Range.empty) ?(rel_types = Range.empty)
      ?(rel_type_lifts = Range.empty) ?(lift = el_id) left right =
    projection_conversion_cached cache ~relevances ~rel_types ~rel_type_lifts
      lift left el_id right in
  assert (not (cached left right));
  remember_projection_conversion cache entry;
  assert (cached left right);
  assert (not (cached right left));
  assert (not (cached ~lift:(el_shft 1 el_id) left right));
  assert (not (cached ~relevances:(Range.cons Sorts.Irrelevant Range.empty) left right));
  assert (not (cached ~rel_types:(Range.cons (Some left) Range.empty) left right));
  assert (not (cached ~rel_type_lifts:(Range.cons el_id Range.empty) left right));
  (* Physical identity, not the mutable representation or its structural hash. *)
  assert (not (cached (inject (Constr.mkRel 1)) right));
  (* Many contexts of one physical pair cannot create an unbounded bucket. *)
  for i = 1 to 10000 do
    remember_projection_conversion cache
      {entry with projection_left_lift = el_shft i el_id};
    assert (cache.projection_size <= 8);
    assert (List.length (ConversionPairs.find cache.projection_table (left, right)) <= 8)
  done;
  assert (cached ~lift:(el_shft 10000 el_id) left right);
  assert (not (cached left right));
  (* Distinct pairs are also bounded; eviction must produce a miss. *)
  let last = ref entry in
  for i = 1 to 20000 do
    let next = { entry with projection_left_term = inject (Constr.mkRel i) } in
    remember_projection_conversion cache next;
    last := next;
    assert (cache.projection_size <= 4096);
    assert (ConversionPairs.length cache.projection_table <= 4096)
  done;
  assert (cached !last.projection_left_term right);
  assert (not (cached left right));
  print_endline "projection conversion cache: PASS (keys, context variants, 4096-entry bound)"
