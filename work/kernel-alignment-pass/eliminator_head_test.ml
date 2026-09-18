open Names
open Constr
open CClosure
open Esubst
open Reviewed_conversion

(* Classification tests, not typing judgments. Real proof acceptance and
   rejection are tested in abbrev_congruence_order.v and the Char replay. *)
let () =
  let path = MPfile (DirPath.make [Id.of_string "EliminatorHead"]) in
  let ind = MutInd.make2 path (Id.of_string "Tag"), 0 in
  let ctor = mkConstructU ((ind, 1), UVars.Instance.empty) in
  let typ = mkIndU (ind, UVars.Instance.empty) in
  let binder = Context.make_annot Anonymous Sorts.Relevant in
  let def body env = Environ.push_rel
    (Context.Rel.Declaration.LocalDef (binder, body, typ)) env in
  let assume env = Environ.push_rel
    (Context.Rel.Declaration.LocalAssum (binder, typ)) env in
  let env = Environ.empty_env |> def ctor |> assume |> def (mkRel 2) in
  let visible env term = visible_constructor_head env term in
  assert (visible env (inject ctor));
  assert (visible env (inject (mkApp (ctor, [|mkRel 2|]))));
  assert (visible env (inject (mkRel 1)));
  assert (not (visible env (inject (mkRel 2))));
  assert (visible env (inject (mkRel 3)));
  assert (not (visible env (inject (mkRel 4))));
  (* A lookup is relative to its environment, not a name/relative-index cache. *)
  assert (not (visible (assume Environ.empty_env) (inject (mkRel 1))));
  (* New binder variables are not environment-relative definitions. *)
  assert (not (visible env (mk_clos (subs_id 3, UVars.Instance.empty) (mkRel 1))));
  let substitution = usubs_cons (inject (mkRel 1)) (subs_id 0, UVars.Instance.empty) in
  assert (visible env (mk_clos substitution (mkRel 1)));
  assert (not (visible env (mk_clos (usubs_lift substitution) (mkRel 1))));
  assert (visible env (mk_clos (usubs_lift substitution) (mkRel 2)));
  assert (visible env (zip (inject (mkRel 1)) [Zshift 7]));
  (* Do not evaluate arbitrary beta-redexes just to choose an unfolding side. *)
  let redex = inject (mkApp (mkLambda (binder, typ, mkRel 1), [|ctor|])) in
  let before = fterm_of redex in
  assert (not (visible env redex));
  assert (fterm_of redex == before);
  let alias = inject (mkRel 1) in
  let before = fterm_of alias in
  for _ = 1 to 1000 do assert (visible env alias) done;
  assert (fterm_of alias == before);
  (* Alias depth and environment lookup indices have independent bounds. *)
  let chain = ref (def ctor Environ.empty_env) in
  for _ = 1 to 100 do chain := def (mkRel 1) !chain done;
  assert (not (visible !chain (inject (mkRel 1))));
  let deep = ref (def ctor Environ.empty_env) in
  for _ = 1 to 4096 do deep := assume !deep done;
  assert (not (visible !deep (inject (mkRel 4097))));
  assert (not (visible env (inject (mkRel max_int))));
  print_endline "eliminator head: PASS (local aliases, offsets, binders, bounds, no mutation)"
