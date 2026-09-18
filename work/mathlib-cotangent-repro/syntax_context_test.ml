(* A closure may reconstruct the (substitution, universes) wrapper without
   changing either component. A completed syntax comparison should survive
   that administrative allocation within the SAME read-only probe. *)
open Constr
open CClosure
open Reviewed_conversion

let instance = UVars.Instance.empty
let binder = Context.make_annot Names.Name.Anonymous Sorts.Relevant
let left = mkLambda (binder, mkSet, mkRel 1)
let right = mkLambda (binder, mkSet, mkRel 1)
let () =
  let s = Esubst.subs_id 0 in
  let wrapper () = Sys.opaque_identity (s, instance) in
  let e = wrapper () and f = wrapper () in
  let memo = lazy (SyntaxPairs.create 17) in
  assert (compare_under ~memo (ref 1024) e left f right);
  let g = wrapper () and h = wrapper () in
  assert (e != g && f != h && fst e == fst g && snd e == snd g);
  let hit = compare_under ~memo (ref 1) g left h right in
  Printf.printf "same substitution components, fresh wrapper: memo_hit=%b\n%!" hit;
  assert hit;
  let closure_memo = lazy (SyntaxPairs.create 17) in
  let closure_pair () = mk_clos (wrapper ()) left, mk_clos (wrapper ()) right in
  let a, b = closure_pair () in
  assert (fast_test_under ~memo:closure_memo (ref 1024) Esubst.el_id a Esubst.el_id b);
  let c, d = closure_pair () in
  assert (a != c && b != d);
  Gc.full_major ();
  Gc.compact ();
  assert (fast_test_under ~memo:closure_memo (ref 2) Esubst.el_id c Esubst.el_id d);
  print_endline "PASS: fresh FCLOS cells reuse the completed raw-syntax comparison";
  let universe = Univ.Level.var 0 in
  let body () = mkLambda (binder,
    mkSort (Sorts.sort_of_univ (Univ.Universe.make universe)), mkRel 1) in
  let l = body () and r = body () in
  let e0 = s, UVars.Instance.of_array ([||], [|Univ.Level.set|])
  and e1 = s, UVars.Instance.of_array ([||], [|Univ.Level.var 1|]) in
  assert (compare_under ~memo (ref 1024) e0 l e0 r);
  let e0_fresh = s, UVars.Instance.of_array ([||], [|Univ.Level.set|]) in
  assert (compare_under ~memo (ref 1) e0_fresh l e0_fresh r);
  assert (not (compare_under ~memo (ref 1024) e0 l e1 r));
  let a = usubs_cons (inject mkSet) (s, instance)
  and b = usubs_cons (inject mkProp) (s, instance) in
  let l = mkLambda (binder, mkRel 1, mkRel 1)
  and r = mkLambda (binder, mkRel 1, mkRel 1) in
  assert (compare_under ~memo (ref 1024) a l a r);
  assert (not (compare_under ~memo (ref 1024) a l b r));
  print_endline "PASS: universe and captured-term differences remain distinct"
