(************************************************************************)
(*         *   The Coq Proof Assistant / The Coq Development Team       *)
(*  v      *   INRIA, CNRS and contributors - Copyright 1999-2019       *)
(* <O___,, *       (see CREDITS file for the list of authors)           *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

open Names
open Univ
open UVars
module RelDecl = Context.Rel.Declaration
open LeanExpr

let __ () = assert false
let invalid = Constr.(mkApp (mkSet, [| mkSet |]))

let add_universe l ~lbound g =
  let g = UGraph.add_universe l ~strict:false g in
  UGraph.enforce_constraint (lbound, Le, l) g

let quickdef ~name ~types ~univs ?(opaque=false) body =
  let entry = Declare.definition_entry ~opaque ?types ~univs body in
  let scope = Locality.(Global ImportDefaultBehavior) in
  let kind = Decls.(IsDefinition Definition) in
  let uctx =
    UState.empty
    (* used for ubinders and hook *)
  in
  Declare.declare_entry ~name ~scope ~kind ~impargs:[] ~uctx entry

type extended_level = Level of Level.t | LSProp

type scheme_family = SchemeSProp | SchemeType

(** produce [args, recargs] inside mixed context [args/recargs] [info] is in
    reverse order, ie the head is about the last arg in application order

    examples: [] -> [],[] [false] -> [1],[] [true] -> [2],[1] [true;false] ->
    [3;2],[1] [false;true] -> [3;1],[2] [false;false] -> [2;1],[] [true;true] ->
    [4;2],[3;1] *)
let reorder_inside_core info =
  let rec aux i args recargs = function
    | [] -> (args, recargs)
    | false :: info -> aux (i + 1) (i :: args) recargs info
    | true :: info -> aux (i + 2) ((i + 1) :: args) (i :: recargs) info
  in
  aux 1 [] [] info

let reorder_inside info =
  let args, recargs = reorder_inside_core info in
  CArray.map_of_list Constr.mkRel (List.append args recargs)

let rec insert_after k ((n, t) as v) c =
  if k = 0 then Constr.mkProd (n, t, Vars.lift 1 c)
  else
    match Constr.kind c with
    | Prod (na, a, b) -> Constr.mkProd (na, a, insert_after (k - 1) v b)
    | _ -> assert false

let insert_after k (n, t) c =
  insert_after k (n, Vars.lift k t) (Vars.subst1 invalid c)

let rec reorder_outside info hyps c =
  match (info, hyps) with
  | [], [] -> (c, 0)
  | false :: info, (n, t) :: hyps ->
    let c, k = reorder_outside info hyps c in
    (Constr.mkProd (n, t, c), k + 1)
  | true :: info, (n, t) :: rhyp :: hyps ->
    let c, k = reorder_outside info hyps c in
    let c = insert_after k rhyp c in
    (Constr.mkProd (n, t, c), k + 1)
  | _ -> assert false

(** produce [forall args recargs, P (C args)] from mixed
    [forall args/recargs, P (C args)] *)
let reorder_outside info ft =
  let hyps, out = Term.decompose_prod ft in
  fst (reorder_outside (List.rev info) (List.rev hyps) out)

(** Whether Rocq's induction-scheme generator will add a recursive hypothesis
    for an argument of type [term].  A mere occurrence of [mind] is not
    enough: for a nested occurrence, Rocq only adds the hypothesis when the
    enclosing inductive has a suitable [AllForall] scheme registered. *)
let rec has_rec_hyp env mind term =
  let locals, head = Reduction.whd_decompose_prod_decls env term in
  let env = Environ.push_rel_context locals env in
  let head, args = Constr.decompose_app head in
  match Constr.kind head with
  | Constr.Ind (((nested_mind, _) as nested_ind), _) ->
    if MutInd.UserOrd.equal mind nested_mind then true
    else
      let nested_mib = Global.lookup_mind nested_mind in
      let positive =
        AllScheme.compute_params_rec_strpos env nested_mind nested_mib
      in
      let uniform = Array.sub args 0 nested_mib.mind_nparams_rec in
      let nested =
        Array.to_list
          (Array.mapi
             (fun i arg ->
               List.nth positive i && has_rec_hyp env mind arg)
             uniform)
      in
      List.exists (fun x -> x) nested
      && Result.is_ok
           (AllScheme.lookup_all_theorem (mind, 0)
              (GlobRef.IndRef nested_ind) nested)
  | Constr.Const (constant, _) when Environ.is_array_type env constant ->
    Array.length args = 1
    && has_rec_hyp env mind args.(0)
    && Result.is_ok
         (AllScheme.lookup_all_theorem (mind, 0)
            (GlobRef.ConstRef constant) [ true ])
  | _ -> false

(** Build the body of a Lean-style scheme. [u] instantiates the inductive, [s]
    is [None] for the SProp scheme and [Some l] for a scheme with motive [l].

    Lean schemes differ from Coq schemes:
    - the motive universe is the first bound universe for Lean but the last for
      Coq (handled by caller)
    - Lean puts induction hypotheses after all the constructor arguments, Coq
      puts them immediately after the corresponding recursive argument. *)
let lean_scheme env ~dep (mind, ind_index) u s =
  let mib = Global.lookup_mind mind in
  let nparams = mib.mind_nparams in
  (* if we start using non recursive params in the translation it will
     involve reordering arguments *)
  assert (nparams = mib.mind_nparams_rec);
	  let body =
	    let sigma = Evd.from_env env in
	    let motive_level = ref None in
	    let sigma, s' = match s with
	    | LSProp -> sigma, EConstr.ESorts.sprop
	    | Level _ ->
	      let sigma, u = Evd.new_univ_level_variable UnivRigid sigma in
	      motive_level := Some u;
	      sigma, EConstr.ESorts.make @@ Sorts.sort_of_univ @@ Universe.make u
	    in
	    let sigma, body =
      if Array.length mib.mind_packets = 1 then
	      Indrec.build_induction_scheme env sigma
	        ((mind, ind_index), EConstr.EInstance.make u)
          dep s'
      else
        let specs =
          List.init (Array.length mib.mind_packets)
            (fun index -> ((mind, index), dep, s'))
        in
        let sigma, bodies =
          Indrec.build_mutual_induction_scheme env sigma ~force_mutual:true
            specs (EConstr.EInstance.make u)
        in
        (sigma, List.nth bodies ind_index)
	    in
	    let body = EConstr.Unsafe.to_constr body in
	    let uctx = Evd.sort_context_set sigma in
	    let subst_scheme_context quality default_level usubst =
	      let (qvars, scheme_levels), csts = uctx in
	      let body_qvars, _ = Vars.sort_and_universes_of_constr body in
	      let qvars =
	        Sorts.Quality.Set.fold
	          (fun q qvars ->
	            match q with
	            | Sorts.Quality.QVar q -> Sorts.QVar.Set.add q qvars
	            | Sorts.Quality.QConstant _ | Sorts.Quality.QGlobal _ -> qvars)
	          body_qvars qvars
	      in
	      let qsubst =
	        Sorts.QVar.Set.fold
	          (fun q subst -> Sorts.QVar.Map.add q quality subst)
	          qvars Sorts.QVar.Map.empty
	      in
	      let _, ind_levels = Instance.to_array u in
	      let allowed_levels =
	        Array.fold_left
	          (fun levels level -> Level.Set.add level levels)
	          (Level.Set.singleton Level.set)
	          ind_levels
	      in
	      let add_scheme_level level graph =
	        try UGraph.add_universe level ~strict:false graph
	        with UGraph.AlreadyDeclared -> graph
	      in
	      let scheme_graph =
	        UGraph.merge_constraints (PConstraints.univs csts)
	          (Level.Set.fold add_scheme_level scheme_levels
	             (Environ.universes env))
	      in
	      let equal_allowed_level level =
	        let level_univ = Universe.make level in
	        Level.Set.fold
	          (fun allowed acc ->
	            match acc with
	            | Some _ -> acc
	            | None ->
	              let allowed_univ = Universe.make allowed in
	              if UGraph.check_eq scheme_graph level_univ allowed_univ then
	                Some allowed
	              else None)
	          allowed_levels None
	      in
	      let usubst =
	        Level.Set.fold
	          (fun level subst ->
	            if Level.Map.mem level subst || Level.Set.mem level allowed_levels then subst
	            else
	              let target =
	                match equal_allowed_level level with
	                | Some allowed -> allowed
	                | None -> default_level
	              in
	              Level.Map.add level target subst)
	          scheme_levels usubst
	      in
	      Vars.subst_univs_level_constr (qsubst, usubst) body
	    in
	    match s with
	    | LSProp ->
	      subst_scheme_context Sorts.Quality.qsprop Level.set Level.Map.empty
	    | Level s ->
	      let v = match !motive_level with Some v -> v | None -> assert false in
	      subst_scheme_context Sorts.Quality.qtype s (Level.Map.singleton v s)
	  in

  let packet_recinfo (mip : Declarations.one_inductive_body) =
    assert (
      CArray.for_all2 Int.equal mip.mind_consnrealargs mip.mind_consnrealdecls);
    Array.mapi
      (fun i (args, _) ->
        let nargs = mip.mind_consnrealargs.(i) in
        (* skip params *)
        let args = CList.firstn nargs args in
        CList.map
          (fun arg ->
            let t = RelDecl.get_type arg in
            has_rec_hyp env mind t)
          args)
      mip.mind_nf_lc
  in
  let recinfo =
    Array.concat
      (Array.to_list (Array.map packet_recinfo mib.mind_packets))
  in
  let hasrec =
    (* NB: if the only recursive arg is the last arg, no need for reordering *)
    Array.exists
      (function [] -> false | _ :: info -> List.exists (fun x -> x) info)
      recinfo
  in

  if not hasrec then body
  else
    (* body := fun params P (fc : forall args/recargs, P (C args)) => ...

       becomes

       fun params P (fc : forall args, forall recargs, P (C args)) =>
       body params P (fun args/recargs, fc args recargs)
    *)
    let open Constr in
    let nlc = Array.length recinfo in
    let nmotives = Array.length mib.mind_packets in
    let paramsP, inside =
      Term.decompose_lambda_n_assum (nparams + nmotives) body
    in
    let fcs, inside = Term.decompose_lambda_n nlc inside in
    let fcs = List.rev fcs in

    let body =
      mkApp
        ( body,
          Array.init (nparams + nmotives)
            (fun i -> mkRel (nlc + nparams + nmotives - i)) )
    in
    let body =
      mkApp
        ( body,
          Array.of_list
            (CList.map_i
               (fun i (_, ft) ->
                 let info = recinfo.(i) in
                 if not (List.exists (fun x -> x) info) then mkRel (nlc - i)
                 else
                   let hyps, _ = Term.decompose_prod ft in
                   let args = reorder_inside info in
                   Term.it_mkLambda_or_LetIn
                     (mkApp (mkRel (nlc - i + List.length hyps), args))
                     (List.map (fun (n, t) -> RelDecl.LocalAssum (n, t)) hyps))
               0 fcs) )
    in

    let fcs =
      CList.map_i
        (fun i (n, ft) ->
          let info = recinfo.(i) in
          let ft = reorder_outside info ft in
          RelDecl.LocalAssum (n, ft))
        0 fcs
    in
    let fcs = List.rev fcs in
    let body =
      let open CClosure in
      let open RedFlags in
      let env = Environ.push_rel_context paramsP env in
      let env = Environ.push_rel_context fcs env in
      norm_val (create_clos_infos betaiota env) (create_tab ()) (inject body)
    in
    Term.it_mkLambda_or_LetIn (Term.it_mkLambda_or_LetIn body fcs) paramsP

let with_unsafe_univs f () =
  let flags = Global.typing_flags () in
  Global.set_typing_flags { flags with check_eliminations = false };
  try
    let v = f () in
    Global.set_typing_flags flags;
    v
  with e ->
    let e = Exninfo.capture e in
    Global.set_typing_flags flags;
    Exninfo.iraise e

module N = LeanName

let sort_of_level = function
  | LSProp -> Sorts.sprop
  | Level u -> Sorts.sort_of_univ (Universe.make u)

let univ_of_sort = function
  | Sorts.SProp -> None
  | Prop -> assert false
  | Set -> Some Universe.type0
  | Type u | GSort (_, u) | VSort (_, u) -> Some u

let sort_max (s1 : Sorts.t) (s2 : Sorts.t) =
  match (s1, s2) with
  | SProp, SProp | Prop, Prop | Set, Set -> s1
  | SProp, ((Prop | Set | Type _) as s) | ((Prop | Set | Type _) as s), SProp ->
    s
  | Prop, ((Set | Type _) as s) | ((Set | Type _) as s), Prop -> s
  | Set, Type u | Type u, Set ->
    Sorts.sort_of_univ (Univ.Universe.sup Univ.Universe.type0 u)
  | Type u, Type v -> Sorts.sort_of_univ (Univ.Universe.sup u v)
  | GSort _, _ | _, GSort _ -> assert false
  | VSort _, _ | _, VSort _ -> assert false

(** [map] goes from lean names to universes (in practice either SProp or a named
    level) *)
let rec to_universe map = function
  | U.Prop -> Sorts.sprop
  | UNamed n -> sort_of_level (N.Map.get n map)
  | Succ u -> Sorts.super (to_universe map u)
  | Max (a, b) -> sort_max (to_universe map a) (to_universe map b)
  | IMax (a, b) ->
    let ub = to_universe map b in
    if Sorts.is_sprop ub then ub else sort_max (to_universe map a) ub

let rec do_n f x n = if n = 0 then x else do_n f (f x) (n - 1)

(** in lean, imax(Prop+1,l)+1 <= max(Prop+1,l+1) because:
    - either l=Prop, so Prop+1 <= Prop+1
    - or Prop+1 <= l so l+1 <= l+1

    to simulate this, each named level becomes > Set and we compute maxes
    accordingly *)

let simplify_universe u =
  match Universe.repr u with
  | (l, n) :: (l', n') :: rest when Level.is_set l ->
    if n <= n' + 1 || List.exists (fun (_, n') -> n <= n' + 1) rest then
      List.fold_left
        (fun u (l, n) ->
          Universe.sup u (do_n Universe.super (Universe.make l) n))
        (do_n Universe.super (Universe.make l') n')
        rest
    else u
  | _ -> u

let simplify_sort = function
  | Sorts.Type u -> Sorts.sort_of_univ (simplify_universe u)
  | s -> s

(* Return the biggest [n] such that [Set+n <= u]. Assumes a simplified
   [u] as above. *)
let max_increment u =
  match Universe.repr u with
  | (l, n) :: rest when Level.is_set l -> n
  | l -> List.fold_left (fun m (_, n) -> max m (n + 1)) 0 l

let to_universe map u =
  let u = to_universe map u in
  simplify_sort u

(** Map from [n] to the global level standing for [Set+n] (not including n=0).
*)
let sets : Level.t Int.Map.t ref =
  Summary.ref ~name:"lean-set-surrogates" Int.Map.empty

type uconv = {
  map : extended_level N.Map.t;  (** Map from lean names to Coq universes *)
  levels : Level.t Universe.Map.t;
      (** Map from algebraic universes to levels (only levels representing an
          algebraic) *)
  direct : Level.Set.t;
      (** Named Lean levels that occur directly in universe instances. Levels
          that only occur below an algebraic successor do not need to be exposed
          as parameters of the translated declaration. *)
  graph : UGraph.t;
}

let lean_id = Id.of_string "Lean"

let { Goptions.get = lean_fancy_univs } =
  Goptions.declare_bool_option_and_ref
    ~key:[ "Lean"; "Fancy"; "Universes" ]
    ~value:true ()

let level_of_universe_core u =
  let u =
    List.map
      (fun (l, n) ->
        let open Level in
        if is_set l then "Set+" ^ string_of_int n
        else
          match name l with
          | None -> assert false
          | Some name ->
            let d, s, i = UGlobal.repr name in
            let d = DirPath.repr d in
            (match (d, i) with
            | [ name; l ], 0 when Id.equal l lean_id ->
              Id.to_string name ^ if n = 0 then "" else "+" ^ string_of_int n
            | _ -> to_string l))
      u
  in
  let s = (match u with [ _ ] -> "" | _ -> "max__") ^ String.concat "_" u in
  Level.(
    make (UGlobal.make (DirPath.make [ Id.of_string_soft s; lean_id ]) "" 0))

let level_of_universe u =
  let u = Universe.repr u in
  level_of_universe_core u

let level_of_universe u =
  if lean_fancy_univs () then level_of_universe u else UnivGen.fresh_level ()

let update_graph (l, u) (l', u') graph =
  if UGraph.check_leq graph (Universe.super u) u' then
    UGraph.enforce_constraint (l, Lt, l') graph
  else if UGraph.check_leq graph (Universe.super u') u then
    UGraph.enforce_constraint (l', Lt, l) graph
  else if UGraph.check_leq graph u u' then
    UGraph.enforce_constraint (l, Le, l') graph
  else if UGraph.check_leq graph u' u then
    UGraph.enforce_constraint (l', Le, l) graph
  else graph

let is_sets u =
  match Universe.repr u with
  | [ (u, n) ] -> if Level.is_set u then Some n else None
  | _ -> None

(** Find or add a global level for Set+n *)
let rec level_of_sets uconv n =
  if n = 0 then (uconv, Level.set)
  else
    try (uconv, Int.Map.find n !sets)
    with Not_found ->
      let uconv, p = level_of_sets uconv (n - 1) in
      let l =
        if lean_fancy_univs () then level_of_universe_core [ (Level.set, n) ]
        else UnivGen.fresh_level ()
      in
      Global.push_context_set
        (Level.Set.singleton l, UnivConstraints.singleton (p, Lt, l));
      sets := Int.Map.add n l !sets;
      let graph = add_universe l ~lbound:p uconv.graph in
      ({ uconv with graph }, l)

let to_univ_level u uconv =
  match Universe.level u with
  | Some l -> ({ uconv with direct = Level.Set.add l uconv.direct }, l)
  | None ->
    (match is_sets u with
    | Some n -> level_of_sets uconv n
    | None ->
      (match Universe.Map.find_opt u uconv.levels with
      | Some l -> (uconv, l)
      | None ->
        let uconv, mset = level_of_sets uconv (max_increment u) in
        let l = level_of_universe u in
        let graph = add_universe l ~lbound:mset uconv.graph in
        let graph =
          Universe.Map.fold
            (fun u' l' graph -> update_graph (l, u) (l', u') graph)
            uconv.levels graph
        in
        let graph =
          N.Map.fold
            (fun _ l' graph ->
              match l' with
              | LSProp -> graph
              | Level l' -> update_graph (l, u) (l', Universe.make l') graph)
            uconv.map graph
        in
        let uconv =
          { uconv with levels = Universe.Map.add u l uconv.levels; graph }
        in
        (uconv, l)))

(** Definitional height, used for unfolding heuristics.

    The definitional height is the longest sequence of constant unfoldings until
    we get a term without definitions (recursors don't count). *)

let height_cache = Summary.ref ~name:"lean-heights" N.Map.empty

let rec height = function
  | Const (c, _) ->
    (try N.Map.find c !height_cache + 1
     with Not_found ->
       (* non constant, recursor, or just skipped *)
       0)
  | Bound _ | Sort _ -> 0
  | Lam (_, _, a, b) | Pi (_, _, a, b) | App (a, b) -> max (height a) (height b)
  | Let { name = _; ty; v; rest } -> max (height ty) (max (height v) (height rest))
  | Proj (_, _, c) -> height c
  | Nat _ | String _ -> 0

let height n body =
  match N.Map.find_opt n !height_cache with
  | Some h -> h
  | None ->
    let h = height body in
    height_cache := N.Map.add n h !height_cache;
    h

(** Lean code sometimes uses huge Nat literals as fuel values. If Rocq unfolds
    these constants too eagerly during conversion, it can start reducing a large
    recursive computation under projections. Make just these literal constants
    lower priority while preserving the usual height heuristic for definitions
    that merely refer to them. *)

let large_nat_literal_cache =
  Summary.ref ~name:"lean-large-nat-literals" N.Map.empty

let large_nat_threshold = Z.of_int 5000
let large_nat_unfold_level = 1000

let rec contains_large_nat_literal = function
  | Nat n -> Z.geq n large_nat_threshold
  | Bound _ | Sort _ | Const _ | String _ -> false
  | App (a, b) | Lam (_, _, a, b) | Pi (_, _, a, b) ->
    contains_large_nat_literal a || contains_large_nat_literal b
  | Let { name = _; ty; v; rest } ->
    contains_large_nat_literal ty
    || contains_large_nat_literal v
    || contains_large_nat_literal rest
  | Proj (_, _, c) ->
    contains_large_nat_literal c

let contains_large_nat_literal n body =
  match N.Map.find_opt n !large_nat_literal_cache with
  | Some b -> b
  | None ->
    let b = contains_large_nat_literal body in
    large_nat_literal_cache := N.Map.add n b !large_nat_literal_cache;
    b

type instantiation = {
  ref : GlobRef.t;
  algs : Universe.t list;
      (** Full Rocq universe instance as algebraic universes over the Lean
          universe parameters. *)
}

let universe_var i = Universe.make (Level.var i)
let identity_algs n = List.init n universe_var

let non_sprop_univ_count nunivs i =
  let rec loop j acc =
    if j = nunivs then acc
    else
      let acc = if i land (1 lsl j) = 0 then acc + 1 else acc in
      loop (j + 1) acc
  in
  loop 0 0

(*
Lean classifies inductives in the following way:
- inductive landing in always >Prop (even when instantiated to all Prop) -> never squashed
- inductive which has Prop instantiation:
  + no constructor -> never squashed
  + multi constructor -> always squashed
  + 1 constructor
    * no non param arguments
      -> not squashed, special reduction
      typically [eq]
    * all arguments appear in the output type
      -> not squashed, basic reduction
      no real world examples? eg [Inductive foo : nat -> Prop := bar : forall x, foo x.]
      2019 "type theory of lean" implies that there should be special reduction
      but testing says otherwise
    * some arguments don't appear in the output type, but are Prop or recursive
      -> not squashed, basic reduction
      typically [Acc], [and]
    * some non-Prop non-recursive arguments (for some instantiation) don't appear in the output type
      -> squashed
      typically [exists]

Additionally, the recursor is always dependent (since Lean 4)
(this implem detail isn't in the TTofLean paper)
Special reduction also seems restricted to always-Prop types.

NB: in practice (all stdlib and mathlib) the target universe is available without reduction
(ie syntactic arity) even though the system doesn't require it.
so we can just look at it directly (we don't want to implement a reduction system)
Update: now we have correct Coq envs so we could reduce the Coq term?

Difference with Coq:
- a non-Prop instantiation of possibly Prop types will never be squashed
- non squashed possibly-Prop types at a Prop instantiation are squashed
  (unless empty or uip branch)
- we need uip for the special reduction.
  TTofLean sounds like we need an encoding with primitive records
  but testing indicates otherwise (all args in output type case).
- we will always need unsafe flags for [Acc], and possibly for [and].

Instantiating the type with all-Prop may side-effect instantiate
some other globals with Prop that won't actually be used
(assuming the inductive is not used with all-Prop)
This probably doesn't matter much, also if we start using upfront
instantiations it won't matter at all.

Primitive records:
Lean autodetects all record-capable types as having primitive
projections, and also autogenerates the eliminators.
Squashed Props with 1 ctor have primitive projections up to the first non-Prop field.
*)

type squashy = {
  maybe_prop : bool;  (** used for optim, not fundamental *)
  always_prop : bool;
      (** controls special reduction, but we just let Coq do its thing for that
      *)
  lean_squashes : bool;
      (** Self descriptive. We handle necessity of unsafe flags
          per-instantiation. *)
}

let noprop = { maybe_prop = false; always_prop = false; lean_squashes = false }

let pp_squashy { maybe_prop; always_prop; lean_squashes } =
  let open Pp in
  (if maybe_prop then
     if always_prop then str "is always Prop" else str "may be Prop"
   else str "is never Prop")
  ++ spc ()
  ++
  if lean_squashes then str "and is squashed by Lean"
  else str "and is not squashed by Lean"

let coq_squashes graph (entry : Entries.mutual_inductive_entry) =
  let env = Global.env () in
  let env = Environ.set_universes graph env in
  let ind =
    match entry.mind_entry_inds with [ ind ] -> ind | _ -> assert false
  in
  let params = entry.mind_entry_params in
  let ty = ind.mind_entry_arity in
  let env_params = Environ.push_rel_context params env in
  let _, s = Reduction.dest_arity env_params ty in
  (* TODO merge with uip branch *)
  if not (Sorts.is_sprop s) then false
  else
    match ind.mind_entry_lc with
    | [] -> false
    | _ :: _ :: _ -> true
    | [ c ] -> (match Constr.kind c with Rel _ | App _ -> false | _ -> true)

let with_env_evm rels uconv f x =
  (* In non upfront mode,
     because we interleave defining new constants as we encounter them,
     pushing rels and handling local universes,
     we pass just the rel_context_val and merge it with the global env and the uconv here *)
  let env = Global.env () in
  let env = Environ.set_rel_context_val rels env in
  let env = Environ.set_universes uconv.graph env in
  let evd = Evd.from_env env in
  f env evd x

let to_annot rels n t uconv =
  let r =
    with_env_evm rels uconv
      (fun env evd r ->
        let r = Retyping.relevance_of_type env evd r in
        EConstr.Unsafe.to_relevance r)
      (EConstr.of_constr t)
  in
  Context.make_annot (N.to_name n) r

(* bit n of [int_of_univs univs] is 1 iff [List.nth univs n] is SProp *)
let int_of_univs =
  let rec aux i acc = function
    | [] -> (i, acc)
    | u :: rest ->
      (match univ_of_sort u with
      | None -> aux ((i * 2) + 1) acc rest
      | Some u -> aux (i * 2) (u :: acc) rest)
  in
  fun l -> aux 0 [] (List.rev l)

let univ_of_name u =
  if lean_fancy_univs () then
    let u = DirPath.make [ N.to_id u; lean_id ] in
    Level.(make (UGlobal.make u "" 0))
  else UnivGen.fresh_level ()

let start_uconv univs i =
  let uconv =
    {
      graph = Global.universes ();
      map = N.Map.empty;
      levels = Universe.Map.empty;
      direct = Level.Set.empty;
    }
  in
  let uconv, set1 = level_of_sets uconv 1 in
  let rec aux uconv i = function
    | [] ->
      assert (i = 0);
      uconv
    | u :: univs ->
      let map, graph =
        if i mod 2 = 0 then
          let v = univ_of_name u in
          ( N.Map.add u (Level v) uconv.map,
            add_universe v ~lbound:set1 uconv.graph )
        else (N.Map.add u LSProp uconv.map, uconv.graph)
      in
      aux { uconv with map; graph } (i / 2) univs
  in
  aux uconv i univs

let rec _make_unames univs ounivs =
  match (univs, ounivs) with
  | _, [] ->
    List.map (fun u -> Name (Id.of_string_soft (Level.to_string u))) univs
  | _u :: univs, o :: ounivs -> N.to_name o :: _make_unames univs ounivs
  | [], _ :: _ -> assert false

let univ_entry_gen ?(drop_global_lower_bounds = false)
    { map; levels; direct; graph } ounivs =
  let original_pairs =
    CList.map_filter
      (fun u ->
        let v = N.Map.get u map in
        match v with LSProp -> None | Level v -> Some (u, v))
      ounivs
  in
  let original_levels = List.map snd original_pairs in
  let original_instance =
    Instance.of_array ([||], Array.of_list original_levels)
  in
  let original_subst = snd (make_instance_subst original_instance) in
  let direct_pairs =
    List.filter (fun (_, l) -> Level.Set.mem l direct) original_pairs
  in
  let direct_set =
    List.fold_left
      (fun kept (_, l) -> Level.Set.add l kept)
      Level.Set.empty direct_pairs
  in
  let extra_pairs =
    Universe.Map.fold (fun alg l acc -> (alg, l) :: acc) levels [] |> List.rev
  in
  let decl_pairs =
    List.map (fun (u, l) -> (Some u, Universe.make l, l)) direct_pairs
    @ List.map (fun (alg, l) -> (None, alg, l)) extra_pairs
  in
  let univs = List.map (fun (_, _, l) -> l) decl_pairs in
  let uset =
    List.fold_left (fun kept l -> Level.Set.add l kept) Level.Set.empty univs
  in
  let kept = Level.Set.add Level.set uset in
  let kept = Int.Map.fold (fun _ -> Level.Set.add) !sets kept in
  let csts = UGraph.constraints_for ~kept graph in
  let csts =
    UnivConstraints.filter
      (fun (a, _, b) ->
        if drop_global_lower_bounds then
          (Level.Set.mem a uset && Level.Set.mem b uset)
          || Level.Set.mem a direct_set || Level.Set.mem b direct_set
        else Level.Set.mem a uset || Level.Set.mem b uset)
      csts
  in
  let unames =
    {
      quals = [||];
      univs =
        Array.of_list
          (List.map
             (function
               | Some u, _, _ -> N.to_name u
               | None, _, l -> Name (Id.of_string_soft (Level.to_string l)))
             decl_pairs);
    }
  in
  let univs_inst = Instance.of_array ([||], Array.of_list univs) in
  let uctx = UContext.make unames (univs_inst, PConstraints.of_univs csts) in
  let algs =
    List.map
      (fun (_, alg, _) ->
        simplify_universe (subst_univs_level_universe original_subst alg))
      decl_pairs
  in
  (uctx, algs)

let univ_entry a b =
  let uctx, algs = univ_entry_gen a b in
  ((UState.Polymorphic_entry uctx, UnivNames.empty_binders), algs)

(* TODO restrict univs (eg [has_add : Sort (u+1) -> Sort(u+1)] can
   drop the [u] and keep only the replacement for [u+1]??

   Preserve algebraics in codomain position? *)

let name_for_core n i =
  if i = 0 then N.to_id n
  else Id.of_string (N.to_coq_string n ^ "_inst" ^ string_of_int i)

(* NB collisions for constructors/recursors are still possible but
   should be rare *)
let name_for n i =
  let base = name_for_core n i in
  if not (Global.exists_objlabel base) then base
  else
    (* prevent resetting the number *)
    let base = if i = 0 then base else Id.of_string (Id.to_string base ^ "_") in
    Namegen.next_global_ident_away (Global.safe_env ()) base Id.Set.empty

let get_predeclared_ind indn n i =
  if N.equal n (N.append_list N.anon indn) then
    let ind_name = name_for_core n i in
    let reg = "lean." ^ Id.to_string ind_name in
    match Rocqlib.lib_ref reg with
    | IndRef (ind, 0) -> Some (ind_name, ind)
    | _ ->
      CErrors.user_err
        Pp.(
          str "Bad registration for "
          ++ str reg
          ++ str " expected an inductive.")
    | exception _ -> None
  else None

(** Like [get_predeclared_ind] but looks for an inductive predeclared as a
    definition (using a ".cumul" suffix on the registration). Returns the
    ConstRef of the predeclared definition. *)
let get_predeclared_ind_as_def indn n i =
  if N.equal n (N.append_list N.anon indn) then
    let ind_name = name_for_core n i in
    let reg = "lean." ^ Id.to_string ind_name ^ ".cumul" in
    match Rocqlib.lib_ref reg with
    | ConstRef c -> Some (ind_name, c)
    | _ ->
      CErrors.user_err
        Pp.(
          str "Bad registration for "
          ++ str reg
          ++ str " expected a constant.")
    | exception _ -> None
  else None

let get_predeclared_def defn n i =
  if N.equal n (N.append_list N.anon defn) then
    let def_name = name_for_core n i in
    let reg = "lean." ^ Id.to_string def_name in
    match Rocqlib.lib_ref reg with
    | ConstRef c -> Some (def_name, c)
    | _ ->
      CErrors.user_err
        Pp.(
          str "Bad registration for " ++ str reg ++ str " expected a constant.")
    | exception _ -> None
  else None

<<<<<<< HEAD
type predeclared_ind_kind = Eq | Nat | Nat_le | Or | And | Fin | UInt8 | UInt32 | UInt64 | USize | BitVec | Char
type predeclared_def_kind =
  | System_Platform_numBits
  | System_Platform_numBits_eq
  | UInt32_size
  | UInt32_ofNatLT
	  | UInt64_size
	  | UInt64_ofNatLT
	  | USize_toBitVec
	  | USize_toNat
		  | USize_size
		  | USize_size_eq
		  | USize_le_size
		  | USize_size_le
		  | UInt8_toNat
	  | UInt8_toUInt32
  | Add
  | Mult
  | Pow
  | Nat_isValidChar
  | IsValidChar_UInt32
  | IsValidChar_UInt32_match_1_1
  | Char_ofNatAux
  | Char_ofNat
=======
type core_shape = Legacy | Modern

type predeclared_ind_kind =
  | Eq
  | Nat
  | Nat_le
  | Or
  | And
  | Fin
  | UInt32 of core_shape
  | BitVec
  | Char of core_shape
type predeclared_def_kind = UInt32_size | Add | Mult | Pow | Nat_isValidChar
>>>>>>> parent of dec4a1b (Predeclare modern Char construction helpers)
type predeclared_ind_as_def_kind = ULift_cumul

let get_predeclared_cnames (k : predeclared_ind_kind) n =
  match k with
  | Eq -> [ N.append n "refl" ]
  | Nat -> [ N.append n "zero"; N.append n "succ" ]
  | Nat_le -> [ N.append n "refl"; N.append n "step" ]
  | Or -> [ N.append n "inl"; N.append n "inr" ]
  | And -> [ N.append n "intro" ]
  | Fin -> [ N.append n "mk" ]
  | UInt8 -> [ N.append n "ofBitVec" ]
  | UInt32 -> [ N.append n "ofBitVec" ]
  | UInt64 -> [ N.append n "ofBitVec" ]
  | USize -> [ N.append n "ofBitVec" ]
  | BitVec -> [ N.append n "ofFin" ]
  | Char -> [ N.append n "mk" ]

let get_predeclared_ind_any n i =
  List.filter_map
    (fun (indk, indh) ->
      get_predeclared_ind indh n i |> Option.map (fun x -> (indk, indh, x)))
    [
      (Eq, [ "Eq" ]);
      (Nat, [ "Nat" ]);
      (Nat_le, [ "Nat"; "le" ]);
      (Or, [ "Or" ]);
      (And, [ "And" ]);
      (Fin, [ "Fin" ]);
      (UInt8, [ "UInt8" ]);
      (UInt32, [ "UInt32" ]);
      (UInt64, [ "UInt64" ]);
      (USize, [ "USize" ]);
      (BitVec, [ "BitVec" ]);
      (Char, [ "Char" ]);
    ]

let get_predeclared_ind_some n i =
  match get_predeclared_ind_any n i with
  | [] -> None
  | [ x ] -> Some x
  | _ :: _ :: _ ->
    CErrors.user_err
      Pp.(str "Multiple predeclared inductive types for " ++ N.pp n)

let get_predeclared_ind_as_def_any n i =
  List.filter_map
    (fun (k, h) ->
      get_predeclared_ind_as_def h n i |> Option.map (fun x -> (k, h, x)))
    [
      (ULift_cumul, [ "ULift" ]);
    ]

let get_predeclared_ind_as_def_some n i =
  match get_predeclared_ind_as_def_any n i with
  | [] -> None
  | [ x ] -> Some x
  | _ :: _ :: _ ->
    CErrors.user_err
      Pp.(str "Multiple predeclared ind-as-def constants for " ++ N.pp n)

let get_predeclared_def_any n i =
  List.filter_map
    (fun (defk, defh) ->
      get_predeclared_def defh n i |> Option.map (fun x -> (defk, defh, x)))
    [
      (System_Platform_numBits, [ "System"; "Platform"; "numBits" ]);
      (System_Platform_numBits_eq, [ "System"; "Platform"; "numBits_eq" ]);
      (UInt32_size, [ "UInt32"; "size" ]);
      (UInt32_ofNatLT, [ "UInt32"; "ofNatLT" ]);
	      (UInt64_size, [ "UInt64"; "size" ]);
	      (UInt64_ofNatLT, [ "UInt64"; "ofNatLT" ]);
	      (USize_toBitVec, [ "USize"; "toBitVec" ]);
	      (USize_toNat, [ "USize"; "toNat" ]);
		      (USize_size, [ "USize"; "size" ]);
		      (USize_size_eq, [ "USize"; "size_eq" ]);
		      (USize_le_size, [ "USize"; "le_size" ]);
		      (USize_size_le, [ "USize"; "size_le" ]);
		      (UInt8_toNat, [ "UInt8"; "toNat" ]);
	      (UInt8_toUInt32, [ "UInt8"; "toUInt32" ]);
      (Add, [ "Nat"; "add" ]);
      (Mult, [ "Nat"; "mul" ]);
      (Pow, [ "Nat" ; "pow" ]);
      (Nat_isValidChar, [ "Nat"; "isValidChar" ]);
<<<<<<< HEAD
      ( IsValidChar_UInt32_match_1_1,
        [ "_private"; "Init"; "Prelude0"; "isValidChar_UInt32"; "match_1_1" ]
      );
      ( IsValidChar_UInt32,
        [ "_private"; "Init"; "Prelude0"; "isValidChar_UInt32" ]
      );
      (Char_ofNatAux, [ "Char"; "ofNatAux" ]);
      (Char_ofNat, [ "Char"; "ofNat" ]);
=======
>>>>>>> parent of dec4a1b (Predeclare modern Char construction helpers)
    ]

let get_predeclared_def_some n i =
  match get_predeclared_def_any n i with
  | [] -> None
  | [ x ] -> Some x
  | _ :: _ :: _ ->
    CErrors.user_err Pp.(str "Multiple predeclared constants for " ++ N.pp n)

let predeclared_def_strategy = function
  | Pow -> Some (Conv_oracle.Level large_nat_unfold_level)
  | _ -> None

let low_priority_def n =
  List.exists
    (fun defn -> N.equal n (N.append_list N.anon defn))
    [
      [ "BitVec"; "ofNat" ];
      [ "BitVec"; "umod" ];
      [ "BitVec"; "shiftLeft" ];
    ]

let is_assemble2_mod_bound_proof n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.ByteArray.utf8DecodeChar__q.assemble_UU2082_._proof_1"

let is_assemble2_valid_char_proof n =
  String.equal (N.to_lean_string n)
    "ByteArray.utf8DecodeChar__q.assemble_UU2082_._proof_3"

let is_assemble3_mod_bound_proof n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.ByteArray.utf8DecodeChar__q.assemble_UU2083_._proof_3"

let is_assemble3_mid_bound_proof n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.ByteArray.utf8DecodeChar__q.assemble_UU2083_._proof_4"

let is_assemble3_valid_char_proof n =
  String.equal (N.to_lean_string n)
    "ByteArray.utf8DecodeChar__q.assemble_UU2083_._proof_7"

let is_val_assemble1_le_proof n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.ByteArray.utf8DecodeChar__q.val_assemble_UU2081__le"

let is_helper3_proof n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.ByteArray.utf8DecodeChar__q.helper_UU2083_"

let is_utf8size_four_proof_1_4 n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.Char.utf8Size_eq_four_iff._proof_1_4"

let is_utf8size_four_proof_1_5 n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.Char.utf8Size_eq_four_iff._proof_1_5"

let is_assemble3_of_toBitVec_proof_1_8 n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.ByteArray.utf8DecodeChar__q.assemble_UU2083__eq_some_of_toBitVec._proof_1_8"

let is_assemble4_of_toBitVec_proof_1_8 n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.ByteArray.utf8DecodeChar__q.assemble_UU2084__eq_some_of_toBitVec._proof_1_8"

let is_assemble4_iff_proof_1_10 n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.ByteArray.utf8DecodeChar__q.assemble_UU2084__eq_some_iff_utf8EncodeChar_eq._proof_1_10"

let is_char_toNat_val_le_proof_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Init.Data.String.Decode0.Char.toNat_val_le._proof_1_1"

let is_usize_toNat_ofNat_of_lt_32 n =
  String.equal (N.to_lean_string n) "USize.toNat_ofNat_of_lt_32"

let is_usize_size_pos n =
  String.equal (N.to_lean_string n) "USize.size_pos"

let is_int64_toInt_minValue n =
  String.equal (N.to_lean_string n) "Int64.toInt_minValue"

let is_sqrt_iter_sq_le_proof_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Nat.Sqrt0.Nat.sqrt.iter_sq_le._proof_1_1"

let is_sqrt_isSqrt_proof_1_6 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Nat.Sqrt0.Nat.sqrt_isSqrt._proof_1_6"

let is_sqrt_isSqrt_proof_1_7 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Nat.Sqrt0.Nat.sqrt_isSqrt._proof_1_7"

let is_sqrt_add_eq_proof_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Nat.Sqrt0.Nat.sqrt_add_eq._proof_1_1"

let is_sqrt_add_eq_proof_1_2 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Nat.Sqrt0.Nat.sqrt_add_eq._proof_1_2"

let is_le_three_of_sqrt_eq_one_proof_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Nat.Sqrt0.Nat.le_three_of_sqrt_eq_one._proof_1_1"

let is_sqrt_lt_self_proof_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Nat.Sqrt0.Nat.sqrt_lt_self._proof_1_1"

let is_sqrt_succ_le_succ_sqrt_proof_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Nat.Sqrt0.Nat.sqrt_succ_le_succ_sqrt._proof_1_1"

let is_uint32_toUInt64_proof_1 n =
  String.equal (N.to_lean_string n) "UInt32.toUInt64._proof_1"

let is_uint32_not_neg_one n =
  String.equal (N.to_lean_string n) "UInt32.not_neg_one"

let is_uint64_max_bound_proof n =
  List.exists
    (String.equal (N.to_lean_string n))
    [
      "UInt64.ofNatTruncate._proof_1";
      "UInt64.toFin_ofNatTruncate_of_le._proof_1";
      "UInt64.toBitVec_ofNatTruncate_of_le._proof_1";
    ]

let is_uint64_toNat_ofNatTruncate_of_le n =
  String.equal (N.to_lean_string n) "UInt64.toNat_ofNatTruncate_of_le"

let is_uint64_toNat_ofNatLT n =
  String.equal (N.to_lean_string n) "UInt64.toNat_ofNatLT"

let is_uint64_toFin_ofNatTruncate_of_le n =
  String.equal (N.to_lean_string n) "UInt64.toFin_ofNatTruncate_of_le"

let is_uint64_toBitVec_ofNatTruncate_of_le n =
  String.equal (N.to_lean_string n) "UInt64.toBitVec_ofNatTruncate_of_le"

let is_uint64_of_fin n =
  String.equal (N.to_lean_string n) "UInt64.ofFin"

let is_except_conds_and_eq_left n =
  String.equal (N.to_lean_string n) "Std.Do.ExceptConds.and_eq_left"

let is_nat_locally_finite_order_proof_3 n =
  String.equal (N.to_lean_string n) "Nat.instLocallyFiniteOrder._proof_3"

let is_nat_locally_finite_order_proof_4 n =
  String.equal (N.to_lean_string n) "Nat.instLocallyFiniteOrder._proof_4"

let is_nat_ico_image_const_sub_proof_1_4 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Order.Interval.Finset.Nat0.Nat.Ico_image_const_sub_eq_Ico._proof_1_4"

let is_nat_ico_image_const_sub_proof_1_3 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Order.Interval.Finset.Nat0.Nat.Ico_image_const_sub_eq_Ico._proof_1_3"

let is_nat_icc_insert_succ_right_proof_1_3 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Order.Interval.Finset.Nat0.Nat.Icc_insert_succ_right._proof_1_3"

let is_list_prev_reverse_eq_next_proof_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.prev_reverse_eq_next._proof_1_1"

let is_list_next_eq_get_elem_proof_1 n =
  String.equal (N.to_lean_string n) "List.next_eq_getElem._proof_1"

let is_list_next_eq_get_elem n =
  String.equal (N.to_lean_string n) "List.next_eq_getElem"

let is_list_next_eq_get_elem_proof_1_3 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.next_eq_getElem._proof_1_3"

let is_list_next_eq_get_elem_proof_1_4 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.next_eq_getElem._proof_1_4"

let is_list_next_eq_get_elem_proof_1_34 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.next_eq_getElem._proof_1_34"

let is_list_next_eq_get_elem_proof_1_19 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.next_eq_getElem._proof_1_19"

let is_list_next_eq_get_elem_proof_1_36 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.next_eq_getElem._proof_1_36"

let is_list_next_get_elem_proof_1_4 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.next_getElem._proof_1_4"

let is_list_next_get_elem_proof_1_6 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.next_getElem._proof_1_6"

let is_list_next_get_elem n =
  String.equal (N.to_lean_string n) "List.next_getElem"

let is_list_pmap_next_eq_rotate_one n =
  String.equal (N.to_lean_string n) "List.pmap_next_eq_rotate_one"

let is_list_pmap_prev_eq_rotate_length_sub_one n =
  String.equal (N.to_lean_string n)
    "List.pmap_prev_eq_rotate_length_sub_one"

let is_list_prev_get_elem_proof_1 n =
  String.equal (N.to_lean_string n) "List.prev_getElem._proof_1"

let is_list_prev_get_elem_proof_1_4 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.prev_getElem._proof_1_4"

let is_list_prev_get_elem_proof_1_6 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.prev_getElem._proof_1_6"

let is_list_prev_get_elem n =
  String.equal (N.to_lean_string n) "List.prev_getElem"

let is_list_prev_eq_get_elem_proof_1_2 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.prev_eq_getElem._proof_1_2"

let is_list_prev_eq_get_elem_proof_1_3 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.prev_eq_getElem._proof_1_3"

let is_list_prev_eq_get_elem_proof_1_4 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.prev_eq_getElem._proof_1_4"

let is_list_prev_eq_get_elem_proof_1_7 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.prev_eq_getElem._proof_1_7"

let is_list_prev_eq_get_elem_pred_proof_1 n =
  String.equal (N.to_lean_string n)
    "List.prev_eq_getElem_idxOf_pred_of_ne_head._proof_1"

let is_list_prev_eq_get_elem_proof_1_8 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.List.prev_eq_getElem._proof_1_8"

let is_list_prev_eq_get_elem n =
  String.equal (N.to_lean_string n) "List.prev_eq_getElem"

let is_list_prev_reverse_eq_next n =
  String.equal (N.to_lean_string n) "List.prev_reverse_eq_next"

let is_list_next_reverse_eq_prev n =
  String.equal (N.to_lean_string n) "List.next_reverse_eq_prev"

let is_list_is_rotated_next_eq n =
  String.equal (N.to_lean_string n) "List.isRotated_next_eq"

let is_list_is_rotated_prev_eq n =
  String.equal (N.to_lean_string n) "List.isRotated_prev_eq"

let is_list_next_prev n =
  String.equal (N.to_lean_string n) "List.next_prev"

let is_list_prev_next n =
  String.equal (N.to_lean_string n) "List.prev_next"

let is_cycle_prev_proof_1 n =
  String.equal (N.to_lean_string n) "Cycle.prev._proof_1"

let is_cycle_prev n = String.equal (N.to_lean_string n) "Cycle.prev"

let is_cycle_next_proof_1 n =
  String.equal (N.to_lean_string n) "Cycle.next._proof_1"

let is_cycle_next n = String.equal (N.to_lean_string n) "Cycle.next"

let is_cycle_prev_reverse_eq_next n =
  String.equal (N.to_lean_string n) "Cycle.prev_reverse_eq_next"

let is_cycle_next_reverse_eq_prev_simp_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Cycle0.Cycle.next_reverse_eq_prev._simp_1_1"

let is_cycle_prev_congr_simp n =
  String.equal (N.to_lean_string n) "Cycle.prev.congr_simp"

let is_cycle_next_reverse_eq_prev n =
  String.equal (N.to_lean_string n) "Cycle.next_reverse_eq_prev"

let is_cycle_next_mem n =
  String.equal (N.to_lean_string n) "Cycle.next_mem"

let is_cycle_prev_mem n =
  String.equal (N.to_lean_string n) "Cycle.prev_mem"

let is_cycle_next_prev n =
  String.equal (N.to_lean_string n) "Cycle.next_prev"

let is_list_succ_idx_of_mem_drop_last_proof_1_1 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.List.Basic0.List.succ_idxOf_lt_length_of_mem_dropLast._proof_1_1"

let is_nanosecond_offset_of_hours_proof_1 n =
  String.equal (N.to_lean_string n)
    "_private.Std.Time.Time.Unit.Basic0.Std.Time.Nanosecond.Offset.ofHours._proof_1"

let is_nanosecond_offset_of_minutes_proof_1 n =
  String.equal (N.to_lean_string n)
    "_private.Std.Time.Time.Unit.Basic0.Std.Time.Nanosecond.Offset.ofMinutes._proof_1"

let is_millisecond_offset_of_hours_proof_1 n =
  String.equal (N.to_lean_string n)
    "_private.Std.Time.Time.Unit.Basic0.Std.Time.Millisecond.Offset.ofHours._proof_1"

let is_week_offset_of_milliseconds_proof_1 n =
  String.equal (N.to_lean_string n)
    "_private.Std.Time.Date.Unit.Week0.Std.Time.Week.Offset.ofMilliseconds._proof_1"

let is_week_offset_of_nanoseconds_proof_1 n =
  String.equal (N.to_lean_string n)
    "_private.Std.Time.Date.Unit.Week0.Std.Time.Week.Offset.ofNanoseconds._proof_1"

let is_week_offset_to_nanoseconds_proof_1 n =
  String.equal (N.to_lean_string n)
    "_private.Std.Time.Date.Unit.Week0.Std.Time.Week.Offset.toNanoseconds._proof_1"

let is_list_append_cancel_right n =
  String.equal (N.to_lean_string n) "List.append_cancel_right"

let is_nat_subtype_succ_le_of_lt_proof_1_3 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Logic.Denumerable0.Nat.Subtype.succ_le_of_lt._proof_1_3"

let is_nat_subtype_succ_le_of_lt_proof_1_4 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Logic.Denumerable0.Nat.Subtype.succ_le_of_lt._proof_1_4"

let is_nat_subtype_le_succ_of_forall_lt_le_proof_1_2 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Logic.Denumerable0.Nat.Subtype.le_succ_of_forall_lt_le._proof_1_2"

let is_order_iso_subsequence_proof_1_4 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Order.OrderIsoNat0.exists_increasing_or_nonincreasing_subseq'._proof_1_4"

let is_order_iso_subsequence_proof_1_5 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Order.OrderIsoNat0.exists_increasing_or_nonincreasing_subseq'._proof_1_5"

let is_plain_time_of_nanoseconds_large_bound_proof n =
  String.equal (N.to_lean_string n)
    "_private.Std.Time.Time.PlainTime0.Std.Time.PlainTime.ofNanoseconds._proof_1"

let is_std_time_parse_with n =
  String.equal (N.to_lean_string n)
    "_private.Std.Time.Format.Basic0.Std.Time.parseWith"

let is_punit_comm_group_def n =
  List.exists
    (String.equal (N.to_lean_string n))
    [ "PUnit.commGroup"; "PUnit.addCommGroup" ]

let is_equiv_prod_punit_def n =
  List.exists
    (String.equal (N.to_lean_string n))
    [ "Equiv.prodPUnit"; "Equiv.sigmaPUnit" ]

let is_lean_json_cases_on_def n =
  String.equal (N.to_lean_string n) "Lean.Json.casesOn"

let is_lean_info_tree_cases_on_def n =
  String.equal (N.to_lean_string n) "Lean.Elab.InfoTree.casesOn"

let is_remove_after_done_action_sparse_cases_on_3_def n =
  String.equal (N.to_lean_string n)
    "_private.Batteries.CodeAction.Misc0.Batteries.CodeAction.\
     removeAfterDoneAction._sparseCasesOn_3"

let is_lean_json_sparse_cases_on_6_def n =
  String.equal (N.to_lean_string n)
    "Lean.Lsp.instFromJsonResolvableCompletionItemData._sparseCasesOn_6"

let is_lean_json_beq_sparse_cases_on_8_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.Basic0.Lean.Json.beq'._sparseCasesOn_8"

let is_lean_json_beq_sparse_cases_on_3_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.Basic0.Lean.Json.beq'._sparseCasesOn_3"

let is_lean_json_beq_sparse_cases_on_4_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.Basic0.Lean.Json.beq'._sparseCasesOn_4"

let is_lean_json_beq_sparse_cases_on_5_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.Basic0.Lean.Json.beq'._sparseCasesOn_5"

let is_lean_json_beq_sparse_cases_on_6_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.Basic0.Lean.Json.beq'._sparseCasesOn_6"

let is_lean_json_beq_sparse_cases_on_7_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.Basic0.Lean.Json.beq'._sparseCasesOn_7"

let is_option_from_json_sparse_cases_on_1_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.FromToJson.Basic0.Option.fromJson__q._sparseCasesOn_1"

let is_array_from_json_sparse_cases_on_1_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.FromToJson.Basic0.Array.fromJson__q._sparseCasesOn_1"

let is_float_from_json_sparse_cases_on_1_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.FromToJson.Basic0.Float.fromJson__q._sparseCasesOn_1"

let is_name_map_from_json_sparse_cases_on_1_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.FromToJson.Basic0.Lean.NameMap.fromJson__q._sparseCasesOn_1"

let is_json_structured_from_json_sparse_cases_on_1_def n =
  String.equal (N.to_lean_string n)
    "_private.Lean.Data.Json.FromToJson.Basic0.Lean.Json.Structured.fromJson__q._sparseCasesOn_1"

let is_command_parsed_snapshot_below_1_def n =
  String.equal (N.to_lean_string n)
    "Lean.Language.Lean.CommandParsedSnapshot.below_1"

type do_code_below_focus =
  | DoCode
  | DoAltArray
  | DoAltExprArray
  | DoAltList
  | DoAltExprList
  | DoAlt
  | DoAltExpr

let do_code_below_focus n =
  match N.to_lean_string n with
  | "Lean.Elab.Term.Do.Code.below" -> Some DoCode
  | "Lean.Elab.Term.Do.Code.below_1" -> Some DoAltArray
  | "Lean.Elab.Term.Do.Code.below_2" -> Some DoAltExprArray
  | "Lean.Elab.Term.Do.Code.below_3" -> Some DoAltList
  | "Lean.Elab.Term.Do.Code.below_4" -> Some DoAltExprList
  | "Lean.Elab.Term.Do.Code.below_5" -> Some DoAlt
  | "Lean.Elab.Term.Do.Code.below_6" -> Some DoAltExpr
  | _ -> None

let is_do_code_below_def n = Option.has_some (do_code_below_focus n)

let is_persistent_hash_map_node_sizeof_1_def n =
  String.equal (N.to_lean_string n) "Lean.PersistentHashMap.Node._sizeOf_1"

let is_fin_cast_succ_lt_or_lt_succ_proof_1_2 n =
  String.equal (N.to_lean_string n)
    "_private.Mathlib.Data.Fin.SuccPred0.Fin.castSucc_lt_or_lt_succ._proof_1_2"

let reconstruct_def_by_rocq n =
  List.exists
    (fun defn -> N.equal n (N.append_list N.anon defn))
    [ [ "UInt32"; "toNat_shiftLeft" ]; [ "UInt64"; "toNat_shiftLeft" ] ]
  || is_assemble2_mod_bound_proof n
  || is_assemble2_valid_char_proof n
  || is_assemble3_mod_bound_proof n
  || is_assemble3_mid_bound_proof n
  || is_assemble3_valid_char_proof n
  || is_val_assemble1_le_proof n
  || is_helper3_proof n
  || is_utf8size_four_proof_1_4 n
  || is_utf8size_four_proof_1_5 n
  || is_assemble3_of_toBitVec_proof_1_8 n
  || is_assemble4_of_toBitVec_proof_1_8 n
  || is_assemble4_iff_proof_1_10 n
  || is_char_toNat_val_le_proof_1_1 n
  || is_usize_toNat_ofNat_of_lt_32 n
  || is_usize_size_pos n
  || is_int64_toInt_minValue n
  || is_sqrt_iter_sq_le_proof_1_1 n
  || is_sqrt_isSqrt_proof_1_6 n
  || is_sqrt_isSqrt_proof_1_7 n
  || is_sqrt_add_eq_proof_1_1 n
  || is_sqrt_add_eq_proof_1_2 n
  || is_le_three_of_sqrt_eq_one_proof_1_1 n
  || is_sqrt_lt_self_proof_1_1 n
  || is_sqrt_succ_le_succ_sqrt_proof_1_1 n
  || is_uint32_toUInt64_proof_1 n
  || is_uint32_not_neg_one n
  || is_uint64_max_bound_proof n
  || is_uint64_toNat_ofNatTruncate_of_le n
  || is_uint64_toNat_ofNatLT n
  || is_uint64_toFin_ofNatTruncate_of_le n
  || is_uint64_toBitVec_ofNatTruncate_of_le n
  || is_uint64_of_fin n
  || is_except_conds_and_eq_left n
  || is_nat_locally_finite_order_proof_3 n
  || is_nat_locally_finite_order_proof_4 n
  || is_nat_ico_image_const_sub_proof_1_4 n
  || is_nat_ico_image_const_sub_proof_1_3 n
  || is_nat_icc_insert_succ_right_proof_1_3 n
  || is_list_prev_reverse_eq_next_proof_1_1 n
  || is_list_next_eq_get_elem_proof_1 n
  || is_list_next_eq_get_elem n
  || is_list_next_eq_get_elem_proof_1_3 n
  || is_list_next_eq_get_elem_proof_1_4 n
  || is_list_next_eq_get_elem_proof_1_34 n
  || is_list_next_eq_get_elem_proof_1_19 n
  || is_list_next_eq_get_elem_proof_1_36 n
  || is_list_next_get_elem_proof_1_4 n
  || is_list_next_get_elem_proof_1_6 n
  || is_list_next_get_elem n
  || is_list_pmap_next_eq_rotate_one n
  || is_list_pmap_prev_eq_rotate_length_sub_one n
  || is_list_prev_get_elem_proof_1 n
  || is_list_prev_get_elem_proof_1_4 n
  || is_list_prev_get_elem_proof_1_6 n
  || is_list_prev_get_elem n
  || is_list_prev_eq_get_elem_proof_1_2 n
  || is_list_prev_eq_get_elem_proof_1_3 n
  || is_list_prev_eq_get_elem_proof_1_4 n
  || is_list_prev_eq_get_elem_proof_1_7 n
  || is_list_prev_eq_get_elem_pred_proof_1 n
  || is_list_prev_eq_get_elem_proof_1_8 n
  || is_list_prev_eq_get_elem n
  || is_list_prev_reverse_eq_next n
  || is_list_next_reverse_eq_prev n
  || is_list_is_rotated_next_eq n
  || is_list_is_rotated_prev_eq n
  || is_list_next_prev n
  || is_list_prev_next n
  || is_cycle_prev_proof_1 n
  || is_cycle_prev n
  || is_cycle_next_proof_1 n
  || is_cycle_next n
  || is_cycle_prev_reverse_eq_next n
  || is_cycle_next_reverse_eq_prev_simp_1_1 n
  || is_cycle_prev_congr_simp n
  || is_cycle_next_reverse_eq_prev n
  || is_cycle_next_mem n
  || is_cycle_prev_mem n
  || is_cycle_next_prev n
  || is_list_succ_idx_of_mem_drop_last_proof_1_1 n
  || is_nanosecond_offset_of_hours_proof_1 n
  || is_nanosecond_offset_of_minutes_proof_1 n
  || is_millisecond_offset_of_hours_proof_1 n
  || is_week_offset_of_milliseconds_proof_1 n
  || is_week_offset_of_nanoseconds_proof_1 n
  || is_week_offset_to_nanoseconds_proof_1 n
  || is_list_append_cancel_right n
  || is_nat_subtype_succ_le_of_lt_proof_1_3 n
  || is_nat_subtype_succ_le_of_lt_proof_1_4 n
  || is_nat_subtype_le_succ_of_forall_lt_le_proof_1_2 n
  || is_order_iso_subsequence_proof_1_4 n
  || is_order_iso_subsequence_proof_1_5 n
  || is_plain_time_of_nanoseconds_large_bound_proof n
  || is_fin_cast_succ_lt_or_lt_succ_proof_1_2 n
  || is_persistent_hash_map_node_sizeof_1_def n
  || is_lean_info_tree_cases_on_def n
  || is_remove_after_done_action_sparse_cases_on_3_def n
  || is_lean_json_beq_sparse_cases_on_8_def n
  || is_lean_json_beq_sparse_cases_on_3_def n
  || is_lean_json_beq_sparse_cases_on_4_def n
  || is_lean_json_beq_sparse_cases_on_5_def n
  || is_lean_json_beq_sparse_cases_on_6_def n
  || is_lean_json_beq_sparse_cases_on_7_def n
  || is_option_from_json_sparse_cases_on_1_def n
  || is_array_from_json_sparse_cases_on_1_def n
  || is_float_from_json_sparse_cases_on_1_def n
  || is_name_map_from_json_sparse_cases_on_1_def n
  || is_json_structured_from_json_sparse_cases_on_1_def n
  || is_do_code_below_def n

let assemble2_mod_bound_tactic =
  {|
intros w x hb hnot;
apply hnot;
clear x hnot;
unfold LT_lt_inst1, instLTNat in *;
unfold HMul_hMul_inst7, instHMul_inst1, instMulNat in *;
unfold HPow_hPow_inst7, instHPow_inst3, instPowNat_inst1, instNatPowNat in *;
unfold OfNat_ofNat_inst1, instOfNatNat in *;
cbn [lt0 hMul0 mul0 Mul_mul_inst1 hPow0 pow3 pow2 Pow_pow_inst3
     NatPow_pow_inst1 ofNat0] in *;
unfold Nat_lt in *;
pose proof (Nat_mul_pow6_lt_double_pow11_of_lt32 _ hb) as Hbound;
cbn [Nat_double_pow] in Hbound;
repeat first [ exact Hbound | apply Nat_le_double_right ]
|}

let assemble2_valid_char_tactic =
  {|
let prove_ne_uint8 :=
  (vm_compute; intro H; inversion H) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?a ?b =>
    pattern a; eapply (eq_mpr_sprop _ h)
  end in
let rewrite_lean_eq_rev h :=
  lazymatch type of h with
  | Lean.eq ?a ?b =>
    pattern b; eapply (eq_mp_sprop _ h)
  end in
let prove_uint8_ofNat_toNat c Hbound :=
  unfold UInt8_toNat, UInt8_ofNat, UInt8_toBitVec;
  change (Lean.eq
    (BitVec_toNat (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8))
      (BitVec_ofNat (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8)) c))
    c);
  eapply (eq_mpr_sprop (fun n => Lean.eq n c)
    (BitVec_toNat_ofNat c (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8))));
  apply Nat_mod_eq_of_lt;
  exact Hbound in
let prove_mask_bound_direct byte mask Hmask_bound Hupper :=
  (
  let c := constr:(OfNat_ofNat_inst1 UInt8 mask (UInt8_instOfNat mask)) in
  let Hc := fresh "Hc" in
  assert (Hc : Lean.eq (UInt8_toNat c)
    (OfNat_ofNat_inst1 Nat mask (instOfNatNat mask))) by
    (prove_uint8_ofNat_toNat
      (OfNat_ofNat_inst1 Nat mask (instOfNatNat mask)) Hmask_bound);
  rewrite_lean_eq (UInt8_toNat_and byte c);
  rewrite_lean_eq Hc;
  apply Hupper;
  apply Nat_and_le_right) in
let prove_mask_bound byte mask :=
  lazymatch mask with
  | 15 => prove_mask_bound_direct byte 15 Nat_15_lt_pow8 Nat_lt_16_of_le_15
  | 31 => prove_mask_bound_direct byte 31 Nat_31_lt_pow8 Nat_lt_32_of_le_31
  | 63 => prove_mask_bound_direct byte 63 Nat_63_lt_pow8 Nat_lt_64_of_le_63
  | _ =>
    let c := fresh "c" in
    let one := fresh "one" in
    let hne := fresh "hne" in
    let H := fresh "H" in
    pose (c := OfNat_ofNat_inst1 UInt8 mask (UInt8_instOfNat mask));
    pose (one := OfNat_ofNat_inst1 UInt8 1 (UInt8_instOfNat 1));
    assert (hne : Ne UInt8 c (Neg_neg_inst1 UInt8 instNegUInt8 one)) by
      (subst c one; prove_ne_uint8);
    pose proof (Iff_mp _ _
      (UInt8_lt_iff_toNat_lt
        (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
          (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) byte c)
        (HAdd_hAdd_inst7 UInt8 UInt8 UInt8
          (instHAdd_inst1 UInt8 instAddUInt8) c one))
      (UInt8_and_lt_add_one byte c hne)) as H;
    subst c one;
    exact H
  end in
intros w x;
apply Or_inl;
apply Classical_byContradiction;
intro Hnot;
assert (Hw31 : LT_lt_inst1 Nat instLTNat
  (UInt8_toNat
    (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
      (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) w
      (OfNat_ofNat_inst1 UInt8 31 (UInt8_instOfNat 31))))
  (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32))) by
  (prove_mask_bound w 31);
assert (Hx63 : LT_lt_inst1 Nat instLTNat
  (UInt8_toNat
    (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
      (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) x
      (OfNat_ofNat_inst1 UInt8 63 (UInt8_instOfNat 63))))
  (OfNat_ofNat_inst1 Nat 64 (instOfNatNat 64))) by
  (prove_mask_bound x 63);
eapply (_private_Init_Data_String_Decode0_ByteArray_utf8DecodeChar__q_assemble_UU2082___proof_2 w x);
[ exact Hw31
| exact Hx63
| intro Harith;
  apply Hnot;
  unfold ByteArray_utf8DecodeChar__q_assemble_UU2082_Unchecked;
  set (b0 := HAnd_hAnd_inst7 UInt8 UInt8 UInt8
    (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) w
    (OfNat_ofNat_inst1 UInt8 31 (UInt8_instOfNat 31))) in *;
  set (b1 := HAnd_hAnd_inst7 UInt8 UInt8 UInt8
    (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) x
    (OfNat_ofNat_inst1 UInt8 63 (UInt8_instOfNat 63))) in *;
  assert (hb0 : LT_lt_inst1 Nat instLTNat (UInt8_toNat b0)
    (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32))) by
    (subst b0; exact Hw31);
  assert (hb1 : LT_lt_inst1 Nat instLTNat (UInt8_toNat b1)
    (OfNat_ofNat_inst1 Nat 64 (instOfNatNat 64))) by
    (subst b1; exact Hx63);
	  assert (hb1_pow : LT_lt_inst1 Nat instLTNat (UInt8_toNat b1)
	    (HPow_hPow_inst7 Nat Nat Nat
	      (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	      2 6)) by exact hb1;
	  assert (HtoNat6 : Lean.eq
	    (UInt32_toNat (UInt32_ofNat 6))
	    6);
	  [ unfold UInt32_toNat, UInt32_ofNat, UInt32_toBitVec;
	    change (Lean.eq
	      (BitVec_toNat 32 (BitVec_ofNat 32 6))
	      6);
	    eapply (eq_mpr_sprop
	      (fun n => Lean.eq n 6)
	      (BitVec_toNat_ofNat 6 32));
	    apply Nat_mod_eq_of_lt;
	    exact Nat_six_lt_pow32
  | cbn [OfNat_ofNat_inst1 ofNat0 UInt32_instOfNat];
    let sh0 := constr:(HShiftLeft_hShiftLeft_inst7 UInt32 UInt32 UInt32
      (instHShiftLeftOfShiftLeft_inst1 UInt32 instShiftLeftUInt32)
      (UInt8_toUInt32 b0) (UInt32_ofNat 6)) in
    rewrite_lean_eq (UInt32_toNat_or sh0 (UInt8_toUInt32 b1));
    rewrite_lean_eq (UInt32_toNat_shiftLeft (UInt8_toUInt32 b0)
      (UInt32_ofNat 6));
    rewrite_lean_eq (UInt8_toNat_toUInt32 b0);
	    rewrite_lean_eq HtoNat6;
	    rewrite_lean_eq (Nat_mod_eq_of_lt
	      6
	      32
	      Nat_six_lt_32);
	    rewrite_lean_eq (Nat_shiftLeft_eq (UInt8_toNat b0)
	      6);
	    rewrite_lean_eq (Nat_mod_eq_of_lt
	      (HMul_hMul_inst7 Nat Nat Nat (instHMul_inst1 Nat instMulNat)
	        (UInt8_toNat b0)
	        (HPow_hPow_inst7 Nat Nat Nat
	          (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	          2
	          6))
	      (HPow_hPow_inst7 Nat Nat Nat
	        (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	        2
	        32)
	      (Nat_mul_pow6_lt_pow32_of_lt32 (UInt8_toNat b0) hb0));
	    rewrite_lean_eq (Nat_mul_comm (UInt8_toNat b0)
	      (HPow_hPow_inst7 Nat Nat Nat
	        (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	        2
	        6));
	    rewrite_lean_eq (UInt8_toNat_toUInt32 b1);
	    rewrite_lean_eq_rev (Nat_two_pow_add_eq_or_of_lt
	      6
	      (UInt8_toNat b1) hb1_pow (UInt8_toNat b0));
    exact Harith ] ]
|}

let assemble3_mod_bound_tactic =
  {|
intros w x y hb hnot;
apply hnot;
clear x y hnot;
unfold LT_lt_inst1, instLTNat in *;
unfold HMul_hMul_inst7, instHMul_inst1, instMulNat in *;
unfold HPow_hPow_inst7, instHPow_inst3, instPowNat_inst1, instNatPowNat in *;
unfold OfNat_ofNat_inst1, instOfNatNat in *;
cbn [lt0 hMul0 mul0 Mul_mul_inst1 hPow0 pow3 pow2 Pow_pow_inst3
     NatPow_pow_inst1 ofNat0] in *;
unfold Nat_lt in *;
pose proof (Nat_mul_pow12_lt_double_pow16_of_lt16 _ hb) as Hbound;
cbn [Nat_double_pow] in Hbound;
repeat first [ exact Hbound | apply Nat_le_double_right ]
|}

let assemble3_mid_bound_tactic =
  {|
intros w x y hb hnot;
apply hnot;
clear w y hnot;
unfold LT_lt_inst1, instLTNat in *;
unfold HMul_hMul_inst7, instHMul_inst1, instMulNat in *;
unfold HPow_hPow_inst7, instHPow_inst3, instPowNat_inst1, instNatPowNat in *;
unfold OfNat_ofNat_inst1, instOfNatNat in *;
cbn [lt0 hMul0 mul0 Mul_mul_inst1 hPow0 pow3 pow2 Pow_pow_inst3
     NatPow_pow_inst1 ofNat0] in *;
unfold Nat_lt in *;
pose proof (Nat_mul_pow6_lt_double_pow12_of_lt64 _ hb) as Hbound;
cbn [Nat_double_pow] in Hbound;
repeat first [ exact Hbound | apply Nat_le_double_right ]
|}

let assemble3_valid_char_tactic =
  {|
let prove_ne_uint8 :=
  (vm_compute; intro H; inversion H) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?a ?b =>
    pattern a; eapply (eq_mpr_sprop _ h)
  end in
let rewrite_lean_eq_rev h :=
  lazymatch type of h with
  | Lean.eq ?a ?b =>
    pattern b; eapply (eq_mp_sprop _ h)
  end in
let prove_uint8_ofNat_toNat c Hbound :=
  unfold UInt8_toNat, UInt8_ofNat, UInt8_toBitVec;
  change (Lean.eq
    (BitVec_toNat (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8))
      (BitVec_ofNat (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8)) c))
    c);
  eapply (eq_mpr_sprop (fun n => Lean.eq n c)
    (BitVec_toNat_ofNat c (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8))));
  apply Nat_mod_eq_of_lt;
  exact Hbound in
let prove_mask_bound_direct byte mask Hmask_bound Hupper :=
  (
  let c := constr:(OfNat_ofNat_inst1 UInt8 mask (UInt8_instOfNat mask)) in
  let Hc := fresh "Hc" in
  assert (Hc : Lean.eq (UInt8_toNat c)
    (OfNat_ofNat_inst1 Nat mask (instOfNatNat mask))) by
    (prove_uint8_ofNat_toNat
      (OfNat_ofNat_inst1 Nat mask (instOfNatNat mask)) Hmask_bound);
  rewrite_lean_eq (UInt8_toNat_and byte c);
  rewrite_lean_eq Hc;
  apply Hupper;
  apply Nat_and_le_right) in
let prove_mask_bound byte mask :=
  lazymatch mask with
  | 15 => prove_mask_bound_direct byte 15 Nat_15_lt_pow8 Nat_lt_16_of_le_15
  | 31 => prove_mask_bound_direct byte 31 Nat_31_lt_pow8 Nat_lt_32_of_le_31
  | 63 => prove_mask_bound_direct byte 63 Nat_63_lt_pow8 Nat_lt_64_of_le_63
  | _ =>
    let c := fresh "c" in
    let one := fresh "one" in
    let hne := fresh "hne" in
    let H := fresh "H" in
    pose (c := OfNat_ofNat_inst1 UInt8 mask (UInt8_instOfNat mask));
    pose (one := OfNat_ofNat_inst1 UInt8 1 (UInt8_instOfNat 1));
    assert (hne : Ne UInt8 c (Neg_neg_inst1 UInt8 instNegUInt8 one)) by
      (subst c one; prove_ne_uint8);
    pose proof (Iff_mp _ _
      (UInt8_lt_iff_toNat_lt
        (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
          (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) byte c)
        (HAdd_hAdd_inst7 UInt8 UInt8 UInt8
          (instHAdd_inst1 UInt8 instAddUInt8) c one))
      (UInt8_and_lt_add_one byte c hne)) as H;
    subst c one;
    exact H
  end in
let prove_uint32_ofNat_toNat c Hbound :=
  unfold UInt32_toNat, UInt32_ofNat, UInt32_toBitVec;
  change (Lean.eq
    (BitVec_toNat (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32))
      (BitVec_ofNat (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32)) c))
    c);
  eapply (eq_mpr_sprop (fun n => Lean.eq n c)
    (BitVec_toNat_ofNat c (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32))));
  apply Nat_mod_eq_of_lt;
  exact Hbound in
intros w x y hnot_surrogate;
	assert (HtoNat6 : Lean.eq
	  (UInt32_toNat (UInt32_ofNat 6))
	  6) by
	  (prove_uint32_ofNat_toNat 6 Nat_six_lt_pow32);
	assert (HtoNat12 : Lean.eq
	  (UInt32_toNat (UInt32_ofNat 12))
	  12) by
	  (prove_uint32_ofNat_toNat 12 Nat_twelve_lt_pow32);
	assert (HtoNatD800 : Lean.eq
	  (UInt32_toNat
	    (OfNat_ofNat_inst1 UInt32 0xd800 (UInt32_instOfNat 0xd800)))
	  0xd800) by
	  (prove_uint32_ofNat_toNat 0xd800 Nat_0xd800_lt_pow32);
	assert (HtoNatDFFF : Lean.eq
	  (UInt32_toNat
	    (OfNat_ofNat_inst1 UInt32 0xdfff (UInt32_instOfNat 0xdfff)))
	  0xdfff) by
	  (prove_uint32_ofNat_toNat 0xdfff Nat_0xdfff_lt_pow32);
assert (Hw15 : LT_lt_inst1 Nat instLTNat
  (UInt8_toNat
    (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
      (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) w
      (OfNat_ofNat_inst1 UInt8 15 (UInt8_instOfNat 15))))
  (OfNat_ofNat_inst1 Nat 16 (instOfNatNat 16))) by
  (prove_mask_bound w 15);
assert (Hx63 : LT_lt_inst1 Nat instLTNat
  (UInt8_toNat
    (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
      (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) x
      (OfNat_ofNat_inst1 UInt8 63 (UInt8_instOfNat 63))))
  (OfNat_ofNat_inst1 Nat 64 (instOfNatNat 64))) by
  (prove_mask_bound x 63);
assert (Hy63 : LT_lt_inst1 Nat instLTNat
  (UInt8_toNat
    (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
      (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) y
      (OfNat_ofNat_inst1 UInt8 63 (UInt8_instOfNat 63))))
  (OfNat_ofNat_inst1 Nat 64 (instOfNatNat 64))) by
  (prove_mask_bound y 63);
set (z := ByteArray_utf8DecodeChar__q_assemble_UU2083_Unchecked w x y) in *;
assert (HupperUnicode : LT_lt_inst1 Nat instLTNat (UInt32_toNat z)
  Nat_0x110000_double);
[ apply Classical_byContradiction;
  intro Hnot_upper;
  eapply (_private_Init_Data_String_Decode0_ByteArray_utf8DecodeChar__q_assemble_UU2083___proof_6 w x y);
  [ exact Hw15
  | exact Hx63
  | exact Hy63
  | intro Harith;
    apply Hnot_upper;
    subst z;
    unfold ByteArray_utf8DecodeChar__q_assemble_UU2083_Unchecked;
    set (b0 := HAnd_hAnd_inst7 UInt8 UInt8 UInt8
      (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) w
      (OfNat_ofNat_inst1 UInt8 15 (UInt8_instOfNat 15))) in *;
    set (b1 := HAnd_hAnd_inst7 UInt8 UInt8 UInt8
      (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) x
      (OfNat_ofNat_inst1 UInt8 63 (UInt8_instOfNat 63))) in *;
    set (b2 := HAnd_hAnd_inst7 UInt8 UInt8 UInt8
      (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) y
      (OfNat_ofNat_inst1 UInt8 63 (UInt8_instOfNat 63))) in *;
    assert (hb0 : LT_lt_inst1 Nat instLTNat (UInt8_toNat b0)
      (OfNat_ofNat_inst1 Nat 16 (instOfNatNat 16))) by
      (subst b0; exact Hw15);
    assert (hb1 : LT_lt_inst1 Nat instLTNat (UInt8_toNat b1)
      (OfNat_ofNat_inst1 Nat 64 (instOfNatNat 64))) by
      (subst b1; exact Hx63);
    assert (hb2 : LT_lt_inst1 Nat instLTNat (UInt8_toNat b2)
      (OfNat_ofNat_inst1 Nat 64 (instOfNatNat 64))) by
      (subst b2; exact Hy63);
	    assert (hb2_pow : LT_lt_inst1 Nat instLTNat (UInt8_toNat b2)
	      (HPow_hPow_inst7 Nat Nat Nat
	        (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	        2 6)) by exact hb2;
	    assert (Hinner_bound : LT_lt_inst1 Nat instLTNat
	      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
	        (HMul_hMul_inst7 Nat Nat Nat (instHMul_inst1 Nat instMulNat)
	          (HPow_hPow_inst7 Nat Nat Nat
	            (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	            2 6)
	          (UInt8_toNat b1))
	        (UInt8_toNat b2))
	      (HPow_hPow_inst7 Nat Nat Nat
	        (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	        2 12));
    [ apply Classical_byContradiction;
      intro Hnot_inner;
      eapply (_private_Init_Data_String_Decode0_ByteArray_utf8DecodeChar__q_assemble_UU2083___proof_5 w x y);
      [ exact hb1 | exact hb2 | exact Hnot_inner ]
    | cbn [OfNat_ofNat_inst1 ofNat0 UInt32_instOfNat];
      let sh0 := constr:(HShiftLeft_hShiftLeft_inst7 UInt32 UInt32 UInt32
        (instHShiftLeftOfShiftLeft_inst1 UInt32 instShiftLeftUInt32)
        (UInt8_toUInt32 b0) (UInt32_ofNat 12)) in
      let sh1 := constr:(HShiftLeft_hShiftLeft_inst7 UInt32 UInt32 UInt32
        (instHShiftLeftOfShiftLeft_inst1 UInt32 instShiftLeftUInt32)
        (UInt8_toUInt32 b1) (UInt32_ofNat 6)) in
      rewrite_lean_eq (UInt32_toNat_or
        (HOr_hOr_inst7 UInt32 UInt32 UInt32
          (instHOrOfOrOp_inst1 UInt32 instOrOpUInt32) sh0 sh1)
        (UInt8_toUInt32 b2));
      rewrite_lean_eq (UInt32_toNat_or sh0 sh1);
      rewrite_lean_eq (Nat_or_assoc (UInt32_toNat sh0) (UInt32_toNat sh1)
        (UInt32_toNat (UInt8_toUInt32 b2)));
      rewrite_lean_eq (UInt32_toNat_shiftLeft (UInt8_toUInt32 b0)
        (UInt32_ofNat 12));
      rewrite_lean_eq (UInt8_toNat_toUInt32 b0);
	      rewrite_lean_eq HtoNat12;
	      rewrite_lean_eq (Nat_mod_eq_of_lt
	        12
	        32
	        Nat_twelve_lt_32);
	      rewrite_lean_eq (Nat_shiftLeft_eq (UInt8_toNat b0)
	        12);
	      rewrite_lean_eq (Nat_mod_eq_of_lt
	        (HMul_hMul_inst7 Nat Nat Nat (instHMul_inst1 Nat instMulNat)
	          (UInt8_toNat b0)
	          (HPow_hPow_inst7 Nat Nat Nat
	            (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	            2
	            12))
	        (HPow_hPow_inst7 Nat Nat Nat
	          (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	          2
	          32)
	        (Nat_mul_pow12_lt_pow32_of_lt16 (UInt8_toNat b0) hb0));
	      rewrite_lean_eq (Nat_mul_comm (UInt8_toNat b0)
	        (HPow_hPow_inst7 Nat Nat Nat
	          (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	          2
	          12));
      rewrite_lean_eq (UInt32_toNat_shiftLeft (UInt8_toUInt32 b1)
        (UInt32_ofNat 6));
      rewrite_lean_eq (UInt8_toNat_toUInt32 b1);
	      rewrite_lean_eq HtoNat6;
	      rewrite_lean_eq (Nat_mod_eq_of_lt
	        6
	        32
	        Nat_six_lt_32);
	      rewrite_lean_eq (Nat_shiftLeft_eq (UInt8_toNat b1)
	        6);
	      rewrite_lean_eq (Nat_mod_eq_of_lt
	        (HMul_hMul_inst7 Nat Nat Nat (instHMul_inst1 Nat instMulNat)
	          (UInt8_toNat b1)
	          (HPow_hPow_inst7 Nat Nat Nat
	            (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	            2
	            6))
	        (HPow_hPow_inst7 Nat Nat Nat
	          (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	          2
	          32)
	        (Nat_mul_pow6_lt_pow32_of_lt64 (UInt8_toNat b1) hb1));
	      rewrite_lean_eq (Nat_mul_comm (UInt8_toNat b1)
	        (HPow_hPow_inst7 Nat Nat Nat
	          (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	          2
	          6));
	      rewrite_lean_eq (UInt8_toNat_toUInt32 b2);
	      rewrite_lean_eq_rev (Nat_two_pow_add_eq_or_of_lt
	        6
	        (UInt8_toNat b2) hb2_pow (UInt8_toNat b1));
	      rewrite_lean_eq_rev (Nat_two_pow_add_eq_or_of_lt
	        12
	        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
	          (HMul_hMul_inst7 Nat Nat Nat (instHMul_inst1 Nat instMulNat)
	            (HPow_hPow_inst7 Nat Nat Nat
	              (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	              2
	              6)
	            (UInt8_toNat b1))
	          (UInt8_toNat b2))
        Hinner_bound (UInt8_toNat b0));
      exact Harith ] ]
| unfold UInt32_isValidChar;
  apply Classical_byContradiction;
  intro Hnot_valid;
  apply hnot_surrogate;
  apply And_intro;
  [ apply Classical_byContradiction;
    intro Hnot_low;
    apply Hnot_valid;
    apply Or_inl;
    pose proof (Iff_mp _ _ (UInt32_not_le
      (OfNat_ofNat_inst1 UInt32 0xd800 (UInt32_instOfNat 0xd800)) z)
      Hnot_low) as Hlt_low_u32;
    pose proof (Iff_mp _ _ (UInt32_lt_iff_toBitVec_lt z
	      (OfNat_ofNat_inst1 UInt32 0xd800 (UInt32_instOfNat 0xd800)))
	      Hlt_low_u32) as Hlt_low_bv;
	    pose proof (Iff_mp _ _
	      (BitVec_lt_def 32 _ _)
	      Hlt_low_bv) as Hlt_low_nat;
    rewrite_lean_eq HtoNatD800;
    exact Hlt_low_nat
  | apply Classical_byContradiction;
    intro Hnot_high;
    apply Hnot_valid;
    apply Or_inr;
    apply And_intro;
    [ pose proof (Iff_mp _ _ (UInt32_not_le z
        (OfNat_ofNat_inst1 UInt32 0xdfff (UInt32_instOfNat 0xdfff)))
        Hnot_high) as Hlt_high_u32;
      pose proof (Iff_mp _ _ (UInt32_lt_iff_toBitVec_lt
	        (OfNat_ofNat_inst1 UInt32 0xdfff (UInt32_instOfNat 0xdfff)) z)
	        Hlt_high_u32) as Hlt_high_bv;
	      pose proof (Iff_mp _ _
	        (BitVec_lt_def 32 _ _)
	        Hlt_high_bv) as Hlt_high_nat;
      rewrite_lean_eq HtoNatDFFF;
      exact Hlt_high_nat
    | apply Nat_lt_0x110000_of_lt_double_bound;
      exact HupperUnicode ] ] ]
|}

let val_assemble1_le_tactic =
  {|
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?a ?b =>
    pattern a; eapply (eq_mpr_sprop _ h)
  end in
let rewrite_lean_eq_rev h :=
  lazymatch type of h with
  | Lean.eq ?a ?b =>
    pattern b; eapply (eq_mp_sprop _ h)
  end in
let prove_uint8_ofNat_toNat c Hbound :=
  unfold UInt8_toNat, UInt8_ofNat, UInt8_toBitVec;
  change (Lean.eq
    (BitVec_toNat (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8))
      (BitVec_ofNat (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8)) c))
    c);
  eapply (eq_mpr_sprop (fun n => Lean.eq n c)
    (BitVec_toNat_ofNat c (OfNat_ofNat_inst1 Nat 8 (instOfNatNat 8))));
  apply Nat_mod_eq_of_lt;
  exact Hbound in
let prove_uint32_ofNat_toNat c Hbound :=
  unfold UInt32_toNat, UInt32_ofNat, UInt32_toBitVec;
  change (Lean.eq
    (BitVec_toNat (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32))
      (BitVec_ofNat (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32)) c))
    c);
  eapply (eq_mpr_sprop (fun n => Lean.eq n c)
    (BitVec_toNat_ofNat c (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32))));
  apply Nat_mod_eq_of_lt;
  exact Hbound in
intros w h c h';
	assert (HtoNat128 : Lean.eq
	  (UInt8_toNat
	    (OfNat_ofNat_inst1 UInt8 128 (UInt8_instOfNat 128)))
	  128) by
	  (prove_uint8_ofNat_toNat 128 Nat_128_lt_pow8);
	assert (HtoNat127 : Lean.eq
	  (UInt32_toNat
	    (OfNat_ofNat_inst1 UInt32 127 (UInt32_instOfNat 127)))
	  127) by
	  (prove_uint32_ofNat_toNat 127 Nat_127_lt_pow32);
pose proof (Iff_mp _ _
  (UInt8_lt_iff_toNat_lt w
    (OfNat_ofNat_inst1 UInt8 128 (UInt8_instOfNat 128)))
  (_private_Init_Data_String_Decode0_ByteArray_utf8DecodeChar__q_helper_UU2085_
	    w h)) as Hwlt_raw;
	assert (Hwlt : LT_lt_inst1 Nat instLTNat (UInt8_toNat w)
	  128) by
	  (rewrite_lean_eq_rev HtoNat128; exact Hwlt_raw);
apply Classical_byContradiction;
intro Hnot_u32;
eapply (_private_Init_Data_String_Decode0_ByteArray_utf8DecodeChar__q_val_assemble_UU2081__le__proof_1_1 w);
[ exact Hwlt
| intro HleNat;
  apply Hnot_u32;
  eapply (Iff_mpr _ _
    (UInt32_le_iff_toNat_le (Char_val c)
      (OfNat_ofNat_inst1 UInt32 127 (UInt32_instOfNat 127))));
  unfold UInt32_toNat;
  rewrite_lean_eq
    (_private_Init_Data_String_Decode0_ByteArray_utf8DecodeChar__q_toBitVec_val_assemble_UU2081_
      w h c h');
	  rewrite_lean_eq (BitVec_toNat_setWidth
	    8
	    32
	    (UInt8_toBitVec w));
  rewrite_lean_eq (UInt8_toNat_toBitVec w);
  assert (Hmod32 : Lean.eq
    (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
	      (UInt8_toNat w)
	      (HPow_hPow_inst7 Nat Nat Nat
	        (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
	        2
	        32))
	    (UInt8_toNat w)) by
    (apply Nat_mod_eq_of_lt;
     apply Nat_lt_pow32_of_le_127;
     exact HleNat);
	  assert (HtoNat127_bv : Lean.eq
	    (BitVec_toNat 32
	      (UInt32_toBitVec
	        (OfNat_ofNat_inst1 UInt32 127 (UInt32_instOfNat 127))))
	    127) by
    (unfold UInt32_toNat in HtoNat127; exact HtoNat127);
  rewrite_lean_eq Hmod32;
  rewrite_lean_eq HtoNat127_bv;
  exact HleNat ]
|}

let helper3_tactic =
  {|
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?a ?b =>
    pattern a; eapply (eq_mpr_sprop _ h)
	end in
	intros x n hn;
	let one := constr:(1) in
	let two := constr:(2) in
	let eight := constr:(8) in
	let thirtytwo := constr:(32) in
let pow2n := constr:(HPow_hPow_inst7 Nat Nat Nat
  (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
  two n) in
let pow28 := constr:(HPow_hPow_inst7 Nat Nat Nat
  (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
  two eight) in
let pow232 := constr:(HPow_hPow_inst7 Nat Nat Nat
  (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat))
  two thirtytwo) in
let maskNat := constr:(HSub_hSub_inst7 Nat Nat Nat
  (instHSub_inst1 Nat instSubNat) pow2n one) in
let mask8 := constr:(UInt8_ofNat maskNat) in
assert (Hpowlt : LT_lt_inst1 Nat instLTNat pow2n pow28) by
  (exact (Nat_pow_lt_pow_right two n eight Nat_one_lt_two hn));
	assert (Hmasklt : LT_lt_inst1 Nat instLTNat maskNat pow28) by
	  (change (LT_lt_inst1 Nat instLTNat maskNat
	    256);
	   apply Classical_byContradiction;
   intro Hnot;
   eapply (_private_Init_Data_String_Decode0_ByteArray_utf8DecodeChar__q_helper_UU2083___proof_1_1 n);
   [ exact Hpowlt | exact Hnot ]);
assert (Hnle32 : LE_le_inst1 Nat instLENat n thirtytwo) by
  (apply Classical_byContradiction;
   intro Hnot;
   eapply (_private_Init_Data_String_Decode0_ByteArray_utf8DecodeChar__q_helper_UU2083___proof_1_2 n);
   [ exact hn | exact Hnot ]);
eapply (Iff_mpr _ _ (BitVec_toNat_eq thirtytwo _ _));
change (Lean.eq
  (UInt32_toNat
    (UInt8_toUInt32
      (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
        (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) x mask8)))
  (BitVec_toNat thirtytwo
    (BitVec_setWidth n thirtytwo
      (BitVec_setWidth eight n (UInt8_toBitVec x)))));
rewrite_lean_eq (UInt8_toNat_toUInt32
  (HAnd_hAnd_inst7 UInt8 UInt8 UInt8
    (instHAndOfAndOp_inst1 UInt8 instAndOpUInt8) x mask8));
rewrite_lean_eq (UInt8_toNat_and x mask8);
rewrite_lean_eq (UInt8_toNat_ofNat' maskNat);
rewrite_lean_eq (Nat_mod_eq_of_lt maskNat pow28 Hmasklt);
rewrite_lean_eq (Nat_and_two_pow_sub_one_eq_mod (UInt8_toNat x) n);
rewrite_lean_eq (BitVec_toNat_setWidth n thirtytwo
  (BitVec_setWidth eight n (UInt8_toBitVec x)));
rewrite_lean_eq (BitVec_toNat_setWidth eight n (UInt8_toBitVec x));
rewrite_lean_eq (UInt8_toNat_toBitVec x);
rewrite_lean_eq (Nat_mod_mod_of_dvd' (UInt8_toNat x) pow2n pow232
  (Nat_pow_dvd_pow n thirtytwo two Hnle32));
reflexivity
|}

let utf8size_four_proof_1_4_tactic =
  {|
intros c Hle Hnot;
apply Hnot;
apply Nat_le_0xffff_of_le_127;
exact Hle
|}

let utf8size_four_proof_1_5_tactic =
  {|
	intros c Hgt Hle Hnot;
	apply Hnot;
	apply Nat_le_0xffff_of_le_2047;
	exact Hle
	|}

let assemble3_of_toBitVec_proof_1_8_tactic =
  {|
	intros w x y H;
	destruct H as [[Hlo Hhi] Hvalid];
	destruct Hvalid as [Hltlo | Hvalidhi];
	[ unfold LE_le_inst1, instLENat in Hlo;
	  unfold LT_lt_inst1, instLTNat in Hltlo;
	  destruct (Nat_le_lt_false _ _ Hlo Hltlo)
	| destruct Hvalidhi as [Hgtdfff _];
	  unfold LE_le_inst1, instLENat in Hhi;
	  unfold LT_lt_inst1, instLTNat in Hgtdfff;
	  destruct (Nat_le_lt_false _ _ Hhi Hgtdfff) ]
	|}

let assemble4_of_toBitVec_proof_1_8_tactic =
  {|
	intros w x y z H;
	destruct H as [HtooHigh Hvalid];
	destruct Hvalid as [Hltlow | Hvalidhi];
	[ unfold LT_lt_inst1, instLTNat in HtooHigh, Hltlow;
	  destruct (Nat_lt_lt_false_by_nat_succ_le _ _ _
	    Nat_0xd800_le_succ_0x10ffff HtooHigh Hltlow)
	| destruct Hvalidhi as [_ Hltunicode];
	  unfold LT_lt_inst1, instLTNat in HtooHigh, Hltunicode;
	  destruct (Nat_lt_lt_false_by_nat_succ_le _ _ _
	    Nat_0x110000_le_succ_0x10ffff HtooHigh Hltunicode) ]
	|}

let assemble4_iff_proof_1_10_tactic =
  {|
	intros c Hlt Hnot;
	unfold LT_lt_inst1, instLTNat in Hlt;
	apply Hnot;
	unfold LE_le_inst1, instLENat;
	apply Nat_le_0x10000_of_lt_0xffff;
	exact Hlt
	|}

let char_toNat_val_le_proof_1_1_tactic =
  {|
		let solve_bound :=
		  unfold LE_le_inst1, instLENat in *;
	  cbn [le0 Char_val UInt32_toNat toBitVec toFin val Lean.val] in *;
	  first
	    [ eapply Nat_le_0x10ffff_of_lt_0xd800; eassumption
	    | eapply Nat_le_0x10ffff_of_lt_0x110000; eassumption ] in
	intros;
	repeat match goal with
	| H : Or _ _ |- _ =>
	    let H1 := fresh "H" in
	    let H2 := fresh "H" in
	    destruct H as [H1 | H2]
	| H : And _ _ |- _ =>
	    let H1 := fresh "H" in
	    let H2 := fresh "H" in
	    destruct H as [H1 H2]
	end;
	match goal with
	| Hnot : Not ?P |- False =>
	    apply Hnot; solve_bound
		| _ => solve_bound
		end
		|}

let usize_toNat_ofNat_of_lt_32_tactic =
  {|
	intros n h;
	eapply USize_toNat_ofNat_of_lt';
	try unfold LT_lt_inst1, instLTNat in h;
	try cbn [lt0] in h;
	try unfold Nat_lt in h;
	exact (USize_lt_size_of_lt_32_literal n h)
	|}

let uint32_toNat_shiftLeft_tactic =
  {|
		intros a b;
	unfold UInt32_toNat, UInt32_shiftLeft;
set (w := OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32)) in *;
unfold UInt32_toBitVec;
cbn [toBitVec];
unfold UInt32_mod;
unfold UInt32_toBitVec;
cbn [toBitVec];
unfold HShiftLeft_hShiftLeft_inst7, BitVec_instHShiftLeft;
cbn [hShiftLeft0];
unfold BitVec_shiftLeft;
unfold BitVec_ofNat;
unfold BitVec_toNat, BitVec_toFin, Fin_val;
cbn [toFin val Lean.val];
unfold Fin_Internal_ofNat;
cbn [Lean.val];
unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod;
unfold HShiftLeft_hShiftLeft_inst7, instHShiftLeftOfShiftLeft_inst1, Nat_instShiftLeft;
unfold HPow_hPow_inst7, instHPow_inst3, instPowNat_inst1, instNatPowNat;
cbn
  [hMod0 hShiftLeft0 hPow0 Mod_mod_inst1 ShiftLeft_shiftLeft_inst1
   Pow_pow_inst3 NatPow_pow_inst1];
unfold Mod_mod_inst1, ShiftLeft_shiftLeft_inst1, Pow_pow_inst3, NatPow_pow_inst1;
cbn [mod0 shiftLeft0 pow3 pow2];
unfold BitVec_instMod;
cbn [mod0 Mod_mod_inst1];
unfold BitVec_umod;
unfold BitVec_toNat, BitVec_ofNatLT, BitVec_toFin, Fin_val;
cbn [toFin val];
cbn [Lean.val];
unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod, Mod_mod_inst1;
cbn [hMod0 mod0];
assert
  (H32 :
    Lean.val _ (toFin _ (OfNat_ofNat_inst1 (BitVec w) 32 (BitVec_instOfNat w 32))) =
    32);
[ change
    (BitVec_toNat w (OfNat_ofNat_inst1 (BitVec w) 32 (BitVec_instOfNat w 32)) =
     32);
  reflexivity
| subst w; reflexivity ]
|}

let uint64_toNat_shiftLeft_tactic =
  {|
	intros a b;
	unfold UInt64_toNat, UInt64_shiftLeft;
set (w := OfNat_ofNat_inst1 Nat 64 (instOfNatNat 64)) in *;
unfold UInt64_toBitVec;
cbn [toBitVec64];
unfold UInt64_mod;
unfold UInt64_toBitVec;
cbn [toBitVec64];
unfold HShiftLeft_hShiftLeft_inst7, BitVec_instHShiftLeft;
cbn [hShiftLeft0];
unfold BitVec_shiftLeft;
unfold BitVec_ofNat;
unfold BitVec_toNat, BitVec_toFin, Fin_val;
cbn [toFin val Lean.val];
unfold Fin_Internal_ofNat;
cbn [Lean.val];
unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod;
unfold HShiftLeft_hShiftLeft_inst7, instHShiftLeftOfShiftLeft_inst1, Nat_instShiftLeft;
unfold HPow_hPow_inst7, instHPow_inst3, instPowNat_inst1, instNatPowNat;
cbn
  [hMod0 hShiftLeft0 hPow0 Mod_mod_inst1 ShiftLeft_shiftLeft_inst1
   Pow_pow_inst3 NatPow_pow_inst1];
unfold Mod_mod_inst1, ShiftLeft_shiftLeft_inst1, Pow_pow_inst3, NatPow_pow_inst1;
cbn [mod0 shiftLeft0 pow3 pow2];
unfold BitVec_instMod;
cbn [mod0 Mod_mod_inst1];
unfold BitVec_umod;
unfold BitVec_toNat, BitVec_ofNatLT, BitVec_toFin, Fin_val;
cbn [toFin val];
cbn [Lean.val];
unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod, Mod_mod_inst1;
cbn [hMod0 mod0];
assert
  (H64 :
    Lean.val _ (toFin _ (OfNat_ofNat_inst1 (BitVec w) 64 (BitVec_instOfNat w 64))) =
    64);
[ change
    (BitVec_toNat w (OfNat_ofNat_inst1 (BitVec w) 64 (BitVec_instOfNat w 64)) =
     64);
  reflexivity
| subst w; reflexivity ]
|}

let uint32_toUInt64_proof_1_tactic =
  {|exact Nat_pow32_lt_pow64|}

let usize_size_pos_tactic =
  {|exact USize_size_pos|}

let int64_toInt_minValue_tactic =
  {|
assert
  (Hrhs :
    Neg_neg_inst1 Int Int_instNegInt
      (HPow_hPow_inst7 Int Nat Int
        (instHPow_inst3 Int Nat (instPowNat_inst1 Int Int_instNatPow))
        (OfNat_ofNat_inst1 Int 2 (instOfNat 2)) 63) =
    Int_negOfNat (Nat_pow 2 (Nat_of_nat 63%nat)))
  by reflexivity;
rewrite Hrhs;
rewrite Nat_pow_two_eq_pow2_63_literal;
assert
  (Hmin : Int64_minValue =
    Int64_neg (Int64_ofNat Nat_pow2_63_literal));
[ unfold Int64_minValue, Neg_neg_inst1, OfNat_ofNat_inst1,
    Int64_instNeg, Int64_instOfNat;
  reflexivity
| rewrite Hmin ];
assert
  (Hmod : forall a b : Nat, (a < b)%Nat -> Nat_mod a b = a);
[ intros a b h;
  destruct a as [|a];
  [ reflexivity
  | unfold Nat_mod, Nat_mod_match_1, Nat_casesOn;
    cbn;
    destruct (Nat_decLe b (Nat_succ a)) as [hnle | hle];
    [ reflexivity
    | pose proof
        (@Nat_lt_of_lt_of_le (Nat_succ a) b (Nat_succ a) h hle) as hc;
      exact (False_elim _ (Nat_lt_irrefl (Nat_succ a) hc)) ] ]
| ];
assert
  (Hpredmap : forall a : Nat,
    nat_of_Nat (Nat_pred a) = PeanoNat.Nat.pred (nat_of_Nat a));
[ intros a; destruct a; reflexivity
| ];
assert (Hnatinj : forall a b : Nat,
  nat_of_Nat a = nat_of_Nat b -> a = b);
[ intros a b h;
  rewrite <- (Nat2natid a), <- (Nat2natid b);
  f_equal; exact h
| ];
assert (Hsub0 : forall a : Nat, Nat_sub a Nat_zero = a);
[ intros a; reflexivity
| ];
assert (HsubS : forall a b : Nat,
  Nat_sub a (Nat_succ b) = Nat_pred (Nat_sub a b));
[ intros a b; reflexivity
| ];
assert
  (Hsubmap : forall a b : Nat,
    nat_of_Nat (Nat_sub a b) =
    PeanoNat.Nat.sub (nat_of_Nat a) (nat_of_Nat b));
[ intros a b; revert a;
  induction b as [|b IH]; intros a;
  [ rewrite Hsub0;
    rewrite PeanoNat.Nat.sub_0_r;
    reflexivity
  | rewrite HsubS;
    cbn [nat_of_Nat];
    rewrite PeanoNat.Nat.sub_succ_r;
    rewrite Hpredmap, IH;
    reflexivity ]
| ];
assert
  (Hlt : (Nat_pow2_63_literal < Nat_pow 2 Nat_64_literal)%Nat);
[ unfold Nat_pow2_63_literal;
  unfold Nat_64_literal;
  rewrite (Nat_pow_two_eq_double_pow_nat 64%nat);
  exact (Nat_double_pow_lt_add_succ 63%nat 0%nat)
| ];
assert
  (Hsub : Nat_sub (Nat_pow 2 Nat_64_literal)
    Nat_pow2_63_literal = Nat_pow2_63_literal);
[ apply Hnatinj;
  rewrite Hsubmap, nat_of_Nat_pow;
  unfold Nat_64_literal;
  unfold Nat_pow2_63_literal;
  rewrite !nat_of_Nat_double_pow;
  cbn [nat_of_Nat Nat_of_nat];
  change
    (PeanoNat.Nat.sub (PeanoNat.Nat.pow 2 (S 63))
      (PeanoNat.Nat.pow 2 63) = PeanoNat.Nat.pow 2 63);
  rewrite PeanoNat.Nat.pow_succ_r';
  rewrite PeanoNat.Nat.mul_succ_l, PeanoNat.Nat.mul_1_l;
  rewrite PeanoNat.Nat.add_sub;
  reflexivity
| ];
assert
  (Htwo : Nat_mul 2 Nat_pow2_63_literal =
    Nat_pow 2 Nat_64_literal);
[ rewrite Nat_two_mul_eq_double;
  unfold Nat_pow2_63_literal;
  unfold Nat_64_literal;
  rewrite (Nat_pow_two_eq_double_pow_nat 64%nat);
  exact (Nat_double_pow_succ 63%nat)
| ];
assert
  (HtoNatOfNat : forall n a : Nat,
    (a < Nat_pow 2 n)%Nat ->
    BitVec_toNat n (BitVec_ofNat n a) = a);
[ intros n a h;
  unfold BitVec_toNat, BitVec_ofNat, BitVec_toFin, Fin_val;
  cbn [toFin val];
  unfold Fin_Internal_ofNat;
  cbn [val];
  unfold HPow_hPow_inst7, instHPow_inst3, instPowNat_inst1,
    instNatPowNat;
  cbn [hPow0 Pow_pow_inst3 NatPow_pow_inst1 pow3 pow2];
  unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod, Mod_mod_inst1;
  cbn [hMod0 mod0];
  apply Hmod; exact h
| ];
assert
  (Hneg : BitVec_toNat Nat_64_literal
    (BitVec_neg Nat_64_literal
      (BitVec_ofNat Nat_64_literal Nat_pow2_63_literal)) =
    Nat_pow2_63_literal);
[ unfold BitVec_neg;
  unfold HSub_hSub_inst7, instHSub_inst1, instSubNat, Sub_sub_inst1;
  cbn [hSub0 sub0];
  unfold HPow_hPow_inst7, instHPow_inst3, instPowNat_inst1,
    instNatPowNat;
  cbn [hPow0 Pow_pow_inst3 NatPow_pow_inst1 pow3 pow2];
  rewrite (HtoNatOfNat _ _ Hlt);
  rewrite Hsub;
  apply HtoNatOfNat; exact Hlt
| ];
assert (HsubZero : forall q : Nat, Nat_sub Nat_zero q = Nat_zero);
[ intros q; induction q as [|q IH];
  [ rewrite Hsub0; reflexivity
  | rewrite HsubS, IH; reflexivity ]
| ];
assert
  (HsubNatNeg : forall p q : Nat,
    Nat_sub q p = p -> Int_subNatNat p q = Int_negOfNat p);
[ intros p q h; destruct p as [|p];
  [ rewrite Hsub0 in h;
    rewrite h;
    reflexivity
  | unfold Int_subNatNat, Int_negOfNat;
    unfold HSub_hSub_inst7, instHSub_inst1, instSubNat, Sub_sub_inst1;
    cbn [hSub0 sub0];
    rewrite h;
    unfold Int_negOfNat_match_1, Nat_casesOn;
    cbn;
    reflexivity ]
| ];
assert
  (HIntSubOfNat : forall p q : Nat,
    HSub_hSub_inst7 Int Int Int (instHSub_inst1 Int Int_instSub)
      (Nat_cast_inst1 Int instNatCastInt p)
      (Nat_cast_inst1 Int instNatCastInt q) =
    Int_subNatNat p q);
[ intros p q;
  change (Int_sub (Int_ofNat p) (Int_ofNat q) = Int_subNatNat p q);
  destruct q as [|q];
  [ unfold Int_subNatNat;
    unfold HSub_hSub_inst7, instHSub_inst1, instSubNat, Sub_sub_inst1;
    cbn [hSub0 sub0];
    rewrite (HsubZero p);
    reflexivity
  | reflexivity ]
| ];
assert
  (HIntSub :
    HSub_hSub_inst7 Int Int Int (instHSub_inst1 Int Int_instSub)
      (Nat_cast_inst1 Int instNatCastInt Nat_pow2_63_literal)
      (Nat_cast_inst1 Int instNatCastInt (Nat_pow 2 Nat_64_literal)) =
    Int_negOfNat Nat_pow2_63_literal);
[ rewrite HIntSubOfNat;
  apply HsubNatNeg;
  exact Hsub
| ];
unfold Int64_toInt, Int64_neg, Int64_ofNat, Int64_toBitVec,
  Int64_toUInt64, UInt64_toBitVec;
unfold Neg_neg_inst1, BitVec_instNeg;
cbn [neg0 toBitVec64 toUInt64];
unfold BitVec_toInt;
rewrite Hneg;
unfold LT_lt_inst1, instLTNat;
unfold HMul_hMul_inst7, instHMul_inst1, instMulNat;
unfold HPow_hPow_inst7, instHPow_inst3, instPowNat_inst1,
  instNatPowNat;
cbn [lt0 hMul0 mul0 Mul_mul_inst1 hPow0 pow3 pow2
  Pow_pow_inst3 NatPow_pow_inst1];
rewrite Htwo;
destruct
  (Nat_decLt (Nat_pow 2 Nat_64_literal)
    (Nat_pow 2 Nat_64_literal)) as [hnlt | hlt];
[ unfold ite, Decidable_casesOn;
  unfold LT_lt_inst1, instLTNat;
  cbn [lt0];
  unfold Decidable_recl;
  exact (lean_eq_of_logic_eq HIntSub)
| destruct (Nat_lt_irrefl _ hlt) ]
|}

let uint32_not_neg_one_tactic =
  {|
unfold Complement_complement_inst1, instComplementUInt32,
  Neg_neg_inst1, instNegUInt32,
  OfNat_ofNat_inst1, UInt32_instOfNat;
cbn [complement0 neg0 ofNat0];
unfold UInt32_complement, UInt32_neg, UInt32_ofNat;
apply UInt32_eq_of_toBitVec_eq;
unfold UInt32_toBitVec;
cbn [toBitVec];
unfold Complement_complement_inst1, BitVec_instComplement,
  Neg_neg_inst1, BitVec_instNeg;
cbn [complement0 neg0];
set (p := HPow_hPow_inst7 Nat Nat Nat
  (instHPow_inst3 Nat Nat (instPowNat_inst1 Nat instNatPowNat)) 2 32) in *;
assert (Hsix_lt : (6 < p)%Nat);
[ subst p; exact Nat_six_lt_pow32
| ];
assert (Hpow_ne : Ne Nat p 0);
[ intro H;
  pose proof (eq_mp_sprop (fun n => (7 <= n)%Nat) H Hsix_lt) as Hbad;
  inversion Hbad
| ];
assert (Hone_lt : (1 < p)%Nat);
[
  eapply Nat_le_trans;
  [ repeat constructor
  | exact Hsix_lt ]
| ];
assert (Hneg : Lean.eq
  (BitVec_neg 32 (BitVec_ofNat 32 1))
  (BitVec_allOnes 32));
[ apply BitVec_eq_of_toNat_eq;
  unfold BitVec_neg;
  fold p;
  pose proof (BitVec_toNat_ofNat 1 32) as HtoNatOne;
  fold p in HtoNatOne;
  unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod,
    Mod_mod_inst1 in HtoNatOne;
  cbn [hMod0 mod0] in HtoNatOne;
  pose proof (@Nat_mod_eq_of_lt 1 p Hone_lt) as HmodOne;
  unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod,
    Mod_mod_inst1 in HmodOne;
  cbn [hMod0 mod0] in HmodOne;
  pose proof (Eq_trans Nat _ _ _ HtoNatOne HmodOne) as Hone;
  pose proof (congrArg Nat Nat _ _
    (fun z => BitVec_toNat 32
      (BitVec_ofNat 32
        (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
          p z))) Hone) as HoneCongr;
  pose proof (BitVec_toNat_ofNat
    (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
      p 1) 32) as HtoNatSub;
  fold p in HtoNatSub;
  unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod,
    Mod_mod_inst1 in HtoNatSub;
  cbn [hMod0 mod0] in HtoNatSub;
  pose proof (@Nat_mod_eq_of_lt
    (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat) p 1) p
    (@Nat_sub_one_lt p Hpow_ne)) as HmodSub;
  unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod,
    Mod_mod_inst1 in HmodSub;
  cbn [hMod0 mod0] in HmodSub;
  exact (Eq_trans Nat _ _ _ HoneCongr
    (Eq_trans Nat _ _ _ HtoNatSub
      (Eq_trans Nat _ _ _ HmodSub
        (Eq_symm Nat _ _ (@BitVec_toNat_allOnes 32)))))
| ];
pose proof (congrArg (BitVec 32) (BitVec 32) _ _
  (fun z => BitVec_not 32 z) Hneg) as HnotCongr;
assert (HnotZero : Lean.eq
  (BitVec_not 32 (BitVec_allOnes 32))
  (BitVec_ofNat 32 0));
[ unfold BitVec_not, BitVec_xor;
assert (HboolXorSelf : forall b : Bool, Lean.eq (Bool_xor b b) Bool_false);
[ intros [|]; reflexivity
| ];
assert (Hxor : forall x : Nat, Lean.eq (Nat_xor x x) 0);
[ intro x;
  apply Nat_eq_of_testBit_eq;
  intro i;
  pose proof (Nat_testBit_xor x x i) as HtestXor;
  unfold HXor_hXor_inst7, instHXorOfXorOp_inst1,
    Nat_instXorOp in HtestXor;
  cbn in HtestXor;
  pose proof (HboolXorSelf (Nat_testBit x i)) as Hbool;
  pose proof (Eq_symm Bool _ _ (Nat_zero_testBit i)) as Hzero;
  pose proof (Eq_trans Bool _ _ _ Hbool Hzero) as Hbit;
  exact (Eq_trans Bool _ _ _ HtestXor Hbit)
| ];
unfold HXor_hXor_inst7, instHXorOfXorOp_inst1,
  BitVec_instXorOp;
cbn;
unfold BitVec_xor;
lazymatch goal with
| |- Lean.eq ?l ?r => apply (@BitVec_eq_of_toNat_eq 32 l r)
end;
lazymatch goal with
| |- Lean.eq
    (BitVec_toNat 32 (BitVec_ofNatLT 32 ?x ?hx))
    (BitVec_toNat 32 (BitVec_ofNat 32 0)) =>
  pose proof (@BitVec_toNat_ofNatLT 32 x hx) as Hleft;
  assert (Hxzero : Lean.eq x 0);
  [ change (Lean.eq
      (Nat_xor
        (BitVec_toNat 32 (BitVec_allOnes 32))
        (BitVec_toNat 32 (BitVec_allOnes 32))) 0);
    exact (Hxor (BitVec_toNat 32 (BitVec_allOnes 32)))
  | ];
  pose proof (BitVec_toNat_ofNat 0 32) as Hright;
  fold p in Hright;
  unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod,
    Mod_mod_inst1 in Hright;
  cbn [hMod0 mod0] in Hright;
  pose proof (Nat_zero_mod p) as HzeroMod;
  unfold HMod_hMod_inst7, instHMod_inst1, Nat_instMod,
    Mod_mod_inst1 in HzeroMod;
  cbn [hMod0 mod0] in HzeroMod;
  pose proof (Eq_trans Nat _ _ _ Hright HzeroMod) as HrightZero;
  exact (Eq_trans Nat _ _ _ Hleft
    (Eq_trans Nat _ _ _ Hxzero
      (Eq_symm Nat _ _ HrightZero)))
end
| ];
exact (Eq_trans (BitVec 32) _ _ _ HnotCongr HnotZero)
|}

let sqrt_iter_sq_le_proof_1_1_tactic =
  {|
intros n guess h;
assert (Hiter : Lean.eq (Nat_sqrt_iter n guess) guess);
[ refine
    (Eq_trans Nat _ _ _ (Nat_sqrt_iter_eq_def n guess) _);
  apply lean_eq_of_logic_eq;
  destruct
    (Nat_decLt
      (HDiv_hDiv_inst7 Nat Nat Nat (instHDiv_inst1 Nat Nat_instDiv)
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
          guess
          (HDiv_hDiv_inst7 Nat Nat Nat (instHDiv_inst1 Nat Nat_instDiv)
            n guess))
        2)
      guess) as [hnlt | hlt] eqn:Hdec;
  [ unfold dite, Decidable_casesOn;
    rewrite Hdec;
    unfold LT_lt_inst1, instLTNat;
    cbn [lt0];
    unfold Decidable_recl;
    reflexivity
  | destruct (h hlt) ]
| pose proof
    (Eq_trans Nat _ _ _
      (Eq_symm Nat _ _ (Nat_sqrt_iter_eq_def n guess)) Hiter) as Hbody;
  assert
    (Harith :
      LE_le_inst1 Nat instLENat guess
        (HDiv_hDiv_inst7 Nat Nat Nat (instHDiv_inst1 Nat Nat_instDiv)
          n guess));
  [ apply Nat_le_of_not_gt;
    intros hq;
    apply h;
    apply
      (Iff_mpr _ _
        (Nat_div_lt_iff_lt_mul 2 _ guess (Nat_zero_lt_succ 1)));
    exact
      (Eq_mpr_inst1 _ _
        (congrArg Nat SProp
          (HMul_hMul_inst7 Nat Nat Nat (instHMul_inst1 Nat instMulNat)
            guess 2)
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
            guess guess)
          (fun rhs : Nat =>
            LT_lt_inst1 Nat instLTNat
              (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
                guess
                (HDiv_hDiv_inst7 Nat Nat Nat
                  (instHDiv_inst1 Nat Nat_instDiv) n guess))
              rhs)
          (lean_eq_of_logic_eq (Nat_mul_two_eq_add_self guess)))
        (Nat_add_lt_add_left _ _ hq guess))
  | exact
      (Eq_mpr_inst1 _ _
        (congrArg Nat SProp
          _ guess
          (fun x : Nat =>
            LE_le_inst1 Nat instLENat x
              (HDiv_hDiv_inst7 Nat Nat Nat
                (instHDiv_inst1 Nat Nat_instDiv) n x))
          Hbody)
        Harith) ] ]
|}

let sqrt_isSqrt_proof_1_6_tactic =
  {|
intros n;
apply Nat_div_add_mod'
|}

let sqrt_isSqrt_proof_1_7_tactic =
  {|
intros n;
apply Nat_pow_le_pow_right;
[ exact (Nat_zero_lt_succ 1)
| apply Nat_succ_le_of_lt;
  let k :=
    constr:(Nat_log2
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n 2)) in
  let q :=
    constr:(HDiv_hDiv_inst7 Nat Nat Nat (instHDiv_inst1 Nat Nat_instDiv)
      k 2) in
  let r :=
    constr:(HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
      k 2) in
  pose proof
    (Nat_mod_lt k 2 (Nat_zero_lt_succ 1)) as Hmod;
  pose proof
    (Nat_add_lt_add_left r 2 Hmod (Nat_mul q 2)) as Hlt0;
  pose proof
    (Eq_mpr_inst1 _ _
      (congrArg Nat SProp
        k (Nat_add (Nat_mul q 2) r)
        (fun lhs : Nat =>
          LT_lt_inst1 Nat instLTNat lhs (Nat_add (Nat_mul q 2) 2))
        (Eq_symm Nat _ _ (Nat_div_add_mod' k 2)))
      Hlt0) as Hlt;
  pose proof
    (congrArg Nat Nat
      (Nat_mul q 2) (Nat_add q q)
      (fun x : Nat => Nat_add x 2)
      (Nat_mul_two q)) as Hmul;
  pose proof
    (Eq_trans Nat
      (Nat_add (Nat_add q 1) (Nat_add q 1))
      (Nat_add q (Nat_add 1 (Nat_add q 1)))
      (Nat_add q (Nat_add q 2))
      (Nat_add_assoc q 1 (Nat_add q 1))
      (congrArg Nat Nat
        (Nat_add 1 (Nat_add q 1)) (Nat_add q 2)
        (fun x : Nat => Nat_add q x)
        (Nat_add_left_comm 1 q 1))) as Hshuffle1;
  pose proof
    (Eq_trans Nat
      (Nat_add (Nat_add q 1) (Nat_add q 1))
      (Nat_add q (Nat_add q 2))
      (Nat_add (Nat_add q q) 2)
      Hshuffle1
      (Eq_symm Nat _ _ (Nat_add_assoc q q 2))) as Hshuffle;
  pose proof
    (Eq_trans Nat
      (Nat_add (Nat_mul q 2) 2)
      (Nat_add (Nat_add q q) 2)
      (Nat_add (Nat_add q 1) (Nat_add q 1))
      Hmul
      (Eq_symm Nat _ _ Hshuffle)) as Heq;
  exact
    (Eq_mpr_inst1 _ _
      (congrArg Nat SProp
        (Nat_add (Nat_add q 1) (Nat_add q 1))
        (Nat_add (Nat_mul q 2) 2)
        (fun rhs : Nat => LT_lt_inst1 Nat instLTNat k rhs)
        (Eq_symm Nat _ _ Heq))
      Hlt) ]
|}

let sqrt_add_eq_proof_1_1_tactic =
  {|
intros a n h;
let m := constr:(Nat_add (Nat_mul n n) (Nat_add n n)) in
pose proof
  (Nat_add_le_add_left a (Nat_add n n) h (Nat_mul n n)) as Hle;
pose proof
  (Eq_trans Nat
    (Nat_mul (Nat_succ n) (Nat_succ n))
    (Nat_add (Nat_mul n (Nat_succ n)) (Nat_succ n))
    (Nat_add (Nat_add (Nat_mul n n) n) (Nat_succ n))
    (Nat_succ_mul n (Nat_succ n))
    (congrArg Nat Nat
      (Nat_mul n (Nat_succ n)) (Nat_add (Nat_mul n n) n)
      (fun x : Nat => Nat_add x (Nat_succ n))
      (Nat_mul_succ n n))) as Hexpand1;
pose proof
  (Eq_trans Nat
    (Nat_mul (Nat_succ n) (Nat_succ n))
    (Nat_add (Nat_add (Nat_mul n n) n) (Nat_succ n))
    (Nat_succ m)
    Hexpand1
    (congrArg Nat Nat
      (Nat_add (Nat_add (Nat_mul n n) n) n) m
      Nat_succ
      (Nat_add_assoc (Nat_mul n n) n n))) as Hexpand;
pose proof
  (Eq_mpr_inst1 _ _
    (congrArg Nat SProp
      (Nat_mul (Nat_succ n) (Nat_succ n)) (Nat_succ m)
      (fun rhs : Nat => LT_lt_inst1 Nat instLTNat m rhs)
      Hexpand)
    (Nat_lt_succ_self m)) as Hlt;
exact (Nat_lt_of_le_of_lt _ _ _ Hle Hlt)
|}

let sqrt_add_eq_proof_1_2_tactic =
  {|
intros a n;
exact
  (Nat_add_le_add_left 0 a (Nat_zero_le a) (Nat_mul n n))
|}

let le_three_of_sqrt_eq_one_proof_1_1_tactic =
  {|
intros n h;
exact
  (Eq_mpr_inst1 _ _
    (congrArg Nat SProp
      (Nat_sqrt n) 1
      (fun lhs : Nat => LT_lt_inst1 Nat instLTNat lhs 2)
      h)
    (Nat_lt_succ_self 1))
|}

let sqrt_lt_self_proof_1_1_tactic =
  {|
intros n h;
exact
  (Eq_mpr_inst1 _ _
    (congrArg Nat SProp
      n (Nat_mul n 1)
      (fun lhs : Nat => LT_lt_inst1 Nat instLTNat lhs (Nat_mul n n))
      (Eq_symm Nat _ _ (Nat_mul_one n)))
    h)
|}

let sqrt_succ_le_succ_sqrt_proof_1_1_tactic =
  {|
intros n h;
let s := constr:(Nat_sqrt n) in
let m := constr:(Nat_add (Nat_add (Nat_mul s s) s) s) in
pose proof (Nat_succ_le_succ _ _ h) as Hsucc;
pose proof
  (Eq_trans Nat
    (Nat_mul (Nat_succ s) (Nat_succ s))
    (Nat_add (Nat_mul s (Nat_succ s)) (Nat_succ s))
    (Nat_succ m)
    (Nat_succ_mul s (Nat_succ s))
    (congrArg Nat Nat
      (Nat_mul s (Nat_succ s)) (Nat_add (Nat_mul s s) s)
      (fun x : Nat => Nat_add x (Nat_succ s))
      (Nat_mul_succ s s))) as Hsquare;
pose proof
  (Eq_mpr_inst1 _ _
    (congrArg Nat SProp
      (Nat_mul (Nat_succ s) (Nat_succ s)) (Nat_succ m)
      (fun rhs : Nat => LE_le_inst1 Nat instLENat (Nat_succ n) rhs)
      Hsquare)
    Hsucc) as Hle;
pose proof
  (Nat_mul_self_lt_mul_self
    (Nat_succ s) (Nat_succ (Nat_succ s))
    (Nat_lt_succ_self (Nat_succ s))) as Hlt;
exact (Nat_lt_of_le_of_lt _ _ _ Hle Hlt)
|}

let except_conds_and_eq_left_tactic post_shape_indl =
  {|
intro ps;
induction ps as
  [| sigma ps0 rocqLeanImportExceptCondsIH
   | eps ps0 rocqLeanImportExceptCondsIH]
  using |}
  ^ post_shape_indl
  ^ {|;
intros p q h;
[ destruct p; destruct q; reflexivity
| apply rocqLeanImportExceptCondsIH; assumption
| destruct p as [pf pt];
  destruct q as [qf qt];
  cbn in h |-;
  destruct h as [hf ht];
  apply Prod_ext;
  [ apply funext; intro e;
    apply Std_Do_SPred_bientails_to_eq;
    apply (Iff_mp _ _ (Std_Do_SPred_and_eq_left _ _ _) (hf e))
  | apply rocqLeanImportExceptCondsIH; assumption ] ]
|}

let nat_locally_finite_order_tactic goal =
  "intros a b x;\nchange ("
  ^ goal
  ^ {|
);
assert (Hpredmap : forall a : Nat,
  nat_of_Nat (Nat_pred a) = PeanoNat.Nat.pred (nat_of_Nat a));
[ intros n; destruct n; reflexivity
| ];
assert (Hsub0 : forall a : Nat, Nat_sub a Nat_zero = a);
[ intros n; reflexivity
| ];
assert (HsubS : forall a b : Nat,
  Nat_sub a (Nat_succ b) = Nat_pred (Nat_sub a b));
[ intros m n; reflexivity
| ];
assert (Hsubmap : forall a b : Nat,
  nat_of_Nat (Nat_sub a b) =
    PeanoNat.Nat.sub (nat_of_Nat a) (nat_of_Nat b));
[ intros m n; revert m;
  induction n as [|n IH]; intros m;
  [ rewrite Hsub0, PeanoNat.Nat.sub_0_r; reflexivity
  | rewrite HsubS; cbn [nat_of_Nat];
    rewrite PeanoNat.Nat.sub_succ_r, Hpredmap, IH; reflexivity ]
| ];
let finish H1 H2 :=
  apply nat_le_Nat_le;
  apply Nat_le_nat_le' in H1;
  apply Nat_le_nat_le' in H2;
  repeat rewrite nat_of_Nat_add in H1;
  repeat rewrite nat_of_Nat_add in H2;
  repeat rewrite nat_of_Nat_add;
  repeat rewrite Hsubmap in H1;
  repeat rewrite Hsubmap in H2;
  repeat rewrite Hsubmap;
  repeat rewrite rocq_nat_of_Nat_succ in H1;
  repeat rewrite rocq_nat_of_Nat_succ in H2;
  repeat rewrite rocq_nat_of_Nat_succ;
  repeat rewrite rocq_nat_of_Nat_zero in H1;
  repeat rewrite rocq_nat_of_Nat_zero in H2;
  repeat rewrite rocq_nat_of_Nat_zero;
  lia
in
constructor;
[ intros [H1 H2]; split; finish H1 H2
| intros [H1 H2]; split; finish H1 H2 ]
|}

let nat_locally_finite_order_proof_3_tactic =
  nat_locally_finite_order_tactic
    {|
Iff
  (And (Nat_le (Nat_add a (Nat_succ Nat_zero)) x)
    (Nat_le (Nat_succ x)
      (Nat_add (Nat_add a (Nat_succ Nat_zero)) (Nat_sub b a))))
  (And (Nat_le (Nat_succ a) x) (Nat_le x b))
|}

let nat_locally_finite_order_proof_4_tactic =
  nat_locally_finite_order_tactic
    {|
Iff
  (And (Nat_le (Nat_add a (Nat_succ Nat_zero)) x)
    (Nat_le (Nat_succ x)
      (Nat_add (Nat_add a (Nat_succ Nat_zero))
        (Nat_sub (Nat_sub b a) (Nat_succ Nat_zero)))))
  (And (Nat_le (Nat_succ a) x) (Nat_le (Nat_succ x) b))
|}

let nat_ico_image_const_sub_proof_1_4_tactic =
  {|
intros a b c Hac x Hx;
change (Nat_le a c) in Hac;
change (And (Nat_le a x) (Nat_le (Nat_succ x) b)) in Hx;
change
  (And
    (Nat_le
      (Nat_sub (Nat_add c (Nat_succ Nat_zero)) b)
      (Nat_sub c x))
    (Nat_le
      (Nat_succ (Nat_sub c x))
      (Nat_sub (Nat_add c (Nat_succ Nat_zero)) a)));
destruct Hx as [Hax Hxb];
assert (Hpredmap : forall a : Nat,
  nat_of_Nat (Nat_pred a) = PeanoNat.Nat.pred (nat_of_Nat a));
[ intros n; destruct n; reflexivity
| ];
assert (Hsub0 : forall a : Nat, Nat_sub a Nat_zero = a);
[ intros n; reflexivity
| ];
assert (HsubS : forall a b : Nat,
  Nat_sub a (Nat_succ b) = Nat_pred (Nat_sub a b));
[ intros m n; reflexivity
| ];
assert (Hsubmap : forall a b : Nat,
  nat_of_Nat (Nat_sub a b) =
    PeanoNat.Nat.sub (nat_of_Nat a) (nat_of_Nat b));
[ intros m n; revert m;
  induction n as [|n IH]; intros m;
  [ rewrite Hsub0, PeanoNat.Nat.sub_0_r; reflexivity
  | rewrite HsubS; cbn [nat_of_Nat];
    rewrite PeanoNat.Nat.sub_succ_r, Hpredmap, IH; reflexivity ]
| ];
let normalize H :=
  apply Nat_le_nat_le' in H;
  repeat first
    [ rewrite nat_of_Nat_add in H
    | rewrite Hsubmap in H
    | rewrite rocq_nat_of_Nat_succ in H
    | rewrite rocq_nat_of_Nat_zero in H ]
in
normalize Hac; normalize Hax; normalize Hxb;
split;
apply nat_le_Nat_le;
repeat first
  [ rewrite nat_of_Nat_add
  | rewrite Hsubmap
  | rewrite rocq_nat_of_Nat_succ
  | rewrite rocq_nat_of_Nat_zero ];
lia
|}

let nat_ico_image_const_sub_proof_1_3_tactic =
  {|
intros a b c Hac x Hx;
change (Nat_le a c) in Hac;
change
  (And
    (Nat_le (Nat_sub (Nat_add c (Nat_succ Nat_zero)) b) x)
    (Nat_le (Nat_succ x)
      (Nat_sub (Nat_add c (Nat_succ Nat_zero)) a))) in Hx;
change
  (And
    (And
      (Nat_le a (Nat_sub c x))
      (Nat_le (Nat_succ (Nat_sub c x)) b))
    (Lean.eq (Nat_sub c (Nat_sub c x)) x));
destruct Hx as [Hlo Hhi];
assert (Hpredmap : forall a : Nat,
  nat_of_Nat (Nat_pred a) = PeanoNat.Nat.pred (nat_of_Nat a));
[ intros n; destruct n; reflexivity
| ];
assert (Hnatinj : forall a b : Nat,
  Logic.eq (nat_of_Nat a) (nat_of_Nat b) -> Lean.eq a b);
[ intros m n h;
  apply lean_eq_of_logic_eq;
  rewrite <- (Nat2natid m), <- (Nat2natid n);
  f_equal; exact h
| ];
assert (Hsub0 : forall a : Nat, Nat_sub a Nat_zero = a);
[ intros n; reflexivity
| ];
assert (HsubS : forall a b : Nat,
  Nat_sub a (Nat_succ b) = Nat_pred (Nat_sub a b));
[ intros m n; reflexivity
| ];
assert (Hsubmap : forall a b : Nat,
  nat_of_Nat (Nat_sub a b) =
    PeanoNat.Nat.sub (nat_of_Nat a) (nat_of_Nat b));
[ intros m n; revert m;
  induction n as [|n IH]; intros m;
  [ rewrite Hsub0, PeanoNat.Nat.sub_0_r; reflexivity
  | rewrite HsubS; cbn [nat_of_Nat];
    rewrite PeanoNat.Nat.sub_succ_r, Hpredmap, IH; reflexivity ]
| ];
let normalize H :=
  apply Nat_le_nat_le' in H;
  repeat first
    [ rewrite nat_of_Nat_add in H
    | rewrite Hsubmap in H
    | rewrite rocq_nat_of_Nat_succ in H
    | rewrite rocq_nat_of_Nat_zero in H ]
in
let normalize_goal :=
  repeat first
    [ rewrite nat_of_Nat_add
    | rewrite Hsubmap
    | rewrite rocq_nat_of_Nat_succ
    | rewrite rocq_nat_of_Nat_zero ]
in
normalize Hac; normalize Hlo; normalize Hhi;
split;
[ split; apply nat_le_Nat_le; normalize_goal; lia
| apply Hnatinj; normalize_goal; lia ]
|}

let nat_icc_insert_succ_right_proof_1_3_tactic =
  {|
intros a b hab x;
change (a <= Nat_succ b)%Nat in hab;
change (Iff
  (Or (Lean.eq x (Nat_succ b))
    (And ((a <= x)%Nat) ((x <= b)%Nat)))
  (And ((a <= x)%Nat) ((x <= Nat_succ b)%Nat)));
constructor;
[ intro h;
  destruct h as [hx | hax];
  [ destruct hx;
    constructor;
    [ exact hab
    | exact (Nat_le_refl x) ]
  | destruct hax as [hax hxb];
    constructor;
    [ exact hax
    | exact (Nat_le_step x b hxb) ] ]
| intro h;
  destruct h as [hax hxb];
  pose proof (Nat_le_dest x (Nat_succ b) hxb) as hk;
  destruct hk as [k hk];
  destruct k as [|k];
  [ apply Or_inl;
    change (Lean.eq x (Nat_succ b)) in hk;
    exact hk
  | apply Or_inr;
    constructor;
    [ exact hax
    | change (Lean.eq (Nat_succ (Nat_add x k)) (Nat_succ b)) in hk;
      exact (Nat_le_intro x b k
        (Nat_succ_inj (Nat_add x k) b hk)) ] ] ]
|}

let list_prev_reverse_eq_next_proof_1_1_tactic =
  {|
intros alpha l k hk;
apply Nat_le_nat_le' in hk;
apply nat_le_Nat_le;
assert (Hpredmap : forall a : Nat,
  nat_of_Nat (Nat_pred a) = PeanoNat.Nat.pred (nat_of_Nat a));
[ intros n; destruct n; reflexivity
| ];
assert (Hsub0 : forall a : Nat, Nat_sub a Nat_zero = a);
[ intros n; reflexivity
| ];
assert (HsubS : forall a b : Nat,
  Nat_sub a (Nat_succ b) = Nat_pred (Nat_sub a b));
[ intros m n; reflexivity
| ];
assert (Hsubmap : forall a b : Nat,
  nat_of_Nat (Nat_sub a b) =
    PeanoNat.Nat.sub (nat_of_Nat a) (nat_of_Nat b));
[ intros m n; revert m;
  induction n as [|n IH]; intros m;
  [ rewrite Hsub0, PeanoNat.Nat.sub_0_r; reflexivity
  | rewrite HsubS; cbn [nat_of_Nat];
    rewrite PeanoNat.Nat.sub_succ_r, Hpredmap, IH; reflexivity ]
| ];
repeat first
  [ rewrite Hsubmap
  | rewrite rocq_nat_of_Nat_succ
  | rewrite rocq_nat_of_Nat_zero ];
repeat first
  [ rewrite Hsubmap in hk
  | rewrite rocq_nat_of_Nat_succ in hk
  | rewrite rocq_nat_of_Nat_zero in hk ];
lia
|}

let list_next_eq_get_elem_proof_1_tactic =
  {|
intros alpha l a ha;
destruct l as [|head tail];
[ inversion ha
| exact (Nat_zero_lt_succ (List_length alpha tail)) ]
|}

let list_next_eq_get_elem_proof_1_3_tactic =
  {|
intros alpha inst l a ha;
apply Nat_mod_lt;
exact (List_next_eq_getElem__proof_1 alpha l a ha)
|}

let list_next_eq_get_elem_proof_1_4_tactic =
  {|
intros alpha l hl;
exact hl
|}

let list_next_eq_get_elem_proof_1_34_tactic =
  {|
intros alpha l hl;
exact (Iff_mpr _ _ (List_length_pos_iff alpha l) hl)
|}

let list_next_eq_get_elem_proof_1_19_tactic =
  {|
intros alpha l hl;
exact (List_getLast_mem alpha l hl)
|}

let list_next_eq_get_elem_proof_1_36_tactic =
  {|
intros alpha decEq l a ha hl ha';
let beq := constr:(instBEqOfDecidableEq alpha decEq) in
let lawful := constr:(instLawfulBEq alpha decEq) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
pose proof (List_dropLast_append_getLast alpha l hl) as hdecomp;
pose proof
  (eq_mpr_sprop
    (fun xs => Membership_mem alpha (List alpha)
      (List_instMembership alpha) xs a) hdecomp ha) as haAppend;
pose proof
  (Iff_mp _ _
    (List_mem_append alpha a (List_dropLast alpha l)
      (List_cons alpha (List_getLast alpha l hl) (List_nil alpha)))
    haAppend) as haCases;
assert (haLast : Lean.eq a (List_getLast alpha l hl));
[ destruct haCases as [haDrop | haSingleton];
  [ destruct (ha' haDrop)
  | pose proof
      (Iff_mp _ _
        (List_mem_cons alpha (List_getLast alpha l hl) (List_nil alpha) a)
        haSingleton) as haSingletonCases;
    destruct haSingletonCases as [haLast | haNil];
    [ exact haLast
    | inversion haNil ] ]
| ];
assert (hnotLast : Not
  (Membership_mem alpha (List alpha) (List_instMembership alpha)
    (List_dropLast alpha l) (List_getLast alpha l hl)));
[ intro hmem;
  exact (ha' (eq_mpr_sprop
    (fun x => Membership_mem alpha (List alpha)
      (List_instMembership alpha) (List_dropLast alpha l) x)
    haLast hmem))
| ];
pose proof
  (eq_mp_sprop
    (fun x => forall hx :
      Membership_mem alpha (List alpha) (List_instMembership alpha) l x,
      Lean.eq (List_next alpha decEq l a ha)
        (List_next alpha decEq l x hx))
    haLast
    (fun hx => eq_refl (List_next alpha decEq l a ha))) as hnextArg;
pose proof (hnextArg (List_getLast_mem alpha l hl)) as hnextArgEq;
rewrite_lean_eq hnextArgEq;
rewrite_lean_eq
  (List_next_getLast_eq_head_of_notMem_dropLast
    alpha decEq l hl hnotLast);
rewrite_lean_eq (List_head_eq_getElem alpha l hl);
pose proof
  (congrArg alpha Nat a (List_getLast alpha l hl)
    (fun x => List_idxOf alpha beq x l) haLast) as hidxArg;
assert (hidxAppend :
  Lean.eq
    (List_idxOf alpha beq (List_getLast alpha l hl)
      (HAppend_hAppend (List alpha) (List alpha) (List alpha)
        (instHAppendOfAppend (List alpha) (List_instAppend alpha))
        (List_dropLast alpha l)
        (List_cons alpha (List_getLast alpha l hl) (List_nil alpha))))
    (List_length alpha (List_dropLast alpha l)));
[ rewrite_lean_eq
    (List_idxOf_append alpha beq lawful
      (List_dropLast alpha l)
      (List_cons alpha (List_getLast alpha l hl) (List_nil alpha))
      (List_getLast alpha l hl));
  rewrite_lean_eq
    (if_neg _
      (List_instDecidableMemOfLawfulBEq alpha beq lawful
        (List_getLast alpha l hl) (List_dropLast alpha l))
      hnotLast Nat
      (List_idxOf alpha beq (List_getLast alpha l hl)
        (List_dropLast alpha l))
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        (List_idxOf alpha beq (List_getLast alpha l hl)
          (List_cons alpha (List_getLast alpha l hl) (List_nil alpha)))
        (List_length alpha (List_dropLast alpha l))));
  rewrite_lean_eq
    (List_idxOf_cons_self alpha (List_getLast alpha l hl) beq
      (LawfulBEq_toReflBEq alpha beq lawful) (List_nil alpha));
  exact (Nat_zero_add (List_length alpha (List_dropLast alpha l)))
| ];
pose proof
  (congrArg (List alpha) Nat
    (HAppend_hAppend (List alpha) (List alpha) (List alpha)
      (instHAppendOfAppend (List alpha) (List_instAppend alpha))
      (List_dropLast alpha l)
      (List_cons alpha (List_getLast alpha l hl) (List_nil alpha)))
    l
    (List_idxOf alpha beq (List_getLast alpha l hl))
    hdecomp) as hidxCongr;
assert (hidx : Lean.eq
  (List_idxOf alpha beq (List_getLast alpha l hl) l)
  (List_length alpha (List_dropLast alpha l)));
[ eapply (eq_mp_sprop
    (fun n => Lean.eq n (List_length alpha (List_dropLast alpha l)))
    hidxCongr);
  exact hidxAppend
| ];
pose proof (Iff_mpr _ _ (List_length_pos_iff alpha l) hl) as hpos;
assert (hmod : Lean.eq
  (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
      (List_idxOf alpha beq (List_getLast alpha l hl) l) 1)
    (List_length alpha l))
  0);
[ rewrite_lean_eq hidx;
  rewrite_lean_eq (List_length_dropLast alpha l);
  rewrite_lean_eq (Nat_sub_add_cancel (List_length alpha l) 1 hpos);
  exact (Nat_mod_self (List_length alpha l))
| ];
assert (hmodA : Lean.eq
  (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
      (List_idxOf alpha beq a l) 1)
    (List_length alpha l))
  0);
[ exact
    (eq_mpr_sprop
      (fun n => Lean.eq
        (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n 1)
          (List_length alpha l))
        0)
      hidxArg hmod)
| ];
pose proof
  (eq_mpr_sprop
    (fun i => forall hi : LT_lt_inst1 Nat instLTNat i (List_length alpha l),
      Lean.eq
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) l 0
          (Iff_mpr _ _ (List_length_pos_iff alpha l) hl))
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) l i hi))
    hmodA
    (fun hi => eq_refl
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) l 0
        (Iff_mpr _ _ (List_length_pos_iff alpha l) hl)))) as hgetElem;
exact
  (hgetElem
    (Nat_mod_lt
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        (List_idxOf alpha beq a l) 1)
      (List_length alpha l)
      (List_next_eq_getElem__proof_1 alpha l a ha)))
|}

let list_next_eq_get_elem_tactic =
  {|
intros alpha decEq l a ha;
let beq := constr:(instBEqOfDecidableEq alpha decEq) in
let lawful := constr:(instLawfulBEq alpha decEq) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
pose proof (List_ne_nil_of_mem alpha a l ha) as hl;
destruct
  (List_instDecidableMemOfLawfulBEq alpha beq lawful
    a (List_dropLast alpha l)) as [haNot | haDrop];
[ exact
    (_private_Mathlib_Data_List_Cycle0_List_next_eq_getElem__proof_1_36
      alpha decEq l a ha hl haNot)
| pose proof
    (List_succ_idxOf_lt_length_of_mem_dropLast
      alpha beq lawful l a haDrop) as hsucc;
  lazymatch goal with
  | |- Lean.eq _ ?rhs =>
    change
      (Lean.eq
        (List_nextOr alpha decEq l a
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) l 0
            (List_length_pos_of_mem alpha a l ha)))
        rhs)
  end;
  rewrite_lean_eq
    (List_nextOr_eq_getElem_idxOf_succ_of_mem_dropLast
      alpha decEq l a haDrop
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) l 0
        (List_length_pos_of_mem alpha a l ha)));
  pose proof
    (Nat_mod_eq_of_lt
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        (List_idxOf alpha beq a l) 1)
      (List_length alpha l) hsucc) as hmodEq;
  pose proof
    (eq_mpr_sprop
      (fun i => forall hi : LT_lt_inst1 Nat instLTNat i (List_length alpha l),
        Lean.eq
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) l
            (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
              (List_idxOf alpha beq a l) 1)
            hsucc)
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) l i hi))
      hmodEq
      (fun hi => eq_refl
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) l
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
            (List_idxOf alpha beq a l) 1)
          hsucc))) as hgetElem;
  exact
    (hgetElem
      (Nat_mod_lt
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
          (List_idxOf alpha beq a l) 1)
        (List_length alpha l)
        (List_next_eq_getElem__proof_1 alpha l a ha))) ]
|}

let list_next_get_elem_proof_1_4_tactic =
  {|
intros alpha inst l i hi;
apply Nat_mod_lt;
exact
  (Nat_lt_of_le_of_lt Nat_zero i (List_length alpha l)
    (Nat_zero_le i) hi)
|}

let list_next_get_elem_proof_1_6_tactic =
  {|
intros alpha decEq l nodup i hi;
let beq := constr:(instBEqOfDecidableEq alpha decEq) in
let lawful := constr:(instLawfulBEq alpha decEq) in
let elem := constr:(
  GetElem_getElem_inst2 (List alpha) Nat alpha
    (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
    (List_instGetElemNatLtLength alpha) l i hi) in
let memElem :=
  lazymatch goal with
  | |- Lean.eq (List_next _ _ _ _ ?h) _ => h
  end in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
rewrite_lean_eq (List_next_eq_getElem alpha decEq l elem memElem);
pose proof
  (List_Nodup_idxOf_getElem alpha beq lawful l nodup i hi) as hidx;
pose proof
  (congrArg Nat Nat
    (List_idxOf alpha beq elem l) i
    (fun n =>
      HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n 1)
        (List_length alpha l))
    hidx) as hmodIdx;
pose proof
  (eq_mp_sprop
    (fun j => forall hj : LT_lt_inst1 Nat instLTNat j (List_length alpha l),
      Lean.eq
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) l
          (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
            (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
              (List_idxOf alpha beq elem l) 1)
            (List_length alpha l))
          (Nat_mod_lt
            (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
              (List_idxOf alpha beq elem l) 1)
            (List_length alpha l)
            (List_next_eq_getElem__proof_1 alpha l elem memElem)))
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) l j hj))
    hmodIdx
    (fun hj => eq_refl
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) l
        (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
            (List_idxOf alpha beq elem l) 1)
          (List_length alpha l))
        (Nat_mod_lt
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
            (List_idxOf alpha beq elem l) 1)
          (List_length alpha l)
          (List_next_eq_getElem__proof_1 alpha l elem memElem))))) as hgetElem;
exact
  (hgetElem
    (Nat_mod_lt
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) i 1)
      (List_length alpha l)
      (Nat_lt_of_le_of_lt Nat_zero i (List_length alpha l)
        (Nat_zero_le i) hi)))
|}

let list_next_get_elem_tactic =
  {|
intros alpha decEq l nodup i hi;
exact
  (_private_Mathlib_Data_List_Cycle0_List_next_getElem__proof_1_6
    alpha decEq l nodup i hi)
|}

let list_pmap_next_eq_rotate_one_tactic =
  {|
intros alpha decEq l nodup;
let pred := constr:(fun x =>
  Membership_mem alpha (List alpha) (List_instMembership alpha) l x) in
let nextFn := constr:(List_next alpha decEq l) in
let allMem := constr:(fun x (h :
  Membership_mem alpha (List alpha) (List_instMembership alpha) l x) => h) in
let mapped := constr:(List_pmap alpha alpha pred nextFn l allMem) in
let rotated := constr:(List_rotate alpha l 1) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
apply (List_ext_getElem alpha mapped rotated);
[ rewrite_lean_eq
    (List_length_pmap alpha alpha pred nextFn l allMem);
  rewrite_lean_eq (List_length_rotate alpha l 1);
  reflexivity
| intros i hiMapped hiRotated;
  pose proof
    (eq_mp_sprop
      (fun len => LT_lt_inst1 Nat instLTNat i len)
      (List_length_pmap alpha alpha pred nextFn l allMem)
      hiMapped) as hi;
  rewrite_lean_eq
    (List_getElem_pmap alpha alpha pred nextFn l allMem i hiMapped);
  rewrite_lean_eq
    (List_getElem_rotate alpha l 1 i hiRotated);
  exact
    (List_next_getElem alpha decEq l nodup i hi) ]
|}

let list_pmap_prev_eq_rotate_length_sub_one_tactic =
  {|
intros alpha decEq l nodup;
let pred := constr:(fun x =>
  Membership_mem alpha (List alpha) (List_instMembership alpha) l x) in
let prevFn := constr:(List_prev alpha decEq l) in
let allMem := constr:(fun x (h :
  Membership_mem alpha (List alpha) (List_instMembership alpha) l x) => h) in
let mapped := constr:(List_pmap alpha alpha pred prevFn l allMem) in
let amount := constr:(
  HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
    (List_length alpha l) 1) in
let rotated := constr:(List_rotate alpha l amount) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
apply (List_ext_getElem alpha mapped rotated);
[ rewrite_lean_eq
    (List_length_pmap alpha alpha pred prevFn l allMem);
  rewrite_lean_eq (List_length_rotate alpha l amount);
  reflexivity
| intros i hiMapped hiRotated;
  pose proof
    (eq_mp_sprop
      (fun len => LT_lt_inst1 Nat instLTNat i len)
      (List_length_pmap alpha alpha pred prevFn l allMem)
      hiMapped) as hi;
  rewrite_lean_eq
    (List_getElem_pmap alpha alpha pred prevFn l allMem i hiMapped);
  rewrite_lean_eq
    (List_getElem_rotate alpha l amount i hiRotated);
  exact
    (List_prev_getElem alpha decEq l nodup i hi) ]
|}

let list_prev_get_elem_proof_1_tactic =
  {|
intros alpha l i hi;
exact
  (Nat_lt_of_le_of_lt Nat_zero i (List_length alpha l)
    (Nat_zero_le i) hi)
|}

let list_prev_get_elem_proof_1_4_tactic =
  {|
intros alpha inst l i hi;
apply Nat_mod_lt;
exact
  (Nat_lt_of_le_of_lt Nat_zero i (List_length alpha l)
    (Nat_zero_le i) hi)
|}

let list_prev_get_elem_proof_1_6_tactic =
  {|
intros alpha decEq l nodup i hi;
let beq := constr:(instBEqOfDecidableEq alpha decEq) in
let lawful := constr:(instLawfulBEq alpha decEq) in
let elem := constr:(
  GetElem_getElem_inst2 (List alpha) Nat alpha
    (fun xs j => LT_lt_inst1 Nat instLTNat j (List_length alpha xs))
    (List_instGetElemNatLtLength alpha) l i hi) in
let memElem :=
  lazymatch goal with
  | |- Lean.eq (List_prev _ _ _ _ ?h) _ => h
  end in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
rewrite_lean_eq (List_prev_eq_getElem alpha decEq l elem memElem);
pose proof
  (List_Nodup_idxOf_getElem alpha beq lawful l nodup i hi) as hidx;
pose proof
  (congrArg Nat Nat
    (List_idxOf alpha beq elem l) i
    (fun n =>
      HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
          n
          (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
            (List_length alpha l) 1))
        (List_length alpha l))
    hidx) as hmodIdx;
pose proof
  (eq_mp_sprop
    (fun j => forall hj : LT_lt_inst1 Nat instLTNat j (List_length alpha l),
      Lean.eq
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) l
          (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
            (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
              (List_idxOf alpha beq elem l)
              (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
                (List_length alpha l) 1))
            (List_length alpha l))
          (Nat_mod_lt
            (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
              (List_idxOf alpha beq elem l)
              (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
                (List_length alpha l) 1))
            (List_length alpha l)
            (List_next_eq_getElem__proof_1 alpha l elem memElem)))
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) l j hj))
    hmodIdx
    (fun hj => eq_refl
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) l
        (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
            (List_idxOf alpha beq elem l)
            (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
              (List_length alpha l) 1))
          (List_length alpha l))
        (Nat_mod_lt
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
            (List_idxOf alpha beq elem l)
            (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
              (List_length alpha l) 1))
          (List_length alpha l)
          (List_next_eq_getElem__proof_1 alpha l elem memElem))))) as hgetElem;
exact
  (hgetElem
    (Nat_mod_lt
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        i
        (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
          (List_length alpha l) 1))
      (List_length alpha l)
      (List_prev_getElem__proof_1 alpha l i hi)))
|}

let list_prev_get_elem_tactic =
  {|
intros alpha decEq l nodup i hi;
exact
  (_private_Mathlib_Data_List_Cycle0_List_prev_getElem__proof_1_6
    alpha decEq l nodup i hi)
|}

let list_prev_eq_get_elem_proof_1_2_tactic =
  {|
intros alpha inst a ha;
inversion ha
|}

let list_prev_eq_get_elem_proof_1_3_tactic =
  {|
intros alpha inst a ha;
inversion ha
|}

let list_prev_eq_get_elem_proof_1_4_tactic =
  {|
intros alpha inst a tail ha;
exact (Nat_lt_succ_self (List_length alpha tail))
|}

let list_prev_eq_get_elem_proof_1_7_tactic =
  {|
intros alpha inst a tail ha;
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
rewrite_lean_eq
  (List_getLast_eq_getElem alpha
    (List_cons alpha a tail) (List_cons_ne_nil alpha a tail));
reflexivity
|}

let list_prev_eq_get_elem_pred_proof_1_tactic =
  {|
intros alpha inst l a ha;
let beq := constr:(instBEqOfDecidableEq alpha inst) in
let lawful := constr:(instLawfulBEq alpha inst) in
exact
  (Nat_lt_of_le_of_lt
    (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
      (List_idxOf alpha beq a l) 1)
    (List_idxOf alpha beq a l)
    (List_length alpha l)
    (Nat_sub_le (List_idxOf alpha beq a l) 1)
    (List_idxOf_lt_length_of_mem alpha a beq
      (instEquivBEqOfLawfulBEq alpha beq lawful) l ha))
|}

let list_prev_eq_get_elem_proof_1_8_tactic =
  {|
intros alpha inst a head tail ha hne;
let beq := constr:(instBEqOfDecidableEq alpha inst) in
let lawful := constr:(instLawfulBEq alpha inst) in
exact
  (Nat_lt_of_le_of_lt
    (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
      (List_idxOf alpha beq a (List_cons alpha head tail)) 1)
    (List_idxOf alpha beq a (List_cons alpha head tail))
    (List_length alpha (List_cons alpha head tail))
    (Nat_sub_le (List_idxOf alpha beq a (List_cons alpha head tail)) 1)
    (List_idxOf_lt_length_of_mem alpha a beq
      (instEquivBEqOfLawfulBEq alpha beq lawful)
      (List_cons alpha head tail) ha))
|}

let list_prev_eq_get_elem_tactic =
  {|
intros alpha decEq l a ha;
let beq := constr:(instBEqOfDecidableEq alpha decEq) in
let lawful := constr:(instLawfulBEq alpha decEq) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
destruct l as [|head tail];
[ inversion ha
| destruct (decEq a head) as [hne | heq];
  [ pose proof
      (Iff_mp _ _ (List_mem_cons alpha head tail a) ha) as haCases;
    destruct haCases as [haHead | haTail];
    [ destruct (hne haHead)
    | ];
    assert (hneRev : Not (Lean.eq head a));
    [ intro h;
      exact (hne (Eq_symm alpha head a h))
    | ];
    pose proof
      (List_idxOf_cons_ne alpha beq lawful a head tail hneRev) as hidxCons;
    pose proof
      (List_idxOf_lt_length_of_mem alpha a beq
        (instEquivBEqOfLawfulBEq alpha beq lawful) tail haTail) as hidxTail;
    pose proof (List_length_cons alpha head tail) as hlen;
    let n := constr:(List_idxOf alpha beq a tail) in
    let m := constr:(List_length alpha tail) in
    assert (hsum : Lean.eq
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n 1) m)
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        n (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) m 1)));
    [ rewrite_lean_eq (Nat_add_assoc n 1 m);
      rewrite_lean_eq (Nat_add_comm 1 m);
      reflexivity
    | ];
    pose proof
      (Nat_lt_trans n m (Nat_succ m) hidxTail (Nat_lt_succ_self m)) as hless;
    assert (hindex : Lean.eq
      (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
        (List_idxOf alpha beq a (List_cons alpha head tail)) 1)
      (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
          (List_idxOf alpha beq a (List_cons alpha head tail))
          (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
            (List_length alpha (List_cons alpha head tail)) 1))
        (List_length alpha (List_cons alpha head tail))));
    [ rewrite_lean_eq hidxCons;
      rewrite_lean_eq hlen;
      change
        (Lean.eq n
          (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
            (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
              (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
                n 1) m)
            (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
              m 1)));
      rewrite_lean_eq hsum;
      rewrite_lean_eq
        (Nat_add_mod_right n
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) m 1));
      rewrite_lean_eq
        (Nat_mod_eq_of_lt n
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) m 1)
          hless);
      reflexivity
    | ];
    rewrite_lean_eq
      (List_prev_eq_getElem_idxOf_pred_of_ne_head
        alpha decEq (List_cons alpha head tail) a ha hne);
    pose proof
      (eq_mp_sprop
        (fun j => forall hj : LT_lt_inst1 Nat instLTNat j
          (List_length alpha (List_cons alpha head tail)),
          Lean.eq
            (GetElem_getElem_inst2 (List alpha) Nat alpha
              (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
              (List_instGetElemNatLtLength alpha)
              (List_cons alpha head tail)
              (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
                (List_idxOf alpha beq a (List_cons alpha head tail)) 1)
              (List_prev_eq_getElem_idxOf_pred_of_ne_head__proof_1
                alpha decEq (List_cons alpha head tail) a ha))
            (GetElem_getElem_inst2 (List alpha) Nat alpha
              (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
              (List_instGetElemNatLtLength alpha)
              (List_cons alpha head tail) j hj))
        hindex
        (fun hj => eq_refl
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
            (List_instGetElemNatLtLength alpha)
            (List_cons alpha head tail)
            (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
              (List_idxOf alpha beq a (List_cons alpha head tail)) 1)
            (List_prev_eq_getElem_idxOf_pred_of_ne_head__proof_1
              alpha decEq (List_cons alpha head tail) a ha)))) as hgetElem;
    exact
      (hgetElem
        (Nat_mod_lt
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
            (List_idxOf alpha beq a (List_cons alpha head tail))
            (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
              (List_length alpha (List_cons alpha head tail)) 1))
          (List_length alpha (List_cons alpha head tail))
          (List_next_eq_getElem__proof_1
            alpha (List_cons alpha head tail) a ha)))
  | destruct heq;
    rewrite_lean_eq (List_prev_getLast_cons alpha decEq tail a ha);
    pose proof
      (List_idxOf_cons_self alpha a beq
        (LawfulBEq_toReflBEq alpha beq lawful) tail) as hidxSelf;
    pose proof (List_length_cons alpha a tail) as hlenHead;
    let m := constr:(List_length alpha tail) in
    assert (htarget : Lean.eq
      (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
          (List_idxOf alpha beq a (List_cons alpha a tail))
          (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
            (List_length alpha (List_cons alpha a tail)) 1))
        (List_length alpha (List_cons alpha a tail)))
      m);
    [ rewrite_lean_eq hidxSelf;
      rewrite_lean_eq hlenHead;
      rewrite_lean_eq (Nat_add_sub_cancel m 1);
      rewrite_lean_eq (Nat_zero_add m);
      change
        (Lean.eq
          (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
            m
            (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
              m 1))
          m);
      exact (Nat_mod_succ m)
    | ];
    rewrite_lean_eq
      (_private_Mathlib_Data_List_Cycle0_List_prev_eq_getElem__proof_1_7
        alpha decEq a tail ha);
    let leftProof :=
      lazymatch goal with
      | |- Lean.eq
          (GetElem_getElem_inst2 _ _ _ _ _ _ _ ?h) _ => h
      end in
    pose proof
      (eq_mpr_sprop
        (fun j => forall hj : LT_lt_inst1 Nat instLTNat j
          (List_length alpha (List_cons alpha a tail)),
          Lean.eq
            (GetElem_getElem_inst2 (List alpha) Nat alpha
              (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
              (List_instGetElemNatLtLength alpha)
              (List_cons alpha a tail) m leftProof)
            (GetElem_getElem_inst2 (List alpha) Nat alpha
              (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
              (List_instGetElemNatLtLength alpha)
              (List_cons alpha a tail) j hj))
        htarget
        (fun hj => eq_refl
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs k => LT_lt_inst1 Nat instLTNat k (List_length alpha xs))
            (List_instGetElemNatLtLength alpha)
            (List_cons alpha a tail) m leftProof))) as hgetHead;
    exact
      (hgetHead
        (Nat_mod_lt
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
            (List_idxOf alpha beq a (List_cons alpha a tail))
            (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
              (List_length alpha (List_cons alpha a tail)) 1))
          (List_length alpha (List_cons alpha a tail))
          (List_next_eq_getElem__proof_1
            alpha (List_cons alpha a tail) a ha))) ] ]
|}

let list_prev_reverse_eq_next_tactic =
  {|
intros alpha decEq l nodup x hx;
let rev := constr:(List_reverse alpha l) in
let predRev := constr:(fun y =>
  Membership_mem alpha (List alpha) (List_instMembership alpha) rev y) in
let predL := constr:(fun y =>
  Membership_mem alpha (List alpha) (List_instMembership alpha) l y) in
let prevFn := constr:(List_prev alpha decEq rev) in
let nextFn := constr:(List_next alpha decEq l) in
let allMemRev := constr:(fun y (h :
  Membership_mem alpha (List alpha) (List_instMembership alpha) rev y) => h) in
let allMemL := constr:(fun y (h :
  Membership_mem alpha (List alpha) (List_instMembership alpha) l y) => h) in
let mappedPrev := constr:(List_pmap alpha alpha predRev prevFn rev allMemRev) in
let mappedNext := constr:(List_pmap alpha alpha predL nextFn l allMemL) in
let n := constr:(List_length alpha l) in
let amount := constr:(
  HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat) n 1) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
let rewrite_lean_eq_rev h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern rhs; eapply (eq_mp_sprop _ h)
  end in
pose proof (List_getElem_of_mem alpha x l hx) as hxElem;
destruct hxElem as [k hxElem];
destruct hxElem as [hk hxEq];
let elem := constr:(
  GetElem_getElem_inst2 (List alpha) Nat alpha
    (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
    (List_instGetElemNatLtLength alpha) l k hk) in
let j := constr:(
  HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
    (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat) n 1) k) in
pose proof
  (Nat_lt_of_le_of_lt Nat_zero k n (Nat_zero_le k) hk) as lpos;
pose proof
  (_private_Mathlib_Data_List_Cycle0_List_prev_reverse_eq_next__proof_1_1
    alpha l k hk) as key;
pose proof (Iff_mpr _ _ (List_nodup_reverse alpha l) nodup) as nodupRev;
pose proof
  (Nat_sub_lt n 1 lpos (Nat_zero_lt_succ Nat_zero)) as hsubLt;
pose proof (Nat_mod_eq_of_lt amount n hsubLt) as hmodAmount;
assert (hamount : Lean.eq
  (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
    n
    (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
      amount n))
  1);
[ rewrite_lean_eq hmodAmount;
  exact (Nat_sub_sub_self n 1 lpos)
| ];
pose proof (List_length_reverse alpha l) as hlenRev;
pose proof
  (congrArg Nat Nat
    (List_length alpha rev) n
    (fun len => HSub_hSub_inst7 Nat Nat Nat
      (instHSub_inst1 Nat instSubNat) len 1)
    hlenRev) as hamountRev;
pose proof
  (congrArg Nat (List alpha)
    (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
      (List_length alpha rev) 1)
    amount
    (List_rotate alpha rev)
    hamountRev) as hrotateAmount;
pose proof
  (List_rotate_reverse alpha l amount) as hrotateReverse;
pose proof
  (congrArg Nat (List alpha)
    (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
      n
      (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
        amount n))
    1
    (List_rotate alpha l)
    hamount) as hrotateInner;
pose proof
  (congrArg (List alpha) (List alpha)
    (List_rotate alpha l
      (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
        n
        (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
          amount n)))
    (List_rotate alpha l 1)
    (List_reverse alpha)
    hrotateInner) as hreverseInner;
pose proof
  (List_pmap_prev_eq_rotate_length_sub_one alpha decEq rev nodupRev)
    as hpmapPrev;
pose proof (List_pmap_next_eq_rotate_one alpha decEq l nodup)
  as hpmapNext;
assert (hglobal : Lean.eq mappedPrev (List_reverse alpha mappedNext));
[ eapply (eq_mpr_sprop
    (fun ys => Lean.eq ys (List_reverse alpha mappedNext)) hpmapPrev);
  eapply (eq_mpr_sprop
    (fun ys => Lean.eq ys (List_reverse alpha mappedNext)) hrotateAmount);
  eapply (eq_mpr_sprop
    (fun ys => Lean.eq ys (List_reverse alpha mappedNext)) hrotateReverse);
  eapply (eq_mpr_sprop
    (fun ys => Lean.eq ys (List_reverse alpha mappedNext)) hreverseInner);
  eapply (eq_mpr_sprop
    (fun ys => Lean.eq (List_reverse alpha (List_rotate alpha l 1))
      (List_reverse alpha ys)) hpmapNext);
  reflexivity
| ];
pose proof
  (List_length_pmap alpha alpha predRev prevFn rev allMemRev) as hlenPrev;
pose proof
  (List_length_pmap alpha alpha predL nextFn l allMemL) as hlenNext;
pose proof
  (eq_mpr_sprop
    (fun len => LT_lt_inst1 Nat instLTNat j len)
    hlenRev key) as keyRev;
pose proof
  (eq_mpr_sprop
    (fun len => LT_lt_inst1 Nat instLTNat j len)
    hlenPrev keyRev) as hiPrev;
pose proof
  (eq_mpr_sprop
    (fun len => LT_lt_inst1 Nat instLTNat k len)
    hlenNext hk) as hiNext;
pose proof (List_length_reverse alpha mappedNext) as hlenRevNext;
pose proof
  (eq_mpr_sprop
    (fun len => LT_lt_inst1 Nat instLTNat j len)
    hlenNext key) as keyNext;
pose proof
  (eq_mpr_sprop
    (fun len => LT_lt_inst1 Nat instLTNat j len)
    hlenRevNext keyNext) as hiRevNext;
assert (hcanonical : forall helem : predL elem,
  Lean.eq
    (List_prev alpha decEq rev elem
      (Iff_mpr _ _ (List_mem_reverse alpha elem l) helem))
    (List_next alpha decEq l elem helem));
[ intro helem;
  pose proof (List_getElem_eq_getElem_reverse alpha l k hk) as hrevElem;
  pose proof
    (eq_mp_sprop
      (fun y => forall hy :
        Membership_mem alpha (List alpha) (List_instMembership alpha) rev y,
        Lean.eq
          (List_prev alpha decEq rev elem
            (Iff_mpr _ _ (List_mem_reverse alpha elem l) helem))
          (List_prev alpha decEq rev y hy))
      hrevElem
      (fun hy => eq_refl
        (List_prev alpha decEq rev elem
          (Iff_mpr _ _ (List_mem_reverse alpha elem l) helem)))) as hprevArg;
  pose proof
    (hprevArg (List_getElem_mem alpha rev j keyRev)) as hprevArgEq;
  eapply (eq_mpr_sprop
    (fun lhs => Lean.eq lhs (List_next alpha decEq l elem helem))
    hprevArgEq);
  pose proof
    (List_getElem_pmap alpha alpha predRev prevFn rev allMemRev j hiPrev)
      as hpmapPrevElem;
  eapply (eq_mp_sprop
    (fun lhs => Lean.eq lhs (List_next alpha decEq l elem helem))
    hpmapPrevElem);
  pose proof
    (List_getElem_pmap alpha alpha predL nextFn l allMemL k hiNext)
      as hpmapNextElem;
  eapply (eq_mp_sprop
    (fun rhs => Lean.eq
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) mappedPrev j hiPrev)
      rhs)
    hpmapNextElem);
  pose proof
    (eq_mp_sprop
      (fun ys => forall hj : LT_lt_inst1 Nat instLTNat j (List_length alpha ys),
        Lean.eq
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) mappedPrev j hiPrev)
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) ys j hj))
      hglobal
      (fun hj => eq_refl
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) mappedPrev j hiPrev))) as hglobalAt;
  pose proof (hglobalAt hiRevNext) as hglobalElem;
  eapply (eq_mpr_sprop
    (fun lhs => Lean.eq lhs
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) mappedNext k hiNext))
    hglobalElem);
  pose proof
    (List_getElem_eq_getElem_reverse alpha mappedNext k hiNext) as hnextReverse;
  eapply (eq_mpr_sprop
    (fun rhs => Lean.eq
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
        (List_instGetElemNatLtLength alpha)
        (List_reverse alpha mappedNext) j hiRevNext)
      rhs)
    hnextReverse);
  assert (hidxReverse : Lean.eq
    (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
      (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
        (List_length alpha mappedNext) 1) k)
    j);
  [ rewrite_lean_eq hlenNext;
    reflexivity
  | ];
  let rightProof :=
    lazymatch goal with
    | |- Lean.eq _ (GetElem_getElem_inst2 _ _ _ _ _ _ _ ?h) => h
    end in
  pose proof
    (eq_mpr_sprop
      (fun idx => forall hidx : LT_lt_inst1 Nat instLTNat idx
        (List_length alpha (List_reverse alpha mappedNext)),
        Lean.eq
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
            (List_instGetElemNatLtLength alpha)
            (List_reverse alpha mappedNext) j hiRevNext)
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
            (List_instGetElemNatLtLength alpha)
            (List_reverse alpha mappedNext) idx hidx))
      hidxReverse
      (fun hidx => eq_refl
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
          (List_instGetElemNatLtLength alpha)
          (List_reverse alpha mappedNext) j hiRevNext))) as hidxElem;
  exact (hidxElem rightProof)
| ];
pose proof
  (eq_mp_sprop
    (fun y => forall hy : predL y,
      Lean.eq
        (List_prev alpha decEq rev y
          (Iff_mpr _ _ (List_mem_reverse alpha y l) hy))
        (List_next alpha decEq l y hy))
    hxEq hcanonical) as htransport;
exact (htransport hx)
|}

let list_next_reverse_eq_prev_tactic =
  {|
intros alpha decEq l nodup x hx;
let rev := constr:(List_reverse alpha l) in
let revrev := constr:(List_reverse alpha rev) in
let hxRev := constr:(
  Iff_mpr
    (Membership_mem alpha (List alpha) (List_instMembership alpha) rev x)
    (Membership_mem alpha (List alpha) (List_instMembership alpha) l x)
    (List_mem_reverse alpha x l) hx) in
let hxRevRev := constr:(
  Iff_mpr
    (Membership_mem alpha (List alpha) (List_instMembership alpha) revrev x)
    (Membership_mem alpha (List alpha) (List_instMembership alpha) rev x)
    (List_mem_reverse alpha x rev) hxRev) in
pose proof (Iff_mpr _ _ (List_nodup_reverse alpha l) nodup) as nodupRev;
pose proof
  (List_prev_reverse_eq_next alpha decEq rev nodupRev x hxRev) as hbase;
pose proof (List_reverse_reverse alpha l) as hrevrev;
pose proof
  (eq_mp_sprop
    (fun ys => forall hy :
      Membership_mem alpha (List alpha) (List_instMembership alpha) ys x,
      Lean.eq
        (List_prev alpha decEq revrev x hxRevRev)
        (List_prev alpha decEq ys x hy))
    hrevrev
    (fun hy => eq_refl (List_prev alpha decEq revrev x hxRevRev)))
    as hprevLists;
pose proof (hprevLists hx) as hprevList;
pose proof
  (Eq_symm alpha
    (List_prev alpha decEq revrev x hxRevRev)
    (List_next alpha decEq rev x hxRev)
    hbase) as hbaseSymm;
eapply (eq_mpr_sprop
  (fun lhs => Lean.eq lhs (List_prev alpha decEq l x hx))
  hbaseSymm);
exact hprevList
|}

let list_is_rotated_next_eq_tactic =
  {|
intros alpha decEq l l' hrotated nodup x hx;
let hx' :=
  lazymatch goal with
  | |- Lean.eq _ (List_next _ _ _ _ ?h) => h
  end in
pose proof hx' as hxPrime;
pose proof
  (Iff_mp _ _ (List_IsRotated_nodup_iff alpha l l' hrotated) nodup)
    as nodupL';
pose proof (List_getElem_of_mem alpha x l hx) as hxElem;
destruct hxElem as [k hxElem];
destruct hxElem as [hk hxEq];
destruct hrotated as [rotN hrot];
let rot := constr:(List_rotate alpha l rotN) in
let len := constr:(List_length alpha l) in
let offset := constr:(
  HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
    len
    (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
      rotN len)) in
let r := constr:(
  HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) offset k)
    len) in
let s := constr:(
  HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) k 1)
    len) in
let u := constr:(
  HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) offset s)
    len) in
let elem := constr:(
  GetElem_getElem_inst2 (List alpha) Nat alpha
    (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
    (List_instGetElemNatLtLength alpha) l k hk) in
let predL := constr:(fun y =>
  Membership_mem alpha (List alpha) (List_instMembership alpha) l y) in
let predRot := constr:(fun y =>
  Membership_mem alpha (List alpha) (List_instMembership alpha) rot y) in
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern lhs; eapply (eq_mpr_sprop _ h)
  end in
pose proof
  (Nat_lt_of_le_of_lt Nat_zero k len (Nat_zero_le k) hk) as lpos;
pose proof (List_length_rotate alpha l rotN) as hlenRot;
pose proof
  (eq_mpr_sprop
    (fun n => LT_lt_inst1 Nat instLTNat r n)
    hlenRot
    (Nat_mod_lt
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) offset k)
      len lpos)) as hr;
pose proof
  (Nat_mod_lt
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) k 1)
    len lpos) as hs;
pose proof
  (eq_mpr_sprop (fun ys => List_Nodup alpha ys) hrot nodupL') as nodupRot;
assert (hsum : Lean.eq
  (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) offset k) 1)
  (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) k 1) offset));
[ rewrite_lean_eq (Nat_add_assoc offset k 1);
  rewrite_lean_eq
    (Nat_add_comm offset
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) k 1));
  reflexivity
| ];
assert (hindex : Lean.eq
  (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) r 1)
    (List_length alpha rot))
  u);
[ rewrite_lean_eq hlenRot;
  rewrite_lean_eq
    (Nat_mod_add_mod
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) offset k)
      len 1);
  rewrite_lean_eq (Nat_add_comm offset s);
  rewrite_lean_eq
    (Nat_mod_add_mod
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) k 1)
      len offset);
  exact
    (congrArg Nat Nat
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
          offset k) 1)
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
          k 1) offset)
      (fun z => HMod_hMod_inst7 Nat Nat Nat
        (instHMod_inst1 Nat Nat_instMod) z len)
      hsum)
| ];
assert (hcanonical : forall helem : predL elem,
  forall hrotElem : predRot elem,
  Lean.eq
    (List_next alpha decEq l elem helem)
    (List_next alpha decEq rot elem hrotElem));
[ intros helem hrotElem;
  pose proof (List_getElem_eq_getElem_rotate alpha l rotN k hk) as hgetRot;
  pose proof
    (eq_mp_sprop
      (fun y => forall hy : predRot y,
        Lean.eq
          (List_next alpha decEq rot elem hrotElem)
          (List_next alpha decEq rot y hy))
      hgetRot
      (fun hy => eq_refl (List_next alpha decEq rot elem hrotElem))) as harg;
  pose proof (harg (List_getElem_mem alpha rot r hr)) as hargEq;
  pose proof (List_next_getElem alpha decEq l nodup k hk) as hnextL;
  pose proof (List_next_getElem alpha decEq rot nodupRot r hr) as hnextRot;
  eapply (eq_mpr_sprop
    (fun lhs => Lean.eq lhs (List_next alpha decEq rot elem hrotElem))
    hnextL);
  eapply (eq_mpr_sprop
    (fun rhs => Lean.eq
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) l s hs)
      rhs)
    hargEq);
  eapply (eq_mpr_sprop
    (fun rhs => Lean.eq
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) l s hs)
      rhs)
    hnextRot);
  pose proof (List_getElem_eq_getElem_rotate alpha l rotN s hs) as hgetRotS;
  eapply (eq_mpr_sprop
    (fun lhs => Lean.eq lhs
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) rot
        (HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) r 1)
          (List_length alpha rot))
        (Nat_mod_lt
          (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) r 1)
          (List_length alpha rot)
          (Nat_lt_of_le_of_lt Nat_zero r (List_length alpha rot)
            (Nat_zero_le r) hr))))
    hgetRotS);
  let rightProof :=
    lazymatch goal with
    | |- Lean.eq _ (GetElem_getElem_inst2 _ _ _ _ _ _ _ ?h) => h
    end in
  pose proof
    (eq_mpr_sprop
      (fun idx => forall hidx : LT_lt_inst1 Nat instLTNat idx
        (List_length alpha rot),
        Lean.eq
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) rot u
            (eq_mpr_sprop
              (fun length => LT_lt_inst1 Nat instLTNat u length)
              hlenRot
              (Nat_mod_lt
                (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
                  offset s)
                len lpos)))
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) rot idx hidx))
      hindex
      (fun hidx => eq_refl
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) rot u
          (eq_mpr_sprop
            (fun length => LT_lt_inst1 Nat instLTNat u length)
            hlenRot
            (Nat_mod_lt
              (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
                offset s)
              len lpos))))) as hidxElem;
  exact (hidxElem rightProof)
| ];
pose proof
  (eq_mp_sprop
    (fun y => forall hy : predL y,
      forall hyRot : predRot y,
      Lean.eq
        (List_next alpha decEq l y hy)
        (List_next alpha decEq rot y hyRot))
    hxEq hcanonical) as hcanonicalX;
pose proof
  (eq_mp_sprop
    (fun ys => forall hy :
      Membership_mem alpha (List alpha) (List_instMembership alpha) ys x,
      Lean.eq
        (List_next alpha decEq l x hx)
        (List_next alpha decEq ys x hy))
    hrot
    (hcanonicalX hx)) as htransport;
exact (htransport hxPrime)
|}

let list_is_rotated_prev_eq_tactic =
  {|
intros alpha decEq l l' hrotated nodup x hx;
let hx' :=
  lazymatch goal with
  | |- Lean.eq _ (List_prev _ _ _ _ ?h) => h
  end in
let rev := constr:(List_reverse alpha l) in
let rev' := constr:(List_reverse alpha l') in
let hxRev := constr:(
  Iff_mpr
    (Membership_mem alpha (List alpha) (List_instMembership alpha) rev x)
    (Membership_mem alpha (List alpha) (List_instMembership alpha) l x)
    (List_mem_reverse alpha x l) hx) in
let hxRev' := constr:(
  Iff_mpr
    (Membership_mem alpha (List alpha) (List_instMembership alpha) rev' x)
    (Membership_mem alpha (List alpha) (List_instMembership alpha) l' x)
    (List_mem_reverse alpha x l') hx') in
pose proof
  (Iff_mp _ _ (List_IsRotated_nodup_iff alpha l l' hrotated) nodup)
    as nodupL';
pose proof (Iff_mpr _ _ (List_nodup_reverse alpha l) nodup) as nodupRev;
pose proof
  (Iff_mpr _ _ (List_nodup_reverse alpha l') nodupL') as nodupRev';
pose proof (List_IsRotated_reverse alpha l l' hrotated) as hrotRev;
pose proof
  (List_next_reverse_eq_prev alpha decEq l nodup x hx) as hprevL;
pose proof
  (List_next_reverse_eq_prev alpha decEq l' nodupL' x hx') as hprevL';
pose proof
  (List_isRotated_next_eq alpha decEq rev rev' hrotRev nodupRev x hxRev)
    as hnext;
let hxNext :=
  lazymatch type of hnext with
  | Lean.eq _ (List_next _ _ _ _ ?h) => h
  end in
assert (hproof : Lean.eq
  (List_next alpha decEq rev' x hxNext)
  (List_next alpha decEq rev' x hxRev'));
[ reflexivity
| ];
eapply (eq_mp_sprop
  (fun lhs => Lean.eq lhs (List_prev alpha decEq l' x hx'))
  hprevL);
eapply (eq_mp_sprop
  (fun rhs => Lean.eq (List_next alpha decEq rev x hxRev) rhs)
  hprevL');
eapply (eq_mpr_sprop
  (fun rhs => Lean.eq (List_next alpha decEq rev x hxRev) rhs)
  hproof);
exact hnext
|}

let list_next_prev_tactic =
  {|
intros alpha decEq l nodup x hx;
let rev := constr:(List_reverse alpha l) in
let hxRev := constr:(
  Iff_mpr
    (Membership_mem alpha (List alpha) (List_instMembership alpha) rev x)
    (Membership_mem alpha (List alpha) (List_instMembership alpha) l x)
    (List_mem_reverse alpha x l) hx) in
let prevL := constr:(List_prev alpha decEq l x hx) in
let hxPrev := constr:(List_prev_mem alpha decEq l x hx) in
let hxPrevRev := constr:(
  Iff_mpr
    (Membership_mem alpha (List alpha) (List_instMembership alpha) rev prevL)
    (Membership_mem alpha (List alpha) (List_instMembership alpha) l prevL)
    (List_mem_reverse alpha prevL l) hxPrev) in
pose proof (Iff_mpr _ _ (List_nodup_reverse alpha l) nodup) as nodupRev;
pose proof
  (List_next_reverse_eq_prev alpha decEq l nodup x hx) as hinner;
pose proof
  (List_prev_next alpha decEq rev nodupRev x hxRev) as hprevNext;
let nextRev :=
  lazymatch type of hinner with
  | Lean.eq ?lhs _ => lhs
  end in
let hnextMem :=
  lazymatch type of hprevNext with
  | Lean.eq (List_prev _ _ _ _ ?h) _ => h
  end in
pose proof
  (eq_mp_sprop
    (fun y => forall hy : Membership_mem alpha (List alpha)
      (List_instMembership alpha) rev y,
      Lean.eq
        (List_prev alpha decEq rev nextRev hnextMem)
        (List_prev alpha decEq rev y hy))
    hinner
    (fun hy => eq_refl (List_prev alpha decEq rev nextRev hnextMem)))
  as harg;
pose proof (harg hxPrevRev) as hargEq;
pose proof
  (List_prev_reverse_eq_next alpha decEq l nodup prevL hxPrev) as houter;
pose proof
  (Eq_trans alpha
    (List_next alpha decEq l prevL hxPrev)
    (List_prev alpha decEq rev prevL hxPrevRev)
    (List_prev alpha decEq rev nextRev hnextMem)
    (Eq_symm alpha _ _ houter)
    (Eq_symm alpha _ _ hargEq)) as htoBase;
exact
  (Eq_trans alpha
    (List_next alpha decEq l prevL hxPrev)
    (List_prev alpha decEq rev nextRev hnextMem)
    x htoBase hprevNext)
|}

let list_prev_next_tactic =
  {|
intros alpha decEq l nodup x hx;
pose proof (List_getElem_of_mem alpha x l hx) as hxElem;
destruct hxElem as [n hxElem];
destruct hxElem as [hn hxEq];
let len := constr:(List_length alpha l) in
let elem := constr:(
  GetElem_getElem_inst2 (List alpha) Nat alpha
    (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
    (List_instGetElemNatLtLength alpha) l n hn) in
assert (hcanonical : forall helem : Membership_mem alpha (List alpha)
  (List_instMembership alpha) l elem,
  Lean.eq
    (List_prev alpha decEq l
      (List_next alpha decEq l elem helem)
      (List_next_mem alpha decEq l elem helem))
    elem);
[ intro helem;
  let j := constr:(
    HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n 1)
      len) in
  let k := constr:(
    HMod_hMod_inst7 Nat Nat Nat (instHMod_inst1 Nat Nat_instMod)
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        j
        (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
          len 1))
      len) in
  pose proof
    (Nat_lt_of_le_of_lt Nat_zero n len (Nat_zero_le n) hn) as lpos;
  let hj := constr:(
    Nat_mod_lt
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n 1)
      len lpos) in
  pose proof
    (List_next_getElem alpha decEq l nodup n hn) as hnext;
  pose proof
    (List_prev_getElem alpha decEq l nodup j hj) as hprev;
  let elemJ :=
    lazymatch type of hnext with
    | Lean.eq _ ?rhs => rhs
    end in
  let elemJMem :=
    lazymatch type of hprev with
    | Lean.eq (List_prev _ _ _ _ ?h) _ => h
    end in
  let hk :=
    lazymatch type of hprev with
    | Lean.eq _ (GetElem_getElem_inst2 _ _ _ _ _ _ _ ?h) => h
    end in
  pose proof
    (eq_mp_sprop
      (fun y => forall hy : Membership_mem alpha (List alpha)
        (List_instMembership alpha) l y,
        Lean.eq
          (List_prev alpha decEq l
            (List_next alpha decEq l elem helem)
            (List_next_mem alpha decEq l elem helem))
          (List_prev alpha decEq l y hy))
      hnext
      (fun hy => eq_refl
        (List_prev alpha decEq l
          (List_next alpha decEq l elem helem)
          (List_next_mem alpha decEq l elem helem)))) as harg;
  pose proof (harg elemJMem) as hargEq;
  pose proof (Nat_succ_le_of_lt Nat_zero len lpos) as honele;
  pose proof (Nat_sub_add_cancel len 1 honele) as hsubadd;
  let rewrite_lean_eq h :=
    lazymatch type of h with
    | Lean.eq ?lhs ?rhs =>
      pattern lhs; eapply (eq_mpr_sprop _ h)
    end in
  assert (hsum : Lean.eq
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n 1)
      (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat) len 1))
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n len));
  [ rewrite_lean_eq
      (Nat_add_assoc n 1
        (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
          len 1));
    rewrite_lean_eq
      (Nat_add_comm 1
        (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
          len 1));
    rewrite_lean_eq hsubadd;
    reflexivity
  | ];
  assert (hindex : Lean.eq k n);
  [ rewrite_lean_eq
      (Nat_mod_add_mod
        (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat) n 1)
        len
        (HSub_hSub_inst7 Nat Nat Nat (instHSub_inst1 Nat instSubNat)
          len 1));
    rewrite_lean_eq hsum;
    rewrite_lean_eq (Nat_add_mod_right n len);
    exact (Nat_mod_eq_of_lt n len hn)
  | ];
  pose proof
    (eq_mp_sprop
      (fun idx => forall hidx : LT_lt_inst1 Nat instLTNat idx len,
        Lean.eq
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs i => LT_lt_inst1 Nat instLTNat i
              (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) l k hk)
          (GetElem_getElem_inst2 (List alpha) Nat alpha
            (fun xs i => LT_lt_inst1 Nat instLTNat i
              (List_length alpha xs))
            (List_instGetElemNatLtLength alpha) l idx hidx))
      hindex
      (fun hidx => eq_refl
        (GetElem_getElem_inst2 (List alpha) Nat alpha
          (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
          (List_instGetElemNatLtLength alpha) l k hk))) as hget;
  pose proof (hget hn) as hgetEq;
  pose proof
    (Eq_trans alpha
      (List_prev alpha decEq l
        (List_next alpha decEq l elem helem)
        (List_next_mem alpha decEq l elem helem))
      (List_prev alpha decEq l elemJ elemJMem)
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) l k hk)
      hargEq hprev) as htoIndex;
  exact
    (Eq_trans alpha
      (List_prev alpha decEq l
        (List_next alpha decEq l elem helem)
        (List_next_mem alpha decEq l elem helem))
      (GetElem_getElem_inst2 (List alpha) Nat alpha
        (fun xs i => LT_lt_inst1 Nat instLTNat i (List_length alpha xs))
        (List_instGetElemNatLtLength alpha) l k hk)
      elem htoIndex hgetEq)
| ];
pose proof
  (eq_mp_sprop
    (fun y => forall hy : Membership_mem alpha (List alpha)
      (List_instMembership alpha) l y,
      Lean.eq
        (List_prev alpha decEq l
          (List_next alpha decEq l y hy)
          (List_next_mem alpha decEq l y hy))
        y)
    hxEq hcanonical) as htransport;
exact (htransport hx)
|}

let cycle_prev_proof_1_tactic =
  {|
intros alpha decEq l1 l2 hrot;
let q1 := constr:(
  Quot.mk (Setoid_r (List alpha) (List_IsRotated_setoid alpha)) l1) in
let q2 := constr:(
  Quot.mk (Setoid_r (List alpha) (List_IsRotated_setoid alpha)) l2) in
let mem1 := constr:(fun z =>
  Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) q1 z) in
let mem2 := constr:(fun z =>
  Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) q2 z) in
eapply Function_hfunext_inst1;
[ exact
    (propext
      (Cycle_Nodup alpha q1)
      (Cycle_Nodup alpha q2)
      (List_IsRotated_nodup_iff alpha l1 l2 hrot))
| intros h1 h2 heN;
  eapply Function_hfunext;
  [ exact (eq_refl alpha)
  | intros x y hxy;
    pose proof
      (Iff_mp
        (HEq alpha x alpha y)
        (Lean.eq x y)
        (heq_iff_eq alpha x y)
        hxy) as hxyEq;
    pose proof
      (propext
        (mem1 x)
        (mem2 x)
        (List_IsRotated_mem_iff alpha l1 l2 hrot x)) as hmemX;
    pose proof
      (congrArg alpha SProp x y mem2 hxyEq) as hmemXY;
    pose proof
      (Eq_trans SProp (mem1 x) (mem2 x) (mem2 y) hmemX hmemXY)
      as hmem;
    eapply Function_hfunext_inst1;
    [ exact hmem
    | intros hm hm' heM;
      let mapped := constr:(
        Iff_mp
          (mem1 x)
          (mem2 x)
          (List_IsRotated_mem_iff alpha l1 l2 hrot x)
          hm) in
      pose proof
        (List_isRotated_prev_eq alpha decEq l1 l2 hrot h1 x hm)
        as hbase;
      pose proof
        (eq_mp_sprop
          (fun z => forall hz : mem2 z,
            Lean.eq
              (List_prev alpha decEq l2 x mapped)
              (List_prev alpha decEq l2 z hz))
          hxyEq
          (fun hz => eq_refl (List_prev alpha decEq l2 x mapped)))
        as harg;
      pose proof (harg hm') as hargEq;
      assert (hout : Lean.eq
        (List_prev alpha decEq l1 x hm)
        (List_prev alpha decEq l2 y hm'));
      [ eapply (eq_mpr_sprop
          (fun lhs => Lean.eq lhs (List_prev alpha decEq l2 y hm'))
          hbase);
        exact hargEq
      | ];
      exact (heq_of_eq alpha _ _ hout) ] ] ]
|}

let cycle_prev_tactic =
  {|
intros alpha decEq s;
exact
  (Quot_hrecOn
    (List alpha)
    (Setoid_r (List alpha) (List_IsRotated_setoid alpha))
    (fun q =>
      Cycle_Nodup alpha q ->
      forall x : alpha,
      Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) q x ->
      alpha)
    s
    (fun l _ x hx => List_prev alpha decEq l x hx)
    (Cycle_prev__proof_1 alpha decEq))
|}

let cycle_next_proof_1_tactic =
  {|
intros alpha decEq l1 l2 hrot;
let q1 := constr:(
  Quot.mk (Setoid_r (List alpha) (List_IsRotated_setoid alpha)) l1) in
let q2 := constr:(
  Quot.mk (Setoid_r (List alpha) (List_IsRotated_setoid alpha)) l2) in
let mem1 := constr:(fun z =>
  Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) q1 z) in
let mem2 := constr:(fun z =>
  Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) q2 z) in
eapply Function_hfunext_inst1;
[ exact
    (propext
      (Cycle_Nodup alpha q1)
      (Cycle_Nodup alpha q2)
      (List_IsRotated_nodup_iff alpha l1 l2 hrot))
| intros h1 h2 heN;
  eapply Function_hfunext;
  [ exact (eq_refl alpha)
  | intros x y hxy;
    pose proof
      (Iff_mp
        (HEq alpha x alpha y)
        (Lean.eq x y)
        (heq_iff_eq alpha x y)
        hxy) as hxyEq;
    pose proof
      (propext
        (mem1 x)
        (mem2 x)
        (List_IsRotated_mem_iff alpha l1 l2 hrot x)) as hmemX;
    pose proof
      (congrArg alpha SProp x y mem2 hxyEq) as hmemXY;
    pose proof
      (Eq_trans SProp (mem1 x) (mem2 x) (mem2 y) hmemX hmemXY)
      as hmem;
    eapply Function_hfunext_inst1;
    [ exact hmem
    | intros hm hm' heM;
      let mapped := constr:(
        Iff_mp
          (mem1 x)
          (mem2 x)
          (List_IsRotated_mem_iff alpha l1 l2 hrot x)
          hm) in
      pose proof
        (List_isRotated_next_eq alpha decEq l1 l2 hrot h1 x hm)
        as hbase;
      pose proof
        (eq_mp_sprop
          (fun z => forall hz : mem2 z,
            Lean.eq
              (List_next alpha decEq l2 x mapped)
              (List_next alpha decEq l2 z hz))
          hxyEq
          (fun hz => eq_refl (List_next alpha decEq l2 x mapped)))
        as harg;
      pose proof (harg hm') as hargEq;
      assert (hout : Lean.eq
        (List_next alpha decEq l1 x hm)
        (List_next alpha decEq l2 y hm'));
      [ eapply (eq_mpr_sprop
          (fun lhs => Lean.eq lhs (List_next alpha decEq l2 y hm'))
          hbase);
        exact hargEq
      | ];
      exact (heq_of_eq alpha _ _ hout) ] ] ]
|}

let cycle_next_tactic =
  {|
intros alpha decEq s;
exact
  (Quot_hrecOn
    (List alpha)
    (Setoid_r (List alpha) (List_IsRotated_setoid alpha))
    (fun q =>
      Cycle_Nodup alpha q ->
      forall x : alpha,
      Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) q x ->
      alpha)
    s
    (fun l _ x hx => List_next alpha decEq l x hx)
    (Cycle_next__proof_1 alpha decEq))
|}

let cycle_prev_reverse_eq_next_tactic =
  {|
intros alpha decEq s;
eapply
  (Quotient_inductionOn'
    (List alpha)
    (List_IsRotated_setoid alpha)
    (fun q =>
      forall (hs : Cycle_Nodup alpha q) (x : alpha)
        (hx : Membership_mem alpha (Cycle alpha)
          (Cycle_instMembership alpha) q x),
      Lean.eq
        (Cycle_prev alpha decEq (Cycle_reverse alpha q)
          (Iff_mpr
            (Cycle_Nodup alpha (Cycle_reverse alpha q))
            (Cycle_Nodup alpha q)
            (Cycle_nodup_reverse_iff alpha q) hs)
          x
          (Iff_mpr
            (Membership_mem alpha (Cycle alpha)
              (Cycle_instMembership alpha) (Cycle_reverse alpha q) x)
            (Membership_mem alpha (Cycle alpha)
              (Cycle_instMembership alpha) q x)
            (Cycle_mem_reverse_iff alpha x q) hx))
        (Cycle_next alpha decEq q hs x hx))
    s);
exact (List_prev_reverse_eq_next alpha decEq)
|}

let cycle_next_reverse_eq_prev_simp_1_1_tactic =
  {|
intros alpha decEq s hs x hx;
exact
  (Eq_symm alpha _ _
    (Cycle_prev_reverse_eq_next alpha decEq s hs x hx))
|}

let cycle_prev_congr_simp_tactic =
  {|
intros alpha decEq s s' hsEq hs x x' hxEq hx;
let rhsHs :=
  lazymatch goal with
  | |- Lean.eq _ (Cycle_prev _ _ _ ?h _ _) => h
  end in
let rhsHx :=
  lazymatch goal with
  | |- Lean.eq _ (Cycle_prev _ _ _ _ _ ?h) => h
  end in
let hxAtX' := constr:(
  eq_mp_sprop
    (fun y => Membership_mem alpha (Cycle alpha)
      (Cycle_instMembership alpha) s y)
    hxEq hx) in
pose proof
  (eq_mp_sprop
    (fun y => forall hy : Membership_mem alpha (Cycle alpha)
      (Cycle_instMembership alpha) s y,
      Lean.eq
        (Cycle_prev alpha decEq s hs x hx)
        (Cycle_prev alpha decEq s hs y hy))
    hxEq
    (fun hy => eq_refl (Cycle_prev alpha decEq s hs x hx)))
  as harg;
pose proof (harg hxAtX') as hargEq;
pose proof
  (eq_mp_sprop
    (fun q =>
      forall hq : Cycle_Nodup alpha q,
      forall hmem : Membership_mem alpha (Cycle alpha)
        (Cycle_instMembership alpha) q x',
      Lean.eq
        (Cycle_prev alpha decEq s hs x' hxAtX')
        (Cycle_prev alpha decEq q hq x' hmem))
    hsEq
    (fun hq hmem =>
      eq_refl (Cycle_prev alpha decEq s hs x' hxAtX')))
  as hcycle;
pose proof (hcycle rhsHs rhsHx) as hcycleEq;
exact
  (Eq_trans alpha
    (Cycle_prev alpha decEq s hs x hx)
    (Cycle_prev alpha decEq s hs x' hxAtX')
    (Cycle_prev alpha decEq s' rhsHs x' rhsHx)
    hargEq hcycleEq)
|}

let cycle_next_reverse_eq_prev_tactic =
  {|
intros alpha decEq s hs x hx;
let rev := constr:(Cycle_reverse alpha s) in
let revrev := constr:(Cycle_reverse alpha rev) in
let hsRev := constr:(
  Iff_mpr
    (Cycle_Nodup alpha rev)
    (Cycle_Nodup alpha s)
    (Cycle_nodup_reverse_iff alpha s) hs) in
let hxRev := constr:(
  Iff_mpr
    (Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) rev x)
    (Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) s x)
    (Cycle_mem_reverse_iff alpha x s) hx) in
pose proof
  (_private_Mathlib_Data_List_Cycle0_Cycle_next_reverse_eq_prev__simp_1_1
    alpha decEq rev hsRev x hxRev) as hbase;
let hsRevRev :=
  lazymatch type of hbase with
  | Lean.eq _ (Cycle_prev _ _ _ ?h _ _) => h
  end in
let hxRevRev :=
  lazymatch type of hbase with
  | Lean.eq _ (Cycle_prev _ _ _ _ _ ?h) => h
  end in
pose proof
  (Cycle_prev_congr_simp alpha decEq
    revrev s (Cycle_reverse_reverse alpha s)
    hsRevRev x x (eq_refl x) hxRevRev) as hreverse;
exact
  (Eq_trans alpha
    (Cycle_next alpha decEq rev hsRev x hxRev)
    (Cycle_prev alpha decEq revrev hsRevRev x hxRevRev)
    (Cycle_prev alpha decEq s hs x hx)
    hbase hreverse)
|}

let cycle_next_mem_tactic =
  {|
intros alpha decEq s hs x hx;
eapply
  (Quotient_inductionOn
    (List alpha)
    (List_IsRotated_setoid alpha)
    (fun q =>
      forall hs0 : Cycle_Nodup alpha q,
      forall hx0 : Membership_mem alpha (Cycle alpha)
        (Cycle_instMembership alpha) q x,
      Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) q
        (Cycle_next alpha decEq q hs0 x hx0))
    s);
intros l hl hx0;
exact (List_next_mem alpha decEq l x hx0)
|}

let cycle_prev_mem_tactic =
  {|
intros alpha decEq s hs x hx;
let rev := constr:(Cycle_reverse alpha s) in
let hsRev := constr:(
  Iff_mpr
    (Cycle_Nodup alpha rev)
    (Cycle_Nodup alpha s)
    (Cycle_nodup_reverse_iff alpha s) hs) in
let hxRev := constr:(
  Iff_mpr
    (Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) rev x)
    (Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha) s x)
    (Cycle_mem_reverse_iff alpha x s) hx) in
let nextRev := constr:(Cycle_next alpha decEq rev hsRev x hxRev) in
pose proof (Cycle_next_mem alpha decEq rev hsRev x hxRev) as hnextRev;
pose proof
  (Iff_mp
    (Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha)
      rev nextRev)
    (Membership_mem alpha (Cycle alpha) (Cycle_instMembership alpha)
      s nextRev)
    (Cycle_mem_reverse_iff alpha nextRev s)
    hnextRev) as hnext;
pose proof (Cycle_next_reverse_eq_prev alpha decEq s hs x hx) as heq;
exact
  (eq_mp_sprop
    (fun z => Membership_mem alpha (Cycle alpha)
      (Cycle_instMembership alpha) s z)
    heq hnext)
|}

let cycle_next_prev_tactic =
  {|
intros alpha decEq s;
eapply
  (Quotient_inductionOn'
    (List alpha)
    (List_IsRotated_setoid alpha)
    (fun q =>
      forall (hs : Cycle_Nodup alpha q) (x : alpha)
        (hx : Membership_mem alpha (Cycle alpha)
          (Cycle_instMembership alpha) q x),
      Lean.eq
        (Cycle_next alpha decEq q hs
          (Cycle_prev alpha decEq q hs x hx)
          (Cycle_prev_mem alpha decEq q hs x hx))
        x)
    s);
exact (List_next_prev alpha decEq)
|}

let list_succ_idx_of_mem_drop_last_proof_1_1_tactic =
  {|
intros alpha beq lawful l a ha hidx;
let rewrite_lean_eq_rev h :=
  lazymatch type of h with
  | Lean.eq ?lhs ?rhs =>
    pattern rhs; eapply (eq_mp_sprop _ h)
  end in
pose proof
  (List_IsPrefix_idxOf_eq_of_mem
    alpha (List_dropLast alpha l) l beq lawful
    (List_dropLast_prefix alpha l) a ha) as hidxeq;
pose proof (List_length_dropLast alpha l) as hlen;
apply
  (Iff_mp _ _
    (Nat_lt_sub_iff_add_lt
      (List_idxOf alpha beq a l) 1 (List_length alpha l)));
rewrite_lean_eq_rev hidxeq;
rewrite_lean_eq_rev hlen;
exact hidx
|}

let nanosecond_offset_scale_proof_1_tactic_template =
  {|
let rewrite_lean_eq h :=
  lazymatch type of h with
  | Lean.eq ?a ?b =>
    pattern a; eapply (eq_mpr_sprop _ h)
  end in
let force_inv_positive Hforce Hpos :=
  unfold Rat_inv; cbn;
  lazymatch goal with
  | |- @Lean.eq Rat (dite Rat ?P ?d ?yes ?no) ?rhs =>
      refine
        (eq_mpr_sprop
          (fun d' => @Lean.eq Rat (dite Rat P d' yes no) rhs)
          (Hforce P d Hpos) _);
      reflexivity
  end
in
unfold HDiv_hDiv_inst7, instHDiv_inst1, Rat_instDiv, Div_div_inst1;
cbn [hDiv0 div0];
set (big := (3600000000000 : Nat)) in *;
set (small := (1000000000 : Nat)) in *;
assert (Hbigpos : Int_le (Int_ofNat 1) (Int_ofNat big));
[ unfold big, Nat_of_num_uint;
  refine
    (Iff_mpr _ _
      (Int_ofNat_lt Nat_zero (Nat_of_N 3600000000000%N)) _);
  exact (Nat_lt_to_N_l Nat_zero 3600000000000%N Logic.eq_refl)
| ];
assert (Hsmallpos : Int_le (Int_ofNat 1) (Int_ofNat small));
[ unfold small, Nat_of_num_uint;
  refine
    (Iff_mpr _ _
      (Int_ofNat_lt Nat_zero (Nat_of_N 1000000000%N)) _);
  exact (Nat_lt_to_N_l Nat_zero 1000000000%N Logic.eq_refl)
| ];
assert (HsmallNatPos : LT_lt_inst1 Nat instLTNat 0 small);
[ unfold small, Nat_of_num_uint;
  exact (Nat_lt_to_N_l Nat_zero 1000000000%N Logic.eq_refl)
| ];
assert
  (Hforce : forall (P : SProp) (d : Decidable P) (h : P),
    @Lean.eq (Decidable P) d (Decidable_isTrue P h));
[ intros P d h; destruct d as [hn | hp];
  [ destruct (hn h) | reflexivity ]
| ];
assert
  (HnatAbsOfNat : forall n : Nat,
    @Lean.eq Nat (Int_natAbs (Int_ofNat n)) n);
[ intro n; reflexivity
| ];
assert
  (HRatExt : forall a b : Rat,
    @Lean.eq Int (Rat_num a) (Rat_num b) ->
    @Lean.eq Nat (Rat_den a) (Rat_den b) ->
    @Lean.eq Rat a b);
[ intros [an ad anz ar] [bn bd bnz br]; cbn;
  intros Hn Hd; destruct Hn; destruct Hd; reflexivity
| ];
assert
  (HRatDivCongr : forall a a' b b' : Rat,
    @Lean.eq Rat a a' -> @Lean.eq Rat b b' ->
    @Lean.eq Rat (Rat_div a b) (Rat_div a' b'));
[ intros a a' b b' ha hb;
  exact
    (Eq_trans Rat _ _ _
      (congrArg Rat Rat a a' (fun x => Rat_div x b) ha)
      (congrArg Rat Rat b b' (fun y => Rat_div a' y) hb))
| ];
assert
  (HnumMul : forall a b : Rat,
    @Lean.eq Int (Rat_num (Rat_mul a b))
      (HMul_hMul_inst7 Int Int Int (instHMul_inst1 Int Int_instMul)
        (Int_tdiv (Rat_num a)
          (Nat_cast_inst1 Int instNatCastInt
            (Nat_gcd (Int_natAbs (Rat_num a)) (Rat_den b))))
        (Int_tdiv (Rat_num b)
          (Nat_cast_inst1 Int instNatCastInt
            (Nat_gcd (Int_natAbs (Rat_num b)) (Rat_den a))))));
[ intros a b; unfold Rat_mul;
  cbv [Rat_num];
  cbn [num];
  rewrite_lean_eq
    (Int_divExact_eq_tdiv (num a)
      (Nat_cast_inst1 Int instNatCastInt
        (Nat_gcd (Int_natAbs (num a)) (Rat_den b)))
      (Rat_mul__proof_1 a b));
  rewrite_lean_eq
    (Int_divExact_eq_tdiv (num b)
      (Nat_cast_inst1 Int instNatCastInt
        (Nat_gcd (Int_natAbs (num b)) (Rat_den a)))
      (Rat_mul__proof_2 a b));
  reflexivity
| ];
assert
  (HdenMul : forall a b : Rat,
    @Lean.eq Nat (Rat_den (Rat_mul a b))
      (HMul_hMul_inst7 Nat Nat Nat (instHMul_inst1 Nat instMulNat)
        (HDiv_hDiv_inst7 Nat Nat Nat (instHDiv_inst1 Nat Nat_instDiv)
          (Rat_den a)
          (Nat_gcd (Int_natAbs (Rat_num b)) (Rat_den a)))
        (HDiv_hDiv_inst7 Nat Nat Nat (instHDiv_inst1 Nat Nat_instDiv)
          (Rat_den b)
          (Nat_gcd (Int_natAbs (Rat_num a)) (Rat_den b)))));
[ intros a b; unfold Rat_mul, Nat_divExact;
  cbv [Rat_den];
  cbn [den];
  reflexivity
| ];
assert
  (HIntTdivCongr : forall (n a b : Nat), @Lean.eq Nat a b ->
    @Lean.eq Int
      (Int_tdiv (Int_ofNat n) (Int_ofNat a))
      (Int_tdiv (Int_ofNat n) (Int_ofNat b)));
[ intros n a b h;
  exact
    (congrArg Nat Int
      a b (fun d => Int_tdiv (Int_ofNat n) (Int_ofNat d)) h)
| ];
assert
  (HIntMulCongr : forall a a' b b' : Int,
    @Lean.eq Int a a' -> @Lean.eq Int b b' ->
    @Lean.eq Int (Int_mul a b) (Int_mul a' b'));
[ intros a a' b b' ha hb;
  exact
    (Eq_trans Int _ _ _
      (congrArg Int Int a a' (fun x => Int_mul x b) ha)
      (congrArg Int Int b b' (fun y => Int_mul a' y) hb))
| ];
assert
  (HinvPos : forall (n : Nat) (h : Int_le (Int_ofNat 1) (Int_ofNat n)),
    @Lean.eq Rat (Rat_inv (Rat_ofInt (Int_ofNat n)))
      (Rat_mk' (Int_ofNat 1) n
        (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat n)) h)
        (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat n)))));
[ intros n h; force_inv_positive Hforce h
| ];
assert
  (HNatInj : forall a b : Nat,
    Logic.eq (nat_of_Nat a) (nat_of_Nat b) -> Logic.eq a b);
[ intros a b h;
  rewrite <- (Nat2natid a), <- (Nat2natid b);
  f_equal; exact h
| ];
assert
  (HsuccN : forall (x : Nat) (n : N),
    @Lean.eq Nat x (Nat_of_N n) ->
    @Lean.eq Nat (Nat_succ x) (Nat_of_N (N.succ n)));
[ intros x n h;
  refine
    (Eq_trans Nat _ _ _
      (congrArg Nat Nat x (Nat_of_N n) Nat_succ h) _);
  apply lean_eq_of_logic_eq;
  apply HNatInj;
  cbn [nat_of_Nat];
  unfold Nat_of_N;
  rewrite !nat2Natid, N2Nat.inj_succ;
  reflexivity
| ];
assert
  (HdoubleN : forall (x : Nat) (n : N),
    @Lean.eq Nat x (Nat_of_N n) ->
    @Lean.eq Nat (double x) (Nat_of_N (N.double n)));
[ intros x n h;
  refine
    (Eq_trans Nat _ _ _
      (congrArg Nat Nat x (Nat_of_N n) double h) _);
  apply lean_eq_of_logic_eq;
  apply HNatInj;
  rewrite nat_of_Nat_double;
  unfold Nat_of_N;
  rewrite !nat2Natid, N2Nat.inj_double;
  reflexivity
| ];
assert
  (Hmulmap : forall a b : N,
    Logic.eq (Nat_mul (Nat_of_N a) (Nat_of_N b)) (Nat_of_N (a * b)));
[ intros a b; apply HNatInj;
  rewrite nat_of_Nat_mul;
  unfold Nat_of_N;
  rewrite !nat2Natid, N2Nat.inj_mul;
  reflexivity
| ];
assert (H3600 : @Lean.eq Nat 3600 (Nat_of_N 3600%N));
[ apply lean_eq_of_logic_eq;
  apply HNatInj;
  unfold Nat_of_N;
  rewrite nat2Natid;
  apply Nat2N.inj;
  vm_compute; reflexivity
| ];
UNIT_SMALL_CANONICALIZATION
assert (HbigMul : @Lean.eq Nat big (Nat_mul small 3600));
[ rewrite_lean_eq H3600;
  UNIT_SMALL_REWRITE
  apply lean_eq_of_logic_eq;
  unfold big, small, Nat_of_num_uint;
  rewrite Hmulmap;
  apply f_equal;
  vm_compute; reflexivity
| ];
assert
  (HGcdFactor : forall n : Nat,
    @Lean.eq Nat
      (Nat_gcd (Nat_mul 1 3600) (Nat_mul n 3600))
      (Nat_mul 1 3600));
[ intro n;
  refine
    (Eq_trans Nat _ _ _ (Nat_gcd_mul_right 1 3600 n) _);
  rewrite_lean_eq (Nat_gcd_one_left n);
  reflexivity
| ];
assert (Hgcd : @Lean.eq Nat (Nat_gcd 3600 big) 3600);
[ rewrite_lean_eq HbigMul;
  exact (HGcdFactor small)
| ];
assert
  (Hfactorpos : LT_lt_inst1 Nat instLTNat 0 3600);
[ refine
    (eq_mpr_sprop
      (fun n => LT_lt_inst1 Nat instLTNat 0 n) H3600 _);
  exact (Nat_lt_to_N_l Nat_zero 3600%N Logic.eq_refl)
| ];
assert
  (Hscale : forall (sm bg : Nat)
    (hbgpos : Int_le (Int_ofNat 1) (Int_ofNat bg))
    (hsmpos : Int_le (Int_ofNat 1) (Int_ofNat sm))
    (hbg : @Lean.eq Nat bg (Nat_mul sm 3600))
    (hg : @Lean.eq Nat (Nat_gcd 3600 bg) 3600),
    @Lean.eq Rat
      (Rat_div (Rat_ofInt (Int_ofNat 3600))
        (Rat_ofInt (Int_ofNat bg)))
      (Rat_div (Rat_ofInt (Int_ofNat 1))
        (Rat_ofInt (Int_ofNat sm))));
[ intros sm bg hbgpos hsmpos hbg hg;
  unfold Rat_div;
  unfold HMul_hMul_inst7, instHMul_inst1, Rat_instMul, Mul_mul_inst1;
  cbn [hMul0 mul0];
  rewrite_lean_eq (HinvPos bg hbgpos);
  rewrite_lean_eq (HinvPos sm hsmpos);
  apply HRatExt;
  [ refine
      (Eq_trans Int _ _ _
        (HnumMul (Rat_ofInt (Int_ofNat 3600))
          (Rat_mk' (Int_ofNat 1) bg
            (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat bg)) hbgpos)
            (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat bg))))) _);
    refine
      (Eq_trans Int _ _ _ _
        (Eq_symm Int _ _
          (HnumMul (Rat_ofInt (Int_ofNat 1))
            (Rat_mk' (Int_ofNat 1) sm
              (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat sm)) hsmpos)
              (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat sm)))))));
    unfold Rat_ofInt;
    cbv [Rat_num Rat_den];
    cbn [num den];
    cbv [Int_natAbs Int_neg_match_1 Int_casesOn Int_recl];
    change
      (@Lean.eq Int
        (Int_mul
          (Int_tdiv (Int_ofNat 3600)
            (Int_ofNat (Nat_gcd 3600 bg)))
          (Int_tdiv (Int_ofNat 1)
            (Int_ofNat (Nat_gcd 1 1))))
        (Int_mul
          (Int_tdiv (Int_ofNat 1)
            (Int_ofNat (Nat_gcd 1 sm)))
          (Int_tdiv (Int_ofNat 1)
            (Int_ofNat (Nat_gcd 1 1)))));
    refine
      (Eq_trans Int _ _ _
        (HIntMulCongr _ _ _ _
          (HIntTdivCongr 3600 _ _ hg)
          (HIntTdivCongr 1 _ _ (Nat_gcd_one_left 1))) _);
    exact
      (Eq_symm Int _ _
        (HIntMulCongr _ _ _ _
          (HIntTdivCongr 1 _ _ (Nat_gcd_one_left sm))
          (HIntTdivCongr 1 _ _ (Nat_gcd_one_left 1))))
  | refine
      (Eq_trans Nat _ _ _
        (HdenMul (Rat_ofInt (Int_ofNat 3600))
          (Rat_mk' (Int_ofNat 1) bg
            (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat bg)) hbgpos)
            (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat bg))))) _);
    refine
      (Eq_trans Nat _ _ _ _
        (Eq_symm Nat _ _
          (HdenMul (Rat_ofInt (Int_ofNat 1))
            (Rat_mk' (Int_ofNat 1) sm
              (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat sm)) hsmpos)
              (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat sm)))))));
    unfold Rat_ofInt;
    cbv [Rat_num Rat_den];
    cbn [num den];
    rewrite_lean_eq (HnatAbsOfNat 3600);
    rewrite_lean_eq (HnatAbsOfNat 1);
    rewrite_lean_eq hg;
    rewrite_lean_eq (Nat_gcd_one_left sm);
    rewrite_lean_eq (Nat_gcd_one_left 1);
    assert
      (HbgLeft : @Lean.eq Nat bg
        (HMul_hMul_inst7 Nat Nat Nat (instHMul_inst1 Nat instMulNat)
          3600 sm));
    [ exact
        (Eq_trans Nat _ _ _ hbg (Nat_mul_comm sm 3600))
    | ];
    assert
      (HdivBg :
        @Lean.eq Nat
          (HDiv_hDiv_inst7 Nat Nat Nat
            (instHDiv_inst1 Nat Nat_instDiv) bg 3600)
          sm);
    [ exact
        (Eq_trans Nat _ _ _
          (congrArg Nat Nat bg
            (HMul_hMul_inst7 Nat Nat Nat
              (instHMul_inst1 Nat instMulNat) 3600 sm)
            (fun n => HDiv_hDiv_inst7 Nat Nat Nat
              (instHDiv_inst1 Nat Nat_instDiv) n 3600)
            HbgLeft)
          (Nat_mul_div_right sm 3600 Hfactorpos))
    | ];
    assert
      (HdivOne : forall n : Nat,
        @Lean.eq Nat
          (HDiv_hDiv_inst7 Nat Nat Nat
            (instHDiv_inst1 Nat Nat_instDiv) n 1)
          n);
    [ intro n;
      exact
        (Eq_trans Nat _ _ _
          (congrArg Nat Nat n
            (HMul_hMul_inst7 Nat Nat Nat
              (instHMul_inst1 Nat instMulNat) 1 n)
            (fun x => HDiv_hDiv_inst7 Nat Nat Nat
              (instHDiv_inst1 Nat Nat_instDiv) x 1)
            (Eq_symm Nat _ _ (Nat_one_mul n)))
          (Nat_mul_div_right n 1 (Nat_zero_lt_succ 0)))
    | ];
    apply
      (congrArg Nat Nat
        (HDiv_hDiv_inst7 Nat Nat Nat
          (instHDiv_inst1 Nat Nat_instDiv) bg 3600)
        (HDiv_hDiv_inst7 Nat Nat Nat
          (instHDiv_inst1 Nat Nat_instDiv) sm 1)
        (fun x => HMul_hMul_inst7 Nat Nat Nat
          (instHMul_inst1 Nat instMulNat)
          (HDiv_hDiv_inst7 Nat Nat Nat
            (instHDiv_inst1 Nat Nat_instDiv) 1 1) x));
    exact
      (Eq_trans Nat _ _ _ HdivBg
        (Eq_symm Nat _ _ (HdivOne sm))) ]
| ];
assert
  (HNatDivOne : forall n : Nat,
    @Lean.eq Nat
      (HDiv_hDiv_inst7 Nat Nat Nat
        (instHDiv_inst1 Nat Nat_instDiv) n 1)
      n);
[ intro n;
  exact
    (Eq_trans Nat _ _ _
      (congrArg Nat Nat n
        (HMul_hMul_inst7 Nat Nat Nat
          (instHMul_inst1 Nat instMulNat) 1 n)
        (fun y => HDiv_hDiv_inst7 Nat Nat Nat
          (instHDiv_inst1 Nat Nat_instDiv) y 1)
        (Eq_symm Nat _ _ (Nat_one_mul n)))
      (Nat_mul_div_right n 1 (Nat_zero_lt_succ 0)))
| ];
assert
  (HIntTdivOne : forall z : Int,
    @Lean.eq Int (Int_tdiv z (Int_ofNat 1)) z);
[ intros [n | n]; cbn [Int_tdiv];
  [ exact
      (congrArg Nat Int
        (HDiv_hDiv_inst7 Nat Nat Nat
          (instHDiv_inst1 Nat Nat_instDiv) n 1)
        n Int_ofNat (HNatDivOne n))
  | refine
      (Eq_trans Int _ _ _
        (congrArg Nat Int
          (HDiv_hDiv_inst7 Nat Nat Nat
            (instHDiv_inst1 Nat Nat_instDiv) (Nat_succ n) 1)
          (Nat_succ n) Int_negOfNat (HNatDivOne (Nat_succ n))) _);
    reflexivity ]
| ];
assert
  (HRatOneMul : forall x : Rat,
    @Lean.eq Rat (Rat_mul (Rat_ofInt (Int_ofNat 1)) x) x);
[ intros [xn xd xnz xr];
  apply HRatExt;
  [ refine
      (Eq_trans Int _ _ _
        (HnumMul (Rat_ofInt (Int_ofNat 1))
          (Rat_mk' xn xd xnz xr)) _);
    unfold Rat_ofInt;
    cbv [Rat_num Rat_den]; cbn [num den];
    repeat rewrite_lean_eq (HnatAbsOfNat 1);
    repeat rewrite_lean_eq (Nat_gcd_one_left 1);
    repeat rewrite_lean_eq (Nat_gcd_one_left xd);
    repeat rewrite_lean_eq (Nat_gcd_one_right (Int_natAbs xn));
    assert
      (HIntNatCastOne : @Lean.eq Int
        (Nat_cast_inst1 Int instNatCastInt 1) (Int_ofNat 1))
      by reflexivity;
    repeat rewrite_lean_eq HIntNatCastOne;
    repeat rewrite_lean_eq (HIntTdivOne (Int_ofNat 1));
    repeat rewrite_lean_eq (HIntTdivOne xn);
    exact (Int_one_mul xn)
  | refine
      (Eq_trans Nat _ _ _
        (HdenMul (Rat_ofInt (Int_ofNat 1))
          (Rat_mk' xn xd xnz xr)) _);
    unfold Rat_ofInt;
    cbv [Rat_num Rat_den]; cbn [num den];
    repeat rewrite_lean_eq (HnatAbsOfNat 1);
    repeat rewrite_lean_eq (Nat_gcd_one_left xd);
    repeat rewrite_lean_eq (Nat_gcd_one_right (Int_natAbs xn));
    repeat rewrite_lean_eq (HNatDivOne 1);
    repeat rewrite_lean_eq (HNatDivOne xd);
    exact (Nat_one_mul xd) ]
| ];
assert
  (HRatOfNatMul : forall x y : Nat,
    @Lean.eq Rat
      (Rat_mul (Rat_ofInt (Int_ofNat x)) (Rat_ofInt (Int_ofNat y)))
      (Rat_ofInt (Int_ofNat (Nat_mul x y))));
[ intros x y;
  apply HRatExt;
  [ refine
      (Eq_trans Int _ _ _
        (HnumMul (Rat_ofInt (Int_ofNat x))
          (Rat_ofInt (Int_ofNat y))) _);
    unfold Rat_ofInt;
    cbv [Rat_num Rat_den]; cbn [num den];
    repeat rewrite_lean_eq (HnatAbsOfNat x);
    repeat rewrite_lean_eq (HnatAbsOfNat y);
    repeat rewrite_lean_eq (Nat_gcd_one_right x);
    repeat rewrite_lean_eq (Nat_gcd_one_right y);
    assert
      (HIntNatCastOne : @Lean.eq Int
        (Nat_cast_inst1 Int instNatCastInt 1) (Int_ofNat 1))
      by reflexivity;
    repeat rewrite_lean_eq HIntNatCastOne;
    repeat rewrite_lean_eq (HIntTdivOne (Int_ofNat x));
    repeat rewrite_lean_eq (HIntTdivOne (Int_ofNat y));
    reflexivity
  | refine
      (Eq_trans Nat _ _ _
        (HdenMul (Rat_ofInt (Int_ofNat x))
          (Rat_ofInt (Int_ofNat y))) _);
    unfold Rat_ofInt;
    cbv [Rat_num Rat_den]; cbn [num den];
    repeat rewrite_lean_eq (HnatAbsOfNat x);
    repeat rewrite_lean_eq (HnatAbsOfNat y);
    repeat rewrite_lean_eq (Nat_gcd_one_right x);
    repeat rewrite_lean_eq (Nat_gcd_one_right y);
    repeat rewrite_lean_eq (HNatDivOne 1);
    reflexivity ]
| ];
let rec compact_nat t k :=
  lazymatch t with
  | Nat_zero =>
      let h := fresh "Hcompact" in
      assert (h : @Lean.eq Nat t (Nat_of_N 0%N));
      [ reflexivity | k h ]
  | Nat_succ ?u =>
      compact_nat u ltac:(fun hu =>
        lazymatch type of hu with
        | @Lean.eq Nat _ (Nat_of_N ?nu) =>
            let h := fresh "Hcompact" in
            assert
              (h : @Lean.eq Nat t (Nat_of_N (N.succ nu)));
            [ exact (HsuccN u nu hu) | k h ]
        end)
  | double ?u =>
      compact_nat u ltac:(fun hu =>
        lazymatch type of hu with
        | @Lean.eq Nat _ (Nat_of_N ?nu) =>
            let h := fresh "Hcompact" in
            assert
              (h : @Lean.eq Nat t (Nat_of_N (N.double nu)));
            [ exact (HdoubleN u nu hu) | k h ]
        end)
  end in
lazymatch goal with
| |- @Lean.eq Rat (Rat_div ?a ?b) (Rat_div ?c ?d) =>
    assert
      (Ha : @Lean.eq Rat a (Rat_ofInt (Int_ofNat 3600)));
    [ UNIT_HA_PROOF
    | ];
    assert (Hb : @Lean.eq Rat b (Rat_ofInt (Int_ofNat big)));
    [ lazymatch b with
      | Int_cast_inst1 Rat Rat_instIntCast ?bi =>
          lazymatch bi with
          | OfNat_ofNat_inst1 Int ?bn ?binst =>
              assert (Hbn : @Lean.eq Nat bn big);
              [ compact_nat bn ltac:(fun hcompact =>
                  refine (Eq_trans Nat _ _ _ hcompact _);
                  unfold big, Nat_of_num_uint;
                  apply congrArg;
                  apply lean_eq_of_logic_eq;
                  vm_compute; reflexivity)
              | ];
              assert
                (Hbi : @Lean.eq Int bi (Int_ofNat big));
              [ refine
                  (Eq_trans Int _ _ _ _
                    (congrArg Nat Int bn big Int_ofNat Hbn));
                reflexivity
              | ];
              refine
                (Eq_trans Rat _ _ _
                  (congrArg Int Rat bi (Int_ofNat big)
                    (fun z => Int_cast_inst1 Rat Rat_instIntCast z) Hbi) _);
              reflexivity
          end
      end
    | ];
    assert
      (Hc : @Lean.eq Rat c (Rat_ofInt (Int_ofNat 1))) by reflexivity;
    assert (Hd : @Lean.eq Rat d (Rat_ofInt (Int_ofNat small)));
    [ lazymatch d with
      | OfNat_ofNat_inst1 Rat ?dn ?dinst =>
          assert (Hdn : @Lean.eq Nat dn small);
          [ UNIT_SMALL_HDN
          | ];
          refine
            (Eq_trans Rat _ _ _ _
              (congrArg Nat Rat dn small
                (fun n => Rat_ofInt (Int_ofNat n)) Hdn));
          reflexivity
      end
    | ];
    refine
      (Eq_trans Rat _ _ _
        (HRatDivCongr a (Rat_ofInt (Int_ofNat 3600))
          b (Rat_ofInt (Int_ofNat big)) Ha Hb) _);
    refine
      (Eq_trans Rat _ _ _
        (Hscale small big Hbigpos Hsmallpos HbigMul Hgcd) _);
    exact
      (Eq_symm Rat _ _
        (HRatDivCongr c (Rat_ofInt (Int_ofNat 1))
          d (Rat_ofInt (Int_ofNat small)) Hc Hd))
UNIT_EXTRA_GOAL_CLAUSE
end
|}

let replace_all text pattern replacement =
  let text_len = String.length text in
  let pattern_len = String.length pattern in
  if pattern_len = 0 then invalid_arg "replace_all: empty pattern";
  let buffer = Buffer.create text_len in
  let rec copy_from i =
    if i > text_len - pattern_len then
      Buffer.add_substring buffer text i (text_len - i)
    else if String.sub text i pattern_len = pattern then (
      Buffer.add_string buffer replacement;
      copy_from (i + pattern_len))
    else (
      Buffer.add_char buffer text.[i];
      copy_from (i + 1))
  in
  copy_from 0;
  Buffer.contents buffer

let unit_offset_scale_proof_1_tactic ~extra_goal_clause ~ha_proof ~scale ~big
    ~small ~canonicalize_small =
  let small_canonicalization =
    if canonicalize_small then
      {|
assert (HsmallN : @Lean.eq Nat small (Nat_of_N 1000000000%N));
[ unfold small, Nat_of_num_uint;
  apply lean_eq_of_logic_eq;
  apply HNatInj;
  unfold Nat_of_N;
  rewrite nat2Natid;
  apply Nat2N.inj;
  vm_compute; reflexivity
| ];
|}
    else ""
  in
  nanosecond_offset_scale_proof_1_tactic_template
  |> fun tactic ->
  replace_all tactic "UNIT_SMALL_CANONICALIZATION" small_canonicalization
  |> fun tactic ->
  replace_all tactic "UNIT_SMALL_REWRITE"
    (if canonicalize_small then "rewrite_lean_eq HsmallN;" else "")
  |> fun tactic ->
  replace_all tactic "UNIT_EXTRA_GOAL_CLAUSE" extra_goal_clause
  |> fun tactic ->
  replace_all tactic "UNIT_SMALL_HDN"
    (if canonicalize_small then "reflexivity"
     else
       {|
compact_nat dn ltac:(fun hcompact =>
  refine (Eq_trans Nat _ _ _ hcompact _);
  unfold small, Nat_of_num_uint;
  apply congrArg;
  apply lean_eq_of_logic_eq;
  vm_compute; reflexivity)
|})
  |> fun tactic -> replace_all tactic "UNIT_HA_PROOF" ha_proof
  |> fun tactic -> replace_all tactic "3600000000000" big
  |> fun tactic -> replace_all tactic "1000000000" small
  |> fun tactic -> replace_all tactic "3600" scale

let week_offset_scale_extra_clause =
  {|
| |- @Lean.eq Rat
      (HMul_hMul_inst7 Rat Rat Rat (instHMul_inst1 Rat Rat_instMul)
        ?leftFactor ?b)
      (HMul_hMul_inst7 Rat Rat Rat (instHMul_inst1 Rat Rat_instMul)
        ?p ?q) =>
    assert
      (HleftDiv : @Lean.eq Rat leftFactor
        (Rat_div (Rat_ofInt (Int_ofNat 1))
          (Rat_ofInt (Int_ofNat small))));
    [ lazymatch leftFactor with
      | Rat_div ?ln ?ld =>
        assert (Hln : @Lean.eq Rat ln (Rat_ofInt (Int_ofNat 1)))
          by reflexivity;
        assert (Hld : @Lean.eq Rat ld (Rat_ofInt (Int_ofNat small)));
        [ lazymatch ld with
          | OfNat_ofNat_inst1 Rat ?dn ?dinst =>
            assert (Hdn : @Lean.eq Nat dn small);
            [ UNIT_SMALL_HDN
            | ];
            refine
              (Eq_trans Rat _ _ _
                (congrArg Nat Rat dn small
                  (fun n => Rat_ofInt (Int_ofNat n)) Hdn) _);
            reflexivity
          end
        | ];
        refine
          (HRatDivCongr ln (Rat_ofInt (Int_ofNat 1))
            ld (Rat_ofInt (Int_ofNat small)) Hln Hld)
      end
    | ];
    assert
      (HleftCanonical : @Lean.eq Rat
        (Rat_div (Rat_ofInt (Int_ofNat 1))
          (Rat_ofInt (Int_ofNat small)))
        (Rat_mk' (Int_ofNat 1) small
          (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat small)) Hsmallpos)
          (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat small)))));
    [ assert
        (HinvOfNat : @Lean.eq Rat
          (Rat_inv (Rat_ofInt (Int_ofNat small)))
          (Rat_mk' (Int_ofNat 1) small
            (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat small)) Hsmallpos)
            (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat small)))));
      [ exact (HinvPos small Hsmallpos)
      | ];
      unfold Rat_div;
      rewrite_lean_eq HinvOfNat;
      unfold HMul_hMul_inst7, instHMul_inst1, Rat_instMul, Mul_mul_inst1;
      cbn [hMul0 mul0];
      exact (HRatOneMul _)
    | ];
    assert
      (Hleft : @Lean.eq Rat leftFactor
        (Rat_mk' (Int_ofNat 1) small
          (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat small)) Hsmallpos)
          (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat small)))));
    [ exact (Eq_trans Rat _ _ _ HleftDiv HleftCanonical)
    | ];
    rewrite_lean_eq Hleft;
    assert
      (HinvMulScale : forall (sm bg : Nat)
        (hsmpos : Int_le (Int_ofNat 1) (Int_ofNat sm))
        (hsmNatPos : LT_lt_inst1 Nat instLTNat 0 sm)
        (hbg : @Lean.eq Nat bg (Nat_mul sm 604800)),
        @Lean.eq Rat
          (Rat_mul
            (Rat_mk' (Int_ofNat 1) sm
              (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat sm)) hsmpos)
              (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat sm))))
            (Rat_ofInt (Int_ofNat bg)))
          (Rat_ofInt (Int_ofNat 604800)));
    [ intros sm bg hsmpos hsmNatPos hbg;
      assert (HgcdBgSm : @Lean.eq Nat (Nat_gcd bg sm) sm);
      [ rewrite_lean_eq hbg;
        refine
          (Eq_trans Nat _ _ _
            (congrArg Nat Nat
              (Nat_mul sm 604800) (Nat_mul 604800 sm)
              (fun n => Nat_gcd n sm)
              (Nat_mul_comm sm 604800)) _);
        refine
          (Eq_trans Nat _ _ _
            (congrArg Nat Nat sm (Nat_mul 1 sm)
              (fun n => Nat_gcd (Nat_mul 604800 sm) n)
              (Eq_symm Nat _ _ (Nat_one_mul sm))) _);
        refine (Eq_trans Nat _ _ _ (Nat_gcd_mul_right 604800 sm 1) _);
        rewrite_lean_eq (Nat_gcd_one_right 604800);
        exact (Nat_one_mul sm)
      | ];
      assert
        (HdivBg : @Lean.eq Nat
          (HDiv_hDiv_inst7 Nat Nat Nat
            (instHDiv_inst1 Nat Nat_instDiv) bg sm)
          604800);
      [ rewrite_lean_eq hbg;
        rewrite_lean_eq (Nat_mul_comm sm 604800);
        exact (Nat_mul_div_right 604800 sm hsmNatPos)
      | ];
      apply HRatExt;
      [ refine
          (Eq_trans Int _ _ _
            (HnumMul
              (Rat_mk' (Int_ofNat 1) sm
                (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat sm)) hsmpos)
                (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat sm))))
              (Rat_ofInt (Int_ofNat bg))) _);
        unfold Rat_ofInt;
        cbv [Rat_num Rat_den]; cbn [num den];
        unfold Nat_cast_inst1, instNatCastInt;
        cbn [natCast0 NatCast_natCast_inst1];
        repeat rewrite_lean_eq (HnatAbsOfNat 1);
        repeat rewrite_lean_eq (HnatAbsOfNat bg);
        repeat rewrite_lean_eq (Nat_gcd_one_left 1);
        repeat rewrite_lean_eq HgcdBgSm;
        assert
          (HIntTdivNat : forall x y : Nat,
            @Lean.eq Int (Int_tdiv (Int_ofNat x) (Int_ofNat y))
              (Int_ofNat
                (HDiv_hDiv_inst7 Nat Nat Nat
                  (instHDiv_inst1 Nat Nat_instDiv) x y)))
          by (intros x y; reflexivity);
        repeat rewrite_lean_eq (HIntTdivNat 1 1);
        repeat rewrite_lean_eq (HIntTdivNat bg sm);
        repeat rewrite_lean_eq (HNatDivOne 1);
        repeat rewrite_lean_eq HdivBg;
        exact (Int_one_mul (Int_ofNat 604800))
      | refine
          (Eq_trans Nat _ _ _
            (HdenMul
              (Rat_mk' (Int_ofNat 1) sm
                (Rat_inv__proof_3 (Rat_ofInt (Int_ofNat sm)) hsmpos)
                (Rat_inv__proof_4 (Rat_ofInt (Int_ofNat sm))))
              (Rat_ofInt (Int_ofNat bg))) _);
        unfold Rat_ofInt;
        cbv [Rat_num Rat_den]; cbn [num den];
        repeat rewrite_lean_eq (HnatAbsOfNat 1);
        repeat rewrite_lean_eq (HnatAbsOfNat bg);
        repeat rewrite_lean_eq HgcdBgSm;
        repeat rewrite_lean_eq (Nat_gcd_one_left 1);
        rewrite_lean_eq (Nat_div_self sm hsmNatPos);
        repeat rewrite_lean_eq (HNatDivOne 1);
        reflexivity ]
    | ];
    assert (Hb : @Lean.eq Rat b (Rat_ofInt (Int_ofNat big)));
    [ lazymatch b with
      | Int_cast_inst1 Rat Rat_instIntCast ?bi =>
          lazymatch bi with
          | OfNat_ofNat_inst1 Int ?bn ?binst =>
              assert (Hbn : @Lean.eq Nat bn big);
              [ compact_nat bn ltac:(fun hcompact =>
                  refine (Eq_trans Nat _ _ _ hcompact _);
                  unfold big, Nat_of_num_uint;
                  apply congrArg;
                  apply lean_eq_of_logic_eq;
                  vm_compute; reflexivity)
              | ];
              refine
                (Eq_trans Rat _ _ _
                  (congrArg Int Rat bi (Int_ofNat big)
                    (fun z => Int_cast_inst1 Rat Rat_instIntCast z)
                    (congrArg Nat Int bn big Int_ofNat Hbn)) _);
              reflexivity
          end
      end
    | ];
    set (part := (86400 : Nat)) in *;
    assert (Hp : @Lean.eq Rat p (Rat_ofInt (Int_ofNat part)));
    [ lazymatch p with
      | OfNat_ofNat_inst1 Rat ?pn ?pinst =>
          assert (Hpn : @Lean.eq Nat pn part);
          [ compact_nat pn ltac:(fun hcompact =>
              refine (Eq_trans Nat _ _ _ hcompact _);
              unfold part, Nat_of_num_uint;
              apply congrArg;
              apply lean_eq_of_logic_eq;
              vm_compute; reflexivity)
          | ];
          refine
            (Eq_trans Rat _ _ _
              (congrArg Nat Rat pn part
                (fun n => Rat_ofInt (Int_ofNat n)) Hpn) _);
          reflexivity
      end
    | ];
    assert (Hq : @Lean.eq Rat q (Rat_ofInt (Int_ofNat 7)))
      by reflexivity;
    assert (HpartN : @Lean.eq Nat part (Nat_of_N 86400%N));
    [ unfold part, Nat_of_num_uint;
      apply lean_eq_of_logic_eq; apply HNatInj;
      unfold Nat_of_N; rewrite nat2Natid; apply Nat2N.inj;
      vm_compute; reflexivity
    | ];
    assert (HsevenN : @Lean.eq Nat 7 (Nat_of_N 7%N));
    [ apply lean_eq_of_logic_eq; apply HNatInj;
      unfold Nat_of_N; rewrite nat2Natid; apply Nat2N.inj;
      vm_compute; reflexivity
    | ];
    assert (HpartMul : @Lean.eq Nat (Nat_mul part 7) 604800);
    [ rewrite_lean_eq HpartN; rewrite_lean_eq HsevenN;
      refine
        (Eq_trans Nat _ _ _
          (lean_eq_of_logic_eq (Hmulmap 86400%N 7%N)) _);
      exact (Eq_symm Nat _ _ H3600)
    | ];
    rewrite_lean_eq Hb;
    rewrite_lean_eq Hp;
    rewrite_lean_eq Hq;
    unfold HMul_hMul_inst7, instHMul_inst1, Rat_instMul, Mul_mul_inst1;
    cbn [hMul0 mul0];
    rewrite_lean_eq
      (HinvMulScale small big Hsmallpos HsmallNatPos HbigMul);
    rewrite_lean_eq (HRatOfNatMul part 7);
    exact
      (congrArg Nat Rat 604800 (Nat_mul part 7)
        (fun n => Rat_ofInt (Int_ofNat n))
        (Eq_symm Nat _ _ HpartMul))
|}

let week_offset_product_ha_proof =
  {|
lazymatch a with
| HMul_hMul_inst7 Rat Rat Rat (instHMul_inst1 Rat Rat_instMul) ?p ?q =>
  set (part := (86400 : Nat)) in *;
  assert (Hp : @Lean.eq Rat p (Rat_ofInt (Int_ofNat part)));
  [ lazymatch p with
    | OfNat_ofNat_inst1 Rat ?pn ?pinst =>
      assert (Hpn : @Lean.eq Nat pn part);
      [ compact_nat pn ltac:(fun hcompact =>
          refine (Eq_trans Nat _ _ _ hcompact _);
          unfold part, Nat_of_num_uint;
          apply congrArg;
          apply lean_eq_of_logic_eq;
          vm_compute; reflexivity)
      | ];
      refine
        (Eq_trans Rat _ _ _
          (congrArg Nat Rat pn part
            (fun n => Rat_ofInt (Int_ofNat n)) Hpn) _);
      reflexivity
    end
  | ];
  assert (Hq : @Lean.eq Rat q (Rat_ofInt (Int_ofNat 7)))
    by reflexivity;
  assert (HpartN : @Lean.eq Nat part (Nat_of_N 86400%N));
  [ unfold part, Nat_of_num_uint;
    apply lean_eq_of_logic_eq; apply HNatInj;
    unfold Nat_of_N; rewrite nat2Natid; apply Nat2N.inj;
    vm_compute; reflexivity
  | ];
  assert (HsevenN : @Lean.eq Nat 7 (Nat_of_N 7%N));
  [ apply lean_eq_of_logic_eq; apply HNatInj;
    unfold Nat_of_N; rewrite nat2Natid; apply Nat2N.inj;
    vm_compute; reflexivity
  | ];
  assert (HpartMul : @Lean.eq Nat (Nat_mul part 7) 604800);
  [ rewrite_lean_eq HpartN; rewrite_lean_eq HsevenN;
    refine
      (Eq_trans Nat _ _ _
        (lean_eq_of_logic_eq (Hmulmap 86400%N 7%N)) _);
    exact (Eq_symm Nat _ _ H3600)
  | ];
  refine
    (Eq_trans Rat _ _ _
      (congrArg Rat Rat p (Rat_ofInt (Int_ofNat part))
        (fun x => HMul_hMul_inst7 Rat Rat Rat
          (instHMul_inst1 Rat Rat_instMul) x q) Hp) _);
  refine
    (Eq_trans Rat _ _ _
      (congrArg Rat Rat q (Rat_ofInt (Int_ofNat 7))
        (fun y => HMul_hMul_inst7 Rat Rat Rat
          (instHMul_inst1 Rat Rat_instMul)
          (Rat_ofInt (Int_ofNat part)) y) Hq) _);
  refine (Eq_trans Rat _ _ _ (HRatOfNatMul part 7) _);
  exact
    (congrArg Nat Rat (Nat_mul part 7) 604800
      (fun n => Rat_ofInt (Int_ofNat n)) HpartMul)
end
|}

let week_offset_of_milliseconds_proof_1_tactic =
  unit_offset_scale_proof_1_tactic ~scale:"604800" ~big:"604800000"
    ~small:"1000" ~canonicalize_small:true
    ~extra_goal_clause:week_offset_scale_extra_clause ~ha_proof:"reflexivity"

let week_offset_of_nanoseconds_proof_1_tactic =
  unit_offset_scale_proof_1_tactic ~scale:"604800"
    ~big:"604800000000000" ~small:"1000000000"
    ~canonicalize_small:false
    ~extra_goal_clause:week_offset_scale_extra_clause ~ha_proof:"reflexivity"

let week_offset_to_nanoseconds_proof_1_tactic =
  unit_offset_scale_proof_1_tactic ~scale:"604800"
    ~big:"604800000000000" ~small:"1000000000"
    ~canonicalize_small:false ~extra_goal_clause:""
    ~ha_proof:week_offset_product_ha_proof

let list_append_cancel_right_tactic =
  {|
intros alpha as0 bs;
induction as0 as [|a as0 IH]; intros cs h;
[ destruct cs as [|c cs];
  [ reflexivity
  | assert
      (Hlen : @Lean.eq Nat
        (List_length alpha (List_append alpha (List_nil alpha) bs))
        (List_length alpha
          (List_append alpha (List_cons alpha c cs) bs)));
    [ exact
        (congrArg (List alpha) Nat
          (List_append alpha (List_nil alpha) bs)
          (List_append alpha (List_cons alpha c cs) bs)
          (List_length alpha) h)
    | ];
    assert
      (Hlen' : @Lean.eq Nat
        (Nat_add (List_length alpha (List_nil alpha))
          (List_length alpha bs))
        (Nat_add (List_length alpha (List_cons alpha c cs))
          (List_length alpha bs)));
    [ exact
        (Eq_trans Nat _ _ _
          (Eq_symm Nat _ _
            (List_length_append alpha (List_nil alpha) bs))
          (Eq_trans Nat _ _ _ Hlen
            (List_length_append alpha (List_cons alpha c cs) bs)))
    | ];
    clear Hlen; rename Hlen' into Hlen;
    assert
      (HlenNorm : @Lean.eq Nat (List_length alpha bs)
        (Nat_succ
          (Nat_add (List_length alpha cs) (List_length alpha bs))));
    [ refine
        (Eq_trans Nat _ _ _
          (Eq_symm Nat _ _ (Nat_zero_add (List_length alpha bs))) _);
      refine
        (Eq_trans Nat _ _ _
          (congrArg Nat Nat Nat_zero
            (List_length alpha (List_nil alpha))
            (fun n => Nat_add n (List_length alpha bs))
            (Eq_symm Nat _ _ (eq_refl Nat_zero))) _);
      refine (Eq_trans Nat _ _ _ Hlen _);
      refine
        (Eq_trans Nat _ _ _
          (congrArg Nat Nat
            (List_length alpha (List_cons alpha c cs))
            (Nat_succ (List_length alpha cs))
            (fun n => Nat_add n (List_length alpha bs))
            (eq_refl (Nat_succ (List_length alpha cs)))) _);
      exact (Nat_succ_add (List_length alpha cs) (List_length alpha bs))
    | ];
    clear Hlen; rename HlenNorm into Hlen;
    assert
      (Hlt : Nat_lt (List_length alpha bs)
        (Nat_succ
          (Nat_add (List_length alpha cs) (List_length alpha bs))));
    [ exact
        (Nat_lt_succ_of_le _ _
          (Nat_le_add_left (List_length alpha bs) (List_length alpha cs)))
    | ];
    pose proof
      (eq_mpr_sprop
        (fun n => Nat_lt (List_length alpha bs) n) Hlen Hlt) as Hbad;
    destruct (Nat_lt_irrefl (List_length alpha bs) Hbad) ]
| destruct cs as [|c cs];
  [ assert
      (Hlen : @Lean.eq Nat
        (List_length alpha
          (List_append alpha (List_cons alpha a as0) bs))
        (List_length alpha (List_append alpha (List_nil alpha) bs)));
    [ exact
        (congrArg (List alpha) Nat
          (List_append alpha (List_cons alpha a as0) bs)
          (List_append alpha (List_nil alpha) bs)
          (List_length alpha) h)
    | ];
    assert
      (Hlen' : @Lean.eq Nat
        (Nat_add (List_length alpha (List_cons alpha a as0))
          (List_length alpha bs))
        (Nat_add (List_length alpha (List_nil alpha))
          (List_length alpha bs)));
    [ exact
        (Eq_trans Nat _ _ _
          (Eq_symm Nat _ _
            (List_length_append alpha (List_cons alpha a as0) bs))
          (Eq_trans Nat _ _ _ Hlen
            (List_length_append alpha (List_nil alpha) bs)))
    | ];
    clear Hlen; rename Hlen' into Hlen;
    assert
      (HlenNorm : @Lean.eq Nat
        (Nat_succ
          (Nat_add (List_length alpha as0) (List_length alpha bs)))
        (List_length alpha bs));
    [ refine
        (Eq_trans Nat _ _ _
          (Eq_symm Nat _ _
            (Nat_succ_add (List_length alpha as0)
              (List_length alpha bs))) _);
      refine
        (Eq_trans Nat _ _ _
          (congrArg Nat Nat
            (Nat_succ (List_length alpha as0))
            (List_length alpha (List_cons alpha a as0))
            (fun n => Nat_add n (List_length alpha bs))
            (Eq_symm Nat _ _
              (eq_refl (Nat_succ (List_length alpha as0))))) _);
      refine (Eq_trans Nat _ _ _ Hlen _);
      refine
        (Eq_trans Nat _ _ _
          (congrArg Nat Nat
            (List_length alpha (List_nil alpha)) Nat_zero
            (fun n => Nat_add n (List_length alpha bs))
            (eq_refl Nat_zero)) _);
      exact (Nat_zero_add (List_length alpha bs))
    | ];
    clear Hlen; rename HlenNorm into Hlen;
    assert
      (Hlt : Nat_lt (List_length alpha bs)
        (Nat_succ
          (Nat_add (List_length alpha as0) (List_length alpha bs))));
    [ exact
        (Nat_lt_succ_of_le _ _
          (Nat_le_add_left (List_length alpha bs) (List_length alpha as0)))
    | ];
    pose proof
      (eq_mp_sprop
        (fun n => Nat_lt (List_length alpha bs) n) Hlen Hlt) as Hbad;
    destruct (Nat_lt_irrefl (List_length alpha bs) Hbad)
  | cbn [List_append] in h;
    assert (Hhead : @Lean.eq alpha a c);
    [ exact
        (congrArg (List alpha) alpha
          (List_cons alpha a (List_append alpha as0 bs))
          (List_cons alpha c (List_append alpha cs bs))
          (fun xs =>
            match xs with
            | List_nil _ => a
            | List_cons _ x _ => x
            end) h)
    | ];
    assert
      (Htail : @Lean.eq (List alpha)
        (List_append alpha as0 bs) (List_append alpha cs bs));
    [ exact
        (congrArg (List alpha) (List alpha)
          (List_cons alpha a (List_append alpha as0 bs))
          (List_cons alpha c (List_append alpha cs bs))
          (fun xs =>
            match xs with
            | List_nil _ => List_nil alpha
            | List_cons _ _ tail => tail
            end) h)
    | ];
    destruct Hhead;
    exact
      (congrArg (List alpha) (List alpha) as0 cs
        (fun xs => List_cons alpha a xs) (IH cs Htail)) ] ]
|}

let nat_subtype_succ_le_of_lt_proof_1_3_tactic =
  {|
intros s decMem y h;
destruct h as [n hn];
exists n;
refine
  (eq_mpr_sprop
    (fun z =>
      Membership_mem_inst3 Nat (Set_inst1 Nat)
        (Set_instMembership_inst1 Nat) s z)
    (congrArg Nat Nat
      (Nat_add n (Subtype_val Nat
        (fun x =>
          Membership_mem_inst3 Nat (Set_inst1 Nat)
            (Set_instMembership_inst1 Nat) s x) y))
      (Nat_add (Subtype_val Nat
        (fun x =>
          Membership_mem_inst3 Nat (Set_inst1 Nat)
            (Set_instMembership_inst1 Nat) s x) y) n)
      (fun z => Nat_add z 1)
      (Nat_add_comm n
        (Subtype_val Nat
          (fun x =>
            Membership_mem_inst3 Nat (Set_inst1 Nat)
              (Set_instMembership_inst1 Nat) s x) y)))
    hn)
|}

let nat_subtype_succ_le_of_lt_proof_1_4_tactic =
  {|
intros s decMem x y hx k hk hfind;
lazymatch type of hk with
| @Lean.eq Nat ?xv
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        ?yv k) 1) =>
  lazymatch type of hfind with
  | LE_le_inst1 Nat instLENat ?found k =>
    change (Nat_le found k) in hfind;
    change (@Lean.eq Nat xv (Nat_add (Nat_add yv k) 1)) in hk;
    change (Nat_le (Nat_add (Nat_add yv found) 1) xv);
    assert
      (Hbase : Nat_le (Nat_add yv found) (Nat_add yv k));
    [ exact (Nat_add_le_add_left found k hfind yv)
    | ];
    assert
      (Hplus : Nat_le
        (Nat_add (Nat_add yv found) 1)
        (Nat_add (Nat_add yv k) 1));
    [ exact
        (Nat_add_le_add_right
          (Nat_add yv found) (Nat_add yv k) Hbase 1)
    | ];
    exact
      (eq_mpr_sprop
        (fun n => Nat_le (Nat_add (Nat_add yv found) 1) n)
        hk Hplus)
  end
end
|}

let nat_subtype_le_succ_of_forall_lt_le_proof_1_2_tactic =
  {|
intros s decMem y hx;
lazymatch goal with
| |- LT_lt_inst1 Nat instLTNat ?yv
    (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
      (HAdd_hAdd_inst7 Nat Nat Nat (instHAdd_inst1 Nat instAddNat)
        _ ?found) 1) =>
  change (Nat_lt yv (Nat_succ (Nat_add yv found)));
  exact
    (Nat_lt_succ_of_le yv (Nat_add yv found)
      (Nat_le_add_right yv found))
end
|}

let order_iso_subsequence_proof_1_4_tactic =
  {|
intros m n n' h;
change (Nat_le (Nat_succ (Nat_add n m)) n') in h;
change (Nat_le (Nat_succ n) (Nat_sub (Nat_sub (Nat_add n n') n) m));
assert (Hadd : Nat_le (Nat_add (Nat_succ n) m) n');
[ exact
    (eq_mpr_sprop
      (fun z => Nat_le z n') (Nat_succ_add n m) h)
| ];
assert (Hlt : Nat_le (Nat_succ n) (Nat_sub n' m));
[ exact (Nat_le_sub_of_add_le (Nat_succ n) m n' Hadd)
| ];
assert
  (Hcancel : @Lean.eq Nat (Nat_sub (Nat_add n n') n) n');
[ exact (Nat_add_sub_cancel_left n n')
| ];
exact
  (eq_mpr_sprop
    (fun z => Nat_le (Nat_succ n) z)
    (congrArg Nat Nat (Nat_sub (Nat_add n n') n) n'
      (fun z => Nat_sub z m) Hcancel)
    Hlt)
|}

let order_iso_subsequence_proof_1_5_tactic =
  {|
intros m n n' h;
change (Nat_lt (Nat_add n m) n') in h;
change (@Lean.eq Nat
  (Nat_add (Nat_sub (Nat_sub (Nat_add n n') n) m) m) n');
assert (Hnm : Nat_le (Nat_add n m) n');
[ exact (Nat_le_of_lt (Nat_add n m) n' h)
| ];
assert (Hm : Nat_le m n');
[ exact
    (Nat_le_trans m (Nat_add n m) n'
      (Nat_le_add_left m n) Hnm)
| ];
assert
  (Hcancel : @Lean.eq Nat (Nat_sub (Nat_add n n') n) n');
[ exact (Nat_add_sub_cancel_left n n')
| ];
exact
  (Eq_trans Nat _ _ _
    (congrArg Nat Nat (Nat_sub (Nat_add n n') n) n'
      (fun z => Nat_add (Nat_sub z m) m) Hcancel)
    (Nat_sub_add_cancel n' m Hm))
|}

let plain_time_of_nanoseconds_large_bound_tactic =
  {|
assert
  (HNatInj : forall a b : Nat,
    Logic.eq (nat_of_Nat a) (nat_of_Nat b) -> Logic.eq a b);
[ intros a b h;
  rewrite <- (Nat2natid a), <- (Nat2natid b);
  f_equal; exact h
| ];
assert
  (HsuccN : forall (x : Nat) (n : N),
    @Lean.eq Nat x (Nat_of_N n) ->
    @Lean.eq Nat (Nat_succ x) (Nat_of_N (N.succ n)));
[ intros x n h;
  refine
    (Eq_trans Nat _ _ _
      (congrArg Nat Nat x (Nat_of_N n) Nat_succ h) _);
  apply lean_eq_of_logic_eq;
  apply HNatInj;
  cbn [nat_of_Nat];
  unfold Nat_of_N;
  rewrite !nat2Natid, N2Nat.inj_succ;
  reflexivity
| ];
assert
  (HdoubleN : forall (x : Nat) (n : N),
    @Lean.eq Nat x (Nat_of_N n) ->
    @Lean.eq Nat (double x) (Nat_of_N (N.double n)));
[ intros x n h;
  refine
    (Eq_trans Nat _ _ _
      (congrArg Nat Nat x (Nat_of_N n) double h) _);
  apply lean_eq_of_logic_eq;
  apply HNatInj;
  rewrite nat_of_Nat_double;
  unfold Nat_of_N;
  rewrite !nat2Natid, N2Nat.inj_double;
  reflexivity
| ];
let rec compact_nat t k :=
  lazymatch t with
  | Nat_zero =>
      let h := fresh "Hcompact" in
      assert (h : @Lean.eq Nat t (Nat_of_N 0%N));
      [ reflexivity | k h ]
  | Nat_succ ?u =>
      compact_nat u ltac:(fun hu =>
        lazymatch type of hu with
        | @Lean.eq Nat _ (Nat_of_N ?nu) =>
            let h := fresh "Hcompact" in
            assert
              (h : @Lean.eq Nat t (Nat_of_N (N.succ nu)));
            [ exact (HsuccN u nu hu) | k h ]
        end)
  | double ?u =>
      compact_nat u ltac:(fun hu =>
        lazymatch type of hu with
        | @Lean.eq Nat _ (Nat_of_N ?nu) =>
            let h := fresh "Hcompact" in
            assert
              (h : @Lean.eq Nat t (Nat_of_N (N.double nu)));
            [ exact (HdoubleN u nu hu) | k h ]
        end)
  end in
lazymatch goal with
| |- GT_gt_inst1 Int Int_instLTInt
      (OfNat_ofNat_inst1 Int ?bn ?binst)
      (OfNat_ofNat_inst1 Int 0 ?zinst) =>
    change (Int_lt (Int_ofNat Nat_zero) (Int_ofNat bn));
    refine
      (Iff_mpr _ _ (Int_ofNat_lt Nat_zero bn) _);
    compact_nat bn ltac:(fun hcompact =>
      refine
        (eq_mpr_sprop
          (fun n => Nat_lt Nat_zero n) hcompact _);
      apply Nat_lt_to_N_l;
      vm_compute; reflexivity)
end
|}

let equiv_prod_punit_tactic =
  {|
intro A;
unshelve econstructor;
[ intros [a u]; assumption
| intro a; constructor; [ assumption | exact PUnit_unit ]
| intros [a u]; destruct u; reflexivity
| intro a; reflexivity ]
|}

let lean_json_cases_on_tactic =
  {|
intros motive t null bool num str arr obj;
destruct t as [| b | n | s | elems | kvPairs];
[ exact null
| exact (bool b)
| exact (num n)
| exact (str s)
| exact (arr elems)
| exact (obj kvPairs) ]
|}

let lean_info_tree_cases_on_tactic =
  {|
intros motive t context node hole;
destruct t as [i t | i children | mvarId];
[ exact (context i t)
| exact (node i children)
| exact (hole mvarId) ]
|}

let remove_after_done_action_sparse_cases_on_3_tactic =
  {|
intros motive t node other;
destruct t as [i t | i children | mvarId];
[ apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 2 0)) 1 (eq_refl Bool_false))
| exact (node i children)
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 2 2)) 1 (eq_refl Bool_false)) ]
|}

let lean_json_sparse_cases_on_6_tactic =
  {|
intros motive t arr other;
destruct t as [| b | n | s | elems | kvPairs];
[ apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 16 0)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 16 1)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 16 2)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 16 3)) 1 (eq_refl Bool_false))
| exact (arr elems)
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 16 5)) 1 (eq_refl Bool_false)) ]
|}

let lean_json_beq_sparse_cases_on_8_tactic =
  {|
intros motive t obj other;
destruct t as [| b | n | s | elems | kvPairs];
[ apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 32 0)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 32 1)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 32 2)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 32 3)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 32 4)) 1 (eq_refl Bool_false))
| exact (obj kvPairs) ]
|}

let option_from_json_sparse_cases_on_1_tactic =
  {|
intros motive t null other;
destruct t as [| b | n | s | elems | kvPairs];
[ exact null
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 1 1)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 1 2)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 1 3)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 1 4)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 1 5)) 1 (eq_refl Bool_false)) ]
|}

let lean_json_beq_sparse_cases_on_4_tactic =
  {|
intros motive t bool other;
let prove_other idx :=
  apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 2 idx)) 1 (eq_refl Bool_false)) in
destruct t as [| b | n | s | elems | kvPairs];
[ prove_other 0
| exact (bool b)
| prove_other 2
| prove_other 3
| prove_other 4
| prove_other 5 ]
|}

let lean_json_beq_sparse_cases_on_5_tactic =
  {|
intros motive t num other;
let prove_other idx :=
  apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 4 idx)) 1 (eq_refl Bool_false)) in
destruct t as [| b | n | s | elems | kvPairs];
[ prove_other 0
| prove_other 1
| exact (num n)
| prove_other 3
| prove_other 4
| prove_other 5 ]
|}

let lean_json_beq_sparse_cases_on_6_tactic =
  {|
intros motive t str other;
let prove_other idx :=
  apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 8 idx)) 1 (eq_refl Bool_false)) in
destruct t as [| b | n | s | elems | kvPairs];
[ prove_other 0
| prove_other 1
| prove_other 2
| exact (str s)
| prove_other 4
| prove_other 5 ]
|}

let float_from_json_sparse_cases_on_1_tactic =
  {|
intros motive t str num other;
destruct t as [| b | n | s | elems | kvPairs];
[ apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 12 0)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 12 1)) 1 (eq_refl Bool_false))
| exact (num n)
| exact (str s)
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 12 4)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 12 5)) 1 (eq_refl Bool_false)) ]
|}

let json_structured_from_json_sparse_cases_on_1_tactic =
  {|
intros motive t arr obj other;
destruct t as [| b | n | s | elems | kvPairs];
[ apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 48 0)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 48 1)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 48 2)) 1 (eq_refl Bool_false))
| apply other;
  exact
    (Nat_ne_of_beq_eq_false
      (Nat_land 1 (Nat_shiftRight 48 3)) 1 (eq_refl Bool_false))
| exact (arr elems)
| exact (obj kvPairs) ]
|}

let command_parsed_snapshot_below_1_tactic =
  {|
intros motive1 motive2 motive3 motive4 t;
exact
  (let fix belowMain
    (x : Lean_Language_Lean_CommandParsedSnapshot) :=
    match x with
    | Lean_Language_Lean_CommandParsedSnapshot_mk
        toSnapshot stx parserState elabSnap next =>
      rocqLeanImportCommandParsedSnapshotPProd (motive2 next)
        (match next with
         | Option_none_inst1 _ =>
           rocqLeanImportCommandParsedSnapshotPUnit (motive2 next)
         | Option_some_inst1 _ snapshotTask =>
           rocqLeanImportCommandParsedSnapshotPProd (motive3 snapshotTask)
             (match snapshotTask with
              | Lean_Language_SnapshotTask_mk
                  _ stxOpt reportingRange cancelTkOpt task =>
                rocqLeanImportCommandParsedSnapshotPProd (motive4 task)
                  (match task with
                   | Task_pure_inst1 _ get =>
                     rocqLeanImportCommandParsedSnapshotPProd
                       (motive1 get) (belowMain get)
                   end)
              end)
         end)
    end in
   match t with
   | Option_none_inst1 _ =>
     rocqLeanImportCommandParsedSnapshotPUnit (motive2 t)
   | Option_some_inst1 _ snapshotTask =>
     rocqLeanImportCommandParsedSnapshotPProd (motive3 snapshotTask)
       (match snapshotTask with
        | Lean_Language_SnapshotTask_mk
            _ stxOpt reportingRange cancelTkOpt task =>
          rocqLeanImportCommandParsedSnapshotPProd (motive4 task)
            (match task with
             | Task_pure_inst1 _ get =>
               rocqLeanImportCommandParsedSnapshotPProd
                 (motive1 get) (belowMain get)
             end)
        end)
   end)
|}

let do_code_alt_list_below target =
  {|
(let fix belowList
   (l : List_inst1
          (Lean_Elab_Term_Do_Alt Lean_Elab_Term_Do_Code)) :=
   match l with
   | List_nil_inst1 _ => rocqLeanImportDoCodePUnit (motive4 l)
   | List_cons_inst1 _ head tail =>
     rocqLeanImportDoCodePProd
       (rocqLeanImportDoCodePProd (motive6 head)
          (match head with
           | Lean_Elab_Term_Do_Alt_mk _ _ _ _ altRhs =>
             rocqLeanImportDoCodePProd
               (motive1 altRhs) (belowMain altRhs)
           end))
       (rocqLeanImportDoCodePProd (motive4 tail) (belowList tail))
   end in
 belowList |}
  ^ target ^ ")"

let do_code_alt_expr_list_below target =
  {|
(let fix belowList
   (l : List_inst1
          (Lean_Elab_Term_Do_AltExpr Lean_Elab_Term_Do_Code)) :=
   match l with
   | List_nil_inst1 _ => rocqLeanImportDoCodePUnit (motive5 l)
   | List_cons_inst1 _ head tail =>
     rocqLeanImportDoCodePProd
       (rocqLeanImportDoCodePProd (motive7 head)
          (match head with
           | Lean_Elab_Term_Do_AltExpr_mk _ _ _ _ _ altRhs =>
             rocqLeanImportDoCodePProd
               (motive1 altRhs) (belowMain altRhs)
           end))
       (rocqLeanImportDoCodePProd (motive5 tail) (belowList tail))
   end in
 belowList |}
  ^ target ^ ")"

let do_code_below_tactic focus =
  let alt_list = do_code_alt_list_below in
  let alt_expr_list = do_code_alt_expr_list_below in
  let alt_array target =
    Printf.sprintf
      "(match %s with | Array_mk_inst1 _ l => \
       rocqLeanImportDoCodePProd (motive4 l) %s end)" target
      (alt_list "l")
  in
  let alt_expr_array target =
    Printf.sprintf
      "(match %s with | Array_mk_inst1 _ l => \
       rocqLeanImportDoCodePProd (motive5 l) %s end)" target
      (alt_expr_list "l")
  in
  let result =
    match focus with
    | DoCode -> "belowMain t"
    | DoAltArray -> alt_array "t"
    | DoAltExprArray -> alt_expr_array "t"
    | DoAltList -> alt_list "t"
    | DoAltExprList -> alt_expr_list "t"
    | DoAlt ->
      "(match t with | Lean_Elab_Term_Do_Alt_mk _ _ _ _ altRhs => \
       rocqLeanImportDoCodePProd (motive1 altRhs) (belowMain altRhs) end)"
    | DoAltExpr ->
      "(match t with | Lean_Elab_Term_Do_AltExpr_mk _ _ _ _ _ altRhs => \
       rocqLeanImportDoCodePProd (motive1 altRhs) (belowMain altRhs) end)"
  in
  Printf.sprintf
    {|
intros motive1 motive2 motive3 motive4 motive5 motive6 motive7 t;
exact
  (let fix belowMain (x : Lean_Elab_Term_Do_Code) :=
   match x with
   | Lean_Elab_Term_Do_Code_decl _ _ k =>
     rocqLeanImportDoCodePProd (motive1 k) (belowMain k)
   | Lean_Elab_Term_Do_Code_reassign _ _ k =>
     rocqLeanImportDoCodePProd (motive1 k) (belowMain k)
   | Lean_Elab_Term_Do_Code_joinpoint _ _ body k =>
     rocqLeanImportDoCodePProd
       (rocqLeanImportDoCodePProd (motive1 body) (belowMain body))
       (rocqLeanImportDoCodePProd (motive1 k) (belowMain k))
   | Lean_Elab_Term_Do_Code_seq _ k =>
     rocqLeanImportDoCodePProd (motive1 k) (belowMain k)
   | Lean_Elab_Term_Do_Code_action _ =>
     rocqLeanImportDoCodePUnit (motive1 x)
   | Lean_Elab_Term_Do_Code_break _ =>
     rocqLeanImportDoCodePUnit (motive1 x)
   | Lean_Elab_Term_Do_Code_continue _ =>
     rocqLeanImportDoCodePUnit (motive1 x)
   | Lean_Elab_Term_Do_Code_return _ _ =>
     rocqLeanImportDoCodePUnit (motive1 x)
   | Lean_Elab_Term_Do_Code_ite _ _ _ _ thenBranch elseBranch =>
     rocqLeanImportDoCodePProd
       (rocqLeanImportDoCodePProd
          (motive1 thenBranch) (belowMain thenBranch))
       (rocqLeanImportDoCodePProd
          (motive1 elseBranch) (belowMain elseBranch))
   | Lean_Elab_Term_Do_Code_match _ _ _ _ alts =>
     rocqLeanImportDoCodePProd (motive2 alts) %s
   | Lean_Elab_Term_Do_Code_matchExpr _ _ _ alts elseBranch =>
     rocqLeanImportDoCodePProd
       (rocqLeanImportDoCodePProd (motive3 alts) %s)
       (rocqLeanImportDoCodePProd
          (motive1 elseBranch) (belowMain elseBranch))
   | Lean_Elab_Term_Do_Code_jmp _ _ _ =>
     rocqLeanImportDoCodePUnit (motive1 x)
   end in
   %s)
|}
    (alt_array "alts") (alt_expr_array "alts") result

let fin_cast_succ_lt_or_lt_succ_proof_1_2_tactic =
  {|
intros n p i;
cbn;
lazymatch goal with
| |- Or (Nat_lt ?iv ?pv) _ =>
  destruct
    (PeanoNat.Nat.lt_ge_cases (nat_of_Nat iv) (nat_of_Nat pv))
    as [Hlt | Hge];
  [ apply Or_inl; apply nat_le_Nat_le; cbn; lia
  | apply Or_inr; apply nat_le_Nat_le; cbn; lia ]
end
|}

let uint64_max_bound_proof_tactic =
  {|
unfold LT_lt_inst1, instLTNat;
unfold HSub_hSub_inst7, instHSub_inst1, instSubNat, Sub_sub_inst1;
cbn [lt0 hSub0 sub0];
assert (Hsub : forall x : Nat,
  (0 < x)%Nat -> (Nat_sub x 1 < x)%Nat);
[ intros x Hpos;
  destruct x as [|x];
  [ inversion Hpos
  | cbn [Nat_sub]; apply Nat_le_refl ]
| apply Hsub;
  unfold UInt64_size;
  change (0 < Nat_pow 2 (Nat_of_nat 64%nat))%Nat;
  rewrite Nat_pow_two_eq_double_pow_nat;
  exact (Nat_double_pow_pos 64%nat) ]
|}

let uint64_toNat_ofNatTruncate_of_le_tactic =
  {|
intros n Hle;
unfold LE_le_inst1, instLENat in Hle;
cbn [le0] in Hle;
unfold UInt64_ofNatTruncate;
destruct (Nat_decLt n UInt64_size) as [Hnot | Hlt];
[ unfold dite, Decidable_casesOn;
  unfold LT_lt_inst1, instLTNat;
  cbn [lt0];
  unfold Decidable_recl;
  apply UInt64_toNat_ofNatLT
| destruct (Nat_le_lt_false UInt64_size n Hle Hlt) ]
|}

let uint64_toNat_ofNatLT_tactic =
  {|
intros n Hlt;
unfold UInt64_toNat, UInt64_ofNatLT, UInt64_toBitVec;
unfold BitVec_toNat, BitVec_toFin, Fin_val;
cbn [toBitVec64 toFin val];
reflexivity
|}

let uint64_toFin_ofNatTruncate_of_le_tactic =
  {|
intros n Hle;
eapply (Iff_mp _ _ (Fin_val_inj _ _ _));
unfold UInt64_toFin, Fin_val;
cbn [val];
change (Lean.eq
  (UInt64_toNat (UInt64_ofNatTruncate n))
  (Nat_sub UInt64_size 1));
apply UInt64_toNat_ofNatTruncate_of_le;
exact Hle
|}

let uint64_toBitVec_ofNatTruncate_of_le_tactic =
  {|
intros n Hle;
eapply BitVec_eq_of_toNat_eq;
change (Lean.eq
  (UInt64_toNat (UInt64_ofNatTruncate n))
  (Nat_sub UInt64_size 1));
apply UInt64_toNat_ofNatTruncate_of_le;
exact Hle
|}

let uint64_of_fin_tactic =
  {|
intros a;
destruct a as [n h];
exact (UInt64_ofNatLT n h)
|}

let persistent_hash_map_node_sizeof_1_tactic =
  {|
intros A B sizeA sizeB;
fix nodeSize 1;
intro x;
destruct x as [es | ks vs h];
[ destruct es as [contents];
  let contentsType := type of contents in
  assert (listSize : contentsType -> Nat);
  [ fix listSize 1;
    intro xs;
    destruct xs as [|head tail];
    [ exact 1
    | destruct head as [key val | node |];
      [ exact
          (Nat_add
            (Nat_add 1
              (Nat_add
                (Nat_add 1 (SizeOf_sizeOf A sizeA key))
                (SizeOf_sizeOf B sizeB val)))
            (listSize tail))
      | exact
          (Nat_add (Nat_add 1 (Nat_add 1 (nodeSize node)))
            (listSize tail))
      | exact (Nat_add (Nat_add 1 1) (listSize tail)) ] ]
  | exact (Nat_add 1 (Nat_add 1 (listSize contents))) ]
| destruct ks as [keys];
  destruct vs as [vals];
  let keysType := type of keys in
  assert (listSizeA : keysType -> Nat);
  [ fix listSizeA 1;
    intro xs;
    destruct xs as [|head tail];
    [ exact 1
    | exact
        (Nat_add (Nat_add 1 (SizeOf_sizeOf A sizeA head))
          (listSizeA tail)) ]
  | let valsType := type of vals in
    assert (listSizeB : valsType -> Nat);
    [ fix listSizeB 1;
    intro xs;
    destruct xs as [|head tail];
    [ exact 1
    | exact
        (Nat_add (Nat_add 1 (SizeOf_sizeOf B sizeB head))
          (listSizeB tail)) ]
    | exact
      (Nat_add
        (Nat_add
          (Nat_add 1 (Nat_add 1 (listSizeA keys)))
          (Nat_add 1 (listSizeB vals)))
        1) ] ] ]
|}

(* let get_predeclared_eq n i = get_predeclared_ind "eq" n i *)
let mk_char_prim = "Char.mk.reflective_prim"

(*
Register Nat_isValidChar as lean.Nat_isValidChar.
Register reflective_Char_mk_prim as lean.Char.mk.reflective_prim. *)
let nat_double = "Nat_double"
let nat_pow2_63_literal = "Nat_pow2_63_literal"
let nat_64_literal = "Nat_64_literal"

(** For each name, the instantiation with all non-sprop univs should always be
    declared, but the instantiations with SProp may be lazily declared. We
    expect small instance lengths (experimentally at most 4 in the stdlib) so we
    represent instantiations as bit fields, bit n is 1 iff universe n is
    instantiated by SProp. *)
let declared : instantiation Int.Map.t N.Map.t ref =
  Summary.ref ~name:"lean-declared-instances" N.Map.empty

let entries : entry N.Map.t ref = Summary.ref ~name:"lean-entries" N.Map.empty

let squash_info : squashy N.Map.t ref =
  Summary.ref ~name:"lean-squash-info" N.Map.empty

let add_declared n i inst =
  declared :=
    N.Map.update n
      (function
        | None -> Some (Int.Map.singleton i inst)
        | Some m -> Some (Int.Map.add i inst m))
      !declared

let to_univ_level' u uconv =
  match to_universe uconv.map u with
  | SProp -> (uconv, LSProp)
  | Type u | GSort (_, u) | VSort (_, u) ->
    let uconv, u = to_univ_level u uconv in
    (uconv, Level u)
  | Set -> (uconv, Level Level.set)
  | Prop -> assert false

let empty_env = Environ.empty_rel_context_val
let default_proj_id = Id.of_string "default_proj_id"

let is_sprop_type rels uconv ty =
  with_env_evm rels uconv
    (fun env evd ty ->
      EConstr.ESorts.is_sprop evd
        (Retyping.get_sort_of env evd (EConstr.of_constr ty)))
    ty

type error_mode = Skip | Stop | Fail

let { Goptions.get = error_mode } =
  let print = function Skip -> "Skip" | Stop -> "Stop" | Fail -> "Fail" in
  let interp = function
    | "Skip" -> Skip
    | "Stop" -> Stop
    | "Fail" -> Fail
    | s ->
      CErrors.user_err Pp.(str "Unknown error mode " ++ qstring s ++ str ".")
  in
  Goptions.declare_interpreted_string_option_and_ref ~stage:Interp
    ~key:[ "Lean"; "Error"; "Mode" ]
    ~value:Fail interp print ()

exception MissingQuot

let { Goptions.get = skip_missing_quot } =
  Goptions.declare_bool_option_and_ref ~stage:Interp
    ~key:[ "Lean"; "Skip"; "Missing"; "Quotient" ]
    ~value:true ()

let error_mode = function
  | MissingQuot when skip_missing_quot () -> Skip
  | _ -> error_mode ()

module ZMap = CMap.Make (Z)

let nat_ints = ref ZMap.empty
let max_known_int = ref (Z.pred Z.zero)

let one_more_int nat =
  let i = Z.succ !max_known_int in
  let c =
    if Z.equal i Z.zero then Constr.mkConstructU ((nat, 1), UVars.Instance.empty)
    else
      let cpred = ZMap.get !max_known_int !nat_ints in
      Constr.(
        mkApp (mkConstructU ((nat, 2), UVars.Instance.empty), [| cpred |]))
  in
  nat_ints := ZMap.add i c !nat_ints;
  max_known_int := i

let max_nat_int = Z.of_string "5000"

let nat_int_binary nat double i =
  assert (Z.leq Z.zero i);
  let rec to_binary z acc =
    if Z.equal z Z.zero then acc
    else
      let bit = if Z.equal (Z.rem z (Z.of_int 2)) Z.zero then 0 else 1 in
      to_binary (Z.div z (Z.of_int 2)) (bit :: acc)
  in
  let binary_representation = to_binary i [] in
  let xO = Constr.mkConstructU ((nat, 1), UVars.Instance.empty) in
  let xS = Constr.mkConstructU ((nat, 2), UVars.Instance.empty) in
  let fS x = Constr.mkApp (xS, [| x |]) in
  let fDouble x = Constr.mkApp (double, [| x |]) in
  let rec construct_nat binary_list_rev =
    match binary_list_rev with
    | [] -> xO
    | 0 :: rest ->
      let rest_constr = construct_nat rest in
      fDouble rest_constr
    | 1 :: rest ->
      let rest_constr = construct_nat rest in
      fS (fDouble rest_constr)
    | _ -> assert false
  in
  construct_nat (List.rev binary_representation)

let nat_int nat double i =
  assert (Z.leq Z.zero i);
  if Z.leq max_nat_int i then nat_int_binary nat double i
  else begin
    while Z.lt !max_known_int i do
      one_more_int nat
    done;
    ZMap.get i !nat_ints
  end

(* Decode a UTF-8 string into a list of valid codepoints, with error reporting for bad characters *)
(* let string_to_codepoints s =
  (* Create a UTF-8 decoder for the input string *)
  let decoder = Uutf.decoder ~encoding:`UTF_8 (`String s) in

  (* Define the condition for filtering codepoints *)
  let is_valid_codepoint n = n < 0xd800 || (0xdfff < n && n < 0x110000) in

  (* Decode the string and collect valid codepoints *)
  let rec collect_codepoints acc =
    match Uutf.decode decoder with
    | `Uchar u when is_valid_codepoint (Uchar.to_int u) ->
      collect_codepoints (Uchar.to_int u :: acc)
    | `Uchar u when Uchar.to_int u >= 0x110000 ->
      (* Raise an exception with the problematic character *)
      let bad_char = Printf.sprintf "U+%04X" (Uchar.to_int u) in
      failwith (Printf.sprintf "Invalid codepoint (>= 0x110000): %s" bad_char)
    | `Uchar u when Uchar.to_int u >= 0xd800 && 0xdfff >= Uchar.to_int u ->
      (* Raise an exception with the problematic character *)
      let bad_char = Printf.sprintf "U+%04X" (Uchar.to_int u) in
      failwith
        (Printf.sprintf "Invalid codepoint (u >= 0xd800 && 0xdfff >= u): %s"
           bad_char)
    | `Uchar _ -> assert false
    | `End -> List.rev acc
    | `Malformed s ->
      (* Handle malformed UTF-8 sequences *)
      failwith (Printf.sprintf "Malformed UTF-8 sequence: %S" s)
    | `Await -> assert false (* This case should not occur for a string input *)
  in
  collect_codepoints [] *)

let string_to_codepoints str =
  let rec decode_utf8 s pos acc =
    if pos >= String.length s then List.rev acc
    else
      let c = Char.code (String.get s pos) in
      let n =
        if c < 0x80 then (1, c)
        else if c < 0xE0 then (2, c land 0x1F)
        else if c < 0xF0 then (3, c land 0x0F)
        else (4, c land 0x07)
      in
      let bytes, value = n in
      let code_point = ref value in
      for i = 1 to bytes - 1 do
        let next_byte = Char.code (String.get s (pos + i)) in
        code_point := (!code_point lsl 6) lor (next_byte land 0x3F)
      done;
      decode_utf8 s (pos + bytes) (!code_point :: acc)
  in
  decode_utf8 str 0 []

let check_valid_codepoints cs =
  List.map
    (fun c ->
      if c < 0xd800 || (0xdfff < c && c < 0x110000) then c
      else
        let bad_char = Printf.sprintf "U+%04X" c in
        CErrors.user_err
          Pp.(str (Printf.sprintf "Invalid codepoint: %s" bad_char)))
    cs

let mk_char mkChar (c : int) =
  Constr.(mkApp (mkChar, [| mkInt (Uint63.of_int c) |]))

let mk_list list uinst ty l =
  let cNil = Constr.(mkApp (mkConstructU ((list, 1), uinst), [| ty |])) in
  let cCons = Constr.mkConstructU ((list, 2), uinst) in
  let rec mk_list_rec l =
    match l with
    | [] -> cNil
    | hd :: tl -> Constr.mkApp (cCons, [| ty; hd; mk_list_rec tl |])
  in
  mk_list_rec l

let mk_string char list char_uinst mkChar string_mk s =
  let stage = ref "UTF-8 decoding" in
  try
    let codepoints =
      try check_valid_codepoints (string_to_codepoints s)
      with Failure msg as exn ->
        let _, info = Exninfo.capture exn in
        CErrors.user_err ~info Pp.(str msg)
    in
    stage := "character construction";
    let chars = List.map (mk_char mkChar) codepoints in
    stage := "character list construction";
    let ls = mk_list list char_uinst char chars in
    stage := "string construction";
    Constr.(mkApp (string_mk, [| ls |]))
  with Invalid_argument msg ->
    CErrors.user_err
      Pp.(str "String import failed during " ++ str !stage ++ str ": " ++ str msg)

(* [c] has type [indu] applied to [args] *)
let rec unfold_proj_case env evd ~field ~indu ~mib ~mip ~args c =
  let ind = fst indu in
  let npar = mib.Declarations.mind_nparams in
  let ntypes = Declareops.mind_ntypes mib in
  let u = snd indu in
  let ind_subst =
    List.init ntypes (fun i -> Constr.mkIndU ((fst ind, ntypes - i - 1), u))
  in
  let ctx, cty0 = mip.Declarations.mind_nf_lc.(0) in
  let cty_full = Term.it_mkProd_or_LetIn cty0 ctx in
  let rctx, _ = Term.decompose_prod_decls (Vars.substl ind_subst cty_full) in
  let ctor_ctx, _paramslet = CList.chop mip.mind_consnrealdecls.(0) rctx in
  let nargs = mip.mind_consnrealdecls.(0) in
  let ci =
    {
      Constr.ci_ind = ind;
      ci_npar = npar;
      ci_cstr_ndecls = mip.mind_consnrealdecls;
      ci_cstr_nargs = mip.mind_consnrealargs;
      ci_pp_info = { style = LetStyle };
    }
  in
  let params = Array.map EConstr.Unsafe.to_constr (Array.sub args 0 npar) in
  let self_annot = Context.make_annot Name.Anonymous mip.mind_relevance in
  let self_ty =
    Constr.mkApp
      (Constr.mkIndU indu, Array.map EConstr.Unsafe.to_constr args)
  in
  let env_self =
    Environ.push_rel
      (Context.Rel.Declaration.LocalAssum (self_annot, self_ty)) env
  in
  let args_self =
    Array.map
      (fun arg ->
        EConstr.of_constr (Vars.lift 1 (EConstr.Unsafe.to_constr arg)))
      args
  in
  let ret_ty =
    let ctor = Constr.mkConstructU (((fst ind, 0), 1), u) in
    let ctor_applied = Constr.mkApp (ctor, params) in
    let rec get_field_type i ty =
      match Constr.kind ty with
      | Constr.Prod (_, t, rest) ->
        if i = field then t
        else
          let previous =
            unfold_proj_case env_self evd ~field:i ~indu ~mib ~mip
              ~args:args_self (Constr.mkRel 1)
          in
          get_field_type (i + 1) (Vars.subst1 previous rest)
      | _ -> assert false
    in
    let ctor_ty =
      Retyping.get_type_of env evd (EConstr.of_constr ctor_applied)
    in
    let ctor_ty =
      EConstr.Unsafe.to_constr (Reductionops.whd_all env evd ctor_ty)
    in
    get_field_type 0 (Vars.lift 1 ctor_ty)
  in
  let case_relev =
    EConstr.Unsafe.to_relevance
      (Retyping.relevance_of_type env_self evd (EConstr.of_constr ret_ty))
  in
  let p = ([| self_annot |], ret_ty) in
  let branch_nas =
    Array.of_list (List.rev_map Context.Rel.Declaration.get_annot ctor_ctx)
  in
  let branch = (branch_nas, Constr.mkRel (nargs - field)) in
  Constr.mkCase
    (ci, u, params, (p, case_relev), Constr.NoInvert, c, [| branch |])

let punit_eta_proof env evd proof_ty original =
  let annot, domain, codomain = Constr.destProd proof_ty in
  let ind, u = Constr.destInd domain in
  let mib, mip = Inductive.lookup_mind_specif env ind in
  if mib.mind_nparams <> 0 || Array.length mip.mind_consnames <> 1
     || mip.mind_consnrealargs.(0) <> 0
  then
    CErrors.user_err Pp.(str "Unexpected PUnit shape");
  let ci =
    {
      Constr.ci_ind = ind;
      ci_npar = 0;
      ci_cstr_ndecls = mip.mind_consnrealdecls;
      ci_cstr_nargs = mip.mind_consnrealargs;
      ci_pp_info = { style = LetStyle };
    }
  in
  let ctor = Constr.mkConstructU ((ind, 1), u) in
  let self_annot = Context.make_annot Name.Anonymous mip.mind_relevance in
  (* The case predicate is itself under the lambda being constructed.  Keep
     the product's bound variable as the predicate variable, but shift every
     reference to the surrounding environment past that lambda. *)
  let motive = ([| self_annot |], Vars.liftn 1 2 codomain) in
  let branch =
    ([||], Constr.mkApp (Vars.lift 1 original, [| ctor |]))
  in
  let case =
    Constr.mkCase
      ( ci,
        u,
        [||],
        (motive, Sorts.Irrelevant),
        Constr.NoInvert,
        Constr.mkRel 1,
        [| branch |] )
  in
  Constr.mkLambda (annot, domain, case)

(* Lean treats every inhabitant of PUnit as definitionally equal to [unit],
   while Rocq only obtains that equality by eliminating the inhabitant.  This
   matters not only for named PUnit instances: eta proofs can occur as fields
   of arbitrary structures (for example [ComputableSmall]).  At an
   application site we know the exact expected argument type, so repair such
   proof functions by case analysis when the translated argument itself is
   not convertible to that type. *)
let adapt_punit_eta_argument env evd expected argument =
  match Constr.kind expected with
  | Constr.Prod (_, expected_domain, _) ->
    let actual_ty =
      Retyping.get_type_of env evd (EConstr.of_constr argument)
      |> Reductionops.whd_all env evd
      |> EConstr.Unsafe.to_constr
    in
    begin
      match Constr.kind actual_ty with
      | Constr.Prod (_, actual_domain, _) ->
        let expected_domain =
          Reductionops.whd_all env evd (EConstr.of_constr expected_domain)
          |> EConstr.Unsafe.to_constr
        in
        begin
          match Constr.kind expected_domain with
          | Constr.Ind (ind, _) ->
            let mib, mip = Inductive.lookup_mind_specif env ind in
            if not (Id.equal mip.mind_typename (Id.of_string "PUnit"))
               || mib.mind_nparams <> 0
               || Array.length mip.mind_consnames <> 1
               || mip.mind_consnrealargs.(0) <> 0
               || not
                    (Reductionops.is_conv env evd
                       (EConstr.of_constr actual_domain)
                       (EConstr.of_constr expected_domain))
            then argument
            else
              let adapted = punit_eta_proof env evd expected argument in
              let adapted_ty =
                Retyping.get_type_of env evd (EConstr.of_constr adapted)
                |> EConstr.Unsafe.to_constr
              in
              if
                Reductionops.is_conv env evd (EConstr.of_constr adapted_ty)
                  (EConstr.of_constr expected)
              then adapted
              else argument
          | _ -> argument
        end
      | _ -> argument
    end
  | _ -> argument

let next_argument_type env evd head args =
  let partial = Constr.mkApp (head, args) in
  let ty =
    Retyping.get_type_of env evd (EConstr.of_constr partial)
    |> Reductionops.whd_all env evd
    |> EConstr.Unsafe.to_constr
  in
  let _, arg_ty, _ = Constr.destProd ty in
  arg_ty

let adapt_punit_comm_group env evd body =
  let rebuild_with_arg term index arg =
    let head, args = Constr.decompose_app term in
    let args = Array.copy args in
    args.(index) <- arg;
    Constr.mkApp (head, args)
  in
  let _, top_args = Constr.decompose_app body in
  let group = top_args.(1) in
  let _, group_args = Constr.decompose_app group in
  let div_inv_monoid = group_args.(1) in
  let _, div_args = Constr.decompose_app div_inv_monoid in
  let monoid = div_args.(1) in
  let monoid_head, monoid_args = Constr.decompose_app monoid in
  if Array.length monoid_args < 5 then
    CErrors.user_err Pp.(str "Unexpected PUnit CommGroup body shape");
  let proof2_ty =
    next_argument_type env evd monoid_head (Array.sub monoid_args 0 3)
  in
  let proof2 = punit_eta_proof env evd proof2_ty monoid_args.(3) in
  let proof3_prefix = Array.sub monoid_args 0 4 in
  proof3_prefix.(3) <- proof2;
  let proof3_ty = next_argument_type env evd monoid_head proof3_prefix in
  let proof3 = punit_eta_proof env evd proof3_ty monoid_args.(4) in
  let monoid =
    let args = Array.copy monoid_args in
    args.(3) <- proof2;
    args.(4) <- proof3;
    Constr.mkApp (monoid_head, args)
  in
  let div_inv_monoid = rebuild_with_arg div_inv_monoid 1 monoid in
  let group = rebuild_with_arg group 1 div_inv_monoid in
  rebuild_with_arg body 1 group

let lcnt = ref 0

let line_msg name =
  Feedback.msg_info Pp.(str "line " ++ int !lcnt ++ str ": " ++ N.pp name)

let ofnat_ofNat_name = N.append_list N.anon [ "OfNat"; "ofNat" ]
let instOfNatNat_name = N.append N.anon "instOfNatNat"
let instOfNat_name = N.append N.anon "instOfNat"
let nat_name = N.append N.anon "Nat"
let int_name = N.append N.anon "Int"
let list_name = N.append N.anon "List"
let option_name = N.append N.anon "Option"
let array_name = N.append N.anon "Array"
let prod_name = N.append N.anon "Prod"

let array_minds : MutInd.t list ref =
  Summary.ref ~name:"lean-array-minds" []

let prod_minds : MutInd.t list ref =
  Summary.ref ~name:"lean-prod-minds" []

let list_minds : MutInd.t list ref =
  Summary.ref ~name:"lean-list-minds" []

let option_minds : MutInd.t list ref =
  Summary.ref ~name:"lean-option-minds" []

type nested_array_focus = FocusMain | FocusArray | FocusList | FocusProd

type nested_array_shape = ArraySelf | ArrayProdSecond

type nested_array_rec_info = {
  base_rec : N.t;
  nparams : int;
  nctors : int;
  focus : nested_array_focus;
  shape : nested_array_shape;
}

let nested_array_rec_info : nested_array_rec_info N.Map.t ref =
  Summary.ref ~name:"lean-nested-array-recursor-info" N.Map.empty

type mutual_nested_focus = MutualMain of int | MutualAux of int

type mutual_nested_rec_info = {
  base_recs : N.t list;
  mind : MutInd.t;
  nparams : int;
  focus : mutual_nested_focus;
}

let mutual_nested_rec_info : mutual_nested_rec_info N.Map.t ref =
  Summary.ref ~name:"lean-mutual-nested-recursor-info" N.Map.empty

let is_const_named expected = function
  | Const (n, _) -> N.equal n expected
  | _ -> false

let rec has_const_head expected = function
  | Const (n, _) -> N.equal n expected
  | App (f, _) -> has_const_head expected f
  | _ -> false

let append_array a b = Array.append a b

let extended_all_uctx source_uctx =
  let source_inst = UContext.instance source_uctx in
  let source_names = UContext.names source_uctx in
  let qinst, uinst = Instance.to_array source_inst in
  let q = Sorts.Quality.var (Array.length qinst) in
  let u = Level.var (Array.length uinst) in
  let names =
    {
      quals = append_array source_names.quals [| Name (Id.of_string "s") |];
      univs = append_array source_names.univs [| Name (Id.of_string "motive") |];
    }
  in
  let inst = Instance.of_array (append_array qinst [| q |], append_array uinst [| u |]) in
  (UContext.make names (inst, UContext.constraints source_uctx), source_inst, q, u)

let sort_universe_of_type ty =
  match Constr.kind ty with
  | Sort s -> Sorts.univ_of_sort s
  | _ -> Universe.type0

let qsort q u = Constr.mkSort (Sorts.make q u)

let qname q u id =
  Context.make_annot
    (Name (Id.of_string id))
    (Sorts.relevance_of_sort (Sorts.make q u))

let reln n = Constr.mkRel n

let app f args = Constr.mkApp (f, Array.of_list args)

let mk_global_ref ref inst = Constr.mkRef (ref, inst)

let declare_transparent_proof name ty tactic =
  let scope = Locality.(Global ImportDefaultBehavior) in
  let kind = Decls.(IsDefinition Definition) in
  let info = Declare.Info.make ~scope ~kind () in
  let cinfo = Declare.CInfo.make ~name ~typ:(EConstr.of_constr ty) () in
  let proof = Declare.Proof.start ~info ~cinfo (Evd.from_env (Global.env ())) in
  let raw_tac = Procq.parse_string Ltac_plugin.Pltac.tactic_eoi tactic in
  let proof, safe =
    Declare.Proof.by (Global.env ()) (Ltac_plugin.Tacinterp.interp raw_tac) proof
  in
  if not safe then
    CErrors.user_err Pp.(str "Unsafe tactic used while declaring " ++ Id.print name);
  match
    Declare.Proof.save_regular ~proof ~opaque:Vernacexpr.Transparent ~idopt:None
  with
  | [ ConstRef c ] -> c
  | _ -> CErrors.user_err Pp.(str "Unexpected proof output for " ++ Id.print name)

let all_name ind_name = Id.of_string (Id.to_string ind_name ^ "_all")
let all_forall_name ind_name =
  Id.of_string (Id.to_string ind_name ^ "_all_forall")

let _declare_list_all_scheme mind ind_name source_uctx source_params =
  match source_params with
  | [ RelDecl.LocalAssum (a_na, a_ty) ] ->
    let all_uctx, source_inst, q, motive_level = extended_all_uctx source_uctx in
    let motive_univ = Universe.make motive_level in
    let a_univ = sort_universe_of_type a_ty in
    let all_sort =
      qsort q (Universe.sup Universe.type0 (Universe.sup a_univ motive_univ))
    in
    let motive_sort = qsort q motive_univ in
    let a_decl = RelDecl.LocalAssum (a_na, a_ty) in
    let p_na = Context.nameR (Id.of_string "P") in
    let p_ty =
      Constr.mkProd (Context.nameR (Id.of_string "x"), reln 1, motive_sort)
    in
    let p_decl = RelDecl.LocalAssum (p_na, p_ty) in
    let params = [ p_decl; a_decl ] in
    let list_ref = Constr.mkIndU ((mind, 0), source_inst) in
    let nil_ref = Constr.mkConstructU (((mind, 0), 1), source_inst) in
    let cons_ref = Constr.mkConstructU (((mind, 0), 2), source_inst) in
    let list_a rel_a = app list_ref [ reln rel_a ] in
    let nil_a rel_a = app nil_ref [ reln rel_a ] in
    let cons_a rel_a rel_hd rel_tl =
      app cons_ref [ reln rel_a; reln rel_hd; reln rel_tl ]
    in
    let all_app rel_all rel_a rel_p arg =
      app (reln rel_all) [ reln rel_a; reln rel_p; arg ]
    in
    let arity =
      Constr.mkProd
        (Context.nameR (Id.of_string "l"), list_a 2, all_sort)
    in
    let nil_ctor = all_app 3 2 1 (nil_a 2) in
    let cons_result = all_app 7 6 5 (cons_a 6 4 2) in
    let cons_ih =
      Constr.mkProd
        ( qname q motive_univ "ih",
          all_app 6 5 4 (reln 1),
          cons_result )
    in
    let cons_tail =
      Constr.mkProd (Context.nameR (Id.of_string "tail"), list_a 4, cons_ih)
    in
    let cons_pa =
      Constr.mkProd
        (qname q motive_univ "pa", app (reln 2) [ reln 1 ], cons_tail)
    in
    let cons_ctor =
      Constr.mkProd (Context.nameR (Id.of_string "head"), reln 2, cons_pa)
    in
    let all_ind_name = all_name ind_name in
    let all_mind =
      DeclareInd.declare_mutual_inductive_with_eliminations
        {
          Entries.mind_entry_params = params;
          mind_entry_record = None;
          mind_entry_finite = Declarations.Finite;
          mind_entry_inds =
            [
              {
                mind_entry_typename = all_ind_name;
                mind_entry_arity = arity;
                mind_entry_consnames =
                  [
                    Id.of_string (Id.to_string ind_name ^ "_nil_all");
                    Id.of_string (Id.to_string ind_name ^ "_cons_all");
                  ];
                mind_entry_lc = [ nil_ctor; cons_ctor ];
              };
            ];
          mind_entry_private = None;
          mind_entry_universes = Entries.Polymorphic_ind_entry all_uctx;
          mind_entry_variance = None;
        }
        (UState.Polymorphic_entry all_uctx, UnivNames.empty_binders)
        []
    in
    DeclareScheme.declare_scheme Libobject.SuperGlobal "All"
      (GlobRef.IndRef (mind, 0), GlobRef.IndRef (all_mind, 0));
    let all_inst = UContext.instance all_uctx in
    let all_ref = Constr.mkIndU ((all_mind, 0), all_inst) in
    let forall_ty =
      let result = app all_ref [ reln 4; reln 3; reln 1 ] in
      let l_ty = list_a 3 in
      let h_ty =
        Constr.mkProd
          (Context.nameR (Id.of_string "x"), reln 2, app (reln 2) [ reln 1 ])
      in
      let p_ty =
        Constr.mkProd (Context.nameR (Id.of_string "x"), reln 1, motive_sort)
      in
      Constr.mkProd
        ( Context.nameR (Id.of_string "A"),
          a_ty,
          Constr.mkProd
            ( p_na,
              p_ty,
              Constr.mkProd
                ( Context.nameR (Id.of_string "h"),
                  h_ty,
                  Constr.mkProd (Context.nameR (Id.of_string "l"), l_ty, result)
                ) ) )
    in
    let forall_name = all_forall_name ind_name in
    let forall_c =
      declare_transparent_proof forall_name forall_ty
        {|
intros A P h l;
revert l;
fix F 1;
intros l;
destruct l as [|a l]; constructor;
[ exact (h a) | exact (F l) ]
        |}
    in
    DeclareScheme.declare_scheme Libobject.SuperGlobal "AllForall"
      (GlobRef.IndRef (mind, 0), GlobRef.ConstRef forall_c)
  | _ -> ()

let dest_nested_ind_app c =
  let hd, args = Constr.decompose_app c in
  match Constr.kind hd with
  | Ind (ind, inst) -> Some (ind, inst, args)
  | _ -> None

let declare_array_all_scheme mind ind_name source_uctx fields projections =
  match (fields, projections) with
  | [ (_, field_ty) ], [ { Structures.Structure.proj_body = Some proj_c; _ } ] -> (
    match dest_nested_ind_app (EConstr.Unsafe.to_constr field_ty) with
    | Some (list_ind, list_inst, field_args) when Array.length field_args = 1 -> (
      match
        ( DeclareScheme.lookup_scheme_opt "All" (GlobRef.IndRef list_ind),
          DeclareScheme.lookup_scheme_opt "AllForall" (GlobRef.IndRef list_ind) )
      with
      | Some list_all_ref, Some list_all_forall_ref ->
        let all_uctx, source_inst, q, motive_level =
          extended_all_uctx source_uctx
        in
        let motive_univ = Universe.make motive_level in
        let a_ty =
          let params = (Global.lookup_mind mind).mind_params_ctxt in
          match params with
          | [ RelDecl.LocalAssum (_, ty) ] -> ty
          | _ -> Constr.mkSet
        in
        let motive_sort = qsort q motive_univ in
        let qinst, uinst = Instance.to_array list_inst in
        let list_all_inst =
          Instance.of_array
            ( append_array qinst [| q |],
              append_array uinst [| motive_level |] )
        in
        let list_all = mk_global_ref list_all_ref list_all_inst in
        let list_all_forall = mk_global_ref list_all_forall_ref list_all_inst in
        let array_ref = Constr.mkIndU ((mind, 0), source_inst) in
        let proj_ref = Constr.mkConstU (proj_c, source_inst) in
        let array_a rel_a = app array_ref [ reln rel_a ] in
        let proj_a rel_a rel_arr = app proj_ref [ reln rel_a; reln rel_arr ] in
        let all_body =
          let body = app list_all [ reln 3; reln 2; proj_a 3 1 ] in
          Constr.mkLambda
            ( Context.nameR (Id.of_string "A"),
              a_ty,
              Constr.mkLambda
                ( Context.nameR (Id.of_string "P"),
                  Constr.mkProd
                    (Context.nameR (Id.of_string "x"), reln 1, motive_sort),
                  Constr.mkLambda
                    ( Context.nameR (Id.of_string "a"),
                      array_a 2,
                      body ) ) )
        in
        let univs = (UState.Polymorphic_entry all_uctx, UnivNames.empty_binders) in
        let all_c =
          quickdef ~name:(all_name ind_name) ~types:None ~univs all_body
        in
        DeclareScheme.declare_scheme Libobject.SuperGlobal "All"
          (GlobRef.IndRef (mind, 0), all_c);
        let forall_body =
          let body =
            app list_all_forall [ reln 4; reln 3; reln 2; proj_a 4 1 ]
          in
          Constr.mkLambda
            ( Context.nameR (Id.of_string "A"),
              a_ty,
              Constr.mkLambda
                ( Context.nameR (Id.of_string "P"),
                  Constr.mkProd
                    (Context.nameR (Id.of_string "x"), reln 1, motive_sort),
                  Constr.mkLambda
                    ( qname q motive_univ "h",
                      Constr.mkProd
                        ( Context.nameR (Id.of_string "x"),
                          reln 2,
                          app (reln 2) [ reln 1 ] ),
                      Constr.mkLambda
                        ( Context.nameR (Id.of_string "a"),
                          array_a 3,
                          body ) ) ) )
        in
        let forall_c =
          quickdef ~name:(all_forall_name ind_name) ~types:None ~univs forall_body
        in
        DeclareScheme.declare_scheme Libobject.SuperGlobal "AllForall"
          (GlobRef.IndRef (mind, 0), forall_c)
      | _ -> ())
    | _ -> ())
  | _ -> ()

let declare_prod_second_all_scheme mind ind_name source_uctx projections =
  match projections with
  | [ _; { Structures.Structure.proj_body = Some snd_c; _ } ] ->
    let all_uctx, source_inst, q, motive_level =
      extended_all_uctx source_uctx
    in
    let motive_univ = Universe.make motive_level in
    let motive_sort = qsort q motive_univ in
    let params = (Global.lookup_mind mind).mind_params_ctxt in
    let a_ty, b_ty =
      match params with
      | [ RelDecl.LocalAssum (_, b_ty); RelDecl.LocalAssum (_, a_ty) ] ->
        (a_ty, b_ty)
      | _ -> (Constr.mkSet, Constr.mkSet)
    in
    let prod_ref = Constr.mkIndU ((mind, 0), source_inst) in
    let snd_ref = Constr.mkConstU (snd_c, source_inst) in
    let motive_ty =
      Constr.mkProd (Context.nameR (Id.of_string "x"), reln 1, motive_sort)
    in
    let prod_ab rel_a rel_b = app prod_ref [ reln rel_a; reln rel_b ] in
    let snd_abp rel_a rel_b rel_p =
      app snd_ref [ reln rel_a; reln rel_b; reln rel_p ]
    in
    let all_body =
      Constr.mkLambda
        ( Context.nameR (Id.of_string "A"),
          a_ty,
          Constr.mkLambda
            ( Context.nameR (Id.of_string "B"),
              b_ty,
              Constr.mkLambda
                ( Context.nameR (Id.of_string "P"),
                  motive_ty,
                  Constr.mkLambda
                    ( Context.nameR (Id.of_string "p"),
                      prod_ab 3 2,
                      app (reln 2) [ snd_abp 4 3 1 ] ) ) ) )
    in
    let univs =
      (UState.Polymorphic_entry all_uctx, UnivNames.empty_binders)
    in
    let all_c =
      quickdef ~name:(Id.of_string (Id.to_string ind_name ^ "_all_01"))
        ~types:None ~univs all_body
    in
    DeclareScheme.declare_scheme Libobject.SuperGlobal "All_01"
      (GlobRef.IndRef (mind, 0), all_c);
    let all_forall_body =
      Constr.mkLambda
        ( Context.nameR (Id.of_string "A"),
          a_ty,
          Constr.mkLambda
            ( Context.nameR (Id.of_string "B"),
              b_ty,
              Constr.mkLambda
                ( Context.nameR (Id.of_string "P"),
                  motive_ty,
                  Constr.mkLambda
                    ( qname q motive_univ "h",
                      Constr.mkProd
                        ( Context.nameR (Id.of_string "x"),
                          reln 2,
                          app (reln 2) [ reln 1 ] ),
                      Constr.mkLambda
                        ( Context.nameR (Id.of_string "p"),
                          prod_ab 4 3,
                          app (reln 2) [ snd_abp 5 4 1 ] ) ) ) ) )
    in
    let all_forall_c =
      quickdef
        ~name:
          (Id.of_string (Id.to_string ind_name ^ "_all_forall_01"))
        ~types:None ~univs all_forall_body
    in
    DeclareScheme.declare_scheme Libobject.SuperGlobal "AllForall_01"
      (GlobRef.IndRef (mind, 0), all_forall_c)
  | _ -> ()

let declare_last_field_all_scheme mind ind_name source_uctx projections =
  match List.rev projections with
  | { Structures.Structure.proj_body = Some field_c; _ } :: _ -> (
    match (Global.lookup_mind mind).mind_params_ctxt with
    | [ RelDecl.LocalAssum (a_na, a_ty) ] ->
      let all_uctx, source_inst, q, motive_level =
        extended_all_uctx source_uctx
      in
      let motive_univ = Universe.make motive_level in
      let motive_sort = qsort q motive_univ in
      let ind_ref = Constr.mkIndU ((mind, 0), source_inst) in
      let field_ref = Constr.mkConstU (field_c, source_inst) in
      let motive_ty =
        Constr.mkProd
          (Context.nameR (Id.of_string "x"), reln 1, motive_sort)
      in
      let ind_a rel_a = app ind_ref [ reln rel_a ] in
      let field_ap rel_a rel_p = app field_ref [ reln rel_a; reln rel_p ] in
      let all_body =
        Constr.mkLambda
          ( a_na,
            a_ty,
            Constr.mkLambda
              ( Context.nameR (Id.of_string "P"),
                motive_ty,
                Constr.mkLambda
                  ( Context.nameR (Id.of_string "value"),
                    ind_a 2,
                    app (reln 2) [ field_ap 3 1 ] ) ) )
      in
      let univs =
        (UState.Polymorphic_entry all_uctx, UnivNames.empty_binders)
      in
      let all_c =
        quickdef ~name:(all_name ind_name) ~types:None ~univs all_body
      in
      DeclareScheme.declare_scheme Libobject.SuperGlobal "All"
        (GlobRef.IndRef (mind, 0), all_c);
      let all_forall_body =
        Constr.mkLambda
          ( a_na,
            a_ty,
            Constr.mkLambda
              ( Context.nameR (Id.of_string "P"),
                motive_ty,
                Constr.mkLambda
                  ( qname q motive_univ "h",
                    Constr.mkProd
                      ( Context.nameR (Id.of_string "x"),
                        reln 2,
                        app (reln 2) [ reln 1 ] ),
                    Constr.mkLambda
                      ( Context.nameR (Id.of_string "value"),
                        ind_a 3,
                        app (reln 2) [ field_ap 4 1 ] ) ) ) )
      in
      let all_forall_c =
        quickdef ~name:(all_forall_name ind_name) ~types:None ~univs
          all_forall_body
      in
      DeclareScheme.declare_scheme Libobject.SuperGlobal "AllForall"
        (GlobRef.IndRef (mind, 0), all_forall_c)
    | _ -> ())
  | _ -> ()

let rec decompose_lean_app acc = function
  | App (f, x) -> decompose_lean_app (x :: acc) f
  | head -> (head, acc)

let constr_app f args =
  match args with [] -> f | _ -> Constr.mkApp (f, Array.of_list args)

let whd_constr env evd c =
  EConstr.Unsafe.to_constr
    (Reductionops.whd_all env evd (EConstr.of_constr c))

let anon_annot_for_type env evd ty =
  Context.make_annot Name.Anonymous
    (EConstr.Unsafe.to_relevance
       (Retyping.relevance_of_type env evd (EConstr.of_constr ty)))

let prod_domain env evd ty =
  match Constr.kind (whd_constr env evd ty) with
  | Prod (_, domain, _) -> domain
  | _ -> CErrors.user_err Pp.(str "Nested recursor is over-applied")

let prod_codomain env evd ty =
  match Constr.kind (whd_constr env evd ty) with
  | Prod (_, _, body) -> body
  | _ -> CErrors.user_err Pp.(str "Expected a function type")

let prod_after_apply env evd ty arg =
  match Constr.kind (whd_constr env evd ty) with
  | Prod (_, _, body) -> Vars.subst1 arg body
  | _ -> CErrors.user_err Pp.(str "Nested recursor is over-applied")

let split_std_time_parse_with_body univs body =
  match Constr.kind body with
  | Constr.Lambda (config_na, config_ty, rest) -> (
    match Constr.kind rest with
    | Constr.Lambda (modifier_na, modifier_ty, core) ->
      let head, args = Constr.decompose_app core in
      let instance =
        match fst univs with
        | UState.Polymorphic_entry uctx -> UVars.UContext.instance uctx
        | UState.Monomorphic_entry _ -> UVars.Instance.empty
      in
      let helper_constants = ref [] in
      let () =
        match Constr.kind head with
        | Constr.Const (c, _) ->
          helper_constants := c :: !helper_constants;
          Global.set_strategy (Conv_oracle.EvalConstRef c) Conv_oracle.Opaque
        | _ -> ()
      in
      let register_helper = function
        | GlobRef.ConstRef c ->
          helper_constants := c :: !helper_constants;
          Global.set_strategy (Conv_oracle.EvalConstRef c) Conv_oracle.Opaque;
          Constr.mkConstU (c, instance)
        | _ -> assert false
      in
      let transport_with_nanosecond_equality raw_helper expected_helper_ty =
        let global_env = Global.env () in
        let global_evd = Evd.from_env global_env in
        let raw_ty =
          EConstr.Unsafe.to_constr
            (Retyping.get_type_of global_env global_evd
               (EConstr.of_constr raw_helper))
        in
        let branch_ty =
          prod_codomain global_env global_evd raw_ty
          |> prod_codomain global_env global_evd
        in
        let parser_head, parser_args = Constr.decompose_app branch_ty in
        let bounded_ty = parser_args.(Array.length parser_args - 1) in
        let bounded_head, bounded_args = Constr.decompose_app bounded_ty in
        let locate_constant name =
          match
            Nametab.locate
              (Libnames.qualid_of_ident (Id.of_string name))
          with
          | GlobRef.ConstRef c -> Constr.mkConstU (c, UVars.Instance.empty)
          | _ -> CErrors.user_err Pp.(str name ++ str " is not a constant")
        in
        let bound_eq =
          locate_constant "rocqLeanImportStdTimeParseWithNanoBoundEq3"
        in
        let cast = locate_constant "rocqLeanImportStdTimeParseWithCast3" in
        let eq_ty =
          EConstr.Unsafe.to_constr
            (Retyping.get_type_of global_env global_evd
               (EConstr.of_constr bound_eq))
        in
        let _, eq_args = Constr.decompose_app eq_ty in
        if Array.length eq_args <> 3 then
          CErrors.user_err Pp.(str "Unexpected nanosecond equality");
        let int_ty = eq_args.(0) in
        let bounded_args = Array.copy bounded_args in
        bounded_args.(Array.length bounded_args - 1) <- Constr.mkRel 1;
        let bounded_family = Constr.mkApp (bounded_head, bounded_args) in
        let parser_args = Array.copy parser_args in
        parser_args.(Array.length parser_args - 1) <- bounded_family;
        let family =
          Constr.mkLambda
            ( Context.nameR (Id.of_string "upper"),
              int_ty,
              Constr.mkApp (parser_head, parser_args) )
        in
        let argument_ty =
          prod_domain global_env global_evd
            (prod_codomain global_env global_evd expected_helper_ty)
        in
        let raw_value =
          Constr.mkApp
            (raw_helper, [| Constr.mkRel 2; Constr.mkRel 1 |])
        in
        let transported =
          Constr.mkApp
            ( cast,
              [|
                family;
                eq_args.(1);
                eq_args.(2);
                bound_eq;
                raw_value;
              |] )
        in
        let wrapper_body =
          Constr.mkLambda
            ( config_na,
              config_ty,
              Constr.mkLambda
                ( Context.nameR (Id.of_string "format"),
                  argument_ty,
                  transported ) )
        in
        quickdef
          ~name:
            (Id.of_string "rocqLeanImportStdTimeParseWithNanosecondBranch")
          ~types:(Some expected_helper_ty) ~univs wrapper_body
        |> register_helper
      in
      let split_nested_branch outer_index arg =
        if outer_index <> 21 then arg
        else
          match Constr.kind arg with
          | Constr.Lambda (inner_na, inner_ty, inner_core) ->
            let inner_head, inner_args = Constr.decompose_app inner_core in
            let inner_env = Global.env () in
            let inner_env =
              Environ.push_rel
                (RelDecl.LocalAssum (config_na, config_ty)) inner_env
            in
            let inner_env =
              Environ.push_rel
                (RelDecl.LocalAssum (inner_na, inner_ty)) inner_env
            in
            let inner_evd = Evd.from_env inner_env in
            let () =
              match Constr.kind inner_head with
              | Constr.Const (c, _) ->
                helper_constants := c :: !helper_constants;
                Global.set_strategy (Conv_oracle.EvalConstRef c)
                  Conv_oracle.Opaque
              | _ -> ()
            in
            let inner_recursor_ty =
              ref
                (EConstr.Unsafe.to_constr
                   (Retyping.get_type_of inner_env inner_evd
                      (EConstr.of_constr inner_head)))
            in
            let inner_args =
              Array.mapi
                (fun inner_index inner_arg ->
                  let domain =
                    prod_domain inner_env inner_evd !inner_recursor_ty
                  in
                  let mapped =
                    if
                      inner_index <> 0 && Vars.noccurn 1 inner_arg
                      && Vars.noccurn 1 domain
                    then begin
                      let helper_body =
                        Constr.mkLambda
                          ( config_na,
                            config_ty,
                            Vars.subst1 invalid inner_arg )
                      in
                      let raw_helper_ref =
                        quickdef
                          ~name:
                            (Id.of_string
                               ("rocqLeanImportStdTimeParseWithBranch"
                               ^ string_of_int outer_index ^ "Sub"
                               ^ string_of_int inner_index))
                          ~types:None ~univs helper_body
                      in
                      let raw_helper = register_helper raw_helper_ref in
                      let helper =
                        if inner_index <> 2 && inner_index <> 3 then raw_helper
                        else
                          let suffix = string_of_int inner_index in
                          let global_env = Global.env () in
                          let global_evd = Evd.from_env global_env in
                          let raw_ty =
                            EConstr.Unsafe.to_constr
                              (Retyping.get_type_of global_env global_evd
                                 (EConstr.of_constr raw_helper))
                          in
                          let branch_ty =
                            prod_codomain global_env global_evd raw_ty
                            |> prod_codomain global_env global_evd
                          in
                          let _, parser_args =
                            Constr.decompose_app branch_ty
                          in
                          let bounded_ty =
                            parser_args.(Array.length parser_args - 1)
                          in
                          let _, bounded_args =
                            Constr.decompose_app bounded_ty
                          in
                          let actual_upper =
                            bounded_args.(Array.length bounded_args - 1)
                          in
                          let _, cast_args =
                            Constr.decompose_app actual_upper
                          in
                          let nat_bound =
                            cast_args.(Array.length cast_args - 1)
                          in
                          let _, sub_args = Constr.decompose_app nat_bound in
                          if Array.length sub_args <> 2 then
                            CErrors.user_err
                              Pp.(str "Unexpected parseWith nano bound");
                          let billion = sub_args.(0) in
                          let one = sub_args.(1) in
                          let of_nat_sub =
                            match
                              Nametab.locate
                                (Libnames.qualid_of_ident
                                   (Id.of_string "Int_ofNat_sub"))
                            with
                            | GlobRef.ConstRef c ->
                              Constr.mkConstU (c, UVars.Instance.empty)
                            | _ ->
                              CErrors.user_err
                                Pp.(str "Int.ofNat_sub is not a constant")
                          in
                          let theorem_ty =
                            EConstr.Unsafe.to_constr
                              (Retyping.get_type_of global_env global_evd
                                 (EConstr.of_constr of_nat_sub))
                          in
                          let theorem_ty =
                            prod_after_apply global_env global_evd theorem_ty
                              one
                          in
                          let theorem_ty =
                            prod_after_apply global_env global_evd theorem_ty
                              billion
                          in
                          let le_ty =
                            prod_domain global_env global_evd theorem_ty
                          in
                          let le_const =
                            declare_transparent_proof
                              (Id.of_string
                                 ("rocqLeanImportStdTimeParseWithNanoLe"
                                 ^ suffix))
                              le_ty
                              {|
apply nat_le_Nat_le;
repeat rewrite nat_of_Nat_double;
cbn [nat_of_Nat];
lia
|}
                          in
                          let bound_eq_body =
                            Constr.mkApp
                              ( of_nat_sub,
                                [|
                                  one;
                                  billion;
                                  Constr.mkConstU
                                    (le_const, UVars.Instance.empty);
                                |] )
                          in
                          let bound_eq_ref =
                            quickdef
                              ~name:
                                (Id.of_string
                                   ("rocqLeanImportStdTimeParseWithNanoBoundEq"
                                   ^ suffix))
                              ~types:None ~univs bound_eq_body
                          in
                          let bound_eq = register_helper bound_eq_ref in
                          let eq_ty =
                            EConstr.Unsafe.to_constr
                              (Retyping.get_type_of (Global.env ())
                                 (Evd.from_env (Global.env ()))
                                 (EConstr.of_constr bound_eq))
                          in
                          let eq_head, eq_args =
                            Constr.decompose_app eq_ty
                          in
                          if Array.length eq_args <> 3 then
                            CErrors.user_err
                              Pp.(str "Unexpected Int.ofNat_sub equality");
                          let int_ty = eq_args.(0) in
                          let actual_bound = eq_args.(1) in
                          let expected_bound = eq_args.(2) in
                          let family_sort =
                            EConstr.Unsafe.to_constr
                              (Retyping.get_type_of global_env global_evd
                                 (EConstr.of_constr branch_ty))
                          in
                          let p_ty =
                            Constr.mkProd
                              ( Context.nameR (Id.of_string "upper"),
                                int_ty,
                                family_sort )
                          in
                          let cast_ty =
                            let eq_xy =
                              Constr.mkApp
                                ( eq_head,
                                  [|
                                    int_ty;
                                    Constr.mkRel 2;
                                    Constr.mkRel 1;
                                  |] )
                            in
                            let value_ty =
                              Constr.mkApp
                                (Constr.mkRel 4, [| Constr.mkRel 3 |])
                            in
                            let result_ty =
                              Constr.mkApp
                                (Constr.mkRel 5, [| Constr.mkRel 3 |])
                            in
                            Constr.mkProd
                              ( Context.nameR (Id.of_string "P"),
                                p_ty,
                                Constr.mkProd
                                  ( Context.nameR (Id.of_string "x"),
                                    int_ty,
                                    Constr.mkProd
                                      ( Context.nameR (Id.of_string "y"),
                                        int_ty,
                                        Constr.mkProd
                                          ( Context.make_annot
                                              (Name (Id.of_string "h"))
                                              Sorts.Irrelevant,
                                            eq_xy,
                                            Constr.mkProd
                                              ( Context.nameR
                                                  (Id.of_string "value"),
                                                value_ty,
                                                result_ty ) ) ) ) )
                          in
                          let cast_const =
                            declare_transparent_proof
                              (Id.of_string
                                 ("rocqLeanImportStdTimeParseWithCast"
                                 ^ suffix))
                              cast_ty
                              "intros P x y h value; destruct h; exact value"
                          in
                          let cast =
                            Constr.mkConstU
                              (cast_const, UVars.Instance.empty)
                          in
                          let bounded_args = Array.copy bounded_args in
                          bounded_args.(Array.length bounded_args - 1) <-
                            Constr.mkRel 1;
                          let bounded_family =
                            Constr.mkApp
                              (fst (Constr.decompose_app bounded_ty),
                               bounded_args)
                          in
                          let parser_args = Array.copy parser_args in
                          parser_args.(Array.length parser_args - 1) <-
                            bounded_family;
                          let parser_family =
                            Constr.mkApp
                              (fst (Constr.decompose_app branch_ty),
                               parser_args)
                          in
                          let family =
                            Constr.mkLambda
                              ( Context.nameR (Id.of_string "upper"),
                                int_ty,
                                parser_family )
                          in
                          let expected_helper_ty =
                            Constr.mkProd
                              ( config_na,
                                config_ty,
                                Vars.subst1 invalid domain )
                          in
                          let wrapper_body =
                            let raw_value =
                              Constr.mkApp
                                ( raw_helper,
                                  [| Constr.mkRel 2; Constr.mkRel 1 |] )
                            in
                            let transported =
                              Constr.mkApp
                                ( cast,
                                  [|
                                    family;
                                    actual_bound;
                                    expected_bound;
                                    bound_eq;
                                    raw_value;
                                  |] )
                            in
                            Constr.mkLambda
                              ( config_na,
                                config_ty,
                                Constr.mkLambda
                                  ( Context.nameR (Id.of_string "unit"),
                                    prod_domain global_env global_evd
                                      (prod_codomain global_env global_evd
                                         expected_helper_ty),
                                    transported ) )
                          in
                          let wrapper_ref =
                            quickdef
                              ~name:
                                (Id.of_string
                                   ("rocqLeanImportStdTimeParseWithNanoBranch"
                                   ^ suffix))
                              ~types:(Some expected_helper_ty) ~univs
                              wrapper_body
                          in
                          let wrapper = register_helper wrapper_ref in
                          wrapper
                      in
                      Constr.mkApp (helper, [| Constr.mkRel 2 |])
                    end
                    else inner_arg
                  in
                  inner_recursor_ty :=
                    prod_after_apply inner_env inner_evd !inner_recursor_ty
                      mapped;
                  mapped)
                inner_args
            in
            let inner_chain_ty =
              ref
                (EConstr.Unsafe.to_constr
                   (Retyping.get_type_of inner_env inner_evd
                      (EConstr.of_constr inner_head)))
            in
            let inner_chain = ref inner_head in
            Array.iteri
              (fun inner_index inner_arg ->
                let applied =
                  Constr.mkApp (!inner_chain, [| inner_arg |])
                in
                let applied_ty =
                  prod_after_apply inner_env inner_evd !inner_chain_ty
                    inner_arg
                in
                let step_body =
                  Constr.mkLambda
                    ( config_na,
                      config_ty,
                      Constr.mkLambda (inner_na, inner_ty, applied) )
                in
                let step_ty =
                  Constr.mkProd
                    ( config_na,
                      config_ty,
                      Constr.mkProd (inner_na, inner_ty, applied_ty) )
                in
                let step_ref =
                  quickdef
                    ~name:
                      (Id.of_string
                         ("rocqLeanImportStdTimeParseWithBranch21Step"
                         ^ string_of_int inner_index))
                    ~types:(Some step_ty) ~univs step_body
                in
                let step = register_helper step_ref in
                inner_chain :=
                  Constr.mkApp
                    (step, [| Constr.mkRel 2; Constr.mkRel 1 |]);
                inner_chain_ty := applied_ty)
              inner_args;
            Constr.mkLambda
              (inner_na, inner_ty, !inner_chain)
          | _ -> arg
      in
      let env = Global.env () in
      let env =
        Environ.push_rel (RelDecl.LocalAssum (config_na, config_ty)) env
      in
      let env =
        Environ.push_rel (RelDecl.LocalAssum (modifier_na, modifier_ty)) env
      in
      let evd = Evd.from_env env in
      let recursor_ty =
        ref
          (EConstr.Unsafe.to_constr
             (Retyping.get_type_of env evd (EConstr.of_constr head)))
      in
      let args =
        Array.mapi
          (fun index arg ->
            let domain = prod_domain env evd !recursor_ty in
            let mapped =
              if Vars.noccurn 1 arg && Vars.noccurn 1 domain then begin
                let arg = Vars.subst1 invalid arg in
                let arg = split_nested_branch index arg in
                let helper_body =
                    Constr.mkLambda (config_na, config_ty, arg)
                  in
                  let helper_ty =
                    Constr.mkProd
                      (config_na, config_ty, Vars.subst1 invalid domain)
                  in
                  let helper_ref =
                    let helper_types =
                      if index = 23 then None else Some helper_ty
                    in
                    quickdef
                      ~name:
                        (Id.of_string
                           ("rocqLeanImportStdTimeParseWithBranch"
                           ^ string_of_int index))
                      ~types:helper_types ~univs helper_body
                  in
                let helper = register_helper helper_ref in
                let helper =
                  if index = 23 then
                    transport_with_nanosecond_equality helper helper_ty
                  else helper
                in
                  Constr.mkApp (helper, [| Constr.mkRel 2 |])
              end
              else arg
            in
            recursor_ty := prod_after_apply env evd !recursor_ty mapped;
            mapped)
          args
      in
      let chain_ty =
        ref
          (EConstr.Unsafe.to_constr
             (Retyping.get_type_of env evd (EConstr.of_constr head)))
      in
      let chain = ref head in
      Array.iteri
        (fun index arg ->
          let applied = Constr.mkApp (!chain, [| arg |]) in
          let applied_ty = prod_after_apply env evd !chain_ty arg in
          let step_body =
            Constr.mkLambda
              ( config_na,
                config_ty,
                Constr.mkLambda (modifier_na, modifier_ty, applied) )
          in
          let step_ty =
            Constr.mkProd
              ( config_na,
                config_ty,
                Constr.mkProd (modifier_na, modifier_ty, applied_ty) )
          in
          let step_ref =
            quickdef
              ~name:
                (Id.of_string
                   ("rocqLeanImportStdTimeParseWithStep"
                   ^ string_of_int index))
              ~types:(Some step_ty) ~univs step_body
          in
          let step = register_helper step_ref in
          chain :=
            Constr.mkApp
              (step, [| Constr.mkRel 2; Constr.mkRel 1 |]);
          chain_ty := applied_ty)
        args;
      let core = !chain in
      let result_ty = !chain_ty in
      let helper_ty =
        Constr.mkProd
          ( config_na,
            config_ty,
            Constr.mkProd (modifier_na, modifier_ty, result_ty) )
      in
      ( Constr.mkLambda
          ( config_na,
            config_ty,
            Constr.mkLambda (modifier_na, modifier_ty, core) ),
        helper_ty,
        !helper_constants )
    | _ -> CErrors.user_err Pp.(str "Unexpected parseWith body shape"))
  | _ -> CErrors.user_err Pp.(str "Unexpected parseWith body shape")

let list_all_info env evd ty =
  let ty = whd_constr env evd ty in
  let head, args = Constr.decompose_app ty in
  match Constr.kind head with
  | Ind ((mind, _) as ind, inst)
    when Array.length args = 3
         && String.ends_with
              ~suffix:"_all"
              (Id.to_string
                 (Global.lookup_mind mind).mind_packets.(snd ind).mind_typename)
    -> Some (ind, inst, args)
  | _ -> None

let nested_list_fold env evd ~depth ~motive_list ~nil_case ~cons_case
    ~prod_case ~all_term ~all_inst ~all_ind ~all_args =
  let open Constr in
  let qinst, uinst = Instance.to_array all_inst in
  if Array.length uinst = 0 then
    CErrors.user_err Pp.(str "Nested List.All has no motive universe");
  let motive_level = uinst.(Array.length uinst - 1) in
  let all_head = mkIndU (all_ind, all_inst) in
  let a = all_args.(0) in
  let p = all_args.(1) in
  let list = all_args.(2) in
  let motive_family =
    let motive_at_list = constr_app motive_list [ list ] in
    let sort =
      whd_constr env evd
        (EConstr.Unsafe.to_constr
           (Retyping.get_type_of env evd (EConstr.of_constr motive_at_list)))
    in
    match kind sort with
    | Sort sort -> UnivGen.QualityOrSet.of_sort sort
    | _ -> CErrors.user_err Pp.(str "Nested List motive is not a type")
  in
  let motive_is_sprop = UnivGen.QualityOrSet.is_sprop motive_family in
  (* An erased nested motive needs the SProp eliminator: forcing the Type
     eliminator changes the expected relevance of its recursive hypotheses. *)
  let rect_family =
    if motive_is_sprop then UnivGen.QualityOrSet.sprop
    else UnivGen.QualityOrSet.qtype
  in
  let rect_inst =
    if motive_is_sprop then all_inst
    else Instance.of_array (qinst, append_array uinst [| motive_level |])
  in
  let rect_ref =
    Elimschemes.lookup_eliminator env all_ind rect_family
  in
  let rect = mkRef (rect_ref, rect_inst) in
  let list_ty =
    EConstr.Unsafe.to_constr
      (Retyping.get_type_of env evd (EConstr.of_constr list))
  in
  let motive_list_here = Vars.lift depth motive_list in
  let motive =
    let list_annot = anon_annot_for_type env evd list_ty in
    let env_list =
      Environ.push_rel (RelDecl.LocalAssum (list_annot, list_ty)) env
    in
    let all_l =
      constr_app (Vars.lift 2 all_head)
        [ Vars.lift 1 a; Vars.lift 1 p; mkRel 1 ]
    in
    let all_l_annot = anon_annot_for_type env_list evd all_l in
    let body = constr_app (Vars.lift 2 motive_list_here) [ mkRel 2 ] in
    mkLambda
      ( list_annot,
        list_ty,
        mkLambda (all_l_annot, all_l, body) )
  in
  let cons_branch =
    let a_here = a in
    let p_here = p in
    let list_ty_here = list_ty in
    let head_ty = a_here in
    let head_annot = anon_annot_for_type env evd head_ty in
    let env_head =
      Environ.push_rel (RelDecl.LocalAssum (head_annot, head_ty)) env
    in
    let p_head_ty = constr_app (Vars.lift 1 p_here) [ mkRel 1 ] in
    let p_head_annot = anon_annot_for_type env_head evd p_head_ty in
    let env_p_head =
      Environ.push_rel
        (RelDecl.LocalAssum (p_head_annot, p_head_ty))
        env_head
    in
    let tail_ty = Vars.lift 2 list_ty_here in
    let tail_annot = anon_annot_for_type env_p_head evd tail_ty in
    let env_tail =
      Environ.push_rel (RelDecl.LocalAssum (tail_annot, tail_ty)) env_p_head
    in
    let all_tail_ty =
      constr_app (Vars.lift 3 all_head)
        [ Vars.lift 3 a_here; Vars.lift 3 p_here; mkRel 1 ]
    in
    let all_tail_annot = anon_annot_for_type env_tail evd all_tail_ty in
    let env_all_tail =
      Environ.push_rel
        (RelDecl.LocalAssum (all_tail_annot, all_tail_ty))
        env_tail
    in
    let ih_ty =
      constr_app (Vars.lift 4 motive_list_here) [ mkRel 2 ]
    in
    let ih_annot = anon_annot_for_type env_all_tail evd ih_ty in
    let body =
      let head_ih =
        match prod_case with
        | None -> mkRel 4
        | Some prod_case ->
          let prod_head, _ = decompose_app a_here in
          let prod_ind, _ =
            match kind prod_head with
            | Ind (ind, inst) -> (ind, inst)
            | _ -> CErrors.user_err Pp.(str "Nested element is not a Prod")
          in
          let mib = Global.lookup_mind (fst prod_ind) in
          let fst_p, fst_r =
            Declareops.inductive_make_projection prod_ind mib ~proj_arg:0
          in
          let snd_p, snd_r =
            Declareops.inductive_make_projection prod_ind mib ~proj_arg:1
          in
          let head = mkRel 5 in
          let fst = mkProj (Projection.make fst_p false, fst_r, head) in
          let snd = mkProj (Projection.make snd_p false, snd_r, head) in
          constr_app (Vars.lift (depth + 5) prod_case)
            [ fst; snd; mkRel 4 ]
      in
      constr_app (Vars.lift (depth + 5) cons_case)
        [ mkRel 5; mkRel 3; head_ih; mkRel 1 ]
    in
    mkLambda
      ( head_annot,
        head_ty,
        mkLambda
          ( p_head_annot,
            p_head_ty,
            mkLambda
              ( tail_annot,
                tail_ty,
                mkLambda
                  ( all_tail_annot,
                    all_tail_ty,
                    mkLambda (ih_annot, ih_ty, body) ) ) ) )
  in
  let folded =
    constr_app rect
      [
        a;
        p;
        motive;
        Vars.lift depth nil_case;
        cons_branch;
        list;
        all_term;
      ]
  in
  (list, folded)

let nested_array_fold env evd ~depth ~motive_list ~array_case ~nil_case
    ~cons_case ~prod_case ~all_inst ~all_ind ~all_args =
  let list, folded =
    nested_list_fold env evd ~depth ~motive_list ~nil_case ~cons_case
      ~prod_case ~all_term:(Constr.mkRel 1) ~all_inst ~all_ind ~all_args
  in
  constr_app (Vars.lift depth array_case) [ list; folded ]

let adapt_nested_array_branch env evd ~motive_list ~array_case ~nil_case
    ~cons_case ~prod_case branch_ty branch =
  let rec loop env depth ty mapped =
    let ty = whd_constr env evd ty in
    match Constr.kind ty with
    | Prod (annot, binder_ty, body) ->
      let all_info = list_all_info env evd binder_ty in
      let env' =
        Environ.push_rel
          (RelDecl.LocalAssum (annot, binder_ty))
          env
      in
      let mapped = List.map (Vars.lift 1) mapped in
      let mapped_arg =
        match all_info with
        | None -> Constr.mkRel 1
        | Some (all_ind, all_inst, all_args) ->
          let all_args = Array.map (Vars.lift 1) all_args in
          nested_array_fold env' evd ~depth:(depth + 1) ~motive_list
            ~array_case ~nil_case ~cons_case ~prod_case ~all_inst ~all_ind
            ~all_args
      in
      let inner = loop env' (depth + 1) body (mapped @ [ mapped_arg ]) in
      Constr.mkLambda (annot, binder_ty, inner)
    | _ -> constr_app (Vars.lift depth branch) mapped
  in
  loop env 0 branch_ty []

let nested_list_all_forall env evd recursor motive main_rec list =
  let list_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr list)))
  in
  let list_head, list_args = Constr.decompose_app list_ty in
  let list_ind, list_inst =
    match Constr.kind list_head with
    | Ind (ind, inst) when Array.length list_args = 1 -> (ind, inst)
    | _ -> CErrors.user_err Pp.(str "Nested Array projection is not a List")
  in
  let all_ind, all_forall_ref =
    match
      ( DeclareScheme.lookup_scheme_opt "All" (GlobRef.IndRef list_ind),
        DeclareScheme.lookup_scheme_opt "AllForall" (GlobRef.IndRef list_ind) )
    with
    | Some (GlobRef.IndRef all_ind), Some all_forall_ref ->
      (all_ind, all_forall_ref)
    | _ -> CErrors.user_err Pp.(str "Nested List schemes are unavailable")
  in
  let _, rec_inst = Constr.destConst recursor in
  let _, rec_levels = Instance.to_array rec_inst in
  if Array.length rec_levels = 0 then
    CErrors.user_err Pp.(str "Nested recursor has no motive universe");
  let motive_level = rec_levels.(0) in
  let list_qs, list_levels = Instance.to_array list_inst in
  let all_inst =
    Instance.of_array
      ( append_array list_qs [| Sorts.Quality.qtype |],
        append_array list_levels [| motive_level |] )
  in
  let all_forall = Constr.mkRef (all_forall_ref, all_inst) in
  let a = list_args.(0) in
  let all_term = constr_app all_forall [ a; motive; main_rec; list ] in
  let all_args = [| a; motive; list |] in
  (all_ind, all_inst, all_args, all_term)

let prod_parts env evd prod =
  let prod_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr prod)))
  in
  let prod_head, _ = Constr.decompose_app prod_ty in
  let prod_ind =
    match Constr.kind prod_head with
    | Ind (ind, _) -> ind
    | _ -> CErrors.user_err Pp.(str "Nested recursor target is not a Prod")
  in
  let mib = Global.lookup_mind (fst prod_ind) in
  let fst_p, fst_r =
    Declareops.inductive_make_projection prod_ind mib ~proj_arg:0
  in
  let snd_p, snd_r =
    Declareops.inductive_make_projection prod_ind mib ~proj_arg:1
  in
  ( Constr.mkProj (Projection.make fst_p false, fst_r, prod),
    Constr.mkProj (Projection.make snd_p false, snd_r, prod) )

let adapt_nested_array_recursor env evd info recursor args =
  let nctors = info.nctors in
  let nmotives, ncontainer_cases =
    match info.shape with ArraySelf -> (3, 3) | ArrayProdSecond -> (4, 4)
  in
  let needed = info.nparams + nmotives + nctors + ncontainer_cases + 1 in
  if List.length args < needed then None
  else
    let params, args = CList.chop info.nparams args in
    let motive, args = (List.hd args, List.tl args) in
    let motive_array, args = (List.hd args, List.tl args) in
    let motive_list, args = (List.hd args, List.tl args) in
    let motive_prod, args =
      match info.shape with
      | ArraySelf -> (None, args)
      | ArrayProdSecond -> (Some (List.hd args), List.tl args)
    in
    let branches, args = CList.chop nctors args in
    let array_case, args = (List.hd args, List.tl args) in
    let nil_case, args = (List.hd args, List.tl args) in
    let cons_case, args = (List.hd args, List.tl args) in
    let prod_case, args =
      match info.shape with
      | ArraySelf -> (None, args)
      | ArrayProdSecond -> (Some (List.hd args), List.tl args)
    in
    let target, extra = (List.hd args, List.tl args) in
    let rec_ty =
      EConstr.Unsafe.to_constr
        (Retyping.get_type_of env evd (EConstr.of_constr recursor))
    in
    let rec_ty =
      List.fold_left (prod_after_apply env evd) rec_ty params
    in
    let rec_ty = prod_after_apply env evd rec_ty motive in
    let rec_ty, branches =
      CList.fold_left_map
        (fun rec_ty branch ->
          let branch_ty = prod_domain env evd rec_ty in
          let branch =
            adapt_nested_array_branch env evd ~motive_list ~array_case
              ~nil_case ~cons_case ~prod_case branch_ty branch
          in
          (prod_after_apply env evd rec_ty branch, branch))
        rec_ty branches
    in
    let _ = rec_ty in
    let main_rec = constr_app recursor (params @ (motive :: branches)) in
    let adapted =
      match info.focus with
      | FocusMain -> constr_app main_rec (target :: extra)
      | FocusArray | FocusList ->
        let list =
          match info.focus with
          | FocusList -> target
          | FocusArray ->
            let target_ty =
              whd_constr env evd
                (EConstr.Unsafe.to_constr
                   (Retyping.get_type_of env evd (EConstr.of_constr target)))
            in
            let target_head, _ = Constr.decompose_app target_ty in
            let array_ind, array_inst =
              match Constr.kind target_head with
              | Ind (ind, inst) -> (ind, inst)
              | _ ->
                CErrors.user_err Pp.(str "Nested recursor target is not an Array")
            in
            let mib = Global.lookup_mind (fst array_ind) in
            let projection, relevance =
              Declareops.inductive_make_projection array_ind mib ~proj_arg:0
            in
            Constr.mkProj
              ( Projection.make projection false,
                relevance,
                target )
          | FocusMain | FocusProd -> assert false
        in
        let element_motive, element_rec =
          match info.shape with
          | ArraySelf -> (motive, main_rec)
          | ArrayProdSecond ->
            let list_ty =
              whd_constr env evd
                (EConstr.Unsafe.to_constr
                   (Retyping.get_type_of env evd (EConstr.of_constr list)))
            in
            let _, list_args = Constr.decompose_app list_ty in
            let element_ty = list_args.(0) in
            let make_body f =
              let _, snd = prod_parts
                  (Environ.push_rel
                    (RelDecl.LocalAssum (Context.anonR, element_ty)) env)
                  evd (Constr.mkRel 1)
              in
              Constr.mkLambda
                (Context.anonR, element_ty, constr_app (Vars.lift 1 f) [ snd ])
            in
            (make_body motive, make_body main_rec)
        in
        let all_ind, all_inst, all_args, all_term =
          nested_list_all_forall env evd recursor element_motive element_rec
            list
        in
        let list, folded =
          nested_list_fold env evd ~depth:0 ~motive_list ~nil_case
            ~cons_case ~prod_case ~all_term ~all_inst ~all_ind ~all_args
        in
        let result =
          match info.focus with
          | FocusArray -> constr_app array_case [ list; folded ]
          | FocusList -> folded
          | FocusMain | FocusProd -> assert false
        in
        let _ = motive_array in
        constr_app result extra
      | FocusProd ->
        let prod_case = Option.get prod_case in
        let fst, snd = prod_parts env evd target in
        let result = constr_app prod_case [ fst; snd; constr_app main_rec [ snd ] ] in
        let _ = motive_prod in
        constr_app result extra
    in
    Some adapted

type mutual_aux_spec = {
  aux_domain : Constr.t;
  aux_motive : Constr.t;
  aux_cases : Constr.t list;
}

let mind_is_one_of mind minds =
  List.exists (MutInd.UserOrd.equal mind) minds

let type_head_ind env evd ty =
  let ty = whd_constr env evd ty in
  let head, args = Constr.decompose_app ty in
  match Constr.kind head with
  | Constr.Ind (ind, inst) -> Some (ind, inst, args)
  | _ -> None

let motive_domain env evd motive =
  let ty =
    EConstr.Unsafe.to_constr
      (Retyping.get_type_of env evd (EConstr.of_constr motive))
  in
  match Constr.kind (whd_constr env evd ty) with
  | Constr.Prod (_, domain, _) -> Some domain
  | _ -> None

let convertible env evd a b =
  Reductionops.is_conv env evd (EConstr.of_constr a) (EConstr.of_constr b)

let aux_ctor_count env evd domain =
  match type_head_ind env evd domain with
  | Some ((mind, index), _, _) ->
    Some
      (Array.length
         (Global.lookup_mind mind).mind_packets.(index).mind_consnames)
  | None -> None

let all_rect env evd all_ind all_inst motive_at_target =
  let result_ty =
    EConstr.Unsafe.to_constr
      (Retyping.get_type_of env evd (EConstr.of_constr motive_at_target))
  in
  let result_sort = whd_constr env evd result_ty in
  let result_sort =
    match Constr.kind result_sort with
    | Constr.Sort sort -> sort
    | _ -> CErrors.user_err Pp.(str "Nested motive does not return a sort")
  in
  let _, rect =
    Indrec.build_induction_scheme env evd
      (all_ind, EConstr.EInstance.make all_inst)
      true (EConstr.ESorts.make result_sort)
  in
  EConstr.Unsafe.to_constr rect

let rec fold_mutual_nested env evd ~depth mind specs target proof =
  let open Constr in
  let target_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr target)))
  in
  match type_head_ind env evd target_ty with
  | Some ((target_mind, _), _, _)
    when MutInd.UserOrd.equal target_mind mind -> proof
  | Some (((target_mind, target_index) as target_ind), _, _) ->
    let spec =
      match
        List.find_opt
          (fun spec -> convertible env evd target_ty spec.aux_domain)
          specs
      with
      | Some spec -> spec
      | None ->
        CErrors.user_err
          Pp.(
            str "No nested motive matches recursive constructor argument "
            ++ Printer.pr_constr_env env evd target_ty
            ++ str "; candidates: "
            ++ prlist_with_sep (fun () -> str ", ")
                 (fun spec ->
                   Printer.pr_constr_env env evd spec.aux_domain)
                 specs)
    in
    let motive = Vars.lift depth spec.aux_motive in
    let cases = List.map (Vars.lift depth) spec.aux_cases in
    if mind_is_one_of target_mind !array_minds then
      let target_head, _ = Constr.decompose_app target_ty in
      let array_ind, _ = Constr.destInd target_head in
      let array_mib = Global.lookup_mind (fst array_ind) in
      let projection, relevance =
        Declareops.inductive_make_projection array_ind array_mib ~proj_arg:0
      in
      let list =
        mkProj (Projection.make projection false, relevance, target)
      in
      let folded =
        fold_mutual_nested env evd ~depth mind specs list proof
      in
      (match cases with
      | [ array_case ] -> constr_app array_case [ list; folded ]
      | _ -> CErrors.user_err Pp.(str "Nested Array has unexpected cases"))
    else if mind_is_one_of target_mind !prod_minds then
      let fst, snd = prod_parts env evd target in
      let folded = fold_mutual_nested env evd ~depth mind specs snd proof in
      (match cases with
      | [ prod_case ] -> constr_app prod_case [ fst; snd; folded ]
      | _ -> CErrors.user_err Pp.(str "Nested Prod has unexpected cases"))
    else if mind_is_one_of target_mind !list_minds then
      fold_mutual_list env evd ~depth mind specs motive cases target proof
    else if mind_is_one_of target_mind !option_minds then
      fold_mutual_option env evd ~depth mind specs motive cases target proof
    else
      let target_mib = Global.lookup_mind target_mind in
      let packet = target_mib.mind_packets.(target_index) in
      (match (packet.mind_record, cases) with
      | Declarations.PrimRecord _, [ record_case ] ->
        let proof_ty =
          whd_constr env evd
            (EConstr.Unsafe.to_constr
               (Retyping.get_type_of env evd (EConstr.of_constr proof)))
        in
        if convertible env evd proof_ty (constr_app motive [ target ]) then
          proof
        else
          let nfields = packet.mind_consnrealargs.(0) in
          let fields =
            List.init nfields (fun proj_arg ->
              let projection, relevance =
                Declareops.inductive_make_projection target_ind target_mib
                  ~proj_arg
              in
              mkProj (Projection.make projection false, relevance, target))
          in
          constr_app record_case (fields @ [ proof ])
      | _ -> CErrors.user_err Pp.(str "Unsupported nested mutual container"))
  | None -> CErrors.user_err Pp.(str "Nested recursive argument is not inductive")

and fold_mutual_option env evd ~depth mind specs motive cases target proof =
  let open Constr in
  let proof_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr proof)))
  in
  let all_head, all_args = decompose_app proof_ty in
  let all_ind, all_inst =
    match kind all_head with
    | Ind (ind, inst) when Array.length all_args = 3 -> (ind, inst)
    | _ -> CErrors.user_err Pp.(str "Nested Option proof is not an All proof")
  in
  let a = all_args.(0) in
  let p = all_args.(1) in
  let target_ty =
    EConstr.Unsafe.to_constr
      (Retyping.get_type_of env evd (EConstr.of_constr target))
  in
  let motive_at_target = constr_app motive [ target ] in
  let rect = all_rect env evd all_ind all_inst motive_at_target in
  let all_ind_head = mkIndU (all_ind, all_inst) in
  let all_motive =
    let target_annot = anon_annot_for_type env evd target_ty in
    let env_target =
      Environ.push_rel (RelDecl.LocalAssum (target_annot, target_ty)) env
    in
    let all_ty =
      constr_app (Vars.lift 1 all_ind_head)
        [ Vars.lift 1 a; Vars.lift 1 p; mkRel 1 ]
    in
    let all_annot = anon_annot_for_type env_target evd all_ty in
    mkLambda
      ( target_annot,
        target_ty,
        mkLambda
          (all_annot, all_ty, constr_app (Vars.lift 2 motive) [ mkRel 2 ]) )
  in
  match cases with
  | [ none_case; some_case ] ->
    let head_ty = a in
    let head_annot = anon_annot_for_type env evd head_ty in
    let env_head =
      Environ.push_rel (RelDecl.LocalAssum (head_annot, head_ty)) env
    in
    let p_head_ty = constr_app (Vars.lift 1 p) [ mkRel 1 ] in
    let p_head_annot = anon_annot_for_type env_head evd p_head_ty in
    let env_p_head =
      Environ.push_rel
        (RelDecl.LocalAssum (p_head_annot, p_head_ty))
        env_head
    in
    let head_ih =
      fold_mutual_nested env_p_head evd ~depth:(depth + 2) mind specs
        (mkRel 2) (mkRel 1)
    in
    let some_branch =
      mkLambda
        ( head_annot,
          head_ty,
          mkLambda
            ( p_head_annot,
              p_head_ty,
              constr_app (Vars.lift 2 some_case) [ mkRel 2; head_ih ] ) )
    in
    constr_app rect
      [ a; p; all_motive; none_case; some_branch; target; proof ]
  | _ -> CErrors.user_err Pp.(str "Nested Option has unexpected cases")

and fold_mutual_list env evd ~depth mind specs motive cases target proof =
  let open Constr in
  let proof_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr proof)))
  in
  let all_head, all_args = decompose_app proof_ty in
  let all_ind, all_inst =
    match kind all_head with
    | Ind (ind, inst) when Array.length all_args = 3 -> (ind, inst)
    | _ -> CErrors.user_err Pp.(str "Nested List proof is not an All proof")
  in
  let a = all_args.(0) in
  let p = all_args.(1) in
  let target_ty =
    EConstr.Unsafe.to_constr
      (Retyping.get_type_of env evd (EConstr.of_constr target))
  in
  let motive_at_target = constr_app motive [ target ] in
  let rect = all_rect env evd all_ind all_inst motive_at_target in
  let all_ind_head = mkIndU (all_ind, all_inst) in
  let all_motive =
    let target_annot = anon_annot_for_type env evd target_ty in
    let env_target =
      Environ.push_rel (RelDecl.LocalAssum (target_annot, target_ty)) env
    in
    let all_ty =
      constr_app (Vars.lift 1 all_ind_head)
        [ Vars.lift 1 a; Vars.lift 1 p; mkRel 1 ]
    in
    let all_annot = anon_annot_for_type env_target evd all_ty in
    mkLambda
      ( target_annot,
        target_ty,
        mkLambda
          (all_annot, all_ty, constr_app (Vars.lift 2 motive) [ mkRel 2 ]) )
  in
  match cases with
  | [ nil_case; cons_case ] ->
    let head_ty = a in
    let head_annot = anon_annot_for_type env evd head_ty in
    let env_head =
      Environ.push_rel (RelDecl.LocalAssum (head_annot, head_ty)) env
    in
    let p_head_ty = constr_app (Vars.lift 1 p) [ mkRel 1 ] in
    let p_head_annot = anon_annot_for_type env_head evd p_head_ty in
    let env_p_head =
      Environ.push_rel
        (RelDecl.LocalAssum (p_head_annot, p_head_ty))
        env_head
    in
    let tail_ty = Vars.lift 2 target_ty in
    let tail_annot = anon_annot_for_type env_p_head evd tail_ty in
    let env_tail =
      Environ.push_rel (RelDecl.LocalAssum (tail_annot, tail_ty)) env_p_head
    in
    let all_tail_ty =
      constr_app (Vars.lift 3 all_ind_head)
        [ Vars.lift 3 a; Vars.lift 3 p; mkRel 1 ]
    in
    let all_tail_annot = anon_annot_for_type env_tail evd all_tail_ty in
    let env_all_tail =
      Environ.push_rel
        (RelDecl.LocalAssum (all_tail_annot, all_tail_ty))
        env_tail
    in
    let ih_ty = constr_app (Vars.lift 4 motive) [ mkRel 2 ] in
    let ih_annot = anon_annot_for_type env_all_tail evd ih_ty in
    let head_ih =
      fold_mutual_nested env_all_tail evd ~depth:(depth + 4) mind specs
        (mkRel 4) (mkRel 3)
    in
    let body =
      constr_app (Vars.lift 5 cons_case)
        [ mkRel 5; mkRel 3; Vars.lift 1 head_ih; mkRel 1 ]
    in
    let cons_branch =
      mkLambda
        ( head_annot,
          head_ty,
          mkLambda
            ( p_head_annot,
              p_head_ty,
              mkLambda
                ( tail_annot,
                  tail_ty,
                  mkLambda
                    ( all_tail_annot,
                      all_tail_ty,
                      mkLambda (ih_annot, ih_ty, body) ) ) ) )
    in
    constr_app rect
      [ a; p; all_motive; nil_case; cons_branch; target; proof ]
  | _ -> CErrors.user_err Pp.(str "Nested List has unexpected cases")

let rec fold_mutual_direct env evd ~depth mind specs main_recs target =
  let open Constr in
  let target_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr target)))
  in
  match type_head_ind env evd target_ty with
  | Some ((target_mind, target_index), _, _)
    when MutInd.UserOrd.equal target_mind mind ->
    constr_app (Vars.lift depth (List.nth main_recs target_index)) [ target ]
  | Some ((target_mind, _), _, _) ->
    let spec =
      match
        List.find_opt
          (fun spec -> convertible env evd target_ty spec.aux_domain)
          specs
      with
      | Some spec -> spec
      | None ->
        CErrors.user_err Pp.(str "No motive for auxiliary recursive target")
    in
    let motive = Vars.lift depth spec.aux_motive in
    let cases = List.map (Vars.lift depth) spec.aux_cases in
    if mind_is_one_of target_mind !array_minds then
      let target_head, _ = decompose_app target_ty in
      let array_ind, _ = destInd target_head in
      let array_mib = Global.lookup_mind (fst array_ind) in
      let projection, relevance =
        Declareops.inductive_make_projection array_ind array_mib ~proj_arg:0
      in
      let list = mkProj (Projection.make projection false, relevance, target) in
      let folded =
        fold_mutual_direct env evd ~depth mind specs main_recs list
      in
      (match cases with
      | [ array_case ] -> constr_app array_case [ list; folded ]
      | _ -> CErrors.user_err Pp.(str "Auxiliary Array has unexpected cases"))
    else if mind_is_one_of target_mind !prod_minds then
      let fst, snd = prod_parts env evd target in
      let folded =
        fold_mutual_direct env evd ~depth mind specs main_recs snd
      in
      (match cases with
      | [ prod_case ] -> constr_app prod_case [ fst; snd; folded ]
      | _ -> CErrors.user_err Pp.(str "Auxiliary Prod has unexpected cases"))
    else if mind_is_one_of target_mind !list_minds then
      fold_mutual_list_direct env evd ~depth mind specs main_recs motive cases
        target
    else if mind_is_one_of target_mind !option_minds then
      fold_mutual_option_direct env evd ~depth mind specs main_recs motive
        cases target
    else CErrors.user_err Pp.(str "Unsupported auxiliary mutual container")
  | None -> CErrors.user_err Pp.(str "Auxiliary recursive target is not inductive")

and fold_mutual_option_direct env evd ~depth mind specs main_recs motive cases
    target =
  let open Constr in
  let target_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr target)))
  in
  let option_ind, option_inst, option_args =
    match type_head_ind env evd target_ty with
    | Some (ind, inst, args) when Array.length args = 1 -> (ind, inst, args)
    | _ -> CErrors.user_err Pp.(str "Malformed auxiliary Option target")
  in
  let a = option_args.(0) in
  let rect =
    all_rect env evd option_ind option_inst (constr_app motive [ target ])
  in
  match cases with
  | [ none_case; some_case ] ->
    let head_annot = anon_annot_for_type env evd a in
    let env_head = Environ.push_rel (RelDecl.LocalAssum (head_annot, a)) env in
    let head_ih =
      fold_mutual_direct env_head evd ~depth:(depth + 1) mind specs main_recs
        (mkRel 1)
    in
    let some_branch =
      mkLambda
        ( head_annot,
          a,
          constr_app (Vars.lift 1 some_case) [ mkRel 1; head_ih ] )
    in
    constr_app rect [ a; motive; none_case; some_branch; target ]
  | _ -> CErrors.user_err Pp.(str "Auxiliary Option has unexpected cases")

and fold_mutual_list_direct env evd ~depth mind specs main_recs motive cases
    target =
  let open Constr in
  let target_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr target)))
  in
  let list_ind, list_inst, list_args =
    match type_head_ind env evd target_ty with
    | Some (ind, inst, args) when Array.length args = 1 -> (ind, inst, args)
    | _ -> CErrors.user_err Pp.(str "Malformed auxiliary List target")
  in
  let a = list_args.(0) in
  let rect = all_rect env evd list_ind list_inst (constr_app motive [ target ]) in
  match cases with
  | [ nil_case; cons_case ] ->
    let head_annot = anon_annot_for_type env evd a in
    let env_head = Environ.push_rel (RelDecl.LocalAssum (head_annot, a)) env in
    let tail_ty = Vars.lift 1 target_ty in
    let tail_annot = anon_annot_for_type env_head evd tail_ty in
    let env_tail =
      Environ.push_rel (RelDecl.LocalAssum (tail_annot, tail_ty)) env_head
    in
    let tail_ih_ty = constr_app (Vars.lift 2 motive) [ mkRel 1 ] in
    let tail_ih_annot = anon_annot_for_type env_tail evd tail_ih_ty in
    let env_tail_ih =
      Environ.push_rel
        (RelDecl.LocalAssum (tail_ih_annot, tail_ih_ty))
        env_tail
    in
    let head_ih =
      fold_mutual_direct env_tail_ih evd ~depth:(depth + 3) mind specs
        main_recs (mkRel 3)
    in
    let body =
      constr_app (Vars.lift 3 cons_case)
        [ mkRel 3; mkRel 2; head_ih; mkRel 1 ]
    in
    let cons_branch =
      mkLambda
        ( head_annot,
          a,
          mkLambda
            ( tail_annot,
              tail_ty,
              mkLambda (tail_ih_annot, tail_ih_ty, body) ) )
    in
    constr_app rect [ a; motive; nil_case; cons_branch; target ]
  | _ -> CErrors.user_err Pp.(str "Auxiliary List has unexpected cases")

let rec mutual_nested_leaf env evd ~depth mind specs main_motives main_recs
    target =
  let target_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr target)))
  in
  match type_head_ind env evd target_ty with
  | Some ((target_mind, target_index), _, _)
    when MutInd.UserOrd.equal target_mind mind ->
    let predicate =
      constr_app (Vars.lift depth (List.nth main_motives target_index))
        [ target ]
    in
    let proof =
      constr_app (Vars.lift depth (List.nth main_recs target_index)) [ target ]
    in
    (predicate, proof)
  | Some ((target_mind, _), _, _)
    when mind_is_one_of target_mind !prod_minds ->
    let _, snd = prod_parts env evd target in
    mutual_nested_leaf env evd ~depth mind specs main_motives main_recs snd
  | Some (((target_mind, target_index) as target_ind), _, _) ->
    let spec =
      List.find_opt
        (fun spec -> convertible env evd target_ty spec.aux_domain)
        specs
    in
    (match spec with
    | Some { aux_motive; aux_cases = [ record_case ]; _ } ->
      let target_mib = Global.lookup_mind target_mind in
      let packet = target_mib.mind_packets.(target_index) in
      (match packet.mind_record with
      | Declarations.PrimRecord _ ->
        let nfields = packet.mind_consnrealargs.(0) in
        let fields =
          List.init nfields (fun proj_arg ->
            let projection, relevance =
              Declareops.inductive_make_projection target_ind target_mib
                ~proj_arg
            in
            Constr.mkProj
              (Projection.make projection false, relevance, target))
        in
        let recursive_field = List.hd (List.rev fields) in
        let _, recursive_proof =
          mutual_nested_leaf env evd ~depth mind specs main_motives main_recs
            recursive_field
        in
        ( constr_app (Vars.lift depth aux_motive) [ target ],
          constr_app (Vars.lift depth record_case)
            (fields @ [ recursive_proof ]) )
      | _ ->
        CErrors.user_err
          Pp.(str "Nested All predicate has an unsupported record type"))
    | _ ->
      CErrors.user_err
        Pp.(str "Nested All predicate has an unsupported element type"))
  | _ ->
    CErrors.user_err
      Pp.(str "Nested All predicate has an unsupported element type")

let mutual_element_functions env evd ~depth mind specs main_motives main_recs
    element_ty =
  let open Constr in
  let annot = anon_annot_for_type env evd element_ty in
  let env_element =
    Environ.push_rel (RelDecl.LocalAssum (annot, element_ty)) env
  in
  let predicate_at, proof_at =
    mutual_nested_leaf env_element evd ~depth:(depth + 1) mind specs
      main_motives main_recs (mkRel 1)
  in
  (mkLambda (annot, element_ty, predicate_at),
   mkLambda (annot, element_ty, proof_at))

let container_all_forall env evd recursor predicate proof target =
  let target_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr target)))
  in
  let option_ind, option_inst, option_args =
    match type_head_ind env evd target_ty with
    | Some (ind, inst, args) when Array.length args = 1 -> (ind, inst, args)
    | _ -> CErrors.user_err Pp.(str "Nested target is not unary")
  in
  let all_forall_ref =
    match
      DeclareScheme.lookup_scheme_opt "AllForall" (GlobRef.IndRef option_ind)
    with
    | Some all_forall_ref -> all_forall_ref
    | None -> CErrors.user_err Pp.(str "Nested AllForall is unavailable")
  in
  let _, rec_inst = Constr.destConst recursor in
  let _, rec_levels = Instance.to_array rec_inst in
  if Array.length rec_levels = 0 then
    CErrors.user_err Pp.(str "Nested recursor has no motive universe");
  let motive_level = rec_levels.(0) in
  let option_qs, option_levels = Instance.to_array option_inst in
  let all_inst =
    Instance.of_array
      ( append_array option_qs [| Sorts.Quality.qtype |],
        append_array option_levels [| motive_level |] )
  in
  let all_forall = Constr.mkRef (all_forall_ref, all_inst) in
  constr_app all_forall
    [ option_args.(0); predicate; proof; target ]

let fold_mutual_auxiliary env evd info specs recursors main_motives main_recs
    target =
  let target_ty =
    whd_constr env evd
      (EConstr.Unsafe.to_constr
         (Retyping.get_type_of env evd (EConstr.of_constr target)))
  in
  match type_head_ind env evd target_ty with
  | Some ((target_mind, _), _, target_args)
    when mind_is_one_of target_mind !array_minds ->
    let predicate, proof =
      mutual_element_functions env evd ~depth:0 info.mind specs main_motives
        main_recs target_args.(Array.length target_args - 1)
    in
    let all_term =
      container_all_forall env evd (List.hd recursors) predicate proof target
    in
    fold_mutual_nested env evd ~depth:0 info.mind specs target all_term
  | Some ((target_mind, _), _, target_args)
    when mind_is_one_of target_mind !list_minds ->
    let predicate, proof =
      mutual_element_functions env evd ~depth:0 info.mind specs main_motives
        main_recs target_args.(Array.length target_args - 1)
    in
    let all_term =
      container_all_forall env evd (List.hd recursors) predicate proof target
    in
    fold_mutual_nested env evd ~depth:0 info.mind specs target all_term
  | Some ((target_mind, _), _, target_args)
    when mind_is_one_of target_mind !option_minds ->
    let predicate, proof =
      mutual_element_functions env evd ~depth:0 info.mind specs main_motives
        main_recs target_args.(Array.length target_args - 1)
    in
    let all_term =
      container_all_forall env evd (List.hd recursors) predicate proof target
    in
    fold_mutual_nested env evd ~depth:0 info.mind specs target all_term
  | Some ((target_mind, _), _, _)
    when mind_is_one_of target_mind !prod_minds ->
    let _, proof =
      mutual_nested_leaf env evd ~depth:0 info.mind specs main_motives
        main_recs target
    in
    fold_mutual_nested env evd ~depth:0 info.mind specs target proof
  | Some ((target_mind, target_index), _, _) ->
    let packet = (Global.lookup_mind target_mind).mind_packets.(target_index) in
    (match packet.mind_record with
    | Declarations.PrimRecord _ ->
      snd
        (mutual_nested_leaf env evd ~depth:0 info.mind specs main_motives
           main_recs target)
    | _ ->
      fold_mutual_direct env evd ~depth:0 info.mind specs main_recs target)
  | _ ->
    fold_mutual_direct env evd ~depth:0 info.mind specs main_recs target

let adapt_mutual_branch env evd mind specs info branch_ty branch =
  let open Constr in
  let info = List.rev info in
  let nargs = List.length info in
  let rec_positions =
    List.filter_map
      (fun (i, recursive) -> if recursive then Some i else None)
      (CList.map_i (fun i recursive -> (i, recursive)) 0 info)
  in
  (* Products in the motive result are not recursor branch binders. *)
  let nbranch_binders = nargs + List.length rec_positions in
  let rec loop env depth ty original mapped binder_index =
    if binder_index = nbranch_binders then
      constr_app (Vars.lift depth branch) mapped
    else
      let ty = whd_constr env evd ty in
      match kind ty with
      | Prod (annot, binder_ty, body) ->
        let env' =
          Environ.push_rel (RelDecl.LocalAssum (annot, binder_ty)) env
        in
        let original = List.map (Vars.lift 1) original in
        let mapped = List.map (Vars.lift 1) mapped in
        if binder_index < nargs then
          let original = original @ [ mkRel 1 ] in
          let mapped = mapped @ [ mkRel 1 ] in
          mkLambda
            ( annot,
              binder_ty,
              loop env' (depth + 1) body original mapped (binder_index + 1) )
        else
          let rec_index = binder_index - nargs in
          let arg_index =
            match List.nth_opt rec_positions rec_index with
            | Some arg_index -> arg_index
            | None ->
              CErrors.user_err
                Pp.(
                  str "Unexpected mutual branch binder " ++ int binder_index
                  ++ str " after " ++ int nargs
                  ++ str " constructor arguments and "
                  ++ int (List.length rec_positions)
                  ++ str " recursive hypotheses")
          in
          let target = List.nth original arg_index in
          let target_ty =
            EConstr.Unsafe.to_constr
              (Retyping.get_type_of env' evd (EConstr.of_constr target))
          in
          let mapped_hyp =
            match type_head_ind env' evd target_ty with
            | Some ((target_mind, _), _, _)
              when MutInd.UserOrd.equal target_mind mind -> mkRel 1
            | _ ->
              fold_mutual_nested env' evd ~depth:(depth + 1) mind specs target
                (mkRel 1)
          in
          let mapped = mapped @ [ mapped_hyp ] in
          mkLambda
            ( annot,
              binder_ty,
              loop env' (depth + 1) body original mapped (binder_index + 1) )
      | _ ->
        CErrors.user_err
          Pp.(
            str "Mutual branch ended after " ++ int binder_index
            ++ str " binders; expected " ++ int nbranch_binders)
  in
  loop env 0 branch_ty [] [] 0

let adapt_mutual_nested_recursor env evd info recursors args =
  let recursor = List.hd recursors in
  let mib = Global.lookup_mind info.mind in
  let ntypes = Array.length mib.mind_packets in
  let nmain_cases =
    Array.fold_left
      (fun n (packet : Declarations.one_inductive_body) ->
        n + Array.length packet.mind_consnames)
      0 mib.mind_packets
  in
  if List.length args < info.nparams + ntypes + nmain_cases + 1 then None
  else
    let params, args = CList.chop info.nparams args in
    let main_motives, tail = CList.chop ntypes args in
    let focus_matches aux_domains target =
      let target_ty =
        EConstr.Unsafe.to_constr
          (Retyping.get_type_of env evd (EConstr.of_constr target))
      in
      match info.focus with
      | MutualMain index -> (
        match type_head_ind env evd target_ty with
        | Some ((target_mind, target_index), _, _) ->
          MutInd.UserOrd.equal target_mind info.mind && target_index = index
        | None -> false)
      | MutualAux index ->
        index < List.length aux_domains
        && convertible env evd target_ty (List.nth aux_domains index)
    in
    let rec find_layout k =
      if k > List.length tail then None
      else
        let aux_motives, _ = CList.chop k tail in
        let aux_domains = List.map (motive_domain env evd) aux_motives in
        if List.exists Option.is_empty aux_domains then find_layout (k + 1)
        else
          let aux_domains = List.map Option.get aux_domains in
          let counts = List.map (aux_ctor_count env evd) aux_domains in
          if List.exists Option.is_empty counts then find_layout (k + 1)
          else
            let naux_cases =
              List.fold_left ( + ) 0 (List.map Option.get counts)
            in
            let target_index = k + nmain_cases + naux_cases in
            if target_index >= List.length tail then find_layout (k + 1)
            else
              let target = List.nth tail target_index in
              if focus_matches aux_domains target then
                Some (k, aux_domains, List.map Option.get counts)
              else find_layout (k + 1)
    in
    match find_layout 0 with
    | None -> None
    | Some (0, _, _) -> (
      match info.focus with
      | MutualMain index ->
        Some (constr_app (List.nth recursors index) (params @ args))
      | MutualAux _ -> None)
    | Some (naux, aux_domains, aux_counts) ->
      let aux_motives, rest = CList.chop naux tail in
      let lean_main_cases, rest = CList.chop nmain_cases rest in
      let rest, specs =
        CList.fold_left3
          (fun (rest, specs) domain motive count ->
            let cases, rest = CList.chop count rest in
            ((rest, specs @ [ { aux_domain = domain; aux_motive = motive; aux_cases = cases } ])))
          (rest, []) aux_domains aux_motives aux_counts
      in
      let target, extra = (List.hd rest, List.tl rest) in
      let rec_ty =
        EConstr.Unsafe.to_constr
          (Retyping.get_type_of env evd (EConstr.of_constr recursor))
      in
      let rec_ty =
        List.fold_left (prod_after_apply env evd) rec_ty
          (params @ main_motives)
      in
      let ctor_infos =
        Array.to_list
          (Array.concat
             (Array.to_list
                (Array.map
                   (fun (packet : Declarations.one_inductive_body) ->
                     Array.mapi
                       (fun i (ctor_args, _) ->
                         let nargs = packet.mind_consnrealargs.(i) in
                         CList.map
                           (fun arg ->
                             has_rec_hyp env info.mind (RelDecl.get_type arg))
                           (CList.firstn nargs ctor_args))
                       packet.mind_nf_lc)
                   mib.mind_packets)))
      in
      let adapt_cases () =
        snd
          (CList.fold_left2
             (fun (rec_ty, cases) branch ctor_info ->
               let branch_ty = prod_domain env evd rec_ty in
               let branch =
                 adapt_mutual_branch env evd info.mind specs ctor_info
                   branch_ty branch
               in
               (prod_after_apply env evd rec_ty branch, cases @ [ branch ]))
             (rec_ty, []) lean_main_cases ctor_infos)
      in
      let default_cases = adapt_cases () in
      let default_main_recs =
        List.map
          (fun recursor ->
            constr_app recursor (params @ main_motives @ default_cases))
          recursors
      in
      let result =
        match info.focus with
        | MutualMain index ->
          constr_app (List.nth default_main_recs index) [ target ]
        | MutualAux _ ->
          fold_mutual_auxiliary env evd info specs recursors main_motives
            default_main_recs target
      in
      Some (constr_app result extra)

let rec constr_mentions_ind target c =
  match Constr.kind c with
  | Constr.Ind (ind, _) -> Ind.CanOrd.equal target ind
  | _ ->
    Constr.fold
      (fun found child -> found || constr_mentions_ind target child)
      false c

let sprop_scheme_for_ind_in_type ind_name ty =
  let ind_instances = N.Map.get ind_name !declared in
  let ind_index =
    Int.Map.fold
      (fun i inst found ->
        match found, inst.ref with
        | Some _, _ -> found
        | None, GlobRef.IndRef ind when constr_mentions_ind ind ty -> Some i
        | None, _ -> None)
      ind_instances None
  in
  let ind_index =
    match ind_index with
    | Some i -> i
    | None ->
      CErrors.user_err
        Pp.(str "The reconstructed type does not mention " ++ N.pp ind_name)
  in
  let squashy = N.Map.get ind_name !squash_info in
  let scheme_index =
    if squashy.lean_squashes then ind_index else (2 * ind_index) + 1
  in
  let rec_name = N.append ind_name "rec" in
  let scheme = N.Map.get rec_name !declared |> Int.Map.get scheme_index in
  let scheme_ref =
    match scheme.ref with
    | GlobRef.ConstRef _ as ref -> ref
    | _ ->
      CErrors.user_err
        Pp.(str "Unexpected SProp scheme reference for " ++ N.pp ind_name)
  in
  Nametab.shortest_qualid_of_global Id.Set.empty scheme_ref
  |> Libnames.string_of_qualid

let rec to_constr =
  let open Constr in
  let ( >>= ) x f uconv =
    let uconv, x = x uconv in
    f x uconv
  in
  let get_uconv uconv = (uconv, uconv) in
  let ret x uconv = (uconv, x) in
  let to_annot env n t u = (u, to_annot env n t u) in
  let push_rel = Environ.push_rel_context_val in
  fun env -> function
    | Bound i -> ret (mkRel (i + 1))
    | Sort univ ->
      to_univ_level' univ >>= fun u -> ret (mkSort (sort_of_level u))
    | Const (n, univs) -> instantiate n univs
    | App (App (App (Const (ofnat, _), (Const _ as ty)), v), inst)
      when N.equal ofnat ofnat_ofNat_name
           && is_const_named nat_name ty
           && has_const_head instOfNatNat_name inst ->
      to_constr env v
    | App
        ( App
            ( App (Const (ofnat, _), (Const _ as ty)),
              Nat value ),
          inst )
      when N.equal ofnat ofnat_ofNat_name
           && is_const_named int_name ty
           && Z.equal value (Z.of_string "999999999")
           && has_const_head instOfNat_name inst ->
      (* This literal is Lean-definitionally [1000000000 - 1].  Preserve
         that presentation everywhere so nanosecond bounds line up without
         expanding either numeral into a unary natural during conversion. *)
      (fun uconv ->
        let uconv, int_ty = instantiate int_name [] uconv in
        let hsub_name = N.append N.anon "HSub" in
        let uconv, hsub =
          instantiate (N.append hsub_name "hSub")
            [ U.Prop; U.Prop; U.Prop ] uconv
        in
        let uconv, inst_hsub =
          instantiate (N.append N.anon "instHSub") [ U.Prop ] uconv
        in
        let uconv, int_inst_sub =
          instantiate (N.append int_name "instSub") [] uconv
        in
        let uconv, int_of_nat =
          instantiate (N.append int_name "ofNat") [] uconv
        in
        let uconv, billion_nat =
          to_constr env (Nat (Z.of_string "1000000000")) uconv
        in
        let uconv, one_nat = to_constr env (Nat Z.one) uconv in
        let big_int = Constr.mkApp (int_of_nat, [| billion_nat |]) in
        let one_int = Constr.mkApp (int_of_nat, [| one_nat |]) in
        let hsub_instance =
          Constr.mkApp (inst_hsub, [| int_ty; int_inst_sub |])
        in
        let term =
          Constr.mkApp
            ( hsub,
              [| int_ty; int_ty; int_ty; hsub_instance; big_int; one_int |] )
        in
        (uconv, term))
    | App (fn, Nat value)
      when Z.equal value (Z.of_string "999999999")
           && has_const_head
                (N.append_list N.anon
                   [ "_private"; "Std"; "Time"; "Format"; "Basic0";
                     "Std"; "Time"; "parseNatToBounded" ])
                fn ->
      (* Specializing [parseNatToBounded] substitutes this Nat into an Int
         cast.  Keep the predecessor as [1000000000 - 1] so the imported
         [Int.ofNat_sub] theorem can transport it to
         [Nanosecond.Ordinal]'s canonical Int subtraction without reducing a
         unary billion. *)
      to_constr env fn >>= fun fn ->
      instantiate (N.append nat_name "sub") [] >>= fun sub ->
      to_constr env (Nat (Z.of_string "1000000000")) >>= fun billion ->
      to_constr env (Nat Z.one) >>= fun one ->
      ret (mkApp (fn, [| mkApp (sub, [| billion; one |]) |]))
    | (App _ as app_expr) -> (
      let head, args = decompose_lean_app [] app_expr in
      match head with
      | Const (n, univs) when N.Map.mem n !mutual_nested_rec_info ->
        let info = N.Map.get n !mutual_nested_rec_info in
        (fun uconv ->
          let uconv, recursors =
            CList.fold_left_map
              (fun uconv base_rec -> instantiate base_rec univs uconv)
              uconv info.base_recs
          in
          let uconv, args =
            CList.fold_left_map
              (fun uconv arg -> to_constr env arg uconv)
              uconv args
          in
          let adapted =
            with_env_evm env uconv
              (fun env evd () ->
                adapt_mutual_nested_recursor env evd info recursors args)
              ()
          in
          match adapted with
          | Some term -> (uconv, term)
          | None ->
            let term =
              List.fold_left
                (fun f x -> Constr.mkApp (f, [| x |]))
                (List.nth recursors
                   (match info.focus with
                   | MutualMain index -> index
                   | MutualAux _ -> 0))
                args
            in
            (uconv, term))
      | Const (n, univs) when N.Map.mem n !nested_array_rec_info ->
        let info = N.Map.get n !nested_array_rec_info in
        instantiate info.base_rec univs >>= fun recursor ->
        (fun uconv ->
          let uconv, args =
            CList.fold_left_map
              (fun uconv arg -> to_constr env arg uconv)
              uconv args
          in
          let adapted =
            with_env_evm env uconv
              (fun env evd () ->
                adapt_nested_array_recursor env evd info recursor args)
              ()
          in
          match adapted with
          | Some term -> (uconv, term)
          | None ->
            let term =
              List.fold_left
                (fun f x -> Constr.mkApp (f, [| x |]))
                recursor args
            in
            (uconv, term))
      | _ ->
        let a, b = match app_expr with App (a, b) -> (a, b) | _ -> assert false in
        to_constr env a >>= fun a ->
        to_constr env b >>= fun b ->
        begin
          match Constr.kind b with
          | Constr.Lambda (_, domain, _)
            when
              begin
                match Constr.kind domain with
                | Constr.Ind (ind, _) ->
                  let _, mip =
                    Inductive.lookup_mind_specif (Global.env ()) ind
                  in
                  Id.equal mip.mind_typename (Id.of_string "PUnit")
                | _ -> false
              end ->
            get_uconv >>= fun uconv ->
            let b =
              with_env_evm env uconv
                (fun env evd () ->
                  let function_ty =
                    Retyping.get_type_of env evd (EConstr.of_constr a)
                    |> Reductionops.whd_all env evd
                    |> EConstr.Unsafe.to_constr
                  in
                  match Constr.kind function_ty with
                  | Constr.Prod (_, expected, _) ->
                    let actual =
                      Retyping.get_type_of env evd (EConstr.of_constr b)
                      |> EConstr.Unsafe.to_constr
                    in
                    if
                      Reductionops.is_conv env evd (EConstr.of_constr actual)
                        (EConstr.of_constr expected)
                    then b
                    else adapt_punit_eta_argument env evd expected b
                  | _ -> b)
                ()
            in
            ret (mkApp (a, [| b |]))
          | _ -> ret (mkApp (a, [| b |]))
        end)
    | Let { name; ty; v; rest } ->
      to_constr env ty >>= fun ty ->
      to_annot env name ty >>= fun name ->
      to_constr env v >>= fun v ->
      to_constr (push_rel (LocalDef (name, v, ty)) env) rest >>= fun rest ->
      ret (mkLetIn (name, v, ty, rest))
    | Lam (_bk, n, a, b) ->
      to_constr env a >>= fun a ->
      to_annot env n a >>= fun n ->
      to_constr (push_rel (LocalAssum (n, a)) env) b >>= fun b ->
      ret (mkLambda (n, a, b))
    | Pi (_bk, n, a, b) ->
      to_constr env a >>= fun a ->
      to_annot env n a >>= fun n ->
      to_constr (push_rel (LocalAssum (n, a)) env) b >>= fun b ->
      ret (mkProd (n, a, b))
    | Proj (lean_ind, field, c) ->
      to_constr env c >>= fun c ->
      get_uconv >>= fun uconv ->
      (* we retype to get the ind, because otherwise we need the lean
       univs for instantiation
       This means we ignore the lean_ind in the Proj data. *)
      let c =
        with_env_evm env uconv
          (fun env evd () ->
            let tc = Retyping.get_type_of env evd (EConstr.of_constr c) in
            let tc =
              Reductionops.whd_all env evd tc
            in
            let tc_head, args = EConstr.decompose_app evd tc in
            match EConstr.kind evd tc_head with
            | Constr.Ind _ ->
              (* Standard inductive: use normal projection *)
              let ((ind, _) as indu) =
                Constr.destInd (EConstr.Unsafe.to_constr tc_head)
              in
              let mib, mip = Inductive.lookup_mind_specif (Global.env()) ind in
              begin
                match mip.mind_record with
                | PrimRecord infos ->
                  let p, r =
                    Declareops.inductive_make_projection ind mib ~proj_arg:field
                  in
                  (* unfolded?? *)
                  mkProj (Projection.make p false, r, c)
                | NotRecord | FakeRecord ->
                  unfold_proj_case env evd ~field ~indu ~mib ~mip ~args c
              end
            | _ ->
              (* Type is not an inductive (e.g., transparent cumulative ULift).
                 Projection is the identity. *)
              c)
          ()
      in
      ret c
    | Nat i ->
      (* [nat_ints] is not synchronized so ensure Nat is instantiated *)
      instantiate (N.append N.anon "Nat") [] >>= fun nat ->
      let nat, _ = Constr.destInd nat in
      get_uconv >>= fun uconv ->
      let global registered_name =
        with_env_evm env uconv
          (fun env evd () ->
            let _, p =
              Evd.fresh_global env evd
                (Rocqlib.lib_ref ("lean." ^ registered_name))
            in
            EConstr.to_constr evd p)
          ()
      in
      if Z.equal i (Z.of_int 64) then ret (global nat_64_literal)
      else if Z.equal i (Z.of_string "9223372036854775808") then
        ret (global nat_pow2_63_literal)
      else
        let double = global nat_double in
        ret (nat_int nat double i)
    | String s ->
      (* instantiate (N.append N.anon "Char") [] >>= fun char -> *)
      (* let (_, charu) = Constr.destInd char in *)
      instantiate (N.append N.anon "String") [] >>= fun _string ->
      let string_mk_name = N.append (N.append N.anon "String") "mk" in
      let string_of_list_name = N.append (N.append N.anon "String") "ofList" in
      (fun uconv ->
        try instantiate string_mk_name [] uconv
        with e ->
          let e = Exninfo.capture e in
          if N.Map.mem string_of_list_name !entries then
            instantiate string_of_list_name [] uconv
          else Exninfo.iraise e)
      >>= fun string_mk ->
      get_uconv >>= fun uconv ->
      let list, char =
        with_env_evm env uconv
          (fun env evd () ->
            let ty =
              Retyping.get_type_of env evd (EConstr.of_constr string_mk)
            in
            let _, list_char, _ = EConstr.destProd evd ty in
            let list, char =
              match EConstr.destApp evd list_char with
              | list, [| char |] -> (list, char)
              | _ ->
                CErrors.user_err
                  Pp.(
                    str "Invalid type for string constructor: "
                    ++ Printer.pr_type_env env evd (EConstr.to_constr evd ty)
                    ++ str " ("
                    ++ Printer.pr_type_env env evd
                         (EConstr.to_constr evd list_char)
                    ++ str " should be an application of list to char)")
            in
            (EConstr.to_constr evd list, EConstr.to_constr evd char))
          ()
      in
      (* instantiate (N.append N.anon "List") [] >>= fun list -> *)
      let list, _ = Constr.destInd list in
      get_uconv >>= fun uconv ->
      let mkChar =
        with_env_evm env uconv
          (fun env evd () ->
            let _, mkChar =
              Evd.fresh_global env evd
                (Rocqlib.lib_ref ("lean." ^ mk_char_prim))
            in
            EConstr.to_constr evd mkChar)
          ()
      in
      ret (mk_string char list UVars.Instance.empty mkChar string_mk s)

and instantiate n univs uconv =
  assert (List.length univs < Sys.int_size);
  (* TODO what happens when is_large_elim and the motive is instantiated with Prop? *)
  let univs = List.map (to_universe uconv.map) univs in
  let i, univs = int_of_univs univs in
  let inst = ensure_exists n i in
  let subst l =
    let u =
      match Level.var_index l with
      | None -> Universe.make l
      | Some n -> List.nth univs n
    in
    Some u
  in
  let univs =
    List.map
      (fun alg -> simplify_universe (UnivSubst.subst_univs_universe subst alg))
      inst.algs
  in
  let uconv, univs =
    CList.fold_left_map (fun uconv u -> to_univ_level u uconv) uconv univs
  in
  let u = Instance.of_array ([||], Array.of_list univs) in
  (uconv, Constr.mkRef (inst.ref, u))

and ensure_exists n i =
  try !declared |> N.Map.find n |> Int.Map.find i
  with Not_found ->
    (* TODO can we end up asking for a ctor or eliminator before
       asking for the inductive type? *)
    (* if i = 0 then CErrors.user_err Pp.(N.pp n ++ str " was not instantiated!"); *)
    (* assert (not (upfront_instances ())); *)
    (match N.Map.find n !entries with
    | Def def -> declare_def def i
    | Ax ax -> declare_ax ax i
    | Ind ind -> declare_ind ind i
    | Quot _ -> CErrors.user_err Pp.(str "quot must be predeclared")
    | exception Not_found -> CErrors.user_err Pp.(str "missing " ++ N.pp n))

and declare_reconstructed_def ?(transparent = false) n i ty univs =
  let tactic =
    if N.equal n (N.append_list N.anon [ "UInt32"; "toNat_shiftLeft" ]) then
      uint32_toNat_shiftLeft_tactic
    else if N.equal n (N.append_list N.anon [ "UInt64"; "toNat_shiftLeft" ]) then
      uint64_toNat_shiftLeft_tactic
    else if is_assemble2_mod_bound_proof n then assemble2_mod_bound_tactic
    else if is_assemble2_valid_char_proof n then assemble2_valid_char_tactic
    else if is_assemble3_mod_bound_proof n then assemble3_mod_bound_tactic
    else if is_assemble3_mid_bound_proof n then assemble3_mid_bound_tactic
    else if is_assemble3_valid_char_proof n then assemble3_valid_char_tactic
    else if is_val_assemble1_le_proof n then val_assemble1_le_tactic
    else if is_helper3_proof n then helper3_tactic
    else if is_utf8size_four_proof_1_4 n then utf8size_four_proof_1_4_tactic
    else if is_utf8size_four_proof_1_5 n then utf8size_four_proof_1_5_tactic
    else if is_assemble3_of_toBitVec_proof_1_8 n then
      assemble3_of_toBitVec_proof_1_8_tactic
    else if is_assemble4_of_toBitVec_proof_1_8 n then
      assemble4_of_toBitVec_proof_1_8_tactic
    else if is_assemble4_iff_proof_1_10 n then
      assemble4_iff_proof_1_10_tactic
    else if is_char_toNat_val_le_proof_1_1 n then
      char_toNat_val_le_proof_1_1_tactic
    else if is_usize_toNat_ofNat_of_lt_32 n then
      usize_toNat_ofNat_of_lt_32_tactic
    else if is_usize_size_pos n then usize_size_pos_tactic
    else if is_int64_toInt_minValue n then int64_toInt_minValue_tactic
    else if is_sqrt_iter_sq_le_proof_1_1 n then
      sqrt_iter_sq_le_proof_1_1_tactic
    else if is_sqrt_isSqrt_proof_1_6 n then sqrt_isSqrt_proof_1_6_tactic
    else if is_sqrt_isSqrt_proof_1_7 n then sqrt_isSqrt_proof_1_7_tactic
    else if is_sqrt_add_eq_proof_1_1 n then sqrt_add_eq_proof_1_1_tactic
    else if is_sqrt_add_eq_proof_1_2 n then sqrt_add_eq_proof_1_2_tactic
    else if is_le_three_of_sqrt_eq_one_proof_1_1 n then
      le_three_of_sqrt_eq_one_proof_1_1_tactic
    else if is_sqrt_lt_self_proof_1_1 n then sqrt_lt_self_proof_1_1_tactic
    else if is_sqrt_succ_le_succ_sqrt_proof_1_1 n then
      sqrt_succ_le_succ_sqrt_proof_1_1_tactic
    else if is_uint32_toUInt64_proof_1 n then uint32_toUInt64_proof_1_tactic
    else if is_uint32_not_neg_one n then uint32_not_neg_one_tactic
    else if is_except_conds_and_eq_left n then
      let post_shape =
        N.append_list N.anon [ "Std"; "Do"; "PostShape" ]
      in
      except_conds_and_eq_left_tactic
        (sprop_scheme_for_ind_in_type post_shape ty)
    else if is_nat_locally_finite_order_proof_3 n then
      nat_locally_finite_order_proof_3_tactic
    else if is_nat_locally_finite_order_proof_4 n then
      nat_locally_finite_order_proof_4_tactic
    else if is_nat_ico_image_const_sub_proof_1_4 n then
      nat_ico_image_const_sub_proof_1_4_tactic
    else if is_nat_ico_image_const_sub_proof_1_3 n then
      nat_ico_image_const_sub_proof_1_3_tactic
    else if is_nat_icc_insert_succ_right_proof_1_3 n then
      nat_icc_insert_succ_right_proof_1_3_tactic
    else if is_list_prev_reverse_eq_next_proof_1_1 n then
      list_prev_reverse_eq_next_proof_1_1_tactic
    else if is_list_next_eq_get_elem_proof_1 n then
      list_next_eq_get_elem_proof_1_tactic
    else if is_list_next_eq_get_elem n then
      list_next_eq_get_elem_tactic
    else if is_list_next_eq_get_elem_proof_1_3 n then
      list_next_eq_get_elem_proof_1_3_tactic
    else if is_list_next_eq_get_elem_proof_1_4 n then
      list_next_eq_get_elem_proof_1_4_tactic
    else if is_list_next_eq_get_elem_proof_1_34 n then
      list_next_eq_get_elem_proof_1_34_tactic
    else if is_list_next_eq_get_elem_proof_1_19 n then
      list_next_eq_get_elem_proof_1_19_tactic
    else if is_list_next_eq_get_elem_proof_1_36 n then
      list_next_eq_get_elem_proof_1_36_tactic
    else if is_list_next_get_elem_proof_1_4 n then
      list_next_get_elem_proof_1_4_tactic
    else if is_list_next_get_elem_proof_1_6 n then
      list_next_get_elem_proof_1_6_tactic
    else if is_list_next_get_elem n then
      list_next_get_elem_tactic
    else if is_list_pmap_next_eq_rotate_one n then
      list_pmap_next_eq_rotate_one_tactic
    else if is_list_pmap_prev_eq_rotate_length_sub_one n then
      list_pmap_prev_eq_rotate_length_sub_one_tactic
    else if is_list_prev_get_elem_proof_1 n then
      list_prev_get_elem_proof_1_tactic
    else if is_list_prev_get_elem_proof_1_4 n then
      list_prev_get_elem_proof_1_4_tactic
    else if is_list_prev_get_elem_proof_1_6 n then
      list_prev_get_elem_proof_1_6_tactic
    else if is_list_prev_get_elem n then
      list_prev_get_elem_tactic
    else if is_list_prev_eq_get_elem_proof_1_2 n then
      list_prev_eq_get_elem_proof_1_2_tactic
    else if is_list_prev_eq_get_elem_proof_1_3 n then
      list_prev_eq_get_elem_proof_1_3_tactic
    else if is_list_prev_eq_get_elem_proof_1_4 n then
      list_prev_eq_get_elem_proof_1_4_tactic
    else if is_list_prev_eq_get_elem_proof_1_7 n then
      list_prev_eq_get_elem_proof_1_7_tactic
    else if is_list_prev_eq_get_elem_pred_proof_1 n then
      list_prev_eq_get_elem_pred_proof_1_tactic
    else if is_list_prev_eq_get_elem_proof_1_8 n then
      list_prev_eq_get_elem_proof_1_8_tactic
    else if is_list_prev_eq_get_elem n then
      list_prev_eq_get_elem_tactic
    else if is_list_prev_reverse_eq_next n then
      list_prev_reverse_eq_next_tactic
    else if is_list_next_reverse_eq_prev n then
      list_next_reverse_eq_prev_tactic
    else if is_list_is_rotated_next_eq n then
      list_is_rotated_next_eq_tactic
    else if is_list_is_rotated_prev_eq n then
      list_is_rotated_prev_eq_tactic
    else if is_list_next_prev n then list_next_prev_tactic
    else if is_list_prev_next n then list_prev_next_tactic
    else if is_cycle_prev_proof_1 n then
      cycle_prev_proof_1_tactic
    else if is_cycle_prev n then cycle_prev_tactic
    else if is_cycle_next_proof_1 n then
      cycle_next_proof_1_tactic
    else if is_cycle_next n then cycle_next_tactic
    else if is_cycle_prev_reverse_eq_next n then
      cycle_prev_reverse_eq_next_tactic
    else if is_cycle_next_reverse_eq_prev_simp_1_1 n then
      cycle_next_reverse_eq_prev_simp_1_1_tactic
    else if is_cycle_prev_congr_simp n then
      cycle_prev_congr_simp_tactic
    else if is_cycle_next_reverse_eq_prev n then
      cycle_next_reverse_eq_prev_tactic
    else if is_cycle_next_mem n then cycle_next_mem_tactic
    else if is_cycle_prev_mem n then cycle_prev_mem_tactic
    else if is_cycle_next_prev n then cycle_next_prev_tactic
    else if is_list_succ_idx_of_mem_drop_last_proof_1_1 n then
      list_succ_idx_of_mem_drop_last_proof_1_1_tactic
    else if is_nanosecond_offset_of_hours_proof_1 n then
      unit_offset_scale_proof_1_tactic ~scale:"3600"
        ~big:"3600000000000" ~small:"1000000000"
        ~canonicalize_small:false ~extra_goal_clause:"" ~ha_proof:"reflexivity"
    else if is_nanosecond_offset_of_minutes_proof_1 n then
      unit_offset_scale_proof_1_tactic ~scale:"60"
        ~big:"60000000000" ~small:"1000000000"
        ~canonicalize_small:false ~extra_goal_clause:"" ~ha_proof:"reflexivity"
    else if is_millisecond_offset_of_hours_proof_1 n then
      unit_offset_scale_proof_1_tactic ~scale:"3600"
        ~big:"3600000" ~small:"1000" ~canonicalize_small:true
        ~extra_goal_clause:"" ~ha_proof:"reflexivity"
    else if is_week_offset_of_milliseconds_proof_1 n then
      week_offset_of_milliseconds_proof_1_tactic
    else if is_week_offset_of_nanoseconds_proof_1 n then
      week_offset_of_nanoseconds_proof_1_tactic
    else if is_week_offset_to_nanoseconds_proof_1 n then
      week_offset_to_nanoseconds_proof_1_tactic
    else if is_list_append_cancel_right n then list_append_cancel_right_tactic
    else if is_nat_subtype_succ_le_of_lt_proof_1_3 n then
      nat_subtype_succ_le_of_lt_proof_1_3_tactic
    else if is_nat_subtype_succ_le_of_lt_proof_1_4 n then
      nat_subtype_succ_le_of_lt_proof_1_4_tactic
    else if is_nat_subtype_le_succ_of_forall_lt_le_proof_1_2 n then
      nat_subtype_le_succ_of_forall_lt_le_proof_1_2_tactic
    else if is_order_iso_subsequence_proof_1_4 n then
      order_iso_subsequence_proof_1_4_tactic
    else if is_order_iso_subsequence_proof_1_5 n then
      order_iso_subsequence_proof_1_5_tactic
    else if is_plain_time_of_nanoseconds_large_bound_proof n then
      plain_time_of_nanoseconds_large_bound_tactic
    else if is_equiv_prod_punit_def n then equiv_prod_punit_tactic
    else if is_lean_json_cases_on_def n then lean_json_cases_on_tactic
    else if is_lean_info_tree_cases_on_def n then
      lean_info_tree_cases_on_tactic
    else if is_remove_after_done_action_sparse_cases_on_3_def n then
      remove_after_done_action_sparse_cases_on_3_tactic
    else if is_lean_json_sparse_cases_on_6_def n then
      lean_json_sparse_cases_on_6_tactic
    else if is_lean_json_beq_sparse_cases_on_8_def n then
      lean_json_beq_sparse_cases_on_8_tactic
    else if is_lean_json_beq_sparse_cases_on_3_def n then
      option_from_json_sparse_cases_on_1_tactic
    else if is_lean_json_beq_sparse_cases_on_4_def n then
      lean_json_beq_sparse_cases_on_4_tactic
    else if is_lean_json_beq_sparse_cases_on_5_def n then
      lean_json_beq_sparse_cases_on_5_tactic
    else if is_lean_json_beq_sparse_cases_on_6_def n then
      lean_json_beq_sparse_cases_on_6_tactic
    else if is_lean_json_beq_sparse_cases_on_7_def n then
      lean_json_sparse_cases_on_6_tactic
    else if is_option_from_json_sparse_cases_on_1_def n then
      option_from_json_sparse_cases_on_1_tactic
    else if is_array_from_json_sparse_cases_on_1_def n then
      lean_json_sparse_cases_on_6_tactic
    else if is_float_from_json_sparse_cases_on_1_def n then
      float_from_json_sparse_cases_on_1_tactic
    else if is_name_map_from_json_sparse_cases_on_1_def n then
      lean_json_beq_sparse_cases_on_8_tactic
    else if is_json_structured_from_json_sparse_cases_on_1_def n then
      json_structured_from_json_sparse_cases_on_1_tactic
    else if is_command_parsed_snapshot_below_1_def n then
      command_parsed_snapshot_below_1_tactic
    else if is_do_code_below_def n then
      do_code_below_tactic (Option.get (do_code_below_focus n))
    else if is_fin_cast_succ_lt_or_lt_succ_proof_1_2 n then
      fin_cast_succ_lt_or_lt_succ_proof_1_2_tactic
    else if is_uint64_max_bound_proof n then uint64_max_bound_proof_tactic
    else if is_uint64_toNat_ofNatTruncate_of_le n then
      uint64_toNat_ofNatTruncate_of_le_tactic
    else if is_uint64_toNat_ofNatLT n then uint64_toNat_ofNatLT_tactic
    else if is_uint64_toFin_ofNatTruncate_of_le n then
      uint64_toFin_ofNatTruncate_of_le_tactic
    else if is_uint64_toBitVec_ofNatTruncate_of_le n then
      uint64_toBitVec_ofNatTruncate_of_le_tactic
    else if is_uint64_of_fin n then uint64_of_fin_tactic
    else if is_persistent_hash_map_node_sizeof_1_def n then
      persistent_hash_map_node_sizeof_1_tactic
    else CErrors.user_err Pp.(str "No Rocq reconstruction for " ++ N.pp n)
  in
  let uctx =
    match fst univs with
    | UState.Polymorphic_entry uctx -> uctx
    | UState.Monomorphic_entry _ -> assert false
  in
  let () =
    if is_command_parsed_snapshot_below_1_def n then begin
      let _, levels =
        UVars.Instance.to_array (UVars.UContext.instance uctx)
      in
      if Array.length levels <> 1 then
        CErrors.user_err
          Pp.(str "Unexpected CommandParsedSnapshot universe context");
      let pprod_ind =
        match
          Nametab.locate
            (Libnames.qualid_of_ident (Id.of_string "PProd"))
        with
        | GlobRef.IndRef ind -> ind
        | _ -> CErrors.user_err Pp.(str "PProd is not an inductive")
      in
      let level = levels.(0) in
      let instance =
        UVars.Instance.of_array ([||], [| level; level; level |])
      in
      let sort = Constr.mkType (Universe.make level) in
      let body =
        Constr.mkLambda
          ( Context.nameR (Id.of_string "A"),
            sort,
            Constr.mkLambda
              ( Context.nameR (Id.of_string "B"),
                sort,
                Constr.mkApp
                  (Constr.mkIndU (pprod_ind, instance),
                   [| Constr.mkRel 2; Constr.mkRel 1 |]) ) )
      in
      ignore
        (quickdef
           ~name:(Id.of_string "rocqLeanImportCommandParsedSnapshotPProd")
           ~types:None ~univs body);
      let punit_ind =
        match
          Nametab.locate
            (Libnames.qualid_of_ident (Id.of_string "PUnit"))
        with
        | GlobRef.IndRef ind -> ind
        | _ -> CErrors.user_err Pp.(str "PUnit is not an inductive")
      in
      let body =
        Constr.mkLambda
          ( Context.nameR (Id.of_string "A"),
            sort,
            Constr.mkIndU
              (punit_ind, UVars.Instance.of_array ([||], [| level |])) )
      in
      ignore
        (quickdef
           ~name:(Id.of_string "rocqLeanImportCommandParsedSnapshotPUnit")
           ~types:None ~univs body)
    end
  in
  let () =
    if do_code_below_focus n = Some DoCode then begin
      let _, levels =
        UVars.Instance.to_array (UVars.UContext.instance uctx)
      in
      if Array.length levels < 1 then
        CErrors.user_err Pp.(str "Unexpected Do.Code.below universe context");
      let level = levels.(0) in
      let sort = Constr.mkType (Universe.make level) in
      let pprod_ind =
        match
          Nametab.locate
            (Libnames.qualid_of_ident (Id.of_string "PProd"))
        with
        | GlobRef.IndRef ind -> ind
        | _ -> CErrors.user_err Pp.(str "PProd is not an inductive")
      in
      let pprod_inst =
        UVars.Instance.of_array ([||], [| level; level; level |])
      in
      let pprod_body =
        Constr.mkLambda
          ( Context.nameR (Id.of_string "A"),
            sort,
            Constr.mkLambda
              ( Context.nameR (Id.of_string "B"),
                sort,
                Constr.mkApp
                  ( Constr.mkIndU (pprod_ind, pprod_inst),
                    [| Constr.mkRel 2; Constr.mkRel 1 |] ) ) )
      in
      ignore
        (quickdef ~name:(Id.of_string "rocqLeanImportDoCodePProd")
           ~types:None ~univs pprod_body);
      let punit_ind =
        match
          Nametab.locate
            (Libnames.qualid_of_ident (Id.of_string "PUnit"))
        with
        | GlobRef.IndRef ind -> ind
        | _ -> CErrors.user_err Pp.(str "PUnit is not an inductive")
      in
      let punit_body =
        Constr.mkLambda
          ( Context.nameR (Id.of_string "A"),
            sort,
            Constr.mkIndU
              (punit_ind, UVars.Instance.of_array ([||], [| level |])) )
      in
      ignore
        (quickdef ~name:(Id.of_string "rocqLeanImportDoCodePUnit")
           ~types:None ~univs punit_body)
    end
  in
  let scope = Locality.(Global ImportDefaultBehavior) in
  let kind = Decls.(IsDefinition Definition) in
  let env = Global.env () in
  let info, sigma =
    if UVars.UContext.is_empty uctx then
      (Declare.Info.make ~scope ~kind (), Evd.from_env env)
    else
      let _, local_univs = UVars.UContext.to_context_set uctx in
      let ustate = UState.from_env env in
      let ustate =
        UState.merge_universe_context_set ~sideff:false UState.univ_rigid ustate
          local_univs
      in
      let _, levels = UVars.Instance.to_array (UVars.UContext.instance uctx) in
      let udecl =
        {
          UState.default_univ_decl with
          univdecl_instance = Array.to_list levels;
          univdecl_extensible_instance = is_cycle_prev n || is_cycle_next n;
          univdecl_univ_constraints = UVars.UContext.univ_constraints uctx;
        }
      in
      let poly = PolyFlags.of_univ_poly true in
      ( Declare.Info.make ~scope ~kind ~poly ~udecl (),
        Evd.from_ustate ustate )
  in
  let cinfo =
    Declare.CInfo.make ~name:(name_for n i) ~typ:(EConstr.of_constr ty) ()
  in
  let proof = Declare.Proof.start ~info ~cinfo sigma in
  let raw_tac = Procq.parse_string Ltac_plugin.Pltac.tactic_eoi tactic in
  let proof, safe =
    Declare.Proof.by env
      (Ltac_plugin.Tacinterp.interp raw_tac)
      proof
  in
  if not safe then
    CErrors.user_err
      Pp.(str "Unsafe tactic used while reconstructing " ++ N.pp n);
  let opacity =
    if transparent then Vernacexpr.Transparent else Vernacexpr.Opaque
  in
  match
    Declare.Proof.save_regular ~proof ~opaque:opacity ~idopt:None
  with
  | [ ConstRef c ] ->
    Feedback.msg_info
      Pp.(Id.print (name_for_core n i) ++ str " is reconstructed in Rocq");
    GlobRef.ConstRef c
  | _ ->
    CErrors.user_err
      Pp.(str "Unexpected proof output while reconstructing " ++ N.pp n)

and declare_def { name = n; ty; body; univs; } i =
  let ref, algs, proof_like, strategy_override =
    match get_predeclared_def_some n i with
<<<<<<< HEAD
    | Some
	        ( (( UInt32_size
	          | System_Platform_numBits
	          | System_Platform_numBits_eq
	          | UInt32_ofNatLT
	          | UInt64_size
			          | UInt64_ofNatLT
			          | USize_toBitVec
			          | USize_toNat
				          | USize_size
				          | USize_size_eq
				          | USize_le_size
				          | USize_size_le
				          | UInt8_toNat
	          | UInt8_toUInt32
	          | Add
          | Mult
          | Pow
          | Nat_isValidChar
          | IsValidChar_UInt32
          | IsValidChar_UInt32_match_1_1
          | Char_ofNatAux
          | Char_ofNat ) as defk),
          _,
          (def_name, c) ) ->
=======
    | Some ((UInt32_size | Add | Mult | Pow | Nat_isValidChar), _, (def_name, c)) ->
>>>>>>> parent of dec4a1b (Predeclare modern Char construction helpers)
      (* Hack to let the user predeclare some constants
         TODO make a more general Register-like API? *)
      Feedback.msg_info Pp.(Id.print def_name ++ str " is predeclared");
      (GlobRef.ConstRef c, [], false, predeclared_def_strategy defk)
    | None
      when is_equiv_prod_punit_def n || is_lean_json_cases_on_def n
           || is_lean_info_tree_cases_on_def n
           || is_remove_after_done_action_sparse_cases_on_3_def n
           || is_lean_json_sparse_cases_on_6_def n
           || is_lean_json_beq_sparse_cases_on_8_def n
           || is_lean_json_beq_sparse_cases_on_3_def n
           || is_lean_json_beq_sparse_cases_on_4_def n
           || is_lean_json_beq_sparse_cases_on_5_def n
           || is_lean_json_beq_sparse_cases_on_6_def n
           || is_lean_json_beq_sparse_cases_on_7_def n
           || is_option_from_json_sparse_cases_on_1_def n
           || is_array_from_json_sparse_cases_on_1_def n
           || is_float_from_json_sparse_cases_on_1_def n
           || is_name_map_from_json_sparse_cases_on_1_def n
           || is_json_structured_from_json_sparse_cases_on_1_def n
           || is_command_parsed_snapshot_below_1_def n
           || is_do_code_below_def n
           || is_uint64_of_fin n
           || is_persistent_hash_map_node_sizeof_1_def n
           || is_cycle_prev n || is_cycle_next n ->
      let uconv = start_uconv univs i in
      let uconv, ty = to_constr empty_env ty uconv in
      let univs, algs = univ_entry uconv univs in
      let ref =
        declare_reconstructed_def ~transparent:true n i ty univs
      in
      let algs =
        if is_cycle_prev n || is_cycle_next n then
          match List.rev algs with
          | body_level :: _ -> algs @ [ body_level ]
          | [] -> assert false
        else algs
      in
      (ref, algs, false, None)
    | None when reconstruct_def_by_rocq n ->
      (* Some reconstructed definitions use sort-specialized instances that
         are first discovered while translating their original body.  Keep
         those declarations, but discard the original body's universe
         constraints before checking the replacement proof. *)
      (if is_cycle_prev_proof_1 n || is_cycle_next_proof_1 n then
        let body_uconv = start_uconv univs i in
        ignore (to_constr empty_env body body_uconv));
      let uconv = start_uconv univs i in
      let uconv, ty = to_constr empty_env ty uconv in
      let univs, algs = univ_entry uconv univs in
      let ref = declare_reconstructed_def n i ty univs in
      (ref, algs, true, Some Conv_oracle.Opaque)
    | None ->
      let uconv = start_uconv univs i in
      let uconv, ty = to_constr empty_env ty uconv in
      let proof_like = is_sprop_type empty_env uconv ty in
      let uconv, body = to_constr empty_env body uconv in
      let body =
        if is_punit_comm_group_def n then
          with_env_evm empty_env uconv
            (fun env evd () -> adapt_punit_comm_group env evd body)
            ()
        else body
      in
      let univs, algs = univ_entry uconv univs in
      let body, ty, parse_with_helpers =
        if is_std_time_parse_with n then
          split_std_time_parse_with_body univs body
        else (body, ty, [])
      in
      let ref =
        try
          quickdef ~name:(name_for n i) ~types:(Some ty) ~univs
            ~opaque:proof_like body
        with e ->
          let e = Exninfo.capture e in
          Feedback.msg_info
            Pp.(
              str "Failed with" ++ fnl ()
              ++ Printer.pr_constr_env (Global.env ())
                   (Evd.from_env (Global.env ()))
                   body
              ++ fnl () ++ str ": "
              ++ Printer.pr_constr_env (Global.env ())
                   (Evd.from_env (Global.env ()))
                   ty);
          Exninfo.iraise e
      in
      let () =
        List.iter
          (fun c ->
            Global.set_strategy (Conv_oracle.EvalConstRef c)
              (Conv_oracle.Level 0))
          parse_with_helpers
      in
      (ref, algs, proof_like, None)
  in
  let () =
    let c = match ref with ConstRef c -> c | _ -> assert false in
    let level =
      match strategy_override with
      | Some level -> level
      | None when proof_like -> (
        height_cache := N.Map.add n 0 !height_cache;
        Conv_oracle.Opaque)
      | None ->
        let height = height n body in
        if low_priority_def n || contains_large_nat_literal n body then
          Level large_nat_unfold_level
        else Level (-height)
    in
    Global.set_strategy (Conv_oracle.EvalConstRef c) level
  in
  let inst = { ref; algs } in
  let () = add_declared n i inst in
  inst

and declare_ax { name = n; ty; univs } i =
  let uconv = start_uconv univs i in
  let uconv, ty = to_constr empty_env ty uconv in
  let univs, algs = univ_entry uconv univs in
  let entry = Declare.(ParameterEntry (parameter_entry ~univs ty)) in
  let c =
    Declare.declare_constant ~name:(name_for n i)
      ~kind:Decls.(IsAssumption Definitional)
      entry
  in
  let inst = { ref = GlobRef.ConstRef c; algs } in
  let () = add_declared n i inst in
  inst

and to_params uconv params =
  let acc, params =
    CList.fold_left_map
      (fun (env, uconv) (_bk, p, ty) ->
        let uconv, ty = to_constr env ty uconv in
        let d = RelDecl.LocalAssum (to_annot env p ty uconv, ty) in
        let env = Environ.push_rel_context_val d env in
        ((env, uconv), d))
      (empty_env, uconv) params
  in
  (acc, List.rev params)

and declare_ind { name = n; params; ty; ctors; univs } i =
  (* Handle inductives predeclared as definitions (e.g., ULift with cumulativity).
     We check if there's a cumul registration for this specific instance. *)
  match get_predeclared_ind_as_def_some n i with
  | Some (ULift_cumul, _, _) ->
    let def_name = name_for_core n i in
    let cumul_reg nm = "lean." ^ Id.to_string (name_for_core nm i) ^ ".cumul" in
    Feedback.msg_info Pp.(Id.print def_name ++ str " is predeclared (cumulative)");
    (* The Rocq cumul definitions take four universes [r s s1 rs1] where
       [s1] stands for Lean's [s+1] and [rs1] for Lean's [max(r+1, s+1)].
       Lean provides two universes [r; s], so the Rocq instance is represented
       by four algebraic universes over the Lean instance.  For [ULift.rec] at
       scheme j = 2*i (motive non-SProp), Lean also provides [motive] as the
       first universe, shifting [r] and [s] to positions 1 and 2 in [Level.var].
       For [ULift.rec] at j = 2*i+1 (motive SProp), [motive] is filtered out by
       [int_of_univs] so the indices match the non-rec case. *)
    let algs_of r_idx s_idx =
      let r = Universe.make (Level.var r_idx) in
      let s = Universe.make (Level.var s_idx) in
      [
        r;
        s;
        Universe.super s;
        Universe.sup (Universe.super r) (Universe.super s);
      ]
    in
    let algs_2 = algs_of 0 1 in
    let algs_rec = universe_var 0 :: algs_of 1 2 in
    let ulift_ref = Rocqlib.lib_ref (cumul_reg n) in
    let inst = { ref = ulift_ref; algs = algs_2 } in
    add_declared n i inst;
    (* Register ULift.up constructor *)
    let cname = N.append n "up" in
    add_declared cname i { ref = Rocqlib.lib_ref (cumul_reg cname); algs = algs_2 };
    (* Register ULift.down *)
    let dname = N.append n "down" in
    add_declared dname i { ref = Rocqlib.lib_ref (cumul_reg dname); algs = algs_2 };
    (* Register eliminator (Type scheme at j=2*i, SProp scheme at j=2*i+1) *)
    let nrec = N.append n "rec" in
    let rec_base = cumul_reg nrec in
    add_declared nrec (2 * i) { ref = Rocqlib.lib_ref rec_base; algs = algs_rec };
    add_declared nrec ((2 * i) + 1) { ref = Rocqlib.lib_ref (rec_base ^ ".ind"); algs = algs_2 };
    inst
  | None ->
  let mind, algs, ind_name, cnames, univs, squashy =
    match get_predeclared_ind_some n i with
    | Some (Eq, _, (ind_name, mind)) ->
      (* Hack to let the user predeclare eq and quot before running Lean Import
         TODO make a more general Register-like API? *)
      Feedback.msg_info Pp.(Id.print ind_name ++ str " is predeclared");
      let cname = N.append n "refl" in
      let squashy =
        { maybe_prop = true; always_prop = true; lean_squashes = false }
      in
      let univs =
        match i with
        | 0 ->
          UContext.make
            { quals = [||]; univs =  [| Name (Id.of_string "u") |]}
            ( Instance.of_array ([||], [| univ_of_name (N.append N.anon "u") |]),
              PConstraints.empty )
        | 1 -> UContext.empty
        | _ -> assert false
      in
      (mind, identity_algs (non_sprop_univ_count 1 i), ind_name, [ cname ], univs, squashy)
    | Some
        ( ((Nat | Nat_le | Or | And | Fin | UInt8 | UInt32 | UInt64 | USize | BitVec | Char) as k),
          _,
          (ind_name, mind) ) ->
      (* Hack to let the user predeclare various types before running Lean Import
         TODO make a more general Register-like API? *)
      (* this case is for the ones without universes*)
      Feedback.msg_info Pp.(Id.print ind_name ++ str " is predeclared");
      let cnames = get_predeclared_cnames k n in
      let squashy = N.Map.get n !squash_info in
      (mind, [], ind_name, cnames, UContext.empty, squashy)
    | None ->
      let uconv = start_uconv univs i in
      let (env_params, uconv), params = to_params uconv params in
      let uconv, ty = to_constr env_params ty uconv in
      let indices, sort =
        let env_params =
          Environ.set_rel_context_val env_params
            (Environ.set_universes uconv.graph (Global.env ()))
        in
        Reduction.dest_arity env_params ty
      in
      let env_ind =
        Environ.push_rel_context_val
          (LocalAssum
             ( Context.make_annot (N.to_name n) (Sorts.relevance_of_sort sort),
               Term.it_mkProd_or_LetIn ty params ))
          empty_env
      in
      let env_ind_params =
        Context.Rel.fold_outside Environ.push_rel_context_val params
          ~init:env_ind
      in
      let uconv, ctors =
        CList.fold_left_map
          (fun uconv (n, ty) ->
            let uconv, ty = to_constr env_ind_params ty uconv in
            (uconv, (n, ty)))
          uconv ctors
      in
      let cnames, ctys = List.split ctors in
      let graph = uconv.graph in
      let drop_global_lower_bounds =
        N.equal n list_name || N.equal n array_name
      in
      let univs, algs =
        univ_entry_gen ~drop_global_lower_bounds uconv univs
      in
      let ind_name = name_for n i in
      let record, fields, ctys =
        match (indices, ctys) with
        | [], [ cty ] ->
          cty
          |> with_env_evm env_ind_params uconv (fun env evm cty ->
                 let fields, codom =
                   Reductionops.whd_decompose_prod env evm
                     (EConstr.of_constr cty)
                 in
                 let _, fields =
                   CList.fold_left_map
                     (fun ids (na, t) ->
                       match na.Context.binder_name with
                       | Names.Anonymous -> (ids, (na, t))
                       | Names.Name id ->
                         let id = Namegen.next_global_ident_away (Global.safe_env ()) id ids in
                         let ids = Id.Set.add id ids in
                         line_msg
                           (N.of_list
                              [
                                Names.Id.to_string id;
                                "(field)";
                                Names.Id.to_string ind_name;
                              ]);
                         (ids, ({ na with binder_name = Names.Name id }, t)))
                     (Id.Set.add ind_name Id.Set.empty)
                     fields
                 in
                 let cty' = EConstr.it_mkProd codom fields in
                 let cty' = EConstr.Unsafe.to_constr cty' in
                 (* A recursive single-constructor inductive cannot admit
                    eta, so the kernel rejects the primitive-record
                    encoding. Fall through to plain Inductive in that case. *)
                 let npars = List.length params in
                 let is_recursive =
                   let rec walk k c =
                     match Constr.kind c with
                     | Constr.Prod (_, t, body) ->
                       (not (Vars.noccurn k t)) || walk (k + 1) body
                     | _ -> false
                   in
                   walk (npars + 1) cty'
                 in
	                 match (fields, Sorts.is_sprop sort, is_recursive) with
	                 | [], true, _ -> (None, [], ctys)
	                 | _ :: _, false, false ->
	                   if
	                     List.exists
	                       (fun (na, _) ->
	                         na.Context.binder_relevance
                         == EConstr.ERelevance.relevant)
                       fields
                   then (Some (Some [| default_proj_id |]), fields, [ cty' ])
                   else (None, [], ctys)
	                 | [], false, _ -> (None, [], ctys)
	                 | _ :: _, true, false ->
	                   if
	                     List.for_all
	                       (fun (na, _) ->
	                         na.Context.binder_relevance
                         == EConstr.ERelevance.irrelevant)
                       fields
                   then (Some (Some [| default_proj_id |]), fields, [ cty' ])
                   else (None, [], ctys)
                 | _ :: _, _, true -> (None, [], ctys))
        | _ -> (None, [], ctys)
      in
      let entry finite =
        {
          Entries.mind_entry_params = params;
          mind_entry_record = record;
          mind_entry_finite = finite;
          mind_entry_inds =
            [
              {
                mind_entry_typename = ind_name;
                mind_entry_arity = ty;
                mind_entry_consnames = List.map (fun n -> name_for n i) cnames;
                mind_entry_lc = ctys;
              };
            ];
          mind_entry_private = None;
          mind_entry_universes = Polymorphic_ind_entry univs;
          mind_entry_variance = None;
        }
      in
      let squashy = N.Map.get n !squash_info in
      let coq_squashes =
        if squashy.maybe_prop then coq_squashes graph (entry Finite) else false
      in
      let mind =
	        let act finite =
	          let all_depth =
	            if N.equal n list_name || N.equal n option_name then Some 1
	            else None
	          in
	          let schemes =
	            if N.equal n list_name || N.equal n option_name then
	              DeclareInd.Default
	            else DeclareInd.None
	          in
	          DeclareInd.declare_mutual_inductive_with_eliminations ?all_depth
	            ~schemes
	            (entry finite)
	            (* the ubinders API is kind of shit here *)
	            (UState.Polymorphic_entry UContext.empty, UnivNames.empty_binders)
	            []
        in
        let act () = try act BiFinite with e -> act Finite in
        if squashy.lean_squashes || not coq_squashes then act ()
        else with_unsafe_univs act ()
      in
      assert (
        squashy.lean_squashes
        || (Global.lookup_mind mind).mind_packets.(0).mind_squashed == None);
      let () =
        if N.equal n array_name then array_minds := mind :: !array_minds
        else if N.equal n prod_name then prod_minds := mind :: !prod_minds
        else if N.equal n list_name then list_minds := mind :: !list_minds
        else if N.equal n option_name then option_minds := mind :: !option_minds
        else
          match !array_minds with
          | _ :: _ ->
            let nested_shape =
              List.find_map
                (fun cty ->
                  let binders, _ = Term.decompose_prod cty in
                  List.find_map
                    (fun (_, binder_ty) ->
                      let head, args = Constr.decompose_app binder_ty in
                      match Constr.kind head with
                      | Ind ((mind, _), _) ->
                        if
                          List.exists
                            (MutInd.UserOrd.equal mind) !array_minds
                        then
                          let element = args.(Array.length args - 1) in
                          let element_head, _ = Constr.decompose_app element in
                          let shape =
                            match Constr.kind element_head with
                            | Ind ((mind, _), _)
                              when
                                List.exists
                                  (MutInd.UserOrd.equal mind) !prod_minds ->
                              ArrayProdSecond
                            | _ -> ArraySelf
                          in
                          Some shape
                        else None
                      | _ -> None)
                    binders)
                ctys
            in
            Option.iter
              (fun shape ->
              let base_rec = N.append n "rec" in
              let nparams = List.length params in
              let nctors = List.length ctys in
              let add name focus =
                nested_array_rec_info :=
                  N.Map.add name { base_rec; nparams; nctors; focus; shape }
                    !nested_array_rec_info
              in
              add base_rec FocusMain;
              add (N.append n "rec_1") FocusArray;
              add (N.append n "rec_2") FocusList;
              match shape with
              | ArraySelf -> ()
              | ArrayProdSecond -> add (N.append n "rec_3") FocusProd)
              nested_shape
          | _ -> ()
      in
      (* Declare projections if the inductive is a record *)
      let projections =
        match record with
        | Some (Some _) ->
          let inhabitant_id = ind_name in
          let kind = Decls.StructureComponent in
          let proj_flags =
            List.map
              (fun _ ->
                {
                  Record.Data.pf_coercion = None;
                  pf_instance = None;
                  pf_canonical = false;
                })
              fields
          in
          let implfs = List.map (fun _ -> []) fields in
          Record.Internal.declare_projections (mind, 0) ~kind ~inhabitant_id
            proj_flags implfs
        | _ -> []
      in
      let () =
        if N.equal n array_name then
          declare_array_all_scheme mind ind_name univs fields projections
        else if N.equal n prod_name then
          declare_prod_second_all_scheme mind ind_name univs projections
        else if
          List.exists
            (String.equal (N.to_lean_string n))
            [ "Lean.Elab.Term.Do.Alt"; "Lean.Elab.Term.Do.AltExpr" ]
        then
          declare_last_field_all_scheme mind ind_name univs projections
      in
      (mind, algs, ind_name, cnames, univs, squashy)
  in

  (* add ind and ctors to [declared] *)
  let inst = { ref = GlobRef.IndRef (mind, 0); algs } in
  let () = add_declared n i inst in
  let () =
    CList.iteri
      (fun cnum cname ->
        add_declared cname i
          { ref = GlobRef.ConstructRef ((mind, 0), cnum + 1); algs })
      cnames
  in

  (* elim *)
  let make_scheme fam =
    let u =
      if fam = SchemeSProp then LSProp
      else
        let u =
          if lean_fancy_univs () then
            let u = DirPath.make [ Id.of_string "motive"; lean_id ] in
            Level.(make (UGlobal.make u "" 0))
          else UnivGen.fresh_level ()
        in
        Level u
    in
    let motive_constraints u =
      if String.equal (N.to_lean_string n) "Lean.Elab.Term.Do.Code" then
        UnivConstraints.singleton (Level.set, Lt, u)
      else UnivConstraints.empty
    in
    let env = Environ.push_context ~strict:true univs (Global.env ()) in
    let env =
      match u with
      | LSProp -> env
      | Level u ->
        Environ.push_context_set ~strict:false
          (Level.Set.singleton u, motive_constraints u) env
    in
    let inst, uentry =
      let inst = UContext.instance univs in
      let csts = UContext.constraints univs in
      let { quals = qnames; univs = unames} = UContext.names univs in
      let uentry =
        match u with
        | LSProp -> UState.Polymorphic_entry univs
        | Level u ->
          let csts =
            PConstraints.union csts
              (PConstraints.of_univs (motive_constraints u))
          in
          UState.Polymorphic_entry
            (UContext.make
               {quals = qnames; univs = Array.append [| Name (Id.of_string "motive") |] unames}
               ( Instance.of_array
                   ([||], Array.append [| u |] (snd (Instance.to_array inst))),
                 csts ))
      in
      (inst, uentry)
    in
    (* lean 4 change: always dep? was not squashy.always_prop*)
    (lean_scheme env ~dep:true (mind, 0) inst u, uentry)
  in
  let nrec = N.append n "rec" in
  let elims =
    if squashy.lean_squashes then [ ("_indl", SchemeSProp) ]
    else [ ("_recl", SchemeType); ("_indl", SchemeSProp) ]
  in

  let declare_one_scheme (suffix, sort) =
    let id = Id.of_string (Id.to_string ind_name ^ suffix) in
    let body, uentry = make_scheme sort in
    let elim =
      quickdef ~name:id ~types:None
        ~univs:(uentry, UnivNames.empty_binders)
        body
      (* TODO implicits? *)
    in
    (* TODO AFAICT Lean reduces recursors eagerly, but ofc only when applied to a ctor
       Can we simulate that with strategy better than by leaving them at the default strat? *)
    let liftu l =
      let u =
        match Level.var_index l with
        | None -> Universe.make l (* Set *)
        | Some i -> Universe.make (Level.var (i + 1))
      in
      Some u
    in
    let algs =
      if sort = SchemeSProp then algs
      else universe_var 0 :: List.map (UnivSubst.subst_univs_universe liftu) algs
    in
    let elim = { ref = elim; algs } in
    let j =
      if squashy.lean_squashes then i
      else if sort == SchemeType then 2 * i
      else (2 * i) + 1
    in
    add_declared nrec j elim
  in
  let () =
    List.iter
      (fun x ->
        try declare_one_scheme x
        with e when CErrors.noncritical e && error_mode e = Skip ->
          Feedback.msg_info Pp.(str "Skipping scheme"))
      elims
  in
  let () =
    let base_rec = N.append n "rec" in
    let env = Environ.push_context ~strict:true univs (Global.env ()) in
    let packet = (Global.lookup_mind mind).mind_packets.(0) in
    let nested_recursive =
        Array.exists
          (fun (ctor_args, _) ->
            List.exists
              (fun arg ->
                let arg_ty = RelDecl.get_type arg in
                if not (has_rec_hyp env mind arg_ty) then false
                else
                  let _, head = Reduction.whd_decompose_prod_decls env arg_ty in
                  let head, _ = Constr.decompose_app head in
                  match Constr.kind head with
                  | Constr.Ind ((arg_mind, _), _) ->
                    not (MutInd.UserOrd.equal mind arg_mind)
                  | _ -> true)
              ctor_args)
          packet.mind_nf_lc
    in
    let force_mutual_nested =
      String.equal (N.to_lean_string n) "Lean.Elab.Term.Do.Code"
    in
    if
      nested_recursive
      && (force_mutual_nested
          || not (N.Map.mem base_rec !nested_array_rec_info))
    then begin
        let info focus =
          { base_recs = [ base_rec ]; mind; nparams = List.length params; focus }
        in
        mutual_nested_rec_info :=
          N.Map.add base_rec (info (MutualMain 0)) !mutual_nested_rec_info;
        for aux = 0 to 31 do
          let aux_rec = N.append n ("rec_" ^ string_of_int (aux + 1)) in
          mutual_nested_rec_info :=
            N.Map.add aux_rec (info (MutualAux aux))
              !mutual_nested_rec_info
        done
    end
  in
  inst

and declare_mutual_inds inds i =
  match inds with
  | [] | [ _ ] -> assert false
  | first :: _ ->
    let ntypes = List.length inds in
    let nparams = List.length first.params in
    if
      List.exists
        (fun ind -> ind.params <> first.params || ind.univs <> first.univs)
        inds
    then
      CErrors.user_err
        Pp.(str "Mutual inductives have different parameters or universes");
    let group_names = List.map (fun ind -> ind.name) inds in
    let group_index name =
      let rec find i = function
        | [] -> None
        | name' :: names ->
          if N.equal name name' then Some i else find (i + 1) names
      in
      find 0 group_names
    in
    let rec remap_ctor_self current depth = function
      | Bound k when k = nparams + depth ->
        Bound (nparams + (ntypes - current - 1) + depth)
      | Const (name, _) when Option.has_some (group_index name) ->
        let target = Option.get (group_index name) in
        Bound (nparams + (ntypes - target - 1) + depth)
      | (Const _ | Bound _ | Sort _ | Nat _ | String _) as expr -> expr
      | App (f, x) ->
        App (remap_ctor_self current depth f, remap_ctor_self current depth x)
      | Let { name; ty; v; rest } ->
        Let
          {
            name;
            ty = remap_ctor_self current depth ty;
            v = remap_ctor_self current depth v;
            rest = remap_ctor_self current (depth + 1) rest;
          }
      | Lam (bk, name, ty, body) ->
        Lam
          ( bk,
            name,
            remap_ctor_self current depth ty,
            remap_ctor_self current (depth + 1) body )
      | Pi (bk, name, ty, body) ->
        Pi
          ( bk,
            name,
            remap_ctor_self current depth ty,
            remap_ctor_self current (depth + 1) body )
      | Proj (name, field, c) ->
        Proj (name, field, remap_ctor_self current depth c)
    in
    let uconv = start_uconv first.univs i in
    let (env_params, uconv), params = to_params uconv first.params in
    let uconv, arities =
      CList.fold_left_map
        (fun uconv ind ->
          let uconv, ty = to_constr env_params ind.ty uconv in
          let _indices, sort =
            let env =
              Environ.set_rel_context_val env_params
                (Environ.set_universes uconv.graph (Global.env ()))
            in
            Reduction.dest_arity env ty
          in
          (uconv, (ind, ty, sort)))
        uconv inds
    in
    let env_inds =
      List.fold_left
        (fun env (ind, ty, sort) ->
          Environ.push_rel_context_val
            (LocalAssum
               ( Context.make_annot
                   (N.to_name ind.name)
                   (Sorts.relevance_of_sort sort),
                 Term.it_mkProd_or_LetIn ty params ))
            env)
        empty_env arities
    in
    let env_ind_params =
      Context.Rel.fold_outside Environ.push_rel_context_val params
        ~init:env_inds
    in
    let (_current, uconv), packets =
      CList.fold_left_map
        (fun (current, uconv) (ind, ty, _sort) ->
          let uconv, ctors =
            CList.fold_left_map
              (fun uconv (ctor_name, ctor_ty) ->
                let ctor_ty = remap_ctor_self current 0 ctor_ty in
                let uconv, ctor_ty = to_constr env_ind_params ctor_ty uconv in
                (uconv, (ctor_name, ctor_ty)))
              uconv ind.ctors
          in
          let ctor_names, ctor_types = List.split ctors in
          ( (current + 1, uconv),
            ( ind,
              ty,
              ctor_names,
              ctor_types ) ))
        (0, uconv) arities
    in
    let univs, algs = univ_entry_gen uconv first.univs in
    let entry finite =
      {
        Entries.mind_entry_params = params;
        mind_entry_record = None;
        mind_entry_finite = finite;
        mind_entry_inds =
          List.map
            (fun (ind, ty, ctor_names, ctor_types) ->
              {
                Entries.mind_entry_typename = name_for ind.name i;
                mind_entry_arity = ty;
                mind_entry_consnames =
                  List.map (fun name -> name_for name i) ctor_names;
                mind_entry_lc = ctor_types;
              })
            packets;
        mind_entry_private = None;
        mind_entry_universes = Entries.Polymorphic_ind_entry univs;
        mind_entry_variance = None;
      }
    in
    let mind =
      let act finite =
        DeclareInd.declare_mutual_inductive_with_eliminations
          ~schemes:DeclareInd.None
          (entry finite)
          (UState.Polymorphic_entry UContext.empty, UnivNames.empty_binders)
          []
      in
      try act Declarations.BiFinite with _ -> act Declarations.Finite
    in
    List.iteri
      (fun ind_index (ind, _ty, ctor_names, _ctor_types) ->
        add_declared ind.name i
          { ref = GlobRef.IndRef (mind, ind_index); algs };
        List.iteri
          (fun ctor_index ctor_name ->
            add_declared ctor_name i
              {
                ref =
                  GlobRef.ConstructRef
                    ((mind, ind_index), ctor_index + 1);
                algs;
              })
          ctor_names)
      packets;
    let make_scheme ind_index fam =
      let u =
        if fam = SchemeSProp then LSProp
        else
          let u =
            if lean_fancy_univs () then
              let u = DirPath.make [ Id.of_string "motive"; lean_id ] in
              Level.(make (UGlobal.make u "" 0))
            else UnivGen.fresh_level ()
          in
          Level u
      in
      let env = Environ.push_context ~strict:true univs (Global.env ()) in
      let env =
        match u with
        | LSProp -> env
        | Level u ->
          Environ.push_context_set ~strict:false
            (Univ.ContextSet.singleton u) env
      in
      let inst = UContext.instance univs in
      let csts = UContext.constraints univs in
      let { quals = qnames; univs = unames } = UContext.names univs in
      let uentry =
        match u with
        | LSProp -> UState.Polymorphic_entry univs
        | Level u ->
          UState.Polymorphic_entry
            (UContext.make
               {
                 quals = qnames;
                 univs =
                   Array.append [| Name (Id.of_string "motive") |] unames;
               }
               ( Instance.of_array
                   ([||], Array.append [| u |] (snd (Instance.to_array inst))),
                 csts ))
      in
      (lean_scheme env ~dep:true (mind, ind_index) inst u, uentry)
    in
    let () =
      List.iteri
      (fun ind_index (ind, _ty, _ctor_names, _ctor_types) ->
        let squashy = N.Map.get ind.name !squash_info in
        let elims =
          if squashy.lean_squashes then [ ("_indl", SchemeSProp) ]
          else [ ("_recl", SchemeType); ("_indl", SchemeSProp) ]
        in
        List.iter
          (fun (suffix, sort) ->
            let ind_name = name_for ind.name i in
            let id = Id.of_string (Id.to_string ind_name ^ suffix) in
            let body, uentry = make_scheme ind_index sort in
            let elim =
              quickdef ~name:id ~types:None
                ~univs:(uentry, UnivNames.empty_binders) body
            in
            let liftu l =
              let u =
                match Level.var_index l with
                | None -> Universe.make l
                | Some j -> Universe.make (Level.var (j + 1))
              in
              Some u
            in
            let scheme_algs =
              if sort = SchemeSProp then algs
              else
                universe_var 0
                :: List.map
                     (UnivSubst.subst_univs_universe liftu)
                     algs
            in
            let instance = { ref = elim; algs = scheme_algs } in
            let scheme_index =
              if squashy.lean_squashes then i
              else if sort = SchemeType then 2 * i
              else (2 * i) + 1
            in
            add_declared (N.append ind.name "rec") scheme_index instance)
          elims)
      packets
    in
    let base_recs =
      List.map
        (fun (ind, _ty, _ctor_names, _ctor_types) ->
          N.append ind.name "rec")
        packets
    in
    List.iteri
      (fun ind_index (ind, _ty, _ctor_names, _ctor_types) ->
        let base_rec = N.append ind.name "rec" in
        mutual_nested_rec_info :=
          N.Map.add base_rec
            {
              base_recs;
              mind;
              nparams;
              focus = MutualMain ind_index;
            }
            !mutual_nested_rec_info;
        for aux = 0 to 31 do
          let aux_rec =
            N.append ind.name ("rec_" ^ string_of_int (aux + 1))
          in
          mutual_nested_rec_info :=
            N.Map.add aux_rec
              { base_recs; mind; nparams; focus = MutualAux aux }
              !mutual_nested_rec_info
        done)
      packets

(** Generate and add the squashy info *)
let squashify { name = n; params; ty; ctors; univs } =
  let uconvP =
    (* NB: if univs = [] this is just instantiation 0 *)
    start_uconv univs ((1 lsl List.length univs) - 1)
  in
  let (env_paramsP, uconvP), paramsP = to_params uconvP params in
  let uconvP, tyP = to_constr env_paramsP ty uconvP in
  let envP =
    Environ.push_rel_context paramsP
      (Environ.set_universes uconvP.graph (Global.env ()))
  in
  let _, sortP = Reduction.dest_arity envP tyP in
  if not (Sorts.is_sprop sortP) then noprop
  else
    let uconvT = start_uconv univs 0 in
    let (env_paramsT, uconvT), paramsT = to_params uconvT params in
    let uconvT, tyT = to_constr env_paramsT ty uconvT in
    let envT =
      Environ.set_rel_context_val env_paramsT
        (Environ.set_universes uconvT.graph (Global.env ()))
    in
    let _, sortT = Reduction.dest_arity envT tyT in
    let always_prop = Sorts.is_sprop sortT in
    match ctors with
    | [] -> { maybe_prop = true; always_prop; lean_squashes = false }
    | _ :: _ :: _ -> { maybe_prop = true; always_prop; lean_squashes = true }
    | [ (_, ctor) ] ->
      let envT =
        Context.Rel.fold_outside Environ.push_rel_context_val paramsT
          ~init:
            (Environ.push_rel_context_val
               (LocalAssum
                  ( Context.make_annot (N.to_name n)
                      (Sorts.relevance_of_sort sortT),
                    Term.it_mkProd_or_LetIn tyT paramsT ))
               empty_env)
      in
      let uconvT, ctorT = to_constr envT ctor uconvT in
      let envT =
        Environ.set_rel_context_val envT
          (Environ.set_universes uconvT.graph (Global.env ()))
      in
      let args, out = Reduction.whd_decompose_prod envT ctorT in
      let forced =
        (* NB dest_prod returns [out] in whnf *)
        let _, outargs = Constr.decompose_app out in
        Array.fold_left
          (fun forced arg ->
            match Constr.kind arg with
            | Rel i -> Int.Set.add i forced
            | _ -> forced)
          Int.Set.empty outargs
      in
      let sigma = Evd.from_env envT in
      let npars = List.length params in
      let nargs = List.length args in
      let lean_squashes, _, _ =
        Context.Rel.fold_outside
          (fun d (squashed, i, envT) ->
            let squashed =
              if squashed then true
              else if Int.Set.mem (nargs - i) forced then false
              else
                let t = RelDecl.get_type d in
                if not (Vars.noccurn (npars + i + 1) t) then
                  (* recursive argument *)
                  false
                else
                  not
                    (EConstr.ESorts.is_sprop sigma
                       (Retyping.get_sort_of envT sigma (EConstr.of_constr t)))
            in

            (squashed, i + 1, Environ.push_rel d envT))
          args ~init:(false, 0, envT)
      in
      (* TODO translate to use non recursively uniform params (fix extraction)*)
      { maybe_prop = true; always_prop; lean_squashes }

let squashify ind =
  let s = squashify ind in
  squash_info := N.Map.add ind.name s !squash_info

(* pairs of (name * number of univs) *)
let quots = [ ("", 1); ("mk", 1); ("lift", 2); ("ind", 1) ]

let declare_quot quot_name =
  let () =
    List.iter
      (fun (n, nunivs) ->
        let rec loop i =
          if i = 1 lsl nunivs then ()
          else
            let lean =
              if CString.is_empty n then quot_name else N.append quot_name n
            in
            let reg =
              "lean." ^ N.to_lean_string lean
              ^ if i = 0 then "" else "_inst" ^ string_of_int i
            in
            let ref = Rocqlib.lib_ref reg in
            let algs = identity_algs (non_sprop_univ_count nunivs i) in
            let () = add_declared lean i { ref; algs } in
            loop (i + 1)
        in
        loop 0)
      quots
  in
  Feedback.msg_info Pp.(str "quot registered")

let declare_quot quot_name =
  if Rocqlib.has_ref "lean.Quot" then declare_quot quot_name else raise MissingQuot

let { Goptions.get = just_parse } =
  Goptions.declare_bool_option_and_ref
    ~key:[ "Lean"; "Just"; "Parsing" ]
    ~value:false ()

(* with this off: best line 23000 in stdlib
   stack overflow

   update: got fixed by e9e637de26 (distinguish names foo.bar and foo_bar)
*)
let { Goptions.get = upfront_instances } =
  Goptions.declare_bool_option_and_ref
    ~key:[ "Lean"; "Upfront"; "Instantiation" ]
    ~value:false ()

let { Goptions.get = lazy_instances } =
  Goptions.declare_bool_option_and_ref
    ~key:[ "Lean"; "Lazy"; "Instantiation" ]
    ~value:false ()

let declare_instances act univs =
  let stop = if upfront_instances () then 1 lsl List.length univs else 1 in
  let rec loop i =
    if i = stop then ()
    else
      let () = act i in
      loop (i + 1)
  in
  if not (lazy_instances ()) then loop 0

let declare_def def =
  declare_instances (fun i -> ignore (declare_def def i)) def.univs

let declare_ax ax =
  declare_instances (fun i -> ignore (declare_ax ax i)) ax.univs

let declare_ind ind =
  let () = squashify ind in
  declare_instances (fun i -> ignore (declare_ind ind i)) ind.univs

let declare_mutual_inds inds =
  List.iter squashify inds;
  match inds with
  | [] -> assert false
  | first :: _ ->
    declare_instances (fun i -> declare_mutual_inds inds i) first.univs

let entry_name = function
| Quot name | Def { name } | Ax { name } | Ind { name } -> name

let add_entry entry =
  let () =
    match entry with
    | Quot quot_name -> declare_quot quot_name
    | Def def -> declare_def def
    | Ax ax -> declare_ax ax
    | Ind ind -> declare_ind ind
  in
  entries := N.Map.add (entry_name entry) entry !entries

let add_mutual_entries inds =
  declare_mutual_inds inds;
  List.iter
    (fun ind -> entries := N.Map.add ind.name (Ind ind) !entries)
    inds

let rec is_arity = function
  | Sort _ -> true
  | Pi (_, _, _, b) -> is_arity b
  | _ -> false

let { Goptions.get = print_squashes } =
  Goptions.declare_bool_option_and_ref
    ~key:[ "Lean"; "Print"; "Squash"; "Info" ]
    ~value:false ()

type input_state = {
  pstate : LeanParse.parsing_state;
  skips : int;
}

let finish state =
  let max_univs, cnt =
    N.Map.fold
      (fun _ entry (m, cnt) ->
        match entry with
        | Ax { univs } | Def { univs } | Ind { univs } ->
          let l = List.length univs in
          (max m l, cnt + (1 lsl l))
        | Quot _ -> (max m 1, cnt + 2))
      !entries (0, 0)
  in
  let nonarities =
    N.Map.fold
      (fun _ entry cnt ->
        match entry with
        | Ax _ | Def _ | Quot _ -> cnt
        | Ind ind -> if is_arity ind.ty then cnt else cnt + 1)
      !entries 0
  in
  let squashes =
    if not (print_squashes ()) then Pp.mt ()
    else
      N.Map.fold
        (fun n s pp -> Pp.(pp ++ fnl () ++ N.pp n ++ spc () ++ pp_squashy s))
        !squash_info
        Pp.(mt ())
  in
  Feedback.msg_info
    Pp.(
      fnl () ++ fnl () ++ str "Done!" ++ fnl () ++ str "- "
      ++ int (N.Map.cardinal !entries)
      ++ str " entries (" ++ int cnt ++ str " possible instances)"
      ++ (if N.Map.exists (fun _ -> function Quot _ -> true | _ -> false) !entries then
            str " (including quot)."
          else str ".")
      ++ fnl () ++
      LeanParse.pp_state state.pstate ++
      (if state.skips > 0 then str "Skipped " ++ int state.skips ++ fnl ()
       else mt ())
      ++ str "Max universe instance length "
      ++ int max_univs ++ str "." ++ fnl () ++ int nonarities
      ++ str " inductives have non syntactically arity types."
      ++ squashes)

let prtime t0 t1 =
  let diff = System.time_difference t0 t1 in
  if diff > 1.0 then
    Feedback.msg_info
      Pp.(
        str "line " ++ int !lcnt ++ str " took "
        ++ System.fmt_time_difference t0 t1)

let timeout = ref None

let () =
  Goptions.declare_int_option
    {
      optdepr = None;
      optstage = Interp;
      optkey = [ "Lean"; "Line"; "Timeout" ];
      optread = (fun () -> !timeout);
      optwrite = (fun x -> timeout := x);
    }

exception TimedOut

let do_line state l =
  let do_line () = LeanParse.do_line state ~lcnt:!lcnt l in
  match !timeout with
  | None -> do_line ()
  | Some t ->
    (match Control.timeout (float_of_int t) do_line () with
    | Ok v -> v
    | Error info -> Exninfo.iraise (TimedOut, info))

let do_line state l =
  let t0 = System.get_time () in
  match do_line state l with
  | state ->
    let t1 = System.get_time () in
    prtime t0 t1;
    state
  | exception e ->
    let e = Exninfo.capture e in
    (if fst e <> TimedOut then
       let t1 = System.get_time () in
       prtime t0 t1);
    Exninfo.iraise e

let before_from = function None -> false | Some from -> !lcnt < from
let freeze () = (Lib.Interp.freeze (), Summary.Interp.freeze_summaries ())

let unfreeze (lib, sum) =
  Lib.Interp.unfreeze lib;
  Summary.Interp.unfreeze_summaries sum

let process_effect state ch ~line_no ~raw ~name act =
  let st = freeze () in
  match act () with
  | () -> Some state
  | exception e ->
    let e = Exninfo.capture e in
    let epp =
      Pp.(
        str "Error at line " ++ int line_no ++ str " (for " ++ N.pp name
        ++ str ")" ++ str (": " ^ raw) ++ fnl () ++ CErrors.iprint e)
    in
    unfreeze st;
    match error_mode (fst e) with
    | Skip ->
      Feedback.msg_info Pp.(str "Skipping: " ++ epp);
      Some { state with skips = state.skips + 1 }
    | Stop ->
      close_in ch;
      finish state;
      Feedback.msg_info epp;
      None
    | Fail ->
      close_in ch;
      finish state;
      CErrors.user_err epp

let rec do_input_pending state ~from ~until ~pending ch =
  if until = Some !lcnt then begin
    let state_opt =
      match pending with
      | None -> Some state
      | Some (line_no, raw, inds) ->
        let first = List.hd inds in
        process_effect state ch ~line_no ~raw ~name:first.name
          (fun () ->
            match inds with
            | [ ind ] -> add_entry (Ind ind)
            | _ -> add_mutual_entries inds)
    in
    match state_opt with
    | None -> state
    | Some state ->
      close_in ch;
      finish state;
      state
  end
  else
    match input_line ch with
    | exception End_of_file ->
      let state_opt =
        match pending with
        | None -> Some state
        | Some (line_no, raw, inds) ->
          let first = List.hd inds in
          process_effect state ch ~line_no ~raw ~name:first.name
            (fun () ->
              match inds with
              | [ ind ] -> add_entry (Ind ind)
              | _ -> add_mutual_entries inds)
      in
      (match state_opt with
      | None -> state
      | Some state ->
        close_in ch;
        finish state;
        if not (until = None) then
          CErrors.user_err Pp.(str "unexpected EOF!");
        state)
    | _ when before_from from ->
      incr lcnt;
      do_input_pending state ~from ~until ~pending ch
    | l ->
      let pstate, oentry = do_line state.pstate l in
      let state = { state with pstate } in
      (match (just_parse (), oentry) with
      | false, Some (Entry (Ind ind)) ->
        let pending =
          match pending with
          | None -> Some (!lcnt, l, [ ind ])
          | Some (line_no, raw, inds) ->
            Some (line_no, raw, inds @ [ ind ])
        in
        incr lcnt;
        do_input_pending state ~from ~until ~pending ch
      | _ ->
        let state_opt =
          match pending with
          | None -> Some state
          | Some (line_no, raw, inds) ->
            let first = List.hd inds in
            process_effect state ch ~line_no ~raw ~name:first.name
              (fun () ->
                match inds with
                | [ ind ] -> add_entry (Ind ind)
                | _ -> add_mutual_entries inds)
        in
        match state_opt with
        | None -> state
        | Some state ->
          let state_opt =
            match (just_parse (), oentry) with
            | true, _ | false, None | false, Some (Nota _) -> Some state
            | false, Some (Entry entry) ->
              process_effect state ch ~line_no:!lcnt ~raw:l
                ~name:(entry_name entry) (fun () -> add_entry entry)
          in
          match state_opt with
          | None -> state
          | Some state ->
            incr lcnt;
            do_input_pending state ~from ~until ~pending:None ch)

let do_input state ~from ~until ch =
  do_input_pending state ~from ~until ~pending:None ch

let pstate = Summary.ref ~name:"lean-parse-state" LeanParse.empty_state

let lean_obj =
  let cache
      ( pstatev,
        setsv,
        declaredv,
        entriesv,
        squash_infov,
        heightv,
        large_nat_literalv ) =
    pstate := pstatev;
    sets := setsv;
    declared := declaredv;
    entries := entriesv;
    squash_info := squash_infov;
    height_cache := heightv;
    large_nat_literal_cache := large_nat_literalv;
    ()
  in
  let open Libobject in
  declare_object
    {
      (default_object "LEAN-IMPORT-STATE") with
      cache_function = cache;
      load_function = (fun _ v -> cache v);
      classify_function = (fun _ -> Keep);
    }

let import ~from ~until f =
  lcnt := 1;
  (* silence the definition messages from Coq *)
  let { pstate = pstatev } =
    Flags.silently (fun () ->
        do_input { pstate = !pstate; skips = 0 } ~from ~until (open_in f)) ()
  in
  Lib.add_leaf
    (lean_obj
       ( pstatev,
         !sets,
         !declared,
         !entries,
         !squash_info,
         !height_cache,
         !large_nat_literal_cache ))
