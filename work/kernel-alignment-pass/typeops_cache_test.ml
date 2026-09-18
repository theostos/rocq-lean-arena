open Constr
open Names
module Cache = Reviewed_typeops.ApplicationConversions

let () =
  let env = Environ.empty_env in
  let name = Context.make_annot Anonymous Sorts.Relevant in
  let extended = Environ.push_rel
    (Context.Rel.Declaration.LocalAssum (name, mkSort Sorts.type1)) env in
  let left () = mkApp (mkRel 2, [|mkRel 1|]) in
  let right () = mkApp (mkRel 3, [|mkRel 1|]) in
  let count = ref 0 in
  let succeed _ _ _ = incr count; Ok () in
  let cache = Cache.create () in
  assert (Cache.convert cache succeed env (left ()) (right ()) = Ok ());
  assert (!count = 1);
  assert (Cache.convert cache succeed env (left ()) (right ()) = Ok ());
  assert (!count = 1 && cache.hits = 1);
  (* Same raw relative variables in a different context must be checked. *)
  assert (Cache.convert cache succeed extended (left ()) (right ()) = Ok ());
  assert (!count = 2);
  (* Cumulativity is directed, not an unordered equivalence cache. *)
  assert (Cache.convert cache succeed env (right ()) (left ()) = Ok ());
  assert (!count = 3);
  let other = Cache.create () in
  ignore (Cache.convert other succeed env (left ()) (right ()));
  assert (!count = 4);
  let fail _ _ _ = incr count; Error () in
  let failures = Cache.create () in
  assert (Cache.convert failures fail env (left ()) (right ()) = Error ());
  assert (Cache.convert failures fail env (left ()) (right ()) = Error ());
  assert (!count = 6 && failures.hits = 0);
  let interrupted = Cache.create () in
  (try ignore (Cache.convert interrupted (fun _ _ _ -> raise Exit)
      env (left ()) (right ())); assert false with Exit -> ());
  ignore (Cache.convert interrupted succeed env (left ()) (right ()));
  assert (!count = 7 && interrupted.hits = 0);
  (* Exact universe instances/sorts, relocations, and argument order matter. *)
  assert (not (Cache.same_term (mkSort Sorts.set) (mkSort Sorts.type1)));
  assert (not (Cache.same_term (left ()) (right ())));
  assert (not (Cache.same_term (mkApp (mkRel 2, [|mkRel 1; mkRel 2|]))
                              (mkApp (mkRel 2, [|mkRel 2; mkRel 1|]))));
  (* Bounded syntax inspection must not expand a shared DAG exponentially. *)
  let rec dag n = if n = 0 then mkRel 1 else
    let child = dag (n - 1) in mkApp (mkRel 2, [|child; child|]) in
  let shared = dag 30 in
  assert (Cache.same_term shared shared);
  assert (not (Cache.same_term shared (dag 30)));
  let wide () = mkApp (mkRel 2, Array.make 2048 (mkRel 1)) in
  assert (not (Cache.same_term (wide ()) (wide ())));
  for i = 1 to 10000 do
    ignore (Cache.convert cache succeed env
      (mkApp (mkRel 2, [|mkRel i|])) (right ()))
  done;
  assert (Array.for_all (fun entries -> List.length entries <= 4)
    (Lazy.force cache.buckets));
  assert (Array.fold_left (fun n entries -> n + List.length entries) 0
    (Lazy.force cache.buckets) <= 4096);
  (* Exercise the actual typing machine as well as cache dispatch. All local
     declarations below are well-formed. x has a beta-expanded alias of A. *)
  let env = Environ.set_typing_flags
    { (Environ.typing_flags env) with unfold_dep_heuristic = true } env in
  let push typ env = Environ.push_rel
    (Context.Rel.Declaration.LocalAssum (name, typ)) env in
  let arrow a b = mkProd (name, a, b) in
  let universe = mkSort Sorts.type1 in
  let env = push universe env in (* A *)
  let env = push (mkApp (mkLambda (name, universe, mkRel 1), [|mkRel 1|])) env in (* x *)
  let env = push (arrow (mkRel 2) (mkRel 3)) env in (* f : A -> A *)
  let env = push (arrow (mkRel 3) (mkRel 4)) env in (* g : A -> A *)
  let env = push (arrow (mkRel 4) (arrow (mkRel 5) (mkRel 6))) env in (* p *)
  let app f args = mkApp (mkRel f, Array.of_list args) in
  let valid = app 1 [app 3 [mkRel 4]; app 2 [mkRel 4]] in
  let inferred = Reviewed_typeops.infer env valid in
  assert (Constr.equal inferred.Environ.uj_type (mkRel 5));
  let conversions = Cache.create () in
  let typing_cache : Reviewed_typeops.typing_cache =
    { inferred = HConstr.Tbl.create (); conversions } in
  let typ = Reviewed_typeops.execute_aux typing_cache env (HConstr.of_constr env valid) in
  assert (Constr.equal typ (mkRel 5));
  assert (conversions.hits > 0);
  (* The first argument check succeeds, but the second supplies a function
     where A is required. A cached success must not hide this error. *)
  let invalid = app 1 [app 3 [mkRel 4]; app 2 [mkRel 3]] in
  (try ignore (Reviewed_typeops.infer env invalid); assert false
   with Type_errors.TypeError _ -> ());
  print_endline "typing conversion cache: PASS (scope, direction, failure, interrupt, bounds)"
