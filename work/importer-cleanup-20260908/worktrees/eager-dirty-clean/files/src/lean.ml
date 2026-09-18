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

let quickdef ~name ~types ~univs body =
  let entry = Declare.definition_entry ?types ~univs body in
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

(** Rocq normally generates a [match] for a record eliminator.  When the
    scrutinee is neutral, reducing projections of the result can then force the
    scrutinee merely to expose its constructor.  This is especially harmful
    when the neutral term contains a large closed computation.

    Primitive records have judgmental eta in Rocq.  Their one-branch
    eliminator can therefore apply the branch to the primitive projections of
    the scrutinee instead.  We check that the replacement has the original
    generated scheme's type, so this optimization relies only on Rocq's kernel
    eta rule and is independent of any particular Lean declaration. *)
let project_primitive_record_scheme env (mind, ind_index) body =
  let mib = Global.lookup_mind mind in
  let packet = mib.mind_packets.(ind_index) in
  match packet.mind_record with
  | Declarations.PrimRecord _ ->
    let nb_lambdas = mib.mind_nparams + 3 in
    let binders, inside = Term.decompose_lambda_n_assum nb_lambdas body in
    (match Constr.kind inside with
    | Constr.Case (_, _, _, _, _, scrutinee, branches)
      when Constr.equal scrutinee (Constr.mkRel 1)
           && Array.length branches = 1 ->
      let target = Constr.mkRel 1 in
      let fields =
        List.init packet.mind_consnrealargs.(0) (fun proj_arg ->
            let projection, relevance =
              Declareops.inductive_make_projection (mind, ind_index) mib
                ~proj_arg
            in
            Constr.mkProj
              (Projection.make projection false, relevance, target))
      in
      let projected =
        Term.it_mkLambda_or_LetIn
          (Constr.mkApp (Constr.mkRel 2, Array.of_list fields))
          binders
      in
      let evd = Evd.from_env env in
      let type_of term =
        Retyping.get_type_of env evd (EConstr.of_constr term)
      in
      if Reductionops.is_conv env evd (type_of body) (type_of projected) then
        projected
      else
        CErrors.user_err
          Pp.(str "Projection-based primitive-record scheme changed type")
    | _ -> body)
  | _ -> body

(** Whether Rocq's induction-scheme generator will add a recursive hypothesis
    for an argument of type [term]. A mere occurrence of [mind] is not enough:
    for a nested occurrence, Rocq only adds the hypothesis when the enclosing
    inductive has a suitable [AllForall] scheme registered. *)
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
    let sigma, s' =
      match s with
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
        sigma, List.nth bodies ind_index
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
          (Level.Set.singleton Level.set) ind_levels
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
            if
              Level.Map.mem level subst
              || Level.Set.mem level allowed_levels
            then subst
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

  let body =
    if not hasrec then body
    else begin
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
    end
  in
  project_primitive_record_scheme env (mind, ind_index) body

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

(** Lean names whose translated definitions are non-forcing structural
    eliminators.  Rocq's conversion oracle should expose these before it tries
    to reduce their neutral arguments. *)
let expand_head_cache = Summary.ref ~name:"lean-expand-heads" N.Set.empty

let rec expands_at_head = function
  | Const (constant, _) -> N.Set.mem constant !expand_head_cache
  | App (function_, _) -> expands_at_head function_
  | Lam (_, _, _, body) -> expands_at_head body
  | Let { rest; _ } -> expands_at_head rest
  | Bound _ | Sort _ | Pi _ | Proj _ | Nat _ | String _ -> false

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

let get_predeclared_ind_suffixed indn suffix n i =
  if N.equal n (N.append_list N.anon indn) then
    let ind_name = name_for_core n i in
    let reg = "lean." ^ Id.to_string ind_name ^ suffix in
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

let ctor_first_field_head ctors =
  let open LeanExpr in
  match ctors with
  | [ (_, Pi (_, _, field_ty, _)) ] ->
    let rec head = function
      | App (f, _) -> head f
      | Const (n, _) -> Some n
      | _ -> None
    in
    head field_ty
  | _ -> None

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

type core_shape = Legacy | Modern

type predeclared_ind_kind =
  | Eq
  | False
  | Decidable
  | Bool
  | Nat
  | Int
  | Nat_le
  | Or
  | And
  | Fin
  | UInt32 of core_shape
  | BitVec
  | Char of core_shape
type predeclared_def_kind =
  | UInt32_size
  | Decidable_decide
  | Bool_and
  | Add
  | Mult
  | Pow
  | Pred
  | Sub
  | Beq
  | Ble
  | Blt
  | Nat_decEq
  | Nat_isValidChar
  | IsValidChar_UInt32
  | IsValidChar_UInt32_match_1_1
  | Char_ofNatAux
  | Char_ofNat
type predeclared_ind_as_def_kind = ULift_cumul

let get_predeclared_cnames (k : predeclared_ind_kind) n =
  match k with
  | Eq -> [ N.append n "refl" ]
  | False -> []
  | Decidable -> [ N.append n "isFalse"; N.append n "isTrue" ]
  | Bool -> [ N.append n "false"; N.append n "true" ]
  | Nat -> [ N.append n "zero"; N.append n "succ" ]
  | Int -> [ N.append n "ofNat"; N.append n "negSucc" ]
  | Nat_le -> [ N.append n "refl"; N.append n "step" ]
  | Or -> [ N.append n "inl"; N.append n "inr" ]
  | And -> [ N.append n "intro" ]
  | Fin -> [ N.append n "mk" ]
  | UInt32 Legacy -> [ N.append n "mk" ]
  | UInt32 Modern -> [ N.append n "ofBitVec" ]
  | BitVec -> [ N.append n "ofFin" ]
  | Char _ -> [ N.append n "mk" ]

let get_predeclared_ind_any ~ctors ~uint32_is_legacy n i =
  let uint32_shape =
    match ctor_first_field_head ctors with
    | Some head when N.equal head (N.append_list N.anon [ "Fin" ]) -> Legacy
    | _ -> Modern
  in
  let char_shape = if uint32_is_legacy then Legacy else Modern in
  let suffix = function
    | UInt32 Legacy | Char Legacy -> ".legacy"
    | _ -> ""
  in
  List.filter_map
    (fun (indk, indh) ->
      get_predeclared_ind_suffixed indh (suffix indk) n i
      |> Option.map (fun x -> (indk, indh, x)))
    [
      (Eq, [ "Eq" ]);
      (False, [ "False" ]);
      (Decidable, [ "Decidable" ]);
      (Bool, [ "Bool" ]);
      (Nat, [ "Nat" ]);
      (Int, [ "Int" ]);
      (Nat_le, [ "Nat"; "le" ]);
      (Or, [ "Or" ]);
      (And, [ "And" ]);
      (Fin, [ "Fin" ]);
      (UInt32 uint32_shape, [ "UInt32" ]);
      (BitVec, [ "BitVec" ]);
      (Char char_shape, [ "Char" ]);
    ]

let get_predeclared_ind_some ~ctors ~uint32_is_legacy n i =
  match get_predeclared_ind_any ~ctors ~uint32_is_legacy n i with
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
      (UInt32_size, [ "UInt32"; "size" ]);
      (Decidable_decide, [ "Decidable"; "decide" ]);
      (Bool_and, [ "Bool"; "and" ]);
      (Add, [ "Nat"; "add" ]);
      (Mult, [ "Nat"; "mul" ]);
      (Pow, [ "Nat" ; "pow" ]);
      (Pred, [ "Nat"; "pred" ]);
      (Sub, [ "Nat"; "sub" ]);
      (Beq, [ "Nat"; "beq" ]);
      (Ble, [ "Nat"; "ble" ]);
      (Blt, [ "Nat"; "blt" ]);
      (Nat_decEq, [ "Nat"; "decEq" ]);
      (Nat_isValidChar, [ "Nat"; "isValidChar" ]);
      ( IsValidChar_UInt32_match_1_1,
        [ "_private"; "Init"; "Prelude0"; "isValidChar_UInt32"; "match_1_1" ]
      );
      ( IsValidChar_UInt32,
        [ "_private"; "Init"; "Prelude0"; "isValidChar_UInt32" ] );
      (Char_ofNatAux, [ "Char"; "ofNatAux" ]);
      (Char_ofNat, [ "Char"; "ofNat" ]);
    ]

let get_predeclared_def_some n i =
  match get_predeclared_def_any n i with
  | [] -> None
  | [ x ] -> Some x
  | _ :: _ :: _ ->
    CErrors.user_err Pp.(str "Multiple predeclared constants for " ++ N.pp n)

(* let get_predeclared_eq n i = get_predeclared_ind "eq" n i *)
let mk_char_prim = "Char.mk.reflective_prim"
let mk_char_prim_legacy = "Char.legacy.mk.reflective_prim"

(*
Register Nat_isValidChar as lean.Nat_isValidChar.
Register reflective_Char_mk_prim as lean.Char.mk.reflective_prim. *)
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

type projection_alias = {
  projection_inst : instantiation;
  projection_record : N.t;
  projection_ind : Names.inductive;
  projection_field : int;
}

let projection_aliases : projection_alias Int.Map.t N.Map.t ref =
  Summary.ref ~name:"lean-projection-aliases" N.Map.empty

let add_projection_alias name instance alias =
  projection_aliases :=
    N.Map.update name
      (function
        | None -> Some (Int.Map.singleton instance alias)
        | Some aliases -> Some (Int.Map.add instance alias aliases))
      !projection_aliases

let find_projection_alias name instance =
  Option.bind (N.Map.find_opt name !projection_aliases) (fun aliases ->
      Int.Map.find_opt instance aliases)

let find_projection_alias_for_universes uconv name universes =
  let sorts = List.map (to_universe uconv.map) universes in
  let instance, _ = int_of_univs sorts in
  find_projection_alias name instance

let rec is_projection_wrapper record field = function
  | Lam (_, _, _, body) -> is_projection_wrapper record field body
  | Proj (projected_record, projected_field, Bound 0) ->
    N.equal record projected_record && Int.equal field projected_field
  | _ -> false

let add_declared n i inst =
  declared :=
    N.Map.update n
      (function
        | None -> Some (Int.Map.singleton i inst)
        | Some m -> Some (Int.Map.add i inst m))
      !declared

let declared_as n i registration =
  match N.Map.find_opt n !declared with
  | None -> false
  | Some instances -> (
    match Int.Map.find_opt i instances with
    | None -> false
    | Some { ref; _ } ->
      GlobRef.CanOrd.equal ref (Rocqlib.lib_ref registration))

let lookup_char_prim_ref () =
  let char = N.append N.anon "Char" in
  let prim =
    if declared_as char 0 "lean.Char.legacy" then mk_char_prim_legacy
    else mk_char_prim
  in
  Rocqlib.lib_ref ("lean." ^ prim)

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

let registered_ref key =
  Constr.mkRef (Rocqlib.lib_ref key, UVars.Instance.empty)

let rec positive_int i =
  assert (Z.lt Z.zero i);
  if Z.equal i Z.one then registered_ref "num.pos.xH"
  else
    let constructor =
      if Z.equal (Z.rem i (Z.of_int 2)) Z.zero then "num.pos.xO"
      else "num.pos.xI"
    in
    Constr.mkApp
      (registered_ref constructor, [| positive_int (Z.div i (Z.of_int 2)) |])

let n_int i =
  assert (Z.leq Z.zero i);
  if Z.equal i Z.zero then registered_ref "num.N.N0"
  else
    Constr.mkApp (registered_ref "num.N.Npos", [| positive_int i |])

let z_int i =
  if Z.equal i Z.zero then registered_ref "num.Z.Z0"
  else if Z.gt i Z.zero then
    Constr.mkApp (registered_ref "num.Z.Zpos", [| positive_int i |])
  else
    Constr.mkApp
      (registered_ref "num.Z.Zneg", [| positive_int (Z.neg i) |])

let nat_int nat nat_of_n i =
  assert (Z.leq Z.zero i);
  if Z.leq max_nat_int i then Constr.mkApp (nat_of_n, [| n_int i |])
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

let mk_string char list char_uinst mkChar string_of_chars s =
  let codepoints =
    try check_valid_codepoints (string_to_codepoints s)
    with Failure msg as exn ->
      let _, info = Exninfo.capture exn in
      CErrors.user_err ~info Pp.(str msg)
  in
  let chars = List.map (mk_char mkChar) codepoints in
  let ls = mk_list list char_uinst char chars in
  Constr.mkApp (string_of_chars, [| ls |])

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

let lcnt = ref 0

let line_msg name =
  Feedback.msg_info Pp.(str "line " ++ int !lcnt ++ str ": " ++ N.pp name)

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

let qsort q u = Constr.mkSort (Sorts.make q u)

let reln n = Constr.mkRel n

let app f args = Constr.mkApp (f, Array.of_list args)

let annot_for_type env name ty =
  let evd = Evd.from_env env in
  let relevance =
    Retyping.relevance_of_type env evd (EConstr.of_constr ty)
    |> EConstr.Unsafe.to_relevance
  in
  Context.make_annot name relevance

let push_typed_assum env name ty =
  Environ.push_rel
    (RelDecl.LocalAssum (annot_for_type env name ty, ty))
    env

let typed_prod env name ty body =
  Constr.mkProd (annot_for_type env name ty, ty, body)

let rec typed_lambdas env binders body =
  match binders with
  | [] -> body
  | (name, ty) :: rest ->
    let annot = annot_for_type env name ty in
    let env = Environ.push_rel (RelDecl.LocalAssum (annot, ty)) env in
    Constr.mkLambda (annot, ty, typed_lambdas env rest body)

let mk_global_ref ref inst = Constr.mkRef (ref, inst)

let all_name ind_name = Id.of_string (Id.to_string ind_name ^ "_all")
let all_forall_name ind_name =
  Id.of_string (Id.to_string ind_name ^ "_all_forall")

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
        let scheme_env = Environ.push_context all_uctx (Global.env ()) in
        let a_name = Name (Id.of_string "A") in
        let p_name = Name (Id.of_string "P") in
        let x_name = Name (Id.of_string "x") in
        let value_name = Name (Id.of_string "a") in
        let env_a = push_typed_assum scheme_env a_name a_ty in
        let motive_ty = typed_prod env_a x_name (reln 1) motive_sort in
        let env_ap = push_typed_assum env_a p_name motive_ty in
        let forall_ty =
          typed_prod env_ap x_name (reln 2) (app (reln 2) [ reln 1 ])
        in
        let all_body =
          let body = app list_all [ reln 3; reln 2; proj_a 3 1 ] in
          typed_lambdas scheme_env
            [ (a_name, a_ty); (p_name, motive_ty); (value_name, array_a 2) ]
            body
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
          typed_lambdas scheme_env
            [
              (a_name, a_ty);
              (p_name, motive_ty);
              (Name (Id.of_string "h"), forall_ty);
              (value_name, array_a 3);
            ]
            body
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
    let scheme_env = Environ.push_context all_uctx (Global.env ()) in
    let a_name = Name (Id.of_string "A") in
    let b_name = Name (Id.of_string "B") in
    let p_name = Name (Id.of_string "P") in
    let x_name = Name (Id.of_string "x") in
    let value_name = Name (Id.of_string "p") in
    let env_a = push_typed_assum scheme_env a_name a_ty in
    let env_ab = push_typed_assum env_a b_name b_ty in
    let motive_ty =
      typed_prod env_ab x_name (reln 1) motive_sort
    in
    let env_abp = push_typed_assum env_ab p_name motive_ty in
    let forall_ty =
      typed_prod env_abp x_name (reln 2) (app (reln 2) [ reln 1 ])
    in
    let prod_ab rel_a rel_b = app prod_ref [ reln rel_a; reln rel_b ] in
    let snd_abp rel_a rel_b rel_p =
      app snd_ref [ reln rel_a; reln rel_b; reln rel_p ]
    in
    let all_body =
      typed_lambdas scheme_env
        [
          (a_name, a_ty);
          (b_name, b_ty);
          (p_name, motive_ty);
          (value_name, prod_ab 3 2);
        ]
        (app (reln 2) [ snd_abp 4 3 1 ])
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
      typed_lambdas scheme_env
        [
          (a_name, a_ty);
          (b_name, b_ty);
          (p_name, motive_ty);
          (Name (Id.of_string "h"), forall_ty);
          (value_name, prod_ab 4 3);
        ]
        (app (reln 2) [ snd_abp 5 4 1 ])
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

let last_projection_returns_only_parameter mind source_uctx projections =
  match
    ((Global.lookup_mind mind).mind_params_ctxt, List.rev projections)
  with
  | ( [ RelDecl.LocalAssum _ ],
      { Structures.Structure.proj_body = Some field_c; _ } :: _ ) ->
    let env = Environ.push_context source_uctx (Global.env ()) in
    let evd = Evd.from_env env in
    let field_ref = Constr.mkConstU (field_c, UContext.instance source_uctx) in
    let field_ty =
      EConstr.Unsafe.to_constr
        (Retyping.get_type_of env evd (EConstr.of_constr field_ref))
    in
    let whd env term =
      EConstr.Unsafe.to_constr
        (Reductionops.whd_all env evd (EConstr.of_constr term))
    in
    (match Constr.kind (whd env field_ty) with
    | Constr.Prod (param_annot, param_ty, body) ->
      let env =
        Environ.push_rel (RelDecl.LocalAssum (param_annot, param_ty)) env
      in
      (match Constr.kind (whd env body) with
      | Constr.Prod (value_annot, value_ty, result_ty) ->
        let env =
          Environ.push_rel
            (RelDecl.LocalAssum (value_annot, value_ty))
            env
        in
        Reductionops.is_conv env evd
          (EConstr.of_constr result_ty)
          (EConstr.of_constr (Constr.mkRel 2))
      | _ -> false)
    | _ -> false)
  | _ -> false

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
      let scheme_env = Environ.push_context all_uctx (Global.env ()) in
      let a_name = a_na.Context.binder_name in
      let p_name = Name (Id.of_string "P") in
      let x_name = Name (Id.of_string "x") in
      let value_name = Name (Id.of_string "value") in
      let env_a = push_typed_assum scheme_env a_name a_ty in
      let motive_ty =
        typed_prod env_a x_name (reln 1) motive_sort
      in
      let env_ap = push_typed_assum env_a p_name motive_ty in
      let forall_ty =
        typed_prod env_ap x_name (reln 2) (app (reln 2) [ reln 1 ])
      in
      let ind_a rel_a = app ind_ref [ reln rel_a ] in
      let field_ap rel_a rel_p = app field_ref [ reln rel_a; reln rel_p ] in
      let all_body =
        typed_lambdas scheme_env
          [ (a_name, a_ty); (p_name, motive_ty); (value_name, ind_a 2) ]
          (app (reln 2) [ field_ap 3 1 ])
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
        typed_lambdas scheme_env
          [
            (a_name, a_ty);
            (p_name, motive_ty);
            (Name (Id.of_string "h"), forall_ty);
            (value_name, ind_a 3);
          ]
          (app (reln 2) [ field_ap 4 1 ])
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

let eager_reduce_name = N.append N.anon "eagerReduce"
let rfl_name = N.append N.anon "rfl"

let is_eager_reduce_application expression =
  match fst (decompose_lean_app [] expression) with
  | Const (name, _) -> N.equal name eager_reduce_name
  | _ -> false

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

let prod_after_apply env evd ty arg =
  match Constr.kind (whd_constr env evd ty) with
  | Prod (_, _, body) -> Vars.subst1 arg body
  | _ -> CErrors.user_err Pp.(str "Nested recursor is over-applied")

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

let rec fold_mutual_nested env evd ~depth ~folded_leaves mind specs target
    proof =
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
        fold_mutual_nested env evd ~depth ~folded_leaves mind specs list
          proof
      in
      (match cases with
      | [ array_case ] -> constr_app array_case [ list; folded ]
      | _ -> CErrors.user_err Pp.(str "Nested Array has unexpected cases"))
    else if mind_is_one_of target_mind !prod_minds then
      let fst, snd = prod_parts env evd target in
      let folded =
        fold_mutual_nested env evd ~depth ~folded_leaves mind specs snd proof
      in
      (match cases with
      | [ prod_case ] -> constr_app prod_case [ fst; snd; folded ]
      | _ -> CErrors.user_err Pp.(str "Nested Prod has unexpected cases"))
    else if mind_is_one_of target_mind !list_minds then
      fold_mutual_list env evd ~depth ~folded_leaves mind specs motive cases
        target proof
    else if mind_is_one_of target_mind !option_minds then
      fold_mutual_option env evd ~depth ~folded_leaves mind specs motive cases
        target proof
    else
      let target_mib = Global.lookup_mind target_mind in
      let packet = target_mib.mind_packets.(target_index) in
      (match (packet.mind_record, cases) with
      | Declarations.PrimRecord _, [ _ ] when folded_leaves -> proof
      | Declarations.PrimRecord _, [ record_case ] ->
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

and fold_mutual_option env evd ~depth ~folded_leaves mind specs motive cases
    target proof =
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
      fold_mutual_nested env_p_head evd ~depth:(depth + 2) ~folded_leaves
        mind specs (mkRel 2) (mkRel 1)
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

and fold_mutual_list env evd ~depth ~folded_leaves mind specs motive cases
    target proof =
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
      fold_mutual_nested env_all_tail evd ~depth:(depth + 4) ~folded_leaves
        mind specs (mkRel 4) (mkRel 3)
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
    fold_mutual_nested env evd ~depth:0 ~folded_leaves:true info.mind specs
      target all_term
  | Some ((target_mind, _), _, target_args)
    when mind_is_one_of target_mind !list_minds ->
    let predicate, proof =
      mutual_element_functions env evd ~depth:0 info.mind specs main_motives
        main_recs target_args.(Array.length target_args - 1)
    in
    let all_term =
      container_all_forall env evd (List.hd recursors) predicate proof target
    in
    fold_mutual_nested env evd ~depth:0 ~folded_leaves:true info.mind specs
      target all_term
  | Some ((target_mind, _), _, target_args)
    when mind_is_one_of target_mind !option_minds ->
    let predicate, proof =
      mutual_element_functions env evd ~depth:0 info.mind specs main_motives
        main_recs target_args.(Array.length target_args - 1)
    in
    let all_term =
      container_all_forall env evd (List.hd recursors) predicate proof target
    in
    fold_mutual_nested env evd ~depth:0 ~folded_leaves:true info.mind specs
      target all_term
  | Some ((target_mind, _), _, _)
    when mind_is_one_of target_mind !prod_minds ->
    let _, proof =
      mutual_nested_leaf env evd ~depth:0 info.mind specs main_motives
        main_recs target
    in
    fold_mutual_nested env evd ~depth:0 ~folded_leaves:true info.mind specs
      target proof
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
              fold_mutual_nested env' evd ~depth:(depth + 1)
                ~folded_leaves:false mind specs target (mkRel 1)
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

(** Proof-producing reflection for closed natural-number arithmetic.

    This deliberately does not add a reduction rule to Rocq.  [reify_nat]
    evaluates a small, generic arithmetic language with Zarith and constructs
    a proof of [NatCertificate] in parallel.  The proof is later consumed by
    [NatCertificate_equal] and [Nat_transport_sprop], so the value computed by
    OCaml is checked independently by the Rocq kernel. *)
type nat_certificate = {
  nat_term : Constr.t;
  nat_value : Z.t;
  nat_proof : Constr.t;
}

type int_certificate = {
  int_term : Constr.t;
  int_value : Z.t;
  int_proof : Constr.t;
}

let ref_matches env term key =
  try
    let gr, _ = Constr.destRef term in
    Environ.QGlobRef.equal env gr (Rocqlib.lib_ref key)
  with Constr.DestKO -> false

let nat_constructor_matches env term index =
  match Rocqlib.lib_ref "lean.Nat", Constr.kind term with
  | GlobRef.IndRef ind, Construct ((constructor_ind, constructor_index), _) ->
    index = constructor_index && Environ.QInd.equal env ind constructor_ind
  | _ -> false

let int_constructor_matches env term index =
  match Rocqlib.lib_ref "lean.Int", Constr.kind term with
  | GlobRef.IndRef ind, Construct ((constructor_ind, constructor_index), _) ->
    index = constructor_index && Environ.QInd.equal env ind constructor_ind
  | _ -> false

let cert_app key args = Constr.mkApp (registered_ref key, Array.of_list args)

let rec z_of_positive env evd term =
  let head, args = Constr.decompose_app term in
  if ref_matches env head "num.pos.xH" && Array.length args = 0 then Some Z.one
  else if ref_matches env head "num.pos.xO" && Array.length args = 1 then
    Option.map
      (fun n -> Z.mul (Z.of_int 2) n)
      (z_of_positive env evd args.(0))
  else if ref_matches env head "num.pos.xI" && Array.length args = 1 then
    Option.map
      (fun n -> Z.succ (Z.mul (Z.of_int 2) n))
      (z_of_positive env evd args.(0))
  else
    let reduced =
      Reductionops.whd_all env evd (EConstr.of_constr term)
      |> EConstr.Unsafe.to_constr
    in
    if Constr.equal reduced term then None
    else z_of_positive env evd reduced

let rec z_of_n env evd term =
  let head, args = Constr.decompose_app term in
  if ref_matches env head "num.N.N0" && Array.length args = 0 then Some Z.zero
  else if ref_matches env head "num.N.Npos" && Array.length args = 1 then
    z_of_positive env evd args.(0)
  else
    let reduced =
      Reductionops.whd_all env evd (EConstr.of_constr term)
      |> EConstr.Unsafe.to_constr
    in
    if Constr.equal reduced term then None else z_of_n env evd reduced

let beta_apply head args =
  let rec apply head index =
    if index = Array.length args then head
    else
      match Constr.kind head with
      | Lambda (_, _, body) -> apply (Vars.subst1 args.(index) body) (index + 1)
      | LetIn (_, value, _, body) -> apply (Vars.subst1 value body) index
      | _ ->
        Constr.mkApp
          (head, Array.sub args index (Array.length args - index))
  in
  apply head 0

(** Give record-valued definitions an eta-long outer shape.  Conversion can
    then expose the constructor without evaluating the definition's result;
    its fields remain ordinary, independently checked projections of the
    original body.  This is judgmentally equal to [body] for primitive records
    and does not evaluate or trust the imported computation. *)
let eta_expand_primitive_record_definition env evd ty body =
  let binders, result = Term.decompose_lambda body in
  let type_binders, result_ty = Term.decompose_prod ty in
  if List.length binders <> List.length type_binders then body
  else
    let rel_context =
      List.map
        (fun (annot, binder_ty) -> RelDecl.LocalAssum (annot, binder_ty))
        binders
    in
    let result_env = Environ.push_rel_context rel_context env in
    let reduced_ty =
      Reductionops.whd_all result_env evd (EConstr.of_constr result_ty)
      |> EConstr.Unsafe.to_constr
    in
    let head, args = Constr.decompose_app reduced_ty in
    match Constr.kind head with
    | Constr.Ind (ind, instance) ->
      let mib = Global.lookup_mind (fst ind) in
      let packet = mib.mind_packets.(snd ind) in
      (match packet.mind_record with
      | Declarations.PrimRecord _ ->
        let nparams = mib.mind_nparams in
        let nfields = packet.mind_consnrealargs.(0) in
        if Array.length args < nparams || nfields = 0 then body
        else
          let result_head, _ = Constr.decompose_app result in
          (match Constr.kind result_head with
          | Constr.Construct ((result_ind, 1), _)
            when Names.Ind.UserOrd.equal result_ind ind -> body
          | _ ->
            let target = Constr.mkRel 1 in
            let parameters =
              Array.sub args 0 nparams |> Array.map (Vars.lift 1)
            in
            let fields =
              Array.init nfields (fun proj_arg ->
                  let projection, relevance =
                    Declareops.inductive_make_projection ind mib ~proj_arg
                  in
                  Constr.mkProj
                    (Projection.make projection false, relevance, target))
            in
            let rebuilt =
              Constr.mkApp
                ( Constr.mkConstructU ((ind, 1), instance),
                  Array.append parameters fields )
            in
            let relevance =
              Retyping.relevance_of_type result_env evd
                (EConstr.of_constr result_ty)
              |> EConstr.Unsafe.to_relevance
            in
            let annot = Context.make_annot Anonymous relevance in
            Term.compose_lam binders
              (Constr.mkLetIn (annot, result, result_ty, rebuilt)))
      | _ -> body)
    | _ -> body

let unfold_head_once env term =
  let head, args = Constr.decompose_app term in
  match Constr.kind head with
  | Const (constant, instance) -> (
    try beta_apply (Environ.constant_value_in env (constant, instance)) args
    with Environ.NotEvaluableConst _ -> term)
  | Lambda _ | LetIn _ -> beta_apply head args
  | _ -> term

let expose_iota_scrutinee env evd term =
  let head, args = Constr.decompose_app term in
  let expose_scrutinee scrutinee =
    unfold_head_once env scrutinee |> EConstr.of_constr
    |> Reductionops.whd_betaiotazeta env evd |> EConstr.Unsafe.to_constr
  in
  let expose head =
    match Constr.kind head with
    | Case (info, instance, params, return, invert, scrutinee, branches) ->
      let scrutinee = expose_scrutinee scrutinee in
      Constr.mkCase
        (info, instance, params, return, invert, scrutinee, branches)
    | Proj (projection, relevance, scrutinee) ->
      let scrutinee = expose_scrutinee scrutinee in
      let constructor, constructor_args = Constr.decompose_app scrutinee in
      (match Constr.kind constructor with
      | Construct _ ->
        constructor_args.(Projection.npars projection + Projection.arg projection)
      | _ -> Constr.mkProj (projection, relevance, scrutinee))
    | _ -> head
  in
  let exposed = expose head in
  if Array.length args = 0 then exposed else Constr.mkApp (exposed, args)

(** Contract the eta-long form generated for a primitive record back to its
    source.  Imported compatibility projections often have the shape
    [fun x => Record.mk (Record.field x)]; keeping that shell can make Rocq
    unfold arithmetic hidden in [x] merely to use record eta. *)
let contract_primitive_record_eta env evd term =
  let term =
    EConstr.of_constr term |> Reductionops.whd_betaiotazeta env evd
    |> EConstr.Unsafe.to_constr
  in
  let constructor, arguments = Constr.decompose_app term in
  match Constr.kind constructor with
  | Construct ((inductive, 1), _) ->
    let mib = Global.lookup_mind (fst inductive) in
    let packet = mib.mind_packets.(snd inductive) in
    (match packet.mind_record with
    | Declarations.PrimRecord _ ->
      let nparams = mib.mind_nparams in
      let nfields = packet.mind_consnrealargs.(0) in
      if Array.length arguments <> nparams + nfields || nfields = 0 then None
      else
        let source = ref None in
        let valid = ref true in
        for field = 0 to nfields - 1 do
          let projection_term = arguments.(nparams + field) in
          match Constr.kind projection_term with
          | Proj (projection, _, target)
            when Names.Ind.UserOrd.equal
                   (Projection.inductive projection) inductive
                 && Projection.npars projection = nparams
                 && Projection.arg projection = field ->
            (match !source with
            | None -> source := Some target
            | Some previous when Constr.equal previous target -> ()
            | Some _ -> valid := false)
          | _ -> valid := false
        done;
        if !valid then !source else None
    | _ -> None)
  | _ -> None

(** Constants registered for primitive projections are accepted by Rocq as
    surface aliases, but their bodies are not unfoldable.  Reconstruct the
    kernel [Proj] node so that iota reduction can inspect a constructor-valued
    scrutinee without unfolding unrelated definitions. *)
let expose_primitive_projection_constant term =
  let head, arguments = Constr.decompose_app term in
  match Constr.kind head with
  | Const (constant, _) -> (
    match Structures.PrimitiveProjections.find_opt constant with
    | Some representation ->
      let nparams = Projection.Repr.npars representation in
      if Array.length arguments <= nparams then term
      else
        let inductive = Projection.Repr.inductive representation in
        let mib = Global.lookup_mind (fst inductive) in
        let projection, relevance =
          Declareops.inductive_make_projection inductive mib
            ~proj_arg:(Projection.Repr.arg representation)
        in
        let projected =
          Constr.mkProj
            ( Projection.make projection false,
              relevance,
              arguments.(nparams) )
        in
        let extra_count = Array.length arguments - nparams - 1 in
        if extra_count = 0 then projected
        else
          Constr.mkApp
            (projected, Array.sub arguments (nparams + 1) extra_count)
    | None -> term)
  | _ -> term

(** Primitive-projection registrations are persistent Rocq library objects,
    whereas the importer's Lean-name alias table is only an optimization for
    the current import command.  Canonicalizing a registered projection at
    each newly built application therefore also handles projections restored
    from a required [.vo], without inspecting any definition body or walking
    the projection scrutinee. *)
let expose_registered_primitive_projection_application term =
  let head, _ = Constr.decompose_app term in
  match Constr.kind head with
  | Const (constant, _)
    when Structures.PrimitiveProjections.mem constant ->
    expose_primitive_projection_constant term
  | _ -> term

(** Recognize compatibility functions that are only compositions of record
    projections (possibly through eta-long record wrappers).  In particular,
    the scrutinee of every projection must itself be wrapper-only; this keeps
    computational definitions such as [Nat.mod] and [Nat.shiftLeft] out even
    when their final implementation happens to select a product field. *)
let projection_wrapper_constant_cache =
  Summary.ref ~name:"lean-projection-wrapper-constants" Cmap_env.empty

let compute_projection_wrapper_constant env evd constant instance =
  let rec safe_constant fuel constant instance =
    if fuel = 0 then false
    else
      try
        let body = Environ.constant_value_in env (constant, instance) in
        let _, body = Term.decompose_lambda body in
        let body =
          EConstr.of_constr body |> Reductionops.whd_betaiotazeta env evd
          |> EConstr.Unsafe.to_constr
        in
        let body =
          match contract_primitive_record_eta env evd body with
          | Some contracted -> contracted
          | None -> body
        in
        safe_expression (fuel - 1) body
      with Environ.NotEvaluableConst _ -> false
  and safe_expression fuel term =
    if fuel = 0 then false
    else
      let head, arguments = Constr.decompose_app term in
      match Constr.kind head with
      | Rel _ -> Array.length arguments = 0
      | Proj (_, _, scrutinee) -> safe_expression (fuel - 1) scrutinee
      | Const (constant, instance) -> (
        match Structures.PrimitiveProjections.find_opt constant with
        | Some projection ->
          let target = Projection.Repr.npars projection in
          target < Array.length arguments
          && safe_expression (fuel - 1) arguments.(target)
        | None -> safe_constant (fuel - 1) constant instance)
      | LetIn (_, value, _, body) ->
        safe_expression (fuel - 1) (Vars.subst1 value body)
      | _ -> false
  in
  safe_constant 12 constant instance

let is_projection_wrapper_constant env evd constant instance =
  match Cmap_env.find_opt constant !projection_wrapper_constant_cache with
  | Some result -> result
  | None ->
    let result =
      compute_projection_wrapper_constant env evd constant instance
    in
    projection_wrapper_constant_cache :=
      Cmap_env.add constant result !projection_wrapper_constant_cache;
    result

(** A projection is safe to contract only when exposing its scrutinee cannot
    start an unrelated computation.  In particular, a projection applied to a
    recursive function is not an elaboration wrapper merely because it will
    eventually return a record. *)
let rec is_structural_projection_scrutinee env evd fuel term =
  if fuel = 0 then false
  else
    let head, _ = Constr.decompose_app term in
    match Constr.kind head with
    | Construct _ -> true
    | Proj (_, _, scrutinee) ->
      is_structural_projection_scrutinee env evd (fuel - 1) scrutinee
    | Const (constant, instance) ->
      Structures.PrimitiveProjections.mem constant
      || is_projection_wrapper_constant env evd constant instance
      ||
      (* A closed typeclass instance, or an instance factory after its
         parameters have been supplied, commonly unfolds immediately to the
         record constructor.  Looking through that single delta/beta shell is
         structural: unlike weak-head reduction, it cannot start a recursive
         computation or select a branch.  This lets projection iota expose
         the selected operation without evaluating the operation itself. *)
      let exposed = unfold_head_once env term in
      not (Constr.equal exposed term)
      &&
      let exposed_head, _ = Constr.decompose_app exposed in
      (match Constr.kind exposed_head with
      | Construct _ -> true
      | Const _ | Proj _ ->
        is_structural_projection_scrutinee env evd (fuel - 1) exposed
      | _ -> false)
    | _ -> false

(** Resolve primitive-record projections and the immediate aliases selected by
    them without evaluating the operation itself.  This removes elaboration
    shells such as typeclass field access while retaining judgmental equality
    and computational behavior. *)
let canonicalize_projection_wrapper env evd term =
  let head, _ = Constr.decompose_app term in
  let is_wrapper_candidate =
    match Constr.kind head with
    | Const (constant, instance) ->
      Structures.PrimitiveProjections.mem constant
      || is_projection_wrapper_constant env evd constant instance
    | Proj _ | Lambda _ | LetIn _ -> true
    | _ -> false
  in
  if not is_wrapper_candidate then term
  else
    let rec expose fuel term =
      if fuel = 0 then term
      else
        let head, _ = Constr.decompose_app term in
        match Constr.kind head with
        | Const (constant, instance) ->
          let primitive_projection =
            Structures.PrimitiveProjections.mem constant
          in
          let projection_wrapper =
            is_projection_wrapper_constant env evd constant instance
          in
          let reduced =
            if primitive_projection then
              expose_primitive_projection_constant term
            else unfold_head_once env term
          in
          let reduced =
            if primitive_projection then reduced
            else
              EConstr.of_constr reduced
              |> Reductionops.whd_betaiotazeta env evd
              |> EConstr.Unsafe.to_constr
          in
          let reduced =
            if primitive_projection then reduced
            else
              match contract_primitive_record_eta env evd reduced with
              | Some contracted -> contracted
              | None -> reduced
          in
          let reduced_head, _ = Constr.decompose_app reduced in
          let reduced_starts_with_projection =
            match Constr.kind reduced_head with
            | Proj _ -> true
            | Const (next, _) -> Structures.PrimitiveProjections.mem next
            | _ -> false
          in
          if
            Constr.equal reduced term
            ||
            (not primitive_projection
            && not projection_wrapper
            && not reduced_starts_with_projection)
          then term
          else expose (fuel - 1) reduced
        | Proj (_, _, scrutinee)
          when is_structural_projection_scrutinee env evd 12 scrutinee ->
          let reduced = expose_iota_scrutinee env evd term in
          let reduced =
            if Constr.equal reduced term then reduced
            else
              let reduced_head, _ = Constr.decompose_app reduced in
              match Constr.kind reduced_head with
              | Lambda _ | LetIn _ ->
                EConstr.of_constr reduced
                |> Reductionops.whd_betaiotazeta env evd
                |> EConstr.Unsafe.to_constr
              | _ -> reduced
          in
          if Constr.equal reduced term then term else expose (fuel - 1) reduced
        | Proj _ | Lambda _ | LetIn _ -> term
        | _ -> term
    in
    let result = expose 16 term in
    let () =
      if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_WRAPPER_DEBUG") then
        Feedback.msg_info
          Pp.(
            str "wrapper before:" ++ fnl ()
            ++ Printer.pr_constr_env env evd term ++ fnl ()
            ++ str "wrapper after:" ++ fnl ()
            ++ Printer.pr_constr_env env evd result)
    in
    result

(** Apply wrapper canonicalization to natural-number parameters.  Lean
    elaborates notation such as [2 ^ 32] through typeclass projections, while
    Rocq-side predeclarations use [Nat_pow] directly.  Leaving the wrapper in
    an inductive parameter makes conversion evaluate the closed arithmetic;
    inserting a propositional cast instead would break later Lean [rfl]
    proofs. *)
let canonicalize_nat_constructor_parameter env evd term =
  let head, _ = Constr.decompose_app term in
  let is_wrapper_candidate =
    match Constr.kind head with
    | Const (constant, instance) ->
      Structures.PrimitiveProjections.mem constant
      || is_projection_wrapper_constant env evd constant instance
    | Proj _ -> true
    | _ -> false
  in
  if not is_wrapper_candidate then term
  else
    let is_nat =
      try
        let ty =
          Retyping.get_type_of env evd (EConstr.of_constr term)
          |> Reductionops.whd_betaiotazeta env evd
          |> EConstr.Unsafe.to_constr
        in
        ref_matches env (fst (Constr.decompose_app ty)) "lean.Nat"
      with _ -> false
    in
    if is_nat then canonicalize_projection_wrapper env evd term else term

(** Put the outer shell of a proof type in weak-head form without reducing
    arithmetic in its arguments.  This turns elaboration layers such as
    [LT.lt ...] into the underlying relation, allowing the certificate pass to
    identify and transport just the closed Nat subexpression. *)
let expose_sprop_type_head ?(allow_alias = false) env evd term =
  let rec expose fuel allow_alias term =
    if fuel = 0 then term
    else
      let head, _ = Constr.decompose_app term in
      let reduced, allow_alias =
        match Constr.kind head with
        | Const (constant, _)
          when allow_alias
               || Structures.PrimitiveProjections.mem constant
               || ref_matches env head "lean.Nat_isValidChar" ->
          ( unfold_head_once env term,
            Structures.PrimitiveProjections.mem constant )
        | Proj _ -> (expose_iota_scrutinee env evd term, true)
        | Lambda _ | LetIn _ ->
          ( EConstr.of_constr term
            |> Reductionops.whd_betaiotazeta env evd
            |> EConstr.Unsafe.to_constr,
            allow_alias )
        | _ -> (term, false)
      in
      let reduced =
        EConstr.of_constr reduced
        |> Reductionops.whd_betaiotazeta env evd
        |> EConstr.Unsafe.to_constr
      in
      if Constr.equal reduced term then term
      else expose (fuel - 1) allow_alias reduced
  in
  expose 8 allow_alias term

let is_sprop_type_expression env evd term =
  try
    let sort =
      Retyping.get_type_of env evd (EConstr.of_constr term)
      |> Reductionops.whd_betaiotazeta env evd
      |> EConstr.Unsafe.to_constr
    in
    match Constr.kind sort with
    | Sort sort -> Sorts.is_sprop sort
    | _ -> false
  with _ -> false

let canonicalize_sprop_type_wrapper_node env evd term =
  let head, _ = Constr.decompose_app term in
  match Constr.kind head with
  | Const (constant, _)
    when ref_matches env head "lean.Nat_isValidChar" ->
    expose_sprop_type_head env evd term
  | Const (constant, instance)
    when Structures.PrimitiveProjections.mem constant
         || is_projection_wrapper_constant env evd constant instance ->
    let rewritten = canonicalize_projection_wrapper env evd term in
    (* Once a projection has selected an SProp-valued operation, expose one
       immediate relation alias as well.  For example [LT.lt instLTNat]
       selects [Nat.lt], whose body is [fun n m => Nat.succ n <= m].  The
       SProp guard is essential: a data-valued field such as [Pow.pow] must
       remain opaque here, or canonicalization itself would start evaluating
       the arithmetic it is meant only to reveal. *)
    if
      not (Constr.equal rewritten term)
      && is_sprop_type_expression env evd rewritten
    then expose_sprop_type_head ~allow_alias:true env evd rewritten
    else rewritten
  | Proj _ | Lambda _ | LetIn _ ->
    canonicalize_projection_wrapper env evd term
  | _ -> term

(** Canonicalize only the newly built root of a translated expression.
    Translation is bottom-up, so doing this once at each application node
    gives the same canonical form as a later whole-term traversal without
    repeatedly rescanning already completed proof lambdas. *)
let normalize_sprop_type_wrapper_root env evd term =
  let rec normalize fuel term =
    if fuel = 0 then term
    else
      let rewritten = canonicalize_sprop_type_wrapper_node env evd term in
      if Constr.equal rewritten term then term
      else normalize (fuel - 1) rewritten
  in
  normalize 16 term

let normalize_sprop_type_wrappers env evd term =
  let rec normalize depth term =
    if depth = 128 then term
    else
      let rewritten = normalize_sprop_type_wrapper_root env evd term in
      if Constr.equal rewritten term then
        let mapped = Constr.map (normalize (depth + 1)) term in
        if Constr.equal mapped term then term
        else normalize (depth + 1) mapped
      else normalize (depth + 1) rewritten
  in
  normalize 0 term

(** Canonicalize a wrapper-valued function without traversing an arbitrary
    completed argument.  Function arguments introduced by elaboration often
    have the form [fun x => HAdd.hAdd ... x 0]; following only their leading
    binder spine exposes the wrapper at the body root.  In contrast, a proof
    lambda whose body is a large application is returned immediately. *)
let rec normalize_relevant_wrapper_spine env evd term =
  match Constr.kind term with
  | Lambda (annot, domain, body) ->
    let original_body = body in
    let local_env =
      Environ.push_rel (RelDecl.LocalAssum (annot, domain)) env
    in
    let body =
      if is_sprop_type_expression local_env evd body then
        normalize_sprop_type_wrappers local_env evd body
      else normalize_relevant_wrapper_spine local_env evd body
    in
    if Constr.equal body original_body then term
    else Constr.mkLambda (annot, domain, body)
  | LetIn (annot, value, ty, body) ->
    let original_body = body in
    let local_env =
      Environ.push_rel (RelDecl.LocalDef (annot, value, ty)) env
    in
    let body =
      if is_sprop_type_expression local_env evd body then
        normalize_sprop_type_wrappers local_env evd body
      else normalize_relevant_wrapper_spine local_env evd body
    in
    if Constr.equal body original_body then term
    else Constr.mkLetIn (annot, value, ty, body)
  | _ -> normalize_sprop_type_wrapper_root env evd term

let max_reflected_bits = Z.of_int 1_000_000

let reflected_size_ok value =
  Z.leq (Z.of_int (Z.numbits value)) max_reflected_bits

let reflected_pow base exponent =
  if Z.lt exponent Z.zero || not (Z.fits_int exponent) then None
  else
    let estimated_bits =
      if Z.leq base Z.one then Z.one
      else Z.mul (Z.of_int (Z.numbits base)) exponent
    in
    if Z.gt estimated_bits max_reflected_bits then None
    else
      let value = Z.pow base (Z.to_int exponent) in
      if reflected_size_ok value then Some value else None

let close_local_definitions env depth term =
  let debug = Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_DEBUG") in
  let unfolded = ref 0 in
  let rec close binders term =
    match Constr.kind term with
    | Rel index when index > binders ->
      let context_index = index - binders in
      if context_index > depth then raise Not_found;
      (match Environ.lookup_rel context_index env with
      | RelDecl.LocalDef (_, value, _) ->
        incr unfolded;
        if debug && depth > 100 && !unfolded <= 20 then
          Printf.eprintf
            "[bool-certificate] close local rel=%d binders=%d\n%!"
            context_index binders;
        close binders
          (Vars.lift binders (Vars.lift context_index value))
      | RelDecl.LocalAssum _ -> raise Not_found)
    | _ ->
      Constr.map_with_binders (fun binders -> binders + 1) close binders term
  in
  try
    let term = close 0 term in
    if debug && depth > 100 then
      Printf.eprintf
        "[bool-certificate] closed local operand unfolds=%d\n%!" !unfolded;
    if Vars.closed0 term then Some term else None
  with Not_found -> None

(** Expose only the head of an open computation until its result no longer
    depends on the surrounding assumptions.  This handles structurally
    constant functions such as a fold over an empty explicit list.  It is not
    an evaluator for open arithmetic: if head reduction reaches a neutral
    variable, or does not erase all external variables within the bounded
    number of transparent heads, it returns the original term and the
    arithmetic reifier declines it as before. *)
let close_by_head_reduction env evd depth term =
  let rec reduce ?(stop_when_closed = true) fuel unfolded term =
    if fuel = 0 || (stop_when_closed && Vars.closedn depth term) then term
    else
      let whd =
        EConstr.of_constr term |> Reductionops.whd_betaiotazeta env evd
        |> EConstr.Unsafe.to_constr
      in
      if not (Constr.equal whd term) then
        reduce ~stop_when_closed (fuel - 1) unfolded whd
      else
        match Constr.kind term with
        | Case (info, instance, params, return, invert, scrutinee, branches) ->
          let reduced_scrutinee =
            reduce ~stop_when_closed:false (fuel - 1) unfolded scrutinee
          in
          let rebuilt =
            Constr.mkCase
              ( info,
                instance,
                params,
                return,
                invert,
                reduced_scrutinee,
                branches )
          in
          let exposed = expose_iota_scrutinee env evd rebuilt in
          if Constr.equal term exposed then term
          else
            reduce ~stop_when_closed (fuel - 1) unfolded
              exposed
        | Proj (projection, relevance, scrutinee) ->
          let reduced_scrutinee =
            reduce ~stop_when_closed:false (fuel - 1) unfolded scrutinee
          in
          let rebuilt =
            Constr.mkProj (projection, relevance, reduced_scrutinee)
          in
          let exposed = expose_iota_scrutinee env evd rebuilt in
          if Constr.equal term exposed then term
          else
            reduce ~stop_when_closed (fuel - 1) unfolded
              exposed
        | _ ->
          let head, arguments = Constr.decompose_app term in
          let reduce_argument () =
            let rec scan index =
              if index = Array.length arguments then term
              else
                let reduced_argument =
                  reduce ~stop_when_closed:false (fuel - 1) unfolded
                    arguments.(index)
                in
                if Constr.equal arguments.(index) reduced_argument then
                  scan (index + 1)
                else
                  let arguments = Array.copy arguments in
                  arguments.(index) <- reduced_argument;
                  reduce ~stop_when_closed (fuel - 1) unfolded
                    (Constr.mkApp (head, arguments))
            in
            scan 0
          in
          match Constr.kind head with
          | Const (constant, instance)
            when not
                   (List.exists
                      (fun seen -> Environ.QConstant.equal env constant seen)
                      unfolded) -> (
            try
              let body = Environ.constant_value_in env (constant, instance) in
              reduce ~stop_when_closed (fuel - 1) (constant :: unfolded)
                (beta_apply body arguments)
            with Environ.NotEvaluableConst _ -> reduce_argument ())
          | Lambda _ | LetIn _ ->
            reduce ~stop_when_closed (fuel - 1) unfolded
              (beta_apply head arguments)
          | Case _ | Proj _ ->
            let reduced_head =
              reduce ~stop_when_closed:false (fuel - 1) unfolded head
            in
            if Constr.equal head reduced_head then term
            else
              reduce ~stop_when_closed (fuel - 1) unfolded
                (Constr.mkApp (reduced_head, arguments))
          | Fix ((recursive_arguments, selected), _)
            when selected < Array.length recursive_arguments ->
            let index = recursive_arguments.(selected) in
            if index >= Array.length arguments then term
            else
              let reduced_argument =
                reduce ~stop_when_closed:false (fuel - 1) unfolded
                  arguments.(index)
              in
              if Constr.equal arguments.(index) reduced_argument then term
              else
                let arguments = Array.copy arguments in
                arguments.(index) <- reduced_argument;
                reduce ~stop_when_closed (fuel - 1) unfolded
                  (Constr.mkApp (head, arguments))
          | _ -> reduce_argument ()
  in
  reduce 64 [] term

let reify_nat ?(depth = 0) ?(unfold = true) env evd term =
  if not (Vars.closedn depth term) then None
  else
  Option.bind (close_local_definitions env depth term) (fun term ->
  let rec reify fuel unfolded term =
    let preserve_original result =
      Option.map (fun certificate -> { certificate with nat_term = term }) result
    in
    if fuel = 0 || not (Vars.closed0 term) then None
    else
      let head, args = Constr.decompose_app term in
      if ref_matches env head "lean.Nat_of_N" && Array.length args = 1 then
        Option.map
          (fun value ->
            {
              nat_term = term;
              nat_value = value;
              nat_proof =
                cert_app "lean.NatCertificate_of_N" [ n_int value ];
            })
          (z_of_n env evd args.(0))
      else if nat_constructor_matches env head 1 && Array.length args = 0 then
        Some
          {
            nat_term = term;
            nat_value = Z.zero;
            nat_proof = registered_ref "lean.NatCertificate_zero";
          }
      else if nat_constructor_matches env head 2 && Array.length args = 1 then
        Option.bind (reify (fuel - 1) unfolded args.(0)) (fun arg ->
            let value = Z.succ arg.nat_value in
            if not (reflected_size_ok value) then None
            else
              Some
                {
                  nat_term = term;
                  nat_value = value;
                  nat_proof =
                    cert_app "lean.NatCertificate_succ"
                      [ arg.nat_term; n_int arg.nat_value; arg.nat_proof ];
                })
      else
        let binary key proof_key operation =
          if ref_matches env head key && Array.length args = 2 then
            Option.bind (reify (fuel - 1) unfolded args.(0)) (fun left ->
                Option.bind (reify (fuel - 1) unfolded args.(1)) (fun right ->
                    Option.bind (operation left.nat_value right.nat_value)
                      (fun value ->
                        if not (reflected_size_ok value) then None
                        else
                          Some
                            {
                              nat_term = term;
                              nat_value = value;
                              nat_proof =
                                cert_app proof_key
                                  [
                                    left.nat_term;
                                    right.nat_term;
                                    n_int left.nat_value;
                                    n_int right.nat_value;
                                    left.nat_proof;
                                    right.nat_proof;
                                  ];
                            })))
          else None
        in
        match
          binary "lean.Nat_add" "lean.NatCertificate_add"
            (fun a b -> Some (Z.add a b))
        with
        | Some _ as result -> result
        | None -> (
          match
            binary "lean.Nat_mul" "lean.NatCertificate_mul"
              (fun a b -> Some (Z.mul a b))
          with
          | Some _ as result -> result
          | None -> (
            match
              binary "lean.Nat_pow" "lean.NatCertificate_pow" reflected_pow
            with
            | Some _ as result -> result
            | None -> (
              match
                binary "lean.Nat_sub" "lean.NatCertificate_sub"
                  (fun a b -> Some (Z.max Z.zero (Z.sub a b)))
              with
              | Some _ as result -> result
              | None when not unfold -> None
              | None ->
              let reduced =
                expose_iota_scrutinee env evd term |> EConstr.of_constr
                |> Reductionops.whd_betaiotazeta env evd
                |> EConstr.Unsafe.to_constr
              in
              if not (Constr.equal reduced term) then
                preserve_original (reify (fuel - 1) unfolded reduced)
              else (
              match Constr.kind term with
              | LetIn (_, value, _, body) ->
                preserve_original
                  (reify (fuel - 1) unfolded (Vars.subst1 value body))
              | Const (constant, instance)
                when not
                       (List.exists
                          (fun seen -> Environ.QConstant.equal env constant seen)
                          unfolded) -> (
                try
                  let body =
                    Environ.constant_value_in env (constant, instance)
                  in
                  preserve_original
                    (reify (fuel - 1) (constant :: unfolded) body)
                with Environ.NotEvaluableConst _ -> None)
              | App _ -> (
                match Constr.kind head with
                | Const (constant, instance)
                  when not
                         (List.exists
                            (fun seen ->
                              Environ.QConstant.equal env constant seen)
                            unfolded) -> (
                  try
                    let body =
                      Environ.constant_value_in env (constant, instance)
                    in
                    preserve_original
                      (reify (fuel - 1) (constant :: unfolded)
                         (beta_apply body args))
                  with Environ.NotEvaluableConst _ -> None)
                | Lambda _ | LetIn _ ->
                  preserve_original
                    (reify (fuel - 1) unfolded (beta_apply head args))
                | _ -> None)
              | _ -> None))))
  in
  reify 128 [] term)

let is_int_type env evd term =
  try
    let ty =
      Retyping.get_type_of env evd (EConstr.of_constr term)
      |> Reductionops.whd_all env evd |> EConstr.Unsafe.to_constr
    in
    ref_matches env (fst (Constr.decompose_app ty)) "lean.Int"
  with _ -> false

let reify_int ?(depth = 0) ?(assume_int = false) ?(unfold = true) env evd
    term =
  let original = term in
  if (not assume_int) && not (is_int_type env evd original) then None
  else
  (* Structural computation can erase every local assumption before any
     arithmetic is performed.  For example, a fold over an empty explicit
     coefficient list returns its closed accumulator without inspecting the
     open value vector.  Test closure after a bounded, demand-driven head
     reduction and retain [original] as the checked certificate endpoint. *)
  let term =
    if Vars.closedn depth original || not unfold then original
    else close_by_head_reduction env evd depth original
  in
  if not (Vars.closedn depth term) then None
  else
    Option.bind (close_local_definitions env depth term) (fun term ->
        let rec reify fuel unfolded term =
          let preserve_original result =
            Option.map
              (fun certificate -> { certificate with int_term = term })
              result
          in
          if fuel = 0 || not (Vars.closed0 term) then None
          else
            let head, args = Constr.decompose_app term in
            if int_constructor_matches env head 1 && Array.length args = 1 then
              Option.map
                (fun argument ->
                  let value = argument.nat_value in
                  {
                    int_term = term;
                    int_value = value;
                    int_proof =
                      cert_app "lean.IntCertificate_ofNat"
                        [
                          argument.nat_term;
                          n_int argument.nat_value;
                          argument.nat_proof;
                        ];
                  })
                (reify_nat ~unfold env evd args.(0))
            else if
              int_constructor_matches env head 2 && Array.length args = 1
            then
              Option.map
                (fun argument ->
                  let value = Z.neg (Z.succ argument.nat_value) in
                  {
                    int_term = term;
                    int_value = value;
                    int_proof =
                      cert_app "lean.IntCertificate_negSucc"
                        [
                          argument.nat_term;
                          n_int argument.nat_value;
                          argument.nat_proof;
                        ];
                  })
                (reify_nat ~unfold env evd args.(0))
            else
              if not unfold then None
              else
              let reduced =
                EConstr.of_constr term
                |> Reductionops.whd_betaiotazeta env evd
                |> EConstr.Unsafe.to_constr
              in
              if not (Constr.equal reduced term) then
                preserve_original (reify (fuel - 1) unfolded reduced)
              else
                match Constr.kind term with
                | LetIn (_, value, _, body) ->
                  preserve_original
                    (reify (fuel - 1) unfolded (Vars.subst1 value body))
                | Const (constant, instance)
                  when not
                         (List.exists
                            (fun seen ->
                              Environ.QConstant.equal env constant seen)
                            unfolded) -> (
                  try
                    let body =
                      Environ.constant_value_in env (constant, instance)
                    in
                    preserve_original
                      (reify (fuel - 1) (constant :: unfolded) body)
                  with Environ.NotEvaluableConst _ -> None)
                | App _ -> (
                  match Constr.kind head with
                  | Const (constant, instance)
                    when not
                           (List.exists
                              (fun seen ->
                                Environ.QConstant.equal env constant seen)
                              unfolded) -> (
                    try
                      let body =
                        Environ.constant_value_in env (constant, instance)
                      in
                      preserve_original
                        (reify (fuel - 1) (constant :: unfolded)
                           (beta_apply body args))
                    with Environ.NotEvaluableConst _ -> None)
                  | Lambda _ | LetIn _ ->
                    preserve_original
                      (reify (fuel - 1) unfolded (beta_apply head args))
                  | _ -> None)
                | _ -> None
        in
        Option.map
          (fun certificate -> { certificate with int_term = original })
          (reify 128 [] term))

type certificate_path_step =
  | AppFunction
  | AppArgument of int
  | ProdDomain
  | ProdCodomain
  | LambdaDomain
  | LambdaBody
  | LetValue
  | LetType
  | LetBody
  | CaseScrutinee
  | ProjectionScrutinee

let string_of_certificate_path path =
  let step = function
    | AppFunction -> "fun"
    | AppArgument index -> "arg" ^ string_of_int index
    | ProdDomain -> "prod-domain"
    | ProdCodomain -> "prod-codomain"
    | LambdaDomain -> "lambda-domain"
    | LambdaBody -> "lambda-body"
    | LetValue -> "let-value"
    | LetType -> "let-type"
    | LetBody -> "let-body"
    | CaseScrutinee -> "case-scrutinee"
    | ProjectionScrutinee -> "projection-scrutinee"
  in
  String.concat "/" (List.map step path)

let rec first_certified_nat_difference env evd path actual expected =
  if Constr.equal actual expected then None
  else
    match reify_nat env evd actual, reify_nat env evd expected with
    | Some left, Some right when Z.equal left.nat_value right.nat_value ->
      Some (List.rev path, left, right)
    | _ -> (
      match Constr.kind actual, Constr.kind expected with
      | Prod (_, actual_domain, actual_body),
        Prod (_, expected_domain, expected_body) -> (
        match
          first_certified_nat_difference env evd (ProdDomain :: path)
            actual_domain expected_domain
        with
        | Some _ as result -> result
        | None ->
          first_certified_nat_difference env evd (ProdCodomain :: path)
            actual_body expected_body)
      | Lambda (_, actual_domain, actual_body),
        Lambda (_, expected_domain, expected_body) -> (
        match
          first_certified_nat_difference env evd (LambdaDomain :: path)
            actual_domain expected_domain
        with
        | Some _ as result -> result
        | None ->
          first_certified_nat_difference env evd (LambdaBody :: path)
            actual_body expected_body)
      | LetIn (_, actual_value, actual_type, actual_body),
        LetIn (_, expected_value, expected_type, expected_body) -> (
        match
          first_certified_nat_difference env evd (LetValue :: path) actual_value
            expected_value
        with
        | Some _ as result -> result
        | None -> (
          match
            first_certified_nat_difference env evd (LetType :: path) actual_type
              expected_type
          with
          | Some _ as result -> result
          | None ->
            first_certified_nat_difference env evd (LetBody :: path) actual_body
              expected_body))
      | App _, App _ ->
        let actual_head, actual_args = Constr.decompose_app actual in
        let expected_head, expected_args = Constr.decompose_app expected in
        if
          not (Constr.equal actual_head expected_head)
          || Array.length actual_args <> Array.length expected_args
        then None
        else
          let rec scan index =
            if index = Array.length actual_args then None
            else
              match
                first_certified_nat_difference env evd
                  (AppArgument index :: path)
                  actual_args.(index) expected_args.(index)
              with
              | Some _ as result -> result
              | None -> scan (index + 1)
          in
          scan 0
      | _ -> None)

let first_certified_int_difference env evd path actual expected =
  let budget = ref 64 in
  let rec search path actual expected =
    if !budget = 0 || Constr.equal actual expected then None
    else (
      decr budget;
      let certify () =
        match reify_int env evd actual, reify_int env evd expected with
        | Some left, Some right when Z.equal left.int_value right.int_value ->
          Some (List.rev path, left, right)
        | _ -> None
      in
      match Constr.kind actual, Constr.kind expected with
      | Prod (_, actual_domain, actual_body),
        Prod (_, expected_domain, expected_body) -> (
        match
          search (ProdDomain :: path) actual_domain expected_domain
        with
        | Some _ as result -> result
        | None ->
          search (ProdCodomain :: path) actual_body expected_body)
      | Lambda (_, actual_domain, actual_body),
        Lambda (_, expected_domain, expected_body) -> (
        match
          search (LambdaDomain :: path) actual_domain expected_domain
        with
        | Some _ as result -> result
        | None ->
          search (LambdaBody :: path) actual_body expected_body)
      | LetIn (_, actual_value, actual_type, actual_body),
        LetIn (_, expected_value, expected_type, expected_body) -> (
        match
          search (LetValue :: path) actual_value expected_value
        with
        | Some _ as result -> result
        | None -> (
          match
            search (LetType :: path) actual_type expected_type
          with
          | Some _ as result -> result
          | None ->
            search (LetBody :: path) actual_body expected_body))
      | App _, App _ ->
        let actual_head, actual_args = Constr.decompose_app actual in
        let expected_head, expected_args = Constr.decompose_app expected in
        if
          not (Constr.equal actual_head expected_head)
          || Array.length actual_args <> Array.length expected_args
        then certify ()
        else
          let rec scan index =
            if index = Array.length actual_args then None
            else
              match
                search (AppArgument index :: path) actual_args.(index)
                  expected_args.(index)
              with
              | Some _ as result -> result
              | None -> scan (index + 1)
          in
          scan 0
      | _ -> certify ())
  in
  search path actual expected

let replace_certificate_path term path replacement =
  let rec replace depth term = function
    | [] -> Vars.lift depth replacement
    | AppFunction :: rest ->
      let head, args = Constr.decompose_app term in
      let head = replace depth head rest in
      if Array.length args = 0 then head else Constr.mkApp (head, args)
    | AppArgument index :: rest ->
      let head, args = Constr.decompose_app term in
      if index >= Array.length args then assert false;
      let args = Array.copy args in
      args.(index) <- replace depth args.(index) rest;
      Constr.mkApp (head, args)
    | ProdDomain :: rest ->
      let annot, domain, body = Constr.destProd term in
      Constr.mkProd (annot, replace depth domain rest, body)
    | ProdCodomain :: rest ->
      let annot, domain, body = Constr.destProd term in
      Constr.mkProd (annot, domain, replace (depth + 1) body rest)
    | LambdaDomain :: rest ->
      let annot, domain, body = Constr.destLambda term in
      Constr.mkLambda (annot, replace depth domain rest, body)
    | LambdaBody :: rest ->
      let annot, domain, body = Constr.destLambda term in
      Constr.mkLambda (annot, domain, replace (depth + 1) body rest)
    | LetValue :: rest ->
      let annot, value, ty, body = Constr.destLetIn term in
      Constr.mkLetIn (annot, replace depth value rest, ty, body)
    | LetType :: rest ->
      let annot, value, ty, body = Constr.destLetIn term in
      Constr.mkLetIn (annot, value, replace depth ty rest, body)
    | LetBody :: rest ->
      let annot, value, ty, body = Constr.destLetIn term in
      Constr.mkLetIn (annot, value, ty, replace (depth + 1) body rest)
    | CaseScrutinee :: rest ->
      let info, instance, params, return, invert, scrutinee, branches =
        Constr.destCase term
      in
      Constr.mkCase
        ( info,
          instance,
          params,
          return,
          invert,
          replace depth scrutinee rest,
          branches )
    | ProjectionScrutinee :: rest ->
      let projection, relevance, scrutinee = Constr.destProj term in
      Constr.mkProj
        (projection, relevance, replace depth scrutinee rest)
  in
  replace 0 term path

let _first_physical_difference actual reduced =
  let rec difference path actual reduced =
    if actual == reduced then None
    else
      match Constr.kind actual, Constr.kind reduced with
      | LetIn (_, actual_value, actual_type, actual_body),
        LetIn (_, reduced_value, reduced_type, reduced_body)
        when actual_value == reduced_value && actual_type == reduced_type ->
        difference (LetBody :: path) actual_body reduced_body
      | App _, App _ ->
        let actual_head, actual_args = Constr.decompose_app actual in
        let reduced_head, reduced_args = Constr.decompose_app reduced in
        if Array.length actual_args <> Array.length reduced_args then
          Some (List.rev path)
        else if actual_head != reduced_head then
          (match
             difference (AppFunction :: path) actual_head reduced_head
           with
          | Some _ as result -> result
          | None -> Some (List.rev path))
        else
          let rec argument index =
            if index = Array.length actual_args then Some (List.rev path)
            else if actual_args.(index) == reduced_args.(index) then
              argument (index + 1)
            else
              difference (AppArgument index :: path) actual_args.(index)
                reduced_args.(index)
          in
          argument 0
      | Case (_, _, _, _, _, actual_scrutinee, _),
        Case (_, _, _, _, _, reduced_scrutinee, _)
        when actual_scrutinee != reduced_scrutinee ->
        difference (CaseScrutinee :: path) actual_scrutinee
          reduced_scrutinee
      | Proj (_, _, actual_scrutinee), Proj (_, _, reduced_scrutinee)
        when actual_scrutinee != reduced_scrutinee ->
        difference (ProjectionScrutinee :: path) actual_scrutinee
          reduced_scrutinee
      | _ -> Some (List.rev path)
  in
  difference [] actual reduced

let subterm_at_certificate_path term path =
  List.fold_left
    (fun term step ->
      match step with
      | AppFunction -> fst (Constr.decompose_app term)
      | AppArgument index ->
        let _, args = Constr.decompose_app term in
        args.(index)
      | CaseScrutinee ->
        let _, _, _, _, _, scrutinee, _ = Constr.destCase term in
        scrutinee
      | ProjectionScrutinee ->
        let _, _, scrutinee = Constr.destProj term in
        scrutinee
      | ProdDomain -> let _, domain, _ = Constr.destProd term in domain
      | ProdCodomain -> let _, _, body = Constr.destProd term in body
      | LambdaDomain -> let _, domain, _ = Constr.destLambda term in domain
      | LambdaBody -> let _, _, body = Constr.destLambda term in body
      | LetValue -> let _, value, _, _ = Constr.destLetIn term in value
      | LetType -> let _, _, ty, _ = Constr.destLetIn term in ty
      | LetBody -> let _, _, _, body = Constr.destLetIn term in body)
    term path

let atomic_type_level env evd term =
  try
    let ty =
      Retyping.get_type_of env evd (EConstr.of_constr term)
      |> EConstr.Unsafe.to_constr
    in
    let sort =
      Retyping.get_type_of env evd (EConstr.of_constr ty)
      |> Reductionops.whd_all env evd |> EConstr.Unsafe.to_constr
      |> Constr.destSort
    in
    if Sorts.is_sprop sort || Sorts.is_prop sort then None
    else Univ.Universe.level (Sorts.univ_of_sort sort)
  with _ -> None

(* Proof-producing translation can introduce polymorphic Rocq helpers after
   the Lean syntax has been traversed.  Record their instances at construction
   time instead of rescanning the completed (potentially enormous) proof term.
   The stack keeps the accounting local when importing a dependency recursively
   starts another declaration. *)
let generated_universe_scopes : Level.Set.t ref list ref = ref []

let record_generated_universe_levels levels =
  match !generated_universe_scopes with
  | [] -> ()
  | scope :: _ ->
    scope :=
      List.fold_left
        (fun levels level -> Level.Set.add level levels)
        !scope levels

let record_generated_universe_instance instance =
  let _, levels = UVars.Instance.to_array instance in
  record_generated_universe_levels (Array.to_list levels)

let capture_generated_universe_levels f =
  let scope = ref Level.Set.empty in
  let saved = !generated_universe_scopes in
  generated_universe_scopes := scope :: saved;
  match f () with
  | result ->
    generated_universe_scopes := saved;
    (result, !scope)
  | exception exn ->
    let exn = Exninfo.capture exn in
    generated_universe_scopes := saved;
    Exninfo.iraise exn

let registered_ref_at_level key level =
  record_generated_universe_levels [ level ];
  let instance = UVars.Instance.of_array ([||], [| level |]) in
  Constr.mkRef (Rocqlib.lib_ref key, instance)

let registered_ref_at_levels key levels =
  record_generated_universe_levels levels;
  let instance =
    UVars.Instance.of_array ([||], Array.of_list levels)
  in
  Constr.mkRef (Rocqlib.lib_ref key, instance)

type bool_certificate = {
  bool_term : Constr.t;
  bool_value : bool;
  bool_proof : Constr.t;
}

type bool_normalization = {
  bool_normalization_source : Constr.t;
  bool_normalization_residual : Constr.t;
  bool_normalization_proof : Constr.t;
}

type bool_probe_transition =
  | BoolProbeDefinitional of
      Constr.t * Constr.t * certificate_path_step list
  | BoolProbeEquation of
      Constr.t * Constr.t * certificate_path_step list * Constr.t
  | BoolProbeBoolean of
      Constr.t * Constr.t * certificate_path_step list * bool_certificate
  | BoolProbeCompactNat of
      Constr.t * Constr.t * certificate_path_step list * Z.t
  | BoolProbeNat of
      Constr.t * Constr.t * certificate_path_step list * nat_certificate
  | BoolProbeInt of
      Constr.t * Constr.t * certificate_path_step list * int_certificate

(** Compact description of a transition.  Consecutive probe states differ at
    exactly one path; retaining both complete states for every reduction
    otherwise keeps hundreds of almost identical terms alive. *)
type bool_probe_recipe =
  | BoolProbeDefinitionalRecipe of
      Constr.t * Constr.t * certificate_path_step list
  | BoolProbeEquationRecipe of
      Constr.t * Constr.t * certificate_path_step list * Constr.t
  | BoolProbeBooleanRecipe of
      Constr.t * Constr.t * certificate_path_step list * bool_certificate
  | BoolProbeCompactNatRecipe of
      Constr.t * Constr.t * certificate_path_step list * Z.t
  | BoolProbeNatRecipe of
      Constr.t * Constr.t * certificate_path_step list * nat_certificate
  | BoolProbeIntRecipe of
      Constr.t * Constr.t * certificate_path_step list * int_certificate

type bool_probe_trace = {
  bool_probe_residual : Constr.t;
  bool_probe_transitions : bool_probe_transition list;
  bool_probe_exhausted : bool;
}

type bool_probe_rewrite =
  | BoolProbeRewriteBoolean of bool_certificate
  | BoolProbeRewriteEquation of Constr.t

type bool_reification =
  | ReifiedBoolValue of bool_certificate
  | ReifiedBoolResidual of bool_normalization
  | ProbedBoolValue of bool * bool_probe_trace
  | ProbedBoolResidual of bool_probe_trace

type certified_bool_equality = {
  certified_bool_left : Constr.t;
  certified_bool_right : Constr.t;
  certified_bool_proof : Constr.t;
}

let bool_probe_count = ref 0

type bool_equality = {
  bool_equality_left : Constr.t;
  bool_equality_right : Constr.t;
  bool_equality_resume : Constr.t;
  bool_equality_proof : Constr.t;
}

type equation_argument_source =
  | EquationFunctionArgument of int
  | EquationConstructorField of int

type constructor_equation = {
  equation_function : Constant.t;
  equation_function_instance : UVars.Instance.t;
  equation_argument_count : int;
  equation_discriminant : int;
  equation_constructor : Names.constructor;
  equation_parameter_count : int;
  equation_sources : equation_argument_source list;
  equation_theorem : Constr.t;
}

type unfold_equation = {
  unfold_function : Constant.t;
  unfold_function_instance : UVars.Instance.t;
  unfold_argument_count : int;
  unfold_theorem : Constr.t;
}

type blocked_equation_function = {
  blocked_function : Constant.t;
  blocked_function_instance : UVars.Instance.t;
  blocked_argument_count : int;
  blocked_argument : int;
}

type reification_cache = {
  cached_constructor_equations : constructor_equation list ref;
  cached_unfold_equations : unfold_equation list ref;
  cached_blocked_equation_functions : blocked_equation_function list ref;
  cached_bool_probes :
    ( (Constr.t option * Constr.t) list
    * Constr.t
    * bool_reification option )
    list ref;
  cached_bool_normalizations :
    ( (Constr.t option * Constr.t) list
    * Constr.t
    * bool_normalization )
    list ref;
  cached_slow_bool_heads :
    (Constant.t * UVars.Instance.t * int) list ref;
}

(** Equation theorems and their demand metadata may be reused by all proof
    boundaries of one Lean declaration.  They must not escape that
    declaration: imported universe names such as [Lean.u.0] are local to its
    universe context and can be reused with a different meaning by the next
    declaration.  A stack preserves the caller's cache while recursively
    importing a dependency. *)
let reification_cache_scopes : reification_cache list ref = ref []

let with_reification_cache f =
  let cache =
    {
      cached_constructor_equations = ref [];
      cached_unfold_equations = ref [];
      cached_blocked_equation_functions = ref [];
      cached_bool_probes = ref [];
      cached_bool_normalizations = ref [];
      cached_slow_bool_heads = ref [];
    }
  in
  let saved = !reification_cache_scopes in
  reification_cache_scopes := cache :: saved;
  match f () with
  | result ->
    reification_cache_scopes := saved;
    result
  | exception exn ->
    let exn = Exninfo.capture exn in
    reification_cache_scopes := saved;
    Exninfo.iraise exn

let current_reification_cache () =
  match !reification_cache_scopes with
  | cache :: _ -> cache
  | [] ->
    (* [reify_bool] normally runs while translating a declaration.  Retain a
       local fallback for diagnostic callers without extending its lifetime. *)
    {
      cached_constructor_equations = ref [];
      cached_unfold_equations = ref [];
      cached_blocked_equation_functions = ref [];
      cached_bool_probes = ref [];
      cached_bool_normalizations = ref [];
      cached_slow_bool_heads = ref [];
    }

let bool_probe_context_key env =
  Environ.rel_context env
  |> List.map (function
       | RelDecl.LocalAssum (_, types) -> None, types
       | RelDecl.LocalDef (_, value, types) -> Some value, types)

let equal_bool_probe_context left right =
  List.length left = List.length right
  && List.for_all2
       (fun (left_value, left_type) (right_value, right_type) ->
         Constr.equal left_type right_type
         &&
         match left_value, right_value with
         | None, None -> true
         | Some left, Some right -> Constr.equal left right
         | None, Some _ | Some _, None -> false)
       left right

let coq_bool value =
  registered_ref (if value then "core.bool.true" else "core.bool.false")

(** Store an intermediate certificate as an opaque Rocq lemma.  The kernel
    checks [bool_proof] before installing the constant, while later
    certificate segments retain only its type and a constant reference.  This
    is the sharing boundary that keeps proof-producing evaluation from
    duplicating every intermediate term in one enormous proof object. *)
let _share_bool_certificate certificate =
  Gc.full_major ();
  Gc.compact ();
  if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_DEBUG") then (
    let stats = Gc.quick_stat () in
    Printf.eprintf
      "[bool-certificate] compacted heap live_words=%d heap_words=%d\n%!"
      stats.Gc.live_words stats.Gc.heap_words);
  let base = Id.of_string "_lean_import_bool_certificate" in
  let name =
    Namegen.next_global_ident_away (Global.safe_env ()) base Id.Set.empty
  in
  let types =
    cert_app "lean.BoolCertificate"
      [ certificate.bool_term; coq_bool certificate.bool_value ]
  in
  let univs =
    ( UState.Monomorphic_entry Univ.ContextSet.empty,
      UnivNames.empty_binders )
  in
  let entry =
    Declare.definition_entry ~opaque:true ~types ~univs certificate.bool_proof
  in
  if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_DEBUG") then
    Printf.eprintf "[bool-certificate] checking shared segment %s\n%!"
      (Id.to_string name);
  if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_VALIDATE") then (
    Printf.eprintf "[bool-certificate] inferring shared proof %s\n%!"
      (Id.to_string name);
    ignore
      (Retyping.get_type_of (Global.env ()) Evd.empty
         (EConstr.of_constr certificate.bool_proof));
    Printf.eprintf "[bool-certificate] inferred shared proof %s\n%!"
      (Id.to_string name));
  let constant =
    Declare.declare_constant ~name ~kind:Decls.(IsProof Lemma)
      (Declare.DefinitionEntry entry)
  in
  if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_DEBUG") then
    Printf.eprintf "[bool-certificate] shared segment %s\n%!"
      (Id.to_string name);
  { certificate with
    bool_proof = Constr.mkConstU (constant, UVars.Instance.empty) }

let lean_bool_constructor value =
  match Rocqlib.lib_ref "lean.Bool" with
  | GlobRef.IndRef ind ->
    Constr.mkConstructU
      ((ind, if value then 2 else 1), UVars.Instance.empty)
  | _ -> assert false

let lean_nat_constructor index =
  match Rocqlib.lib_ref "lean.Nat" with
  | GlobRef.IndRef ind ->
    Constr.mkConstructU ((ind, index), UVars.Instance.empty)
  | _ -> assert false

let lean_int_constructor index =
  match Rocqlib.lib_ref "lean.Int" with
  | GlobRef.IndRef ind ->
    Constr.mkConstructU ((ind, index), UVars.Instance.empty)
  | _ -> assert false

let bool_constructor_value env term =
  let head, args = Constr.decompose_app term in
  if Array.length args <> 0 then None
  else
    match Rocqlib.lib_ref "lean.Bool", Constr.kind head with
    | GlobRef.IndRef ind, Construct ((constructor_ind, index), _)
      when Environ.QInd.equal env ind constructor_ind ->
      if index = 1 then Some false
      else if index = 2 then Some true
      else None
    | _ -> None

let is_nat_type env evd term =
  try
    let ty =
      Retyping.get_type_of env evd (EConstr.of_constr term)
      |> Reductionops.whd_all env evd |> EConstr.Unsafe.to_constr
    in
    ref_matches env (fst (Constr.decompose_app ty)) "lean.Nat"
  with _ -> false

let is_bool_type env evd term =
  try
    let ty =
      Retyping.get_type_of env evd (EConstr.of_constr term)
      |> Reductionops.whd_all env evd |> EConstr.Unsafe.to_constr
    in
    ref_matches env (fst (Constr.decompose_app ty)) "lean.Bool"
  with _ -> false

let is_canonical_nat env term =
  let head, args = Constr.decompose_app term in
  ref_matches env head "lean.Nat_of_N" && Array.length args = 1

let is_reflected_nat_operation env term =
  let head, _ = Constr.decompose_app term in
  List.exists
    (ref_matches env head)
    [ "lean.Nat_add"; "lean.Nat_mul"; "lean.Nat_pow"; "lean.Nat_sub" ]

let canonical_nat_value env evd term =
  let head, args = Constr.decompose_app term in
  if ref_matches env head "lean.Nat_of_N" && Array.length args = 1 then
    z_of_n env evd args.(0)
  else None

let first_reifiable_nat ?(unfold = true) env evd depth term =
  let rec scan env depth path term =
    let at_current =
      if
        Vars.closedn depth term
        && not (is_canonical_nat env term)
        && is_nat_type env evd term
      then
        match reify_nat ~depth ~unfold env evd term with
        | Some certificate
          when is_reflected_nat_operation env term ->
          Some (List.rev path, certificate)
        | _ -> None
      else None
    in
    match at_current with
    | Some _ as result -> result
    | None -> (
      match Constr.kind term with
      | App _ ->
        let _, args = Constr.decompose_app term in
        let rec arguments index =
          if index = Array.length args then None
          else
            match scan env depth (AppArgument index :: path) args.(index) with
            | Some _ as result -> result
            | None -> arguments (index + 1)
        in
        arguments 0
      | LetIn (annot, value, ty, body) -> (
        match scan env depth (LetValue :: path) value with
        | Some _ as result -> result
        | None -> (
          match scan env depth (LetType :: path) ty with
          | Some _ as result -> result
          | None ->
            let body_env =
              Environ.push_rel (RelDecl.LocalDef (annot, value, ty)) env
            in
            scan body_env (depth + 1) (LetBody :: path) body))
      | Case (_, _, _, _, _, scrutinee, _) ->
        scan env depth (CaseScrutinee :: path) scrutinee
      | Proj (_, _, scrutinee) ->
        scan env depth (ProjectionScrutinee :: path) scrutinee
      | _ -> None)
  in
  scan env depth [] term

let is_canonical_int env term =
  let head, arguments = Constr.decompose_app term in
  Array.length arguments = 1
  && (int_constructor_matches env head 1
     || int_constructor_matches env head 2)
  && is_canonical_nat env arguments.(0)

(** Decide whether an application returns [Lean.Int] without retyping its
    arguments.  In particular, do not call [Retyping.get_type_of] on the
    complete proof currently being evaluated: that proof can contain the
    whole translated theorem and rechecking it at every search step is
    quadratic.  Its head telescope already determines the result type because
    the imported term has previously been typechecked.

    This is only a discovery filter.  A false positive cannot add a trusted
    reduction rule: the generated [IntCertificate] and the surrounding
    equality transport are subsequently checked by the Rocq kernel. *)
let int_result_arity_cache =
  Summary.ref ~name:"lean-int-result-arities" Cmap_env.empty

let constant_int_result_arity env evd constant instance =
  match Cmap_env.find_opt constant !int_result_arity_cache with
  | Some result -> result
  | None ->
    let result =
      try
        let rec conclusion arity ty =
          let ty = whd_constr env evd ty in
          match Constr.kind ty with
          | Prod (_, _, body) -> conclusion (arity + 1) body
          | _ ->
            if
              ref_matches env (fst (Constr.decompose_app ty)) "lean.Int"
            then Some arity
            else None
        in
        conclusion 0
          (Retyping.get_type_of env evd
             (EConstr.of_constr (Constr.mkConstU (constant, instance)))
          |> EConstr.Unsafe.to_constr)
      with _ -> None
    in
    int_result_arity_cache :=
      Cmap_env.add constant result !int_result_arity_cache;
    result

let has_int_application_result env evd term =
  let head, arguments = Constr.decompose_app term in
  match Constr.kind head with
  | Construct _ ->
    Array.length arguments = 1
    && (int_constructor_matches env head 1
       || int_constructor_matches env head 2)
  | Const (constant, instance) -> (
    match constant_int_result_arity env evd constant instance with
    | Some arity -> Array.length arguments = arity
    | None -> false)
  | _ -> false

(** Transporting an equality through a large dependent Boolean context has a
    fixed cost, so canonicalizing [Int.ofNat 0] or [Int.ofNat 1] makes the
    proof larger without avoiding meaningful kernel computation.  Count only
    up to a small, representation-independent threshold; this admits long
    unary numerals, compact numeral wrappers, and closed arithmetic trees,
    while leaving already-cheap constructor values alone. *)
let int_rewrite_is_beneficial certificate =
  let exception Large_enough in
  let remaining = ref 16 in
  let rec count () term =
    decr remaining;
    if !remaining = 0 then raise Large_enough;
    Constr.fold count () term
  in
  try
    count () certificate.int_term;
    false
  with Large_enough -> true

let first_reifiable_int ?(unfold = true) env evd depth term =
  let rec scan env depth path term =
    let at_current =
      if
        Vars.closedn depth term
        && not (is_canonical_int env term)
        && has_int_application_result env evd term
      then
        Option.bind
          (reify_int ~depth ~assume_int:true ~unfold env evd term)
          (fun certificate ->
            if int_rewrite_is_beneficial certificate then
              Some (List.rev path, certificate)
            else None)
      else None
    in
    match at_current with
    | Some _ as result -> result
    | None -> (
      match Constr.kind term with
      | App _ ->
        let _, arguments = Constr.decompose_app term in
        let rec argument index =
          if index = Array.length arguments then None
          else
            match
              scan env depth (AppArgument index :: path) arguments.(index)
            with
            | Some _ as result -> result
            | None -> argument (index + 1)
        in
        argument 0
      | LetIn (annot, value, types, body) -> (
        match scan env depth (LetValue :: path) value with
        | Some _ as result -> result
        | None -> (
          match scan env depth (LetType :: path) types with
          | Some _ as result -> result
          | None ->
            let body_env =
              Environ.push_rel (RelDecl.LocalDef (annot, value, types)) env
            in
            scan body_env (depth + 1) (LetBody :: path) body))
      | Case (_, _, _, _, _, scrutinee, _) ->
        scan env depth (CaseScrutinee :: path) scrutinee
      | Proj (_, _, scrutinee) ->
        scan env depth (ProjectionScrutinee :: path) scrutinee
      | _ -> None)
  in
  scan env depth [] term

let first_compact_nat_discriminator env evd term =
  let demanded_constant_argument constant instance arguments =
    List.find_map
      (fun blocked ->
        if
          Constant.UserOrd.equal blocked.blocked_function constant
          && UVars.Instance.equal
               blocked.blocked_function_instance instance
          && blocked.blocked_argument_count = Array.length arguments
          && blocked.blocked_argument >= 0
          && blocked.blocked_argument < Array.length arguments
        then Some blocked.blocked_argument
        else None)
      !((current_reification_cache ()).cached_blocked_equation_functions)
  in
  let rec scan path term =
    match canonical_nat_value env evd term with
    | Some value -> Some (List.rev path, value)
    | None -> match Constr.kind term with
    | Case (_, _, _, _, _, scrutinee, _) -> (
      match canonical_nat_value env evd scrutinee with
      | Some value -> Some (List.rev (CaseScrutinee :: path), value)
      | None -> scan (CaseScrutinee :: path) scrutinee)
    | App _ ->
      let head, args = Constr.decompose_app term in
      (match Constr.kind head with
      | Fix ((recursive_arguments, selected), _) ->
        let index = recursive_arguments.(selected) in
        if index >= Array.length args then None
        else (
          match canonical_nat_value env evd args.(index) with
          | Some value -> Some (List.rev (AppArgument index :: path), value)
          | None -> scan (AppArgument index :: path) args.(index))
      | Const (constant, instance) -> (
        match demanded_constant_argument constant instance args with
        | Some index ->
          scan (AppArgument index :: path) args.(index)
        | None -> scan (AppFunction :: path) head)
      | _ -> scan (AppFunction :: path) head)
    | Proj (_, _, scrutinee) ->
      scan (ProjectionScrutinee :: path) scrutinee
    | LetIn (_, value, _, body) -> (
      match canonical_nat_value env evd value with
      | Some compact -> Some (List.rev (LetValue :: path), compact)
      | None -> scan (LetBody :: path) body)
    | _ -> None
  in
  scan [] term

let rebuild_app head args =
  if Array.length args = 0 then head else Constr.mkApp (head, args)

let constr_kind_tag term =
  match Constr.kind term with
  | Rel _ -> "Rel"
  | Var _ -> "Var"
  | Meta _ -> "Meta"
  | Evar _ -> "Evar"
  | Sort _ -> "Sort"
  | Cast _ -> "Cast"
  | Prod _ -> "Prod"
  | Lambda _ -> "Lambda"
  | LetIn _ -> "LetIn"
  | App _ -> "App"
  | Const _ -> "Const"
  | Ind _ -> "Ind"
  | Construct _ -> "Construct"
  | Case _ -> "Case"
  | Fix _ -> "Fix"
  | CoFix _ -> "CoFix"
  | Proj _ -> "Proj"
  | Int _ -> "Int"
  | Float _ -> "Float"
  | String _ -> "String"
  | Array _ -> "Array"

let debug_head_shape term =
  let rec strip_lets count term =
    match Constr.kind term with
    | LetIn (_, _, _, body) -> strip_lets (count + 1) body
    | _ -> count, term
  in
  let lets, body = strip_lets 0 term in
  let head, args = Constr.decompose_app body in
  let head =
    match Constr.kind head with
    | Const (constant, _) -> "Const " ^ Constant.to_string constant
    | Rel index -> "Rel " ^ string_of_int index
    | Fix ((_, selected), (names, _, _)) ->
      "Fix "
      ^ Pp.string_of_ppcmds
          (Name.print (Context.binder_name names.(selected)))
    | Lambda _ ->
      let rec count_lambdas count term =
        match Constr.kind term with
        | Lambda (_, _, body) -> count_lambdas (count + 1) body
        | _ -> count
      in
      "Lambda " ^ string_of_int (count_lambdas 0 head)
    | _ -> constr_kind_tag head
  in
  Printf.sprintf "lets=%d head=%s args=%d" lets head (Array.length args)

(** [Constr.t] values are hash-consed DAGs, but Rocq's ordinary universe
    collector recursively visits them as trees.  Generated certificates share
    large contexts intentionally, so a tree traversal can revisit the same
    node exponentially.  Collect the same universe levels while visiting each
    physical DAG node once. *)
let universes_of_constrs_dag ?(init = Level.Set.empty) roots =
  let module Seen = Hashtbl.Make (struct
    type t = Constr.t

    let equal left right = left == right
    let hash term = Hashtbl.hash_param 10 100 term
  end)
  in
  let seen = Seen.create 251 in
  let add_instance levels instance =
    let _, universes = UVars.Instance.to_array instance in
    Array.fold_left
      (fun levels level -> Level.Set.add level levels)
      levels universes
  in
  let add_sort levels = function
    | Sorts.Type universe | Sorts.GSort (_, universe)
    | Sorts.VSort (_, universe) ->
      Univ.Universe.levels ~init:levels universe
    | Sorts.SProp | Sorts.Prop | Sorts.Set -> levels
  in
  let rec visit levels term =
    if Seen.mem seen term then levels
    else begin
      Seen.add seen term ();
      let levels =
        match Constr.kind term with
        | Const (_, instance) | Ind (_, instance)
        | Construct (_, instance) ->
          add_instance levels instance
        | Sort sort -> add_sort levels sort
        | Array (instance, _, _, _) -> add_instance levels instance
        | Case (_, instance, _, _, _, _, _) ->
          add_instance levels instance
        | _ -> levels
      in
      Constr.fold visit levels term
    end
  in
  List.fold_left visit init roots

(** One ordinary kernel reduction, selected by normal order.  This function
    does not decide equality: every returned step is later materialized as a
    [Bool_defeq] proof and checked by Rocq conversion in isolation. *)
let rec reduce_definitional_once ?(depth = 0) ?(path = [])
    ?(before = fun _ _ _ _ -> ()) ?(after = fun _ _ _ _ _ -> ())
    ?(constant_reduction = fun _ _ _ -> None)
    ?(constant_argument = fun _ _ _ -> None) env evd term =
  before env depth path term;
  let reduced result =
    after env depth path term result;
    Some result
  in
  match Constr.kind term with
  | Rel index -> (
    try
      match Environ.lookup_rel index env with
      | RelDecl.LocalDef (_, value, _) -> reduced (Vars.lift index value)
      | RelDecl.LocalAssum _ -> None
    with Not_found ->
      (* Reducer callers may deliberately inspect a subterm below a binder
         without extending the ambient environment: the path itself retains
         that binder.  Such a variable is neutral at this boundary, just as
         a local assumption is; it must not turn a failed reduction attempt
         into an importer anomaly. *)
      None)
  | Const (constant, instance) -> (
    try reduced (Environ.constant_value_in env (constant, instance))
    with Environ.NotEvaluableConst _ -> None)
  | LetIn (_, value, _, body) -> reduced (Vars.subst1 value body)
  | Cast (value, _, _) -> reduced value
  | App _ ->
    let head, args = Constr.decompose_app term in
    (match Constr.kind head with
    | Lambda (annot, domain, body) when Array.length args > 0 ->
      let remaining = Array.sub args 1 (Array.length args - 1) in
      let body = rebuild_app body (Array.map (Vars.lift 1) remaining) in
      reduced (Constr.mkLetIn (annot, args.(0), domain, body))
    | LetIn (annot, value, ty, body) ->
      let body = rebuild_app body (Array.map (Vars.lift 1) args) in
      reduced (Constr.mkLetIn (annot, value, ty, body))
    | Const (constant, instance) -> (
      match constant_reduction constant instance args with
      | Some result -> reduced result
      | None -> (
        match constant_argument constant instance args with
        | Some index when index >= 0 && index < Array.length args ->
          Option.map
            (fun reduced_argument ->
              let reduced_args = Array.copy args in
              reduced_args.(index) <- reduced_argument;
              rebuild_app head reduced_args)
            (reduce_definitional_once ~depth
               ~path:(AppArgument index :: path) ~before ~after
               ~constant_reduction ~constant_argument env evd args.(index))
        | _ -> (
          try
            reduced
              (rebuild_app
                 (Environ.constant_value_in env (constant, instance))
                 args)
          with Environ.NotEvaluableConst _ -> None)))
    | Fix ((recursive_arguments, selected), _) ->
      let recursive_index = recursive_arguments.(selected) in
      if recursive_index >= Array.length args then None
      else (
        match Constr.kind args.(recursive_index) with
        | LetIn (annot, value, ty, body) ->
          let lifted_args = Array.map (Vars.lift 1) args in
          lifted_args.(recursive_index) <- body;
          reduced
            (Constr.mkLetIn
               ( annot,
                 value,
                 ty,
                 rebuild_app (Vars.lift 1 head) lifted_args ))
        | _ ->
        let recursive_head, _ =
          Constr.decompose_app args.(recursive_index)
        in
        (match Constr.kind recursive_head with
        | Construct _ ->
          let contracted =
            match EConstr.kind evd (EConstr.of_constr head) with
            | Fix efix ->
              Reductionops.contract_fix evd efix
              |> EConstr.Unsafe.to_constr
            | _ -> assert false
          in
          reduced (rebuild_app contracted args)
        | _ ->
          let reduced_argument =
            reduce_definitional_once ~depth
              ~path:(AppArgument recursive_index :: path) ~before ~after
              ~constant_reduction ~constant_argument env evd
              args.(recursive_index)
          in
          if
            Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_DEBUG")
            && not (Option.has_some reduced_argument)
          then
            Printf.eprintf
              "[bool-certificate] stuck recursive argument (%s)\n%!"
              (debug_head_shape args.(recursive_index));
          Option.map
            (fun reduced_argument ->
              let reduced_args = Array.copy args in
              reduced_args.(recursive_index) <- reduced_argument;
              rebuild_app head reduced_args)
            reduced_argument))
    | _ -> (
      match
        reduce_definitional_once ~depth ~path:(AppFunction :: path) ~before env
          ~after ~constant_reduction ~constant_argument evd head
      with
      | Some reduced_head -> (
        (* If reducing the function position exposes a beta/zeta redex,
           contract it at the application boundary immediately.  The
           intermediate function term can have a dependent type that is not
           a valid standalone one-hole rewrite, while the complete
           application before and after contraction is well typed. *)
        let exposed_head, exposed_arguments =
          Constr.decompose_app reduced_head
        in
        let all_arguments = Array.append exposed_arguments args in
        match Constr.kind exposed_head with
        | Lambda (annot, domain, body)
          when Array.length all_arguments > 0 ->
          let remaining =
            Array.sub all_arguments 1 (Array.length all_arguments - 1)
          in
          let body = rebuild_app body (Array.map (Vars.lift 1) remaining) in
          reduced
            (Constr.mkLetIn (annot, all_arguments.(0), domain, body))
        | LetIn (annot, value, ty, body) ->
          let body =
            rebuild_app body (Array.map (Vars.lift 1) all_arguments)
          in
          reduced (Constr.mkLetIn (annot, value, ty, body))
        | _ -> Some (rebuild_app reduced_head args))
      | None -> None))
  | Case (info, instance, params, return, invert, scrutinee, branches) -> (
    match Constr.kind scrutinee with
    | LetIn (annot, value, ty, body) ->
      let lifted_case = Vars.lift 1 term in
      let body_case =
        replace_certificate_path lifted_case [ CaseScrutinee ] body
      in
      reduced (Constr.mkLetIn (annot, value, ty, body_case))
    | App _ | Construct _ ->
      let constructor, constructor_args = Constr.decompose_app scrutinee in
      (match Constr.kind constructor with
      | Construct ((ind, index), constructor_instance) ->
        let _, packet = Inductive.lookup_mind_specif env ind in
        let branch_contexts =
          Inductive.expand_branch_contexts
            (Inductive.lookup_mind_specif env ind)
            constructor_instance params branches
        in
        let branch = branches.(index - 1) in
        let branch_term =
          Term.it_mkLambda_or_LetIn (snd branch)
            branch_contexts.(index - 1)
        in
        let real_count = Array.length constructor_args - info.ci_npar in
        if real_count < 0
           || real_count <> packet.mind_consnrealargs.(index - 1)
        then None
        else
          let real_args =
            Array.sub constructor_args info.ci_npar real_count
          in
          reduced (rebuild_app branch_term real_args)
      | _ ->
        Option.map
          (fun reduced_scrutinee ->
            Constr.mkCase
              ( info,
                instance,
                params,
                return,
                invert,
                reduced_scrutinee,
                branches ))
          (reduce_definitional_once ~depth ~path:(CaseScrutinee :: path)
             ~before ~after ~constant_reduction ~constant_argument env evd
             scrutinee))
    | _ -> (
    match
      reduce_definitional_once ~depth ~path:(CaseScrutinee :: path) ~before env
        ~after ~constant_reduction ~constant_argument evd scrutinee
    with
    | Some reduced_scrutinee ->
      Some
        (Constr.mkCase
           ( info,
             instance,
             params,
             return,
             invert,
             reduced_scrutinee,
             branches ))
    | None -> None))
  | Proj (projection, relevance, scrutinee) -> (
    match Constr.kind scrutinee with
    | LetIn (annot, value, ty, body) ->
      reduced
        (Constr.mkLetIn
           (annot, value, ty, Constr.mkProj (projection, relevance, body)))
    | _ ->
    let constructor, constructor_args = Constr.decompose_app scrutinee in
    (match Constr.kind constructor with
    | Construct _ ->
      reduced
        constructor_args.
          (Projection.npars projection + Projection.arg projection)
    | _ -> (
      match
        reduce_definitional_once ~depth ~path:(ProjectionScrutinee :: path)
          ~before ~after ~constant_reduction ~constant_argument env evd
          scrutinee
      with
      | Some reduced_scrutinee ->
        Some (Constr.mkProj (projection, relevance, reduced_scrutinee))
      | None ->
        if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_DEBUG") then
          Printf.eprintf
            "[bool-certificate] stuck projection %s on (%s)\n%!"
            (Projection.to_string projection)
            (debug_head_shape scrutinee);
        None)))
  | _ -> None

let reify_bool ?(proofless = false) ?probe_trace env evd term =
  let debug = Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_DEBUG") in
  let summary_debug =
    Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_SUMMARY")
  in
  let certificate_started = Unix.gettimeofday () in
  let equation_debug =
    Option.has_some (Sys.getenv_opt "ROCQ_LEAN_EQUATION_DEBUG")
  in
  let validate = Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_VALIDATE") in
  let steps = ref 0 in
  let exposures = ref 0 in
  let primitive env depth term =
    let head, args = Constr.decompose_app term in
    let comparison key proof_key operation =
      if ref_matches env head key && Array.length args = 2 then
        let () =
          if debug then
            Printf.eprintf
              "[bool-certificate] demanded %s depth=%d left=(%s) right=(%s)\n%!"
              key depth (debug_head_shape args.(0))
              (debug_head_shape args.(1))
        in
        Option.bind
          (reify_nat ~depth ~unfold:(not proofless) env evd args.(0))
          (fun left ->
            Option.map
              (fun right ->
                let value = operation left.nat_value right.nat_value in
                {
                  bool_term =
                    Constr.mkApp
                      (head, [| left.nat_term; right.nat_term |]);
                  bool_value = value;
                  bool_proof =
                    cert_app proof_key
                      [
                        left.nat_term;
                        right.nat_term;
                        n_int left.nat_value;
                        n_int right.nat_value;
                        left.nat_proof;
                        right.nat_proof;
                      ];
                })
              (reify_nat ~depth ~unfold:(not proofless) env evd args.(1)))
      else None
    in
    let nat_decision () =
      if
        ref_matches env head "lean.Decidable_decide"
        && Array.length args = 2
      then
        let decision_head, decision_args = Constr.decompose_app args.(1) in
        if
          ref_matches env decision_head "lean.Nat_decEq"
          && Array.length decision_args = 2
        then
          Option.bind
            (reify_nat ~depth ~unfold:(not proofless) env evd
               decision_args.(0))
            (fun left ->
              Option.map
                (fun right ->
                  let value = Z.equal left.nat_value right.nat_value in
                  {
                    bool_term = term;
                    bool_value = value;
                    bool_proof =
                      cert_app "lean.NatCertificate_decide_Nat_decEq"
                        [
                          left.nat_term;
                          right.nat_term;
                          n_int left.nat_value;
                          n_int right.nat_value;
                          left.nat_proof;
                          right.nat_proof;
                        ];
                  })
                (reify_nat ~depth ~unfold:(not proofless) env evd
                   decision_args.(1)))
        else None
      else None
    in
    match nat_decision () with
    | Some _ as result -> result
    | None -> (
    match comparison "lean.Nat_beq" "lean.NatCertificate_beq" Z.equal with
    | Some _ as result -> result
    | None -> (
      match comparison "lean.Nat_ble" "lean.NatCertificate_ble" Z.leq with
      | Some _ as result -> result
      | None -> comparison "lean.Nat_blt" "lean.NatCertificate_blt" Z.lt))
  in
  let first_primitive term =
    let rec scan env depth path term =
      match primitive env depth term with
      | Some certificate -> Some (List.rev path, certificate)
      | None -> (
        match Constr.kind term with
        | App _ ->
          let head, args = Constr.decompose_app term in
          (match scan env depth (AppFunction :: path) head with
          | Some _ as result -> result
          | None ->
            let rec argument index =
              if index = Array.length args then None
              else
                match
                  scan env depth (AppArgument index :: path) args.(index)
                with
                | Some _ as result -> result
                | None -> argument (index + 1)
            in
            argument 0)
        | LetIn (annot, value, ty, body) -> (
          match scan env depth (LetValue :: path) value with
          | Some _ as result -> result
          | None -> (
            match scan env depth (LetType :: path) ty with
            | Some _ as result -> result
            | None ->
              let body_env =
                Environ.push_rel (RelDecl.LocalDef (annot, value, ty)) env
              in
              scan body_env (depth + 1) (LetBody :: path) body))
        | Case (_, _, _, _, _, scrutinee, _) ->
          scan env depth (CaseScrutinee :: path) scrutinee
        | Proj (_, _, scrutinee) ->
          scan env depth (ProjectionScrutinee :: path) scrutinee
        | _ -> None)
    in
    scan env 0 [] term
  in
  let _first_demanded_primitive term =
    let rec scan env depth path term =
      match primitive env depth term with
      | Some certificate -> Some (List.rev path, certificate)
      | None -> (
        match Constr.kind term with
        | App _ ->
          let head, args = Constr.decompose_app term in
          (match Constr.kind head with
          | Fix ((recursive_arguments, selected), _)
            when recursive_arguments.(selected) < Array.length args ->
            let index = recursive_arguments.(selected) in
            scan env depth (AppArgument index :: path) args.(index)
          | _ -> scan env depth (AppFunction :: path) head)
        | LetIn (annot, value, ty, body) ->
          let body_env =
            Environ.push_rel (RelDecl.LocalDef (annot, value, ty)) env
          in
          scan body_env (depth + 1) (LetBody :: path) body
        | Case (_, _, _, _, _, scrutinee, _) ->
          scan env depth (CaseScrutinee :: path) scrutinee
        | Proj (_, _, scrutinee) ->
          scan env depth (ProjectionScrutinee :: path) scrutinee
        | _ -> None)
    in
    scan env 0 [] term
  in
  let rec constructor_certificate_under_lets env term =
    match Constr.kind term with
    | LetIn (annot, value, ty, body) ->
      let body_env =
        Environ.push_rel (RelDecl.LocalDef (annot, value, ty)) env
      in
      constructor_certificate_under_lets body_env body
    | _ ->
      Option.map
        (fun value ->
          {
            bool_term = term;
            bool_value = value;
            bool_proof =
              cert_app "lean.BoolCertificate_of_bool" [ coq_bool value ];
          })
        (bool_constructor_value env term)
  in
  let checked_rewrite label term =
    try
      ignore (Typing.type_of env evd (EConstr.of_constr term));
      true
    with _ ->
      if debug then
        Printf.eprintf "[bool-certificate] rejected ill-typed %s rewrite\n%!"
          label;
      false
  in
  let equality_type local_env left right =
    let _ = local_env in
    Constr.mkApp
      ( registered_ref_at_level "lean.Eq" Level.set,
        [| registered_ref "lean.Bool"; left; right |] )
  in
  let shared_bool_contexts = ref [] in
  let shared_bool_states = ref [] in
  let shared_bool_nodes = ref [] in
  let last_shared_bool_state = ref None in
  let dependent_rewrite = ref false in
  let defer_dependent_sharing = ref false in
  let plain_equality_checkpoint = ref false in
  let equality_checkpoints = ref 0 in
  let equality_checkpoint_seconds = ref 0.0 in
  let last_certificate_gc_heap_words = ref (Gc.quick_stat ()).Gc.heap_words in
  let certificate_gc_growth_words =
    256 * 1024 * 1024 / (Sys.word_size / 8)
  in
  let collect_certificate_garbage_if_needed () =
    let stats = Gc.quick_stat () in
    if
      stats.Gc.heap_words - !last_certificate_gc_heap_words
      >= certificate_gc_growth_words
    then begin
      (* Opaque checkpoints release the preceding raw proof graph.  Complete
         one major cycle only after that reclaimable graph has made the heap
         materially grow; do not rescan the live imported environment merely
         because a fixed number of declarations was produced. *)
      Gc.major ();
      last_certificate_gc_heap_words := (Gc.quick_stat ()).Gc.heap_words
    end
  in
  let untransportable_equations = ref [] in
  let refresh_local_env local_env =
    let global_env = Global.env () in
    let global_levels = UGraph.domain (Environ.universes global_env) in
    let local_graph = Environ.universes local_env in
    let local_levels =
      Level.Set.diff (UGraph.domain local_graph) global_levels
    in
    let constraints =
      UGraph.constraints_of_universes local_graph
      |> fst
      |> UnivConstraints.filter (fun (lower, _, upper) ->
           Level.Set.mem lower local_levels
           || Level.Set.mem upper local_levels)
    in
    Environ.push_context_set ~strict:false (local_levels, constraints)
      global_env
    |> Environ.push_rel_context (Environ.rel_context local_env)
  in
  let local_arguments local_env =
    let context = Environ.rel_context local_env in
    context
    |> List.mapi (fun index declaration -> index + 1, declaration)
    |> List.filter_map (fun (index, declaration) ->
         match declaration with
         | RelDecl.LocalAssum _ -> Some (Constr.mkRel index)
         | RelDecl.LocalDef _ -> None)
    |> List.rev |> Array.of_list
  in
  let local_universe_entry ?(terms = []) local_env =
    let global_levels = UGraph.domain (Global.universes ()) in
    let graph_levels =
      Level.Set.diff
        (UGraph.domain (Environ.universes local_env))
        global_levels
    in
    (* A named universe can occur in a translated term without participating
       in any constraint, in which case it is absent from [UGraph.domain].
       Such a level still has to be bound by a polymorphic declaration.  Take
       the union with the levels that occur syntactically in the declaration
       body and type; otherwise Rocq reports an "Undeclared universes" error
       for perfectly valid unconstrained polymorphism. *)
    let term_levels =
      universes_of_constrs_dag terms
      |> fun levels -> Level.Set.diff levels global_levels
    in
    let local_levels = Level.Set.union graph_levels term_levels in
    if Level.Set.is_empty local_levels then
      ( ( UState.Monomorphic_entry Univ.ContextSet.empty,
          UnivNames.empty_binders ),
        UVars.Instance.empty )
    else
      let levels = Level.Set.elements local_levels |> Array.of_list in
      let instance = UVars.Instance.of_array ([||], levels) in
      let constraints =
        UGraph.constraints_of_universes
          (Environ.universes local_env)
        |> fst
        |> UnivConstraints.filter (fun (lower, _, upper) ->
             Level.Set.mem lower local_levels
             || Level.Set.mem upper local_levels)
        |> PConstraints.of_univs
      in
      let names =
        {
          quals = [||];
          univs =
            Array.map
              (fun level ->
                Name (Id.of_string_soft (Level.to_string level)))
              levels;
        }
      in
      let context = UVars.UContext.make names (instance, constraints) in
      ( ( UState.Polymorphic_entry context,
          UnivNames.empty_binders ),
        instance )
  in
  let share_transparent_definition ?types base local_env body =
    let body_type =
      match types with
      | Some types -> types
      | None ->
        Retyping.get_type_of local_env evd (EConstr.of_constr body)
        |> EConstr.Unsafe.to_constr
    in
    (* The declaration being checked may live under a large local context even
       when the shared value is closed.  Abstracting such a value over every
       ambient hypothesis creates spurious parameters, and evaluating the
       resulting sharing node has to beta-reduce all of them again.  In
       particular, proof-producing evaluation used to turn every closed
       checkpoint into a function of the theorem's complete telescope.

       Keep the context when either the value or its type really mentions it;
       the closed case can be declared directly.  This is deliberately only a
       closed-term fast path: dependency-minimising an open context requires
       remapping de Bruijn indices and is a separate operation. *)
    let closed = Vars.closed0 body && Vars.closed0 body_type in
    let context =
      if closed then [] else Environ.rel_context local_env
    in
    let closed_body = Term.it_mkLambda_or_LetIn body context in
    let closed_type = Term.it_mkProd_or_LetIn body_type context in
    let name =
      Namegen.next_global_ident_away (Global.safe_env ())
        (Id.of_string base) Id.Set.empty
    in
    let univs, instance =
      local_universe_entry ~terms:[ closed_body; closed_type ] local_env
    in
    let constant =
      match
        quickdef ~name ~types:(Some closed_type) ~univs closed_body
      with
      | GlobRef.ConstRef constant -> constant
      | _ -> assert false
    in
    if String.equal base "_lean_import_bool_context" then
      shared_bool_contexts := constant :: !shared_bool_contexts;
    if String.equal base "_lean_import_bool_node" then
      shared_bool_nodes := constant :: !shared_bool_nodes;
    let arguments =
      if closed then [||] else local_arguments local_env
    in
    record_generated_universe_instance instance;
    Constr.mkApp
      (Constr.mkConstU (constant, instance), arguments)
  in
  let share_opaque_proof base local_env types proof =
    (* Opaque bodies are checked through a future after their constant handle
       has entered the safe environment.  Several generic zipper strategies
       are intentionally speculative and catch typing failures; letting such
       a failure occur after declaration would leave an unfillable handle.
       Validate the candidate read-only before performing any global update. *)
    let local_env = refresh_local_env local_env in
    ignore
      (Typing.check local_env (Evd.from_env local_env)
         (EConstr.of_constr proof) (EConstr.of_constr types));
    let closed = Vars.closed0 types && Vars.closed0 proof in
    let context =
      if closed then [] else Environ.rel_context local_env
    in
    let closed_type = Term.it_mkProd_or_LetIn types context in
    let closed_proof = Term.it_mkLambda_or_LetIn proof context in
    let name =
      Namegen.next_global_ident_away (Global.safe_env ())
        (Id.of_string base) Id.Set.empty
    in
    let univs, instance =
      local_universe_entry ~terms:[ closed_proof; closed_type ] local_env
    in
    let entry =
      Declare.definition_entry ~opaque:true ~types:closed_type ~univs
        closed_proof
    in
    let scope = Locality.(Global ImportDefaultBehavior) in
    let constant =
      match
        Declare.declare_entry ~name ~scope ~kind:Decls.(IsProof Lemma)
          ~impargs:[] ~uctx:UState.empty entry
      with
      | GlobRef.ConstRef constant -> constant
      | _ -> assert false
    in
    record_generated_universe_instance instance;
    Constr.mkApp
      ( Constr.mkConstU (constant, instance),
        if closed then [||] else local_arguments local_env )
  in
  let certificate_shares = ref 0 in
  let share_certificate certificate =
    incr certificate_shares;
    let types =
      cert_app "lean.BoolCertificate"
        [ certificate.bool_term; coq_bool certificate.bool_value ]
    in
    if debug then
      Printf.eprintf "[bool-certificate] sharing certificate=%d\n%!"
        !certificate_shares;
    let proof =
      share_opaque_proof "_lean_import_bool_certificate" env types
        certificate.bool_proof
    in
    if debug then
      Printf.eprintf "[bool-certificate] shared certificate=%d\n%!"
        !certificate_shares;
    { certificate with bool_proof = proof }
  in
  let reification_cache = current_reification_cache () in
  let constructor_equations =
    reification_cache.cached_constructor_equations
  in
  let unfold_equations = reification_cache.cached_unfold_equations in
  let failed_unfold_equations = ref [] in
  let equation_states = ref [] in
  let blocked_equation_functions =
    reification_cache.cached_blocked_equation_functions
  in
  let equation_functions = ref [] in
  let lifted_equation_heads = ref [] in
  let share_equation_function ?function_type local_env head =
    match
      List.find_opt
        (fun (known_head, _) -> Constr.equal known_head head)
        !lifted_equation_heads
    with
    | Some (_, lifted_function) -> lifted_function
    | None ->
      let function_type =
        match function_type with
        | Some function_type -> function_type
        | None ->
          Retyping.get_type_of local_env (Evd.from_env local_env)
            (EConstr.of_constr head)
          |> EConstr.Unsafe.to_constr
      in
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] declaring lifted equation function\n%!";
      let lifted_function =
        share_transparent_definition ~types:function_type
          "_lean_import_equation_function" local_env head
      in
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] lifted equation function declared\n%!";
      let lifted_head, _ = Constr.decompose_app lifted_function in
      (match Constr.kind lifted_head with
      | Const (constant, _) ->
        equation_functions := constant :: !equation_functions
      | _ -> raise Not_found);
      lifted_equation_heads :=
        (head, lifted_function) :: !lifted_equation_heads;
      lifted_function
  in
  let register_blocked_constant constant instance blocked_argument_count
      blocked_argument =
    if
      not
        (List.exists
           (fun blocked ->
             Constant.UserOrd.equal blocked.blocked_function constant
             && UVars.Instance.equal
                  blocked.blocked_function_instance instance
             && blocked.blocked_argument_count = blocked_argument_count)
           !blocked_equation_functions)
    then
      begin
        blocked_equation_functions :=
          {
            blocked_function = constant;
            blocked_function_instance = instance;
            blocked_argument_count;
            blocked_argument;
          }
          :: !blocked_equation_functions;
        if summary_debug then
          Printf.eprintf
            "[bool-certificate] cached demand function=%s arg=%d/%d\n%!"
            (Constant.to_string constant) blocked_argument
            blocked_argument_count
      end
  in
  let register_blocked_equation_function lifted_function argument_count
      blocked_argument =
    let lifted_head, captured_arguments =
      Constr.decompose_app lifted_function
    in
    match Constr.kind lifted_head with
    | Const (constant, instance) ->
      register_blocked_constant constant instance
        (Array.length captured_arguments + argument_count)
        (Array.length captured_arguments + blocked_argument)
    | _ -> raise Not_found
  in
  let instantiate_constructor_equation ?(check = true) local_env application
      arguments constructor_arguments equation =
    try
      let local_env = refresh_local_env local_env in
      let actual_arguments =
        equation.equation_sources
        |> List.map (function
             | EquationFunctionArgument index -> arguments.(index)
             | EquationConstructorField index ->
               constructor_arguments.
                 (equation.equation_parameter_count + index))
        |> Array.of_list
      in
      let proof = rebuild_app equation.equation_theorem actual_arguments in
      let proof_type =
        if check then
          Retyping.get_type_of local_env (Evd.from_env local_env)
            (EConstr.of_constr proof)
          |> EConstr.Unsafe.to_constr
        else
          Array.fold_left
            (prod_after_apply local_env (Evd.from_env local_env))
            (Retyping.get_type_of local_env (Evd.from_env local_env)
               (EConstr.of_constr equation.equation_theorem)
            |> EConstr.Unsafe.to_constr)
            actual_arguments
      in
      let _, equality_arguments = Constr.decompose_app proof_type in
      if
        Array.length equality_arguments <> 3
        || not (Constr.equal equality_arguments.(1) application)
      then None
      else
        Some
          (equality_arguments.(0), equality_arguments.(2), proof)
    with Out_of_memory as exn -> raise exn | _ -> None
  in
  let make_constructor_equation local_env application function_constant
      function_instance arguments discriminant constructor
      constructor_instance constructor_arguments =
    let stage = ref "initialize" in
    try
      let base_env =
        Environ.pop_rel_context (Environ.nb_rel local_env) local_env
      in
      let symbolic_env = ref base_env in
      let symbolic_type =
        Retyping.get_type_of base_env (Evd.from_env base_env)
          (EConstr.of_constr
             (Constr.mkConstU (function_constant, function_instance)))
        |> EConstr.Unsafe.to_constr |> ref
      in
      let symbolic_arguments = ref [] in
      let context = ref [] in
      let sources = ref [] in
      let add_assumption source annot domain =
        let declaration = RelDecl.LocalAssum (annot, domain) in
        context := declaration :: !context;
        symbolic_env := Environ.push_rel declaration !symbolic_env;
        symbolic_arguments :=
          List.map (Vars.lift 1) !symbolic_arguments;
        sources := !sources @ [ source ]
      in
      let constructor_parameter_count = ref 0 in
      for argument_index = 0 to Array.length arguments - 1 do
        stage := "read function telescope";
        let current_evd = Evd.from_env !symbolic_env in
        let function_type =
          Reductionops.whd_all !symbolic_env current_evd
            (EConstr.of_constr !symbolic_type)
          |> EConstr.Unsafe.to_constr
        in
        let annot, domain, body = Constr.destProd function_type in
        if argument_index <> discriminant then begin
          add_assumption (EquationFunctionArgument argument_index) annot
            domain;
          symbolic_arguments :=
            !symbolic_arguments @ [ Constr.mkRel 1 ];
          symbolic_type := body
        end
        else begin
          stage := "read discriminant inductive";
          let domain =
            Reductionops.whd_all !symbolic_env current_evd
              (EConstr.of_constr domain)
            |> EConstr.Unsafe.to_constr
          in
          let domain_head, domain_arguments = Constr.decompose_app domain in
          let domain_inductive, domain_instance =
            Constr.destInd domain_head
          in
          if
            not
              (Names.Ind.UserOrd.equal domain_inductive
                 (inductive_of_constructor constructor))
          then raise Not_found;
          let mib, mip =
            Inductive.lookup_mind_specif !symbolic_env domain_inductive
          in
          let parameter_count = mib.Declarations.mind_nparams in
          constructor_parameter_count := parameter_count;
          if Array.length domain_arguments < parameter_count then
            raise Not_found;
          if
            mip.Declarations.mind_consnrealdecls.
              (index_of_constructor constructor - 1)
            <> mip.Declarations.mind_consnrealargs.
                 (index_of_constructor constructor - 1)
          then raise Not_found;
          stage := "instantiate constructor parameters";
          let parameters =
            Array.sub domain_arguments 0 parameter_count
            |> Array.to_list |> ref
          in
          let constructor_type =
            Inductive.type_of_constructor
              (constructor, constructor_instance) (mib, mip)
            |> ref
          in
          List.iter
            (fun parameter ->
              let _, _, body =
                Constr.destProd
                  (whd_constr !symbolic_env
                     (Evd.from_env !symbolic_env) !constructor_type)
              in
              constructor_type := Vars.subst1 parameter body)
            !parameters;
          stage := "introduce constructor fields";
          let field_count =
            mip.Declarations.mind_consnrealargs.
              (index_of_constructor constructor - 1)
          in
          let fields = ref [] in
          for field_index = 0 to field_count - 1 do
            let field_annot, field_domain, field_body =
              Constr.destProd
                (whd_constr !symbolic_env
                   (Evd.from_env !symbolic_env) !constructor_type)
            in
            add_assumption (EquationConstructorField field_index)
              field_annot field_domain;
            parameters := List.map (Vars.lift 1) !parameters;
            fields := List.map (Vars.lift 1) !fields @ [ Constr.mkRel 1 ];
            constructor_type := field_body
          done;
          stage := "build symbolic constructor";
          let symbolic_constructor =
            constr_app
              (Constr.mkConstructU (constructor, domain_instance))
              (!parameters @ !fields)
          in
          let symbolic_constructor_type =
            Retyping.get_type_of !symbolic_env
              (Evd.from_env !symbolic_env)
              (EConstr.of_constr symbolic_constructor)
            |> EConstr.Unsafe.to_constr
          in
          let lifted_domain = Vars.lift field_count domain in
          if
            not
              (Reductionops.is_conv !symbolic_env
                 (Evd.from_env !symbolic_env)
                 (EConstr.of_constr symbolic_constructor_type)
                 (EConstr.of_constr lifted_domain))
          then raise Not_found;
          symbolic_arguments :=
            !symbolic_arguments @ [ symbolic_constructor ];
          symbolic_type :=
            Vars.subst1 symbolic_constructor
              (Vars.liftn field_count 2 body)
        end
      done;
      stage := "reduce symbolic application";
      let left =
        constr_app
          (Constr.mkConstU (function_constant, function_instance))
          !symbolic_arguments
      in
      let unfolded =
        constr_app
          (Environ.constant_value_in !symbolic_env
             (function_constant, function_instance))
          !symbolic_arguments
      in
      let right =
        Reductionops.whd_betaiotazeta !symbolic_env
          (Evd.from_env !symbolic_env) (EConstr.of_constr unfolded)
        |> EConstr.Unsafe.to_constr
      in
      if Constr.equal left right then raise Not_found;
      stage := "build checked equation";
      let domain =
        Retyping.get_type_of !symbolic_env (Evd.from_env !symbolic_env)
          (EConstr.of_constr right)
        |> EConstr.Unsafe.to_constr
      in
      let level =
        match atomic_type_level !symbolic_env (Evd.from_env !symbolic_env) right with
        | Some level -> level
        | None -> raise Not_found
      in
      let equality =
        Constr.mkApp
          ( registered_ref_at_level "lean.Eq" level,
            [| domain; left; right |] )
      in
      let reflexivity =
        Constr.mkApp
          ( registered_ref_at_level "lean.definitional_eq" level,
            [| domain; right |] )
      in
      let proof =
        Constr.mkCast (reflexivity, Constr.DEFAULTcast, equality)
      in
      let shared =
        share_opaque_proof "_lean_import_constructor_equation"
          !symbolic_env equality proof
      in
      let theorem, _ = Constr.decompose_app shared in
      let equation =
        {
          equation_function = function_constant;
          equation_function_instance = function_instance;
          equation_argument_count = Array.length arguments;
          equation_discriminant = discriminant;
          equation_constructor = constructor;
          equation_parameter_count = !constructor_parameter_count;
          equation_sources = !sources;
          equation_theorem = theorem;
        }
      in
      (* Reaching this constructor branch confirms the same demand analysis
         used by [make_unfold_equation]: the function must inspect this
         discriminator before the branch equation can fire.  Persist that
         focus even when the actual argument was already a constructor, so
         later open calls reduce only the demanded argument. *)
      register_blocked_constant function_constant function_instance
        (Array.length arguments) discriminant;
      constructor_equations := equation :: !constructor_equations;
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] generated constructor equation %s arg=%d ctor=%d binders=%d\n%!"
          (Constant.to_string function_constant) discriminant
          (index_of_constructor constructor) (List.length !sources);
      instantiate_constructor_equation local_env application arguments
        constructor_arguments equation
    with
    | Out_of_memory as exn -> raise exn
    | exn ->
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] constructor equation rejected stage=%s (%s)\n%!"
          !stage (Printexc.to_string exn);
      None
  in
  let instantiate_unfold_equation ?(check = true) local_env application
      arguments equation =
    try
      let local_env = refresh_local_env local_env in
      let proof = rebuild_app equation.unfold_theorem arguments in
      let proof_type =
        if check then
          Retyping.get_type_of local_env (Evd.from_env local_env)
            (EConstr.of_constr proof)
          |> EConstr.Unsafe.to_constr
        else
          Array.fold_left
            (prod_after_apply local_env (Evd.from_env local_env))
            (Retyping.get_type_of local_env (Evd.from_env local_env)
               (EConstr.of_constr equation.unfold_theorem)
            |> EConstr.Unsafe.to_constr)
            arguments
      in
      let _, equality_arguments = Constr.decompose_app proof_type in
      if Array.length equality_arguments <> 3 then begin
        if equation_debug then
          Printf.eprintf
            "[bool-certificate] unfold instance has equality arity %d\n%!"
            (Array.length equality_arguments);
        None
      end
      else if not (Constr.equal equality_arguments.(1) application) then begin
        if equation_debug then
          Printf.eprintf
            "[bool-certificate] unfold instance left mismatch expected=(%s) actual=(%s)\n%!"
            (debug_head_shape application)
            (debug_head_shape equality_arguments.(1));
        None
      end
      else
        Some
          (equality_arguments.(0), equality_arguments.(2), proof)
    with
    | Out_of_memory as exn -> raise exn
    | exn ->
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] unfold instance rejected (%s)\n%!"
          (Printexc.to_string exn);
      None
  in
  let make_unfold_equation ?(demand_only = false) local_env application
      function_constant function_instance arguments =
    let stage = ref "initialize symbolic unfold" in
    let exception Focused_result of
      (Constr.t * Constr.t * Constr.t) option in
    try
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] trying unfold equation %s args=%d\n%!"
          (Constant.to_string function_constant) (Array.length arguments);
      let base_env =
        Environ.pop_rel_context (Environ.nb_rel local_env) local_env
      in
      let symbolic_env = ref base_env in
      let symbolic_type =
        Retyping.get_type_of base_env (Evd.from_env base_env)
          (EConstr.of_constr
             (Constr.mkConstU (function_constant, function_instance)))
        |> EConstr.Unsafe.to_constr |> ref
      in
      let symbolic_arguments = ref [] in
      for _ = 0 to Array.length arguments - 1 do
        stage := "build symbolic unfold telescope";
        let function_type =
          Reductionops.whd_all !symbolic_env (Evd.from_env !symbolic_env)
            (EConstr.of_constr !symbolic_type)
          |> EConstr.Unsafe.to_constr
        in
        let annot, domain, body = Constr.destProd function_type in
        let declaration = RelDecl.LocalAssum (annot, domain) in
        symbolic_env := Environ.push_rel declaration !symbolic_env;
        symbolic_arguments :=
          List.map (Vars.lift 1) !symbolic_arguments @ [ Constr.mkRel 1 ];
        symbolic_type := body
      done;
      stage := "weak-head reduce symbolic unfold";
      let left =
        constr_app
          (Constr.mkConstU (function_constant, function_instance))
          !symbolic_arguments
      in
      let unfolded =
        constr_app
          (Environ.constant_value_in !symbolic_env
             (function_constant, function_instance))
          !symbolic_arguments
      in
      let is_shared_bool_state =
        List.exists
          (fun known ->
            Environ.QConstant.equal !symbolic_env known function_constant)
          !shared_bool_states
      in
      let is_generated_equation_state =
        List.exists
          (fun (known_constant, known_instance) ->
            Constant.UserOrd.equal known_constant function_constant
            && UVars.Instance.equal known_instance function_instance)
          !equation_states
      in
      let is_equation_function =
        List.exists
          (fun known ->
            Environ.QConstant.equal !symbolic_env known
              function_constant)
          !equation_functions
      in
      let is_bounded_state =
        is_shared_bool_state || is_generated_equation_state
        || is_equation_function
      in
      (* Start from the folded function body.  In particular, do not ask
         Rocq's conversion engine to weak-head normalize an arbitrary Lean
         definition merely to discover which argument it inspects. *)
      let raw_right = unfolded in
      stage := "locate demanded symbolic argument";
      let exception Demanded_rel of int * certificate_path_step list in
      let rec locate_demanded fuel candidate =
        if fuel = 0 then begin
          if equation_debug then
            Printf.eprintf
              "[bool-certificate] symbolic demand probe exhausted on (%s)\n%!"
              (debug_head_shape candidate);
          `Suspended candidate
        end
        else try
          match
            reduce_definitional_once
              ~before:(fun _ _ path candidate ->
                match Constr.kind candidate with
                | Rel index -> raise (Demanded_rel (index, path))
                | _ -> ())
              !symbolic_env (Evd.from_env !symbolic_env) candidate
          with
          | Some reduced -> locate_demanded (fuel - 1) reduced
          | None ->
            let head, _ = Constr.decompose_app candidate in
            (match Constr.kind head with
            | Construct _ -> `Constructor candidate
            | _ ->
              if equation_debug then
                Printf.eprintf
                  "[bool-certificate] symbolic demand probe stuck on (%s)\n%!"
                  (debug_head_shape candidate);
              raise Not_found)
        with
        | Demanded_rel (index, path) -> `Blocked (candidate, index, path)
      in
      let probe_fuel = if is_bounded_state then 8 else 64 in
      let raw_right, blocking_rel, blocking_path, needs_shared_state,
          stop_reason =
        match locate_demanded probe_fuel raw_right with
        | `Blocked (candidate, index, path) ->
          candidate, Some index, path, true, "argument"
        | `Constructor candidate ->
          candidate, None, [], false, "constructor"
        | `Suspended candidate -> candidate, None, [], true, "fuel"
      in
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] symbolic unfold %s stopped at %s rel=%s state=(%s)\n%!"
          (Constant.to_string function_constant)
          stop_reason
          (match blocking_rel with
          | Some index -> string_of_int index
          | None -> "none")
          (debug_head_shape raw_right);
      let blocking_argument =
        Option.map
          (fun index -> Array.length arguments - index)
          blocking_rel
      in
      let valid_blocking_argument =
        match blocking_argument with
        | Some blocked_argument
          when blocked_argument >= 0
               && blocked_argument < Array.length arguments
               &&
               (* A case or projection can itself occur in function position,
                  for example when an eliminator result is immediately
                  applied.  The symbolic variable is still demanded as the
                  scrutinee in that situation.  Exclude only a genuinely
                  higher-order demand where the path enters a function frame
                  without ever reaching an eliminator scrutinee. *)
               ( not
                   (List.exists
                      (function AppFunction -> true | _ -> false)
                      blocking_path)
               || List.exists
                    (function
                      | CaseScrutinee | ProjectionScrutinee -> true
                      | _ -> false)
                    blocking_path ) ->
          Some blocked_argument
        | _ -> None
      in
      (* Demand discovery is computational metadata, not a certificate.
         Probe mode may retain this rollback-aware focus information, but it
         must stop before constructor/unfold equations or helper constants are
         declared. *)
      if demand_only then begin
        if not is_bounded_state then
          Option.iter
            (fun blocked_argument ->
              register_blocked_constant function_constant function_instance
                (Array.length arguments) blocked_argument)
            valid_blocking_argument;
        raise (Focused_result None)
      end;
      (* For an ordinary imported constant, symbolic reduction is only a
         demand analysis.  Keep the actual call folded and let the evaluator
         reduce just the demanded argument.  Once that argument is a
         constructor, [make_constructor_equation] emits the checked branch
         equation.  Generated evaluator nodes retain the state-equation path
         below because their blocking variable can be higher-order. *)
      if not is_bounded_state then begin
        match valid_blocking_argument with
        | Some blocked_argument ->
            let constructor_head, constructor_arguments =
              Constr.decompose_app arguments.(blocked_argument)
            in
            (match Constr.kind constructor_head with
            | Construct (constructor, constructor_instance) ->
              raise
                (Focused_result
                   (make_constructor_equation local_env application
                      function_constant function_instance arguments
                      blocked_argument constructor constructor_instance
                      constructor_arguments))
            | _ ->
              register_blocked_constant function_constant function_instance
                (Array.length arguments) blocked_argument;
              if equation_debug then
                Printf.eprintf
                  "[bool-certificate] registered demanded argument %s arg=%d/%d\n%!"
                  (Constant.to_string function_constant) blocked_argument
                  (Array.length arguments);
              raise (Focused_result None))
        | None when String.equal stop_reason "constructor" -> ()
        | _ -> raise (Focused_result None)
      end;
      if String.equal stop_reason "fuel" then
        raise (Focused_result None);
      let right =
        if String.equal stop_reason "fixpoint" then begin
          let raw_head, raw_arguments =
            Constr.decompose_app raw_right
          in
          match Constr.kind raw_head with
          | Fix
              ( (recursive_arguments, selected),
                (_, function_types, _) )
            when recursive_arguments.(selected)
                 < Array.length raw_arguments ->
            stage := "lift suspended fixpoint";
            let lifted_function =
              share_equation_function
                ~function_type:function_types.(selected)
                !symbolic_env raw_head
            in
            register_blocked_equation_function lifted_function
              (Array.length raw_arguments)
              recursive_arguments.(selected);
            if equation_debug then
              Printf.eprintf
                "[bool-certificate] lifted fixpoint focus registered\n%!";
            let lifted_head, captured_arguments =
              Constr.decompose_app lifted_function
            in
            let right =
              rebuild_app lifted_head
                (Array.append captured_arguments raw_arguments)
            in
            if equation_debug then
              Printf.eprintf
                "[bool-certificate] lifted fixpoint application built\n%!";
            right
          | _ -> raise Not_found
        end
        else if not needs_shared_state then raw_right
        else begin
          (match blocking_argument with
          | Some blocking_argument
            when
              blocking_argument < 0
              || blocking_argument >= Array.length arguments ->
            raise Not_found
          | _ -> ());
          stage := "share symbolic unfold state";
          let raw_type =
            Retyping.get_type_of !symbolic_env (Evd.from_env !symbolic_env)
              (EConstr.of_constr raw_right)
            |> EConstr.Unsafe.to_constr
          in
          let right =
            share_transparent_definition ~types:raw_type
              "_lean_import_equation_state" !symbolic_env raw_right
          in
          let right_head, _ = Constr.decompose_app right in
          let blocked_function, blocked_instance =
            Constr.destConst right_head
          in
          equation_states :=
            (blocked_function, blocked_instance) :: !equation_states;
          equation_functions := blocked_function :: !equation_functions;
          (match blocking_argument with
          | None -> ()
          | Some blocked_argument ->
            blocked_equation_functions :=
              {
                blocked_function;
                blocked_function_instance = blocked_instance;
                blocked_argument_count = Array.length arguments;
                blocked_argument;
              }
              :: !blocked_equation_functions);
          right
        end
      in
      let symbolic_env = refresh_local_env !symbolic_env in
      stage := "check symbolic unfold equation";
      let domain = !symbolic_type in
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] symbolic unfold result type selected\n%!";
      let level =
        let current_evd = Evd.from_env symbolic_env in
        let sort =
          Retyping.get_type_of symbolic_env current_evd
            (EConstr.of_constr domain)
          |> Reductionops.whd_all symbolic_env current_evd
          |> EConstr.Unsafe.to_constr |> Constr.destSort
        in
        if Sorts.is_sprop sort || Sorts.is_prop sort then raise Not_found
        else
          match Univ.Universe.level (Sorts.univ_of_sort sort) with
          | Some level -> level
          | None -> raise Not_found
      in
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] symbolic unfold result level selected\n%!";
      let equality =
        Constr.mkApp
          ( registered_ref_at_level "lean.Eq" level,
            [| domain; left; right |] )
      in
      let reflexivity =
        Constr.mkApp
          ( registered_ref_at_level "lean.definitional_eq" level,
            [| domain; right |] )
      in
      let proof =
        Constr.mkCast (reflexivity, Constr.DEFAULTcast, equality)
      in
      let shared =
        share_opaque_proof "_lean_import_unfold_equation" symbolic_env
          equality proof
      in
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] symbolic unfold proof checked\n%!";
      let theorem, _ = Constr.decompose_app shared in
      let equation =
        {
          unfold_function = function_constant;
          unfold_function_instance = function_instance;
          unfold_argument_count = Array.length arguments;
          unfold_theorem = theorem;
        }
      in
      unfold_equations := equation :: !unfold_equations;
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] generated unfold equation %s args=%d stop=%s blocked=%s\n%!"
          (Constant.to_string function_constant) (Array.length arguments)
          stop_reason
          (match blocking_argument with
          | Some index -> string_of_int index
          | None -> "none");
      instantiate_unfold_equation local_env application arguments equation
    with
    | Focused_result result -> result
    | Out_of_memory as exn -> raise exn
    | exn ->
      if equation_debug then
        Printf.eprintf
          "[bool-certificate] unfold equation rejected stage=%s (%s)\n%!"
          !stage (Printexc.to_string exn);
      None
  in
  let unfold_equation ?(generate = true) ?(check = true)
      ?(demand_only = false) local_env application function_constant
      function_instance arguments =
    let same_key (constant, instance, argument_count) =
      Constant.UserOrd.equal constant function_constant
      && UVars.Instance.equal instance function_instance
      && argument_count = Array.length arguments
    in
    let cached =
      List.find_opt
        (fun equation ->
          Constant.UserOrd.equal equation.unfold_function function_constant
          && UVars.Instance.equal equation.unfold_function_instance
               function_instance
          && equation.unfold_argument_count = Array.length arguments)
        !unfold_equations
    in
    match cached with
    | Some equation ->
      instantiate_unfold_equation ~check local_env application arguments
        equation
    | None when
        (not generate) || List.exists same_key !failed_unfold_equations ->
      None
    | None ->
      let already_blocked =
        List.exists
          (fun blocked ->
            Constant.UserOrd.equal blocked.blocked_function function_constant
            && UVars.Instance.equal blocked.blocked_function_instance
                 function_instance
            && blocked.blocked_argument_count = Array.length arguments)
          !blocked_equation_functions
      in
      if already_blocked then None
      else begin
        let result =
          make_unfold_equation ~demand_only local_env application
            function_constant function_instance arguments
        in
        if (not demand_only) && Option.is_empty result then
          failed_unfold_equations :=
            (function_constant, function_instance, Array.length arguments)
            :: !failed_unfold_equations;
        result
      end
  in
  let constructor_equation ?(generate = true) ?(check = true)
      ?(demand_only = false) local_env application =
    let head, arguments = Constr.decompose_app application in
    match Constr.kind head with
    | Const (function_constant, function_instance)
      when
        Array.length arguments > 0
        && not
             (List.exists
                (fun known ->
                  Environ.QConstant.equal local_env known function_constant)
                !shared_bool_states)
        ->
      let is_managed_function =
        List.exists
          (fun known ->
            Environ.QConstant.equal local_env known function_constant)
          !equation_functions
      in
      let demanded_discriminant =
        List.find_map
          (fun blocked ->
            if
              Constant.UserOrd.equal blocked.blocked_function
                function_constant
              && UVars.Instance.equal
                   blocked.blocked_function_instance function_instance
              && blocked.blocked_argument_count = Array.length arguments
            then Some blocked.blocked_argument
            else None)
          !blocked_equation_functions
      in
      let try_discriminant discriminant =
        let constructor_head, constructor_arguments =
          Constr.decompose_app arguments.(discriminant)
        in
        match Constr.kind constructor_head with
        | Construct (constructor, constructor_instance) ->
          if equation_debug then
            Printf.eprintf
              "[bool-certificate] trying constructor equation %s arg=%d ctor=%d\n%!"
              (Constant.to_string function_constant) discriminant
              (index_of_constructor constructor);
          let cached =
            List.find_opt
              (fun equation ->
                Constant.UserOrd.equal equation.equation_function
                  function_constant
                && UVars.Instance.equal
                     equation.equation_function_instance function_instance
                && equation.equation_argument_count = Array.length arguments
                && equation.equation_discriminant = discriminant
                && Names.Construct.UserOrd.equal
                     equation.equation_constructor constructor)
              !constructor_equations
          in
          (match cached with
          | Some equation ->
            instantiate_constructor_equation ~check local_env application
              arguments constructor_arguments equation
          | None when generate && not demand_only ->
            make_constructor_equation local_env application function_constant
              function_instance arguments discriminant constructor
              constructor_instance constructor_arguments
          | None -> None)
        | _ -> None
      in
      (match demanded_discriminant with
      | Some discriminant -> try_discriminant discriminant
      | None when not is_managed_function ->
        unfold_equation ~generate ~check ~demand_only local_env application
          function_constant function_instance arguments
      | None ->
      let rec scan discriminant =
        if discriminant = Array.length arguments then
          unfold_equation ~generate ~check ~demand_only local_env application
            function_constant function_instance arguments
        else
          match try_discriminant discriminant with
          | Some _ as result -> result
          | None -> scan (discriminant + 1)
      in
      scan 0)
    | _ -> None
  in
  let _compact_term ?(depth_limit = 3) ?(under_binders = false) root_env
      term =
    let shareable term =
      match Constr.kind term with
      | App _ | Cast _ | Prod _ | Lambda _ | LetIn _ | Case _ | Proj _
      | Fix _ | CoFix _ | Array _ -> true
      | Rel _ | Var _ | Meta _ | Evar _ | Sort _ | Const _ | Ind _
      | Construct _ | Int _ | Float _ | String _ -> false
    in
    let independent_of_binders binders term =
      let rec check index =
        index > binders || (Vars.noccurn index term && check (index + 1))
      in
      check 1
    in
    let rec compact depth binders allow_share term =
      let should_share =
        allow_share && depth >= depth_limit
        &&
        (binders = 0
        || (under_binders && independent_of_binders binders term))
        && shareable term
      in
      let child_depth = if should_share then 1 else depth + 1 in
      let term =
        match Constr.kind term with
        | App _ ->
          let head, arguments = Constr.decompose_app term in
          (* Sharing a function position separately from its application
             makes every later checkpoint capture the surrounding context
             once more before reapplying the original arguments.  Besides
             obscuring the redex, this causes generated node arities to grow
             without bound.  A complete application is still shared below,
             and its data arguments may be shared independently. *)
          let head = compact child_depth binders false head in
          let arguments =
            Array.map (compact child_depth binders true) arguments
          in
          (match Constr.kind head with
          | App _ when binders = 0 && Array.length arguments > 0 ->
            let local_env = refresh_local_env root_env in
            let head_type =
              Retyping.get_type_of local_env (Evd.from_env local_env)
                (EConstr.of_constr head)
              |> EConstr.Unsafe.to_constr
            in
            Constr.mkLetIn
              ( Context.make_annot Anonymous Sorts.Relevant,
                head,
                head_type,
                rebuild_app (Constr.mkRel 1)
                  (Array.map (Vars.lift 1) arguments) )
          | _ -> rebuild_app head arguments)
        | _ ->
          Constr.map_with_binders
            (fun binders -> binders + 1)
            (fun binders term ->
              compact child_depth binders true term)
            binders term
      in
      if should_share then begin
        let closed_term =
          if binders = 0 then term
          else Vars.liftn (-binders) (binders + 1) term
        in
        let shared =
          share_transparent_definition "_lean_import_bool_node"
            (refresh_local_env root_env) closed_term
        in
        Vars.lift binders shared
      end
      else term
    in
    compact 0 0 true term
  in
  let rec prune_dead_leading_lets term =
    match Constr.kind term with
    | LetIn (annot, value, ty, body) ->
      let body = prune_dead_leading_lets body in
      if Vars.noccurn 1 body then Vars.subst1 value body
      else Constr.mkLetIn (annot, value, ty, body)
    | _ -> term
  in
  let rec _contextual_definitional_equality local_env original reduced path =
    let local_env = refresh_local_env local_env in
    match path, Constr.kind original, Constr.kind reduced with
    | LetBody :: rest,
      LetIn (annot, value, ty, original_body),
      LetIn (_, reduced_value, reduced_ty, reduced_body)
      when value == reduced_value && ty == reduced_ty ->
      let body_env =
        Environ.push_rel (RelDecl.LocalDef (annot, value, ty)) local_env
      in
      Option.map
        (fun body_equality ->
          {
            bool_equality_left =
              Constr.mkLetIn
                (annot, value, ty, body_equality.bool_equality_left);
            bool_equality_right =
              Constr.mkLetIn
                (annot, value, ty, body_equality.bool_equality_right);
            bool_equality_resume =
              Constr.mkLetIn
                (annot, value, ty, body_equality.bool_equality_resume);
            bool_equality_proof =
              Constr.mkLetIn
                (annot, value, ty, body_equality.bool_equality_proof);
          })
        (_contextual_definitional_equality body_env original_body reduced_body
           rest)
    | _ ->
      let rec choose path =
        let try_path () =
          try
            let redex = subterm_at_certificate_path original path in
            let contractum = subterm_at_certificate_path reduced path in
            if debug && !steps >= 129 then
              Printf.eprintf
                "[bool-certificate] candidate boundary step=%d depth=%d redex=(%s) contractum=(%s)\n%!"
                !steps (List.length path) (debug_head_shape redex)
                (debug_head_shape contractum);
            match atomic_type_level local_env evd redex with
            | None -> None
            | Some level ->
              let boundary_evd = Evd.from_env local_env in
              let canonical_boundary_type term =
                Retyping.get_type_of local_env evd (EConstr.of_constr term)
                |> Reductionops.whd_betaiotazeta local_env boundary_evd
                |> EConstr.Unsafe.to_constr
              in
              let domain = canonical_boundary_type redex in
              let contractum_domain =
                Retyping.get_type_of local_env evd
                  (EConstr.of_constr contractum)
                |> Reductionops.whd_betaiotazeta local_env boundary_evd
                |> EConstr.Unsafe.to_constr
              in
              if not (Constr.equal domain contractum_domain) then (
                let left_head = fst (Constr.decompose_app domain) in
                let right_head =
                  fst (Constr.decompose_app contractum_domain)
                in
                let incompatible =
                  match Constr.kind left_head, Constr.kind right_head with
                  | Const (left, _), Const (right, _) ->
                    not (Environ.QConstant.equal local_env left right)
                  | Ind (left, _), Ind (right, _) ->
                    not (Environ.QInd.equal local_env left right)
                  | Sort left, Sort right -> not (Sorts.equal left right)
                  | _ -> false
                in
                if incompatible then (
                  if debug then
                    Printf.eprintf
                      "[bool-certificate] incompatible boundary depth=%d left=(%s) right=(%s)\n%!"
                      (List.length path) (debug_head_shape domain)
                      (debug_head_shape contractum_domain);
                  raise Not_found));
              let context_body =
                replace_certificate_path (Vars.lift 1 original) path
                  (Constr.mkRel 1)
              in
              let context =
                Constr.mkLambda
                  ( Context.make_annot Anonymous Sorts.Relevant,
                    domain,
                    context_body )
              in
              let context =
                let context_type =
                  Constr.mkProd
                    ( Context.make_annot Anonymous Sorts.Relevant,
                      domain,
                      registered_ref "lean.Bool" )
                in
                share_transparent_definition ~types:context_type
                  "_lean_import_bool_context" local_env context
              in
              let refl =
                Constr.mkApp
                  ( registered_ref_at_level "lean.definitional_eq" level,
                    [| domain; contractum |] )
              in
              let refl_type =
                Retyping.get_type_of local_env evd (EConstr.of_constr refl)
                |> EConstr.Unsafe.to_constr
              in
              let equality, arguments = Constr.decompose_app refl_type in
              if Array.length arguments <> 3 then
                CErrors.anomaly Pp.(str "Unexpected equality shape");
              let arguments = Array.copy arguments in
              arguments.(1) <- redex;
              let local_equality =
                Constr.mkCast
                  ( refl,
                    Constr.DEFAULTcast,
                    Constr.mkApp (equality, arguments) )
              in
              let proof =
                Constr.mkApp
                  ( registered_ref_at_level
                      "lean.BoolEquality_replace_def" level,
                    [| domain; context; redex; contractum; local_equality |] )
              in
              let left = Constr.mkApp (context, [| redex |]) in
              let right = Constr.mkApp (context, [| contractum |]) in
              let resume = Vars.subst1 contractum context_body in
              if debug && !steps >= 132 then
                Printf.eprintf
                  "[bool-certificate] definitional boundary step=%d depth=%d redex=(%s) contractum=(%s) type=(%s)\n%!"
                  !steps (List.length path) (debug_head_shape redex)
                  (debug_head_shape contractum) (debug_head_shape domain);
              Some
                {
                  bool_equality_left = left;
                  bool_equality_right = right;
                  bool_equality_resume = resume;
                  bool_equality_proof = proof;
                }
          with _ -> None
        in
        match try_path () with
        | Some _ as equality -> equality
        | None -> (
          match List.rev path with
          | [] -> None
          | _ :: parent ->
            if debug then
              Printf.eprintf
                "[bool-certificate] widening dependent context to depth=%d\n%!"
                (List.length parent);
            choose (List.rev parent))
      in
      choose path
  in
  let homogeneous_equality_type local_env domain left right =
    let level =
      match atomic_type_level local_env evd right with
      | Some level -> level
      | None -> raise Not_found
    in
    let refl =
      Constr.mkApp
        ( registered_ref_at_level "lean.definitional_eq" level,
          [| domain; right |] )
    in
    let refl_type =
      Retyping.get_type_of local_env evd (EConstr.of_constr refl)
      |> EConstr.Unsafe.to_constr
    in
    let equality, arguments = Constr.decompose_app refl_type in
    if Array.length arguments <> 3 then
      CErrors.anomaly Pp.(str "Unexpected equality shape");
    let arguments = Array.copy arguments in
    arguments.(1) <- left;
    Constr.mkApp (equality, arguments)
  in
  let rec local_definitional_equality local_env original reduced path =
    let local_env = refresh_local_env local_env in
    match path, Constr.kind original, Constr.kind reduced with
    | LetBody :: rest,
      LetIn (annot, value, ty, original_body),
      LetIn (_, reduced_value, reduced_ty, reduced_body)
      when value == reduced_value && ty == reduced_ty ->
      let body_env =
        Environ.push_rel (RelDecl.LocalDef (annot, value, ty)) local_env
      in
      local_definitional_equality body_env original_body reduced_body rest
    | _ ->
      try
        let redex = subterm_at_certificate_path original path in
        let contractum = subterm_at_certificate_path reduced path in
        let domain =
          Retyping.get_type_of local_env evd (EConstr.of_constr contractum)
          |> EConstr.Unsafe.to_constr
        in
        let level =
          match atomic_type_level local_env evd contractum with
          | Some level -> level
          | None -> raise Not_found
        in
        let reflexivity =
          Constr.mkApp
            ( registered_ref_at_level "lean.definitional_eq" level,
              [| domain; contractum |] )
        in
        let equality =
          homogeneous_equality_type local_env domain redex contractum
        in
        Some
          ( domain,
            redex,
            contractum,
            Constr.mkCast (reflexivity, Constr.DEFAULTcast, equality) )
      with _ -> None
  in
  let typed_context_equality local_env equality term hole_path =
    let local_env = refresh_local_env local_env in
    let stage = ref "read equality" in
    try
      let equality_ty =
        Retyping.get_type_of local_env evd (EConstr.of_constr equality)
        |> EConstr.Unsafe.to_constr
      in
      let _, arguments = Constr.decompose_app equality_ty in
      if Array.length arguments <> 3 then raise Not_found;
      let domain = arguments.(0) in
      let redex = arguments.(1) in
      let contractum = arguments.(2) in
      stage := "match redex";
      if
        not
          (Constr.equal (subterm_at_certificate_path term hole_path) redex)
      then raise Not_found;
      stage := "type endpoints";
      let rewritten = replace_certificate_path term hole_path contractum in
      let codomain =
        Retyping.get_type_of local_env evd (EConstr.of_constr term)
        |> EConstr.Unsafe.to_constr
      in
      let rewritten_type =
        Retyping.get_type_of local_env evd (EConstr.of_constr rewritten)
        |> EConstr.Unsafe.to_constr
      in
      stage := "compare endpoint types";
      if not (Constr.equal codomain rewritten_type) then raise Not_found;
      stage := "read universe levels";
      let domain_level =
        match atomic_type_level local_env evd redex with
        | Some level -> level
        | None -> raise Not_found
      in
      let codomain_level =
        match atomic_type_level local_env evd term with
        | Some level -> level
        | None -> raise Not_found
      in
      let context_body =
        replace_certificate_path (Vars.lift 1 term) hole_path
          (Constr.mkRel 1)
      in
      let context =
        Constr.mkLambda
          ( Context.make_annot Anonymous Sorts.Relevant,
            domain,
            context_body )
      in
      stage := "build congruence proof";
      let proof =
        Constr.mkApp
          ( registered_ref_at_levels "lean.Equality_replace_def"
              [ domain_level; codomain_level ],
            [|
              domain;
              codomain;
              context;
              redex;
              contractum;
              equality;
            |] )
      in
      let proof =
        Constr.mkCast
          ( proof,
            Constr.DEFAULTcast,
            homogeneous_equality_type local_env codomain term rewritten )
      in
      stage := "check congruence proof";
      ignore (Typing.type_of local_env evd (EConstr.of_constr proof));
      Some (rewritten, proof)
    with exn ->
      if debug then
        Printf.eprintf
          "[bool-certificate] typed boundary rejected path=%d stage=%s (%s)\n%!"
          (List.length hole_path) !stage (Printexc.to_string exn);
      None
  in
  let dependent_app2_hequality local_env equality term hole_path =
    let local_env = refresh_local_env local_env in
    let evd = Evd.from_env local_env in
    let stage = ref "match application frame" in
    try
      let head, application_args = Constr.decompose_app term in
      if
        hole_path <> [ AppArgument 0 ]
        || Array.length application_args <> 2
      then raise Not_found;
      let equality_ty =
        Retyping.get_type_of local_env evd (EConstr.of_constr equality)
        |> EConstr.Unsafe.to_constr
      in
      let _, equality_args = Constr.decompose_app equality_ty in
      if Array.length equality_args <> 3 then raise Not_found;
      let domain = equality_args.(0) in
      let redex = equality_args.(1) in
      let contractum = equality_args.(2) in
      if not (Constr.equal application_args.(0) redex) then raise Not_found;
      stage := "read dependent function telescope";
      let head_type =
        Retyping.get_type_of local_env evd (EConstr.of_constr head)
        |> Reductionops.whd_betaiotazeta local_env evd
        |> EConstr.Unsafe.to_constr
      in
      if debug then
        Printf.eprintf
          "[bool-certificate] dependent application head type=(%s)\n%!"
          (debug_head_shape head_type);
      stage := "read first function domain";
      let first_annot, first_domain, tail = Constr.destProd head_type in
      stage := "read second function domain";
      let tail_env =
        Environ.push_rel
          (RelDecl.LocalAssum (first_annot, first_domain))
          local_env
      in
      let tail =
        Reductionops.whd_betaiotazeta tail_env (Evd.from_env tail_env)
          (EConstr.of_constr tail)
        |> EConstr.Unsafe.to_constr
      in
      let second_annot, second_domain, result_type =
        Constr.destProd tail
      in
      let second_family =
        Constr.mkLambda (first_annot, first_domain, second_domain)
      in
      let result_family =
        Constr.mkLambda
          ( first_annot,
            first_domain,
            Constr.mkLambda (second_annot, second_domain, result_type) )
      in
      stage := "read application universes";
      let domain_level =
        match atomic_type_level local_env evd redex with
        | Some level -> level
        | None -> raise Not_found
      in
      let second_level =
        match atomic_type_level local_env evd application_args.(1) with
        | Some level -> level
        | None -> raise Not_found
      in
      let result_level =
        match atomic_type_level local_env evd term with
        | Some level -> level
        | None -> raise Not_found
      in
      stage := "build dependent argument transport";
      let transported_argument =
        Constr.mkApp
          ( registered_ref_at_levels "lean.Equality_transport"
              [ domain_level; second_level ],
            [|
              domain;
              second_family;
              redex;
              contractum;
              equality;
              application_args.(1);
            |] )
      in
      let transported_right =
        Constr.mkApp (head, [| contractum; transported_argument |])
      in
      let right =
        Constr.mkApp
          (head, [| contractum; application_args.(1) |])
      in
      stage := "build dependent application congruence";
      let proof =
        Constr.mkApp
          ( registered_ref_at_levels "lean.HEquality_app2_replace_def"
              [ domain_level; second_level; result_level ],
            [|
              domain;
              second_family;
              result_family;
              head;
              redex;
              contractum;
              equality;
              application_args.(1);
            |] )
      in
      if debug then
        Printf.eprintf
          "[bool-certificate] dependent application frame transported (%s -> %s)\n%!"
          (debug_head_shape transported_right) (debug_head_shape right);
      dependent_rewrite := true;
      Some (term, right, proof)
    with exn ->
      if debug then
        Printf.eprintf
          "[bool-certificate] dependent application rejected stage=%s (%s)\n%!"
          !stage (Printexc.to_string exn);
      None
  in
  let dependent_context_hequality ?replacement ?replacement_domain local_env
      equality term hole_path =
    let local_env = refresh_local_env local_env in
    let stage = ref "read equality" in
    let progress next =
      stage := next;
      if debug then
        Printf.eprintf "[bool-certificate] dependent boundary: %s\n%!" next
    in
    try
      let redex = subterm_at_certificate_path term hole_path in
      let domain, contractum =
        match replacement with
        | Some contractum ->
          ( (match replacement_domain with
            | Some domain -> domain
            | None ->
              Retyping.get_type_of local_env evd (EConstr.of_constr redex)
              |> EConstr.Unsafe.to_constr),
            contractum )
        | None ->
          let equality_ty =
            Retyping.get_type_of local_env evd (EConstr.of_constr equality)
            |> EConstr.Unsafe.to_constr
          in
          let _, arguments = Constr.decompose_app equality_ty in
          if Array.length arguments <> 3 then raise Not_found;
          if not (Constr.equal redex arguments.(1)) then raise Not_found;
          arguments.(0), arguments.(2)
      in
      progress "match redex";
      progress "read domain universe";
      let domain_level =
        match atomic_type_level local_env evd redex with
        | Some level -> level
        | None -> raise Not_found
      in
      progress "read codomain universe";
      let codomain_level =
        match atomic_type_level local_env evd term with
        | Some level -> level
        | None -> raise Not_found
      in
      progress "build dependent context";
      let annot = Context.make_annot Anonymous Sorts.Relevant in
      let lifted_redex = Vars.lift 1 redex in
      let rec abstract_redex binders candidate =
        if Constr.equal candidate (Vars.lift binders lifted_redex) then
          Constr.mkRel (binders + 1)
        else
          Constr.map_with_binders
            (fun binders -> binders + 1)
            abstract_redex binders candidate
      in
      let context_body =
        abstract_redex 0 (Vars.lift 1 term)
      in
      progress "infer dependent family";
      let term_type =
        Retyping.get_type_of local_env evd (EConstr.of_constr term)
        |> EConstr.Unsafe.to_constr
      in
      let family_body =
        abstract_redex 0 (Vars.lift 1 term_type)
      in
      let family = Constr.mkLambda (annot, domain, family_body) in
      let context = Constr.mkLambda (annot, domain, context_body) in
      let left = term in
      let right = Vars.subst1 contractum context_body in
      let left_type = Vars.subst1 redex family_body in
      let right_type = Vars.subst1 contractum family_body in
      progress "build heterogeneous proof";
      let proof =
        Constr.mkApp
          ( registered_ref_at_levels "lean.HEquality_replace_def"
              [ domain_level; codomain_level ],
            [|
              domain;
              family;
              context;
              redex;
              contractum;
              equality;
            |] )
      in
      let proof_type =
        Constr.mkApp
          ( registered_ref_at_level "lean.HEquality" codomain_level,
            [| left_type; left; right_type; right |] )
      in
      progress "check heterogeneous proof";
      let proof =
        if !defer_dependent_sharing then proof
        else
          share_opaque_proof "_lean_import_dependent_hequality" local_env
            proof_type proof
      in
      progress "checked heterogeneous proof";
      Some (left, right, proof)
    with exn ->
      if debug then
        Printf.eprintf
          "[bool-certificate] dependent boundary rejected path=%d stage=%s (%s)\n%!"
          (List.length hole_path) !stage (Printexc.to_string exn);
      None
  in
  let hequality_to_equality ?(normalize = false) local_env left right proof =
    let local_env = refresh_local_env local_env in
    let evd = Evd.from_env local_env in
    let stage = ref "read endpoint types" in
    try
      let proof_type =
        Retyping.get_type_of local_env evd (EConstr.of_constr proof)
        |> EConstr.Unsafe.to_constr
      in
      let _, proof_arguments = Constr.decompose_app proof_type in
      let proof_domains =
        if
          Array.length proof_arguments = 4
          && Constr.equal proof_arguments.(1) left
          && Constr.equal proof_arguments.(3) right
        then Some (proof_arguments.(0), proof_arguments.(2))
        else None
      in
      let left_domain, right_domain =
        match proof_domains with
        | Some domains -> domains
        | None ->
          ( Retyping.get_type_of local_env evd (EConstr.of_constr left)
            |> EConstr.Unsafe.to_constr,
            Retyping.get_type_of local_env evd (EConstr.of_constr right)
            |> EConstr.Unsafe.to_constr )
      in
      let domain =
        if Constr.equal left_domain right_domain then left_domain
        else if normalize then
          let () =
            stage := "normalize left endpoint type";
            if debug then
              Printf.eprintf "[bool-certificate] closing heterogeneous proof: %s\n%!"
                !stage
          in
          let left_domain =
            Reductionops.whd_betaiotazeta local_env evd
              (EConstr.of_constr left_domain)
            |> EConstr.Unsafe.to_constr
          in
          let () =
            stage := "normalize right endpoint type";
            if debug then
              Printf.eprintf "[bool-certificate] closing heterogeneous proof: %s\n%!"
                !stage
          in
          let right_domain =
            Reductionops.whd_betaiotazeta local_env evd
              (EConstr.of_constr right_domain)
            |> EConstr.Unsafe.to_constr
          in
          if Constr.equal left_domain right_domain then left_domain
          else raise Not_found
        else raise Not_found
      in
      stage := "read endpoint universe";
      let level =
        match atomic_type_level local_env evd left with
        | Some level -> level
        | None -> raise Not_found
      in
      stage := "build equality bridge";
      let equality =
        Constr.mkApp
          ( registered_ref_at_level "lean.HEquality_to_equality" level,
            [| domain; left; right; proof |] )
      in
      stage := "defer equality bridge check";
      if debug && normalize then
        Printf.eprintf "[bool-certificate] closing heterogeneous proof: %s\n%!"
          !stage;
      if debug && normalize then
        Printf.eprintf
          "[bool-certificate] built heterogeneous equality bridge\n%!";
      Some equality
    with exn ->
      if debug && normalize then
        Printf.eprintf
          "[bool-certificate] heterogeneous close rejected stage=%s (%s)\n%!"
          !stage (Printexc.to_string exn);
      None
  in
  let rec typed_localized_bool_rewrite ?replacement ?replacement_domain
      local_env equality term path =
    match path, Constr.kind term with
    | LetBody :: rest, LetIn (annot, value, ty, body) ->
      let body_env =
        Environ.push_rel (RelDecl.LocalDef (annot, value, ty)) local_env
      in
      Option.map
        (fun (left_body, right_body, proof, homogeneous) ->
          let left = Constr.mkLetIn (annot, value, ty, left_body) in
          let right = Constr.mkLetIn (annot, value, ty, right_body) in
          let proof = Constr.mkLetIn (annot, value, ty, proof) in
          if homogeneous then left, right, proof, true
          else
            match hequality_to_equality local_env left right proof with
            | Some equality ->
              if debug then
                Printf.eprintf
                  "[bool-certificate] heterogeneous proof became homogeneous\n%!";
              left, right, equality, true
            | None -> left, right, proof, false)
        (typed_localized_bool_rewrite ?replacement ?replacement_domain
           body_env equality body rest)
    | _ ->
      let full_path = path in
      let direct_equality () =
        if full_path <> [] then None
        else
          try
            let equality_ty =
              Retyping.get_type_of local_env evd
                (EConstr.of_constr equality)
              |> EConstr.Unsafe.to_constr
            in
            let _, arguments = Constr.decompose_app equality_ty in
            if Array.length arguments <> 3 then raise Not_found;
            if not (Constr.equal term arguments.(1)) then raise Not_found;
            Some (arguments.(1), arguments.(2), equality, true)
          with _ -> None
      in
      match direct_equality () with
      | Some _ as result -> result
      | None ->
      let direct_dependent_equality () =
        if
          List.length full_path < 4
          || not
               (List.exists
                  (function
                    | CaseScrutinee | ProjectionScrutinee -> true
                    | _ -> false)
                  full_path)
        then None
        else
          Option.bind
            (dependent_context_hequality ?replacement ?replacement_domain
               local_env equality term full_path)
            (fun (left, right, heterogeneous) ->
              Option.map
                (fun proof ->
                  dependent_rewrite := true;
                  left, right, proof, true)
                (hequality_to_equality local_env left right heterogeneous))
      in
      match direct_dependent_equality () with
      | Some _ as result -> result
      | None ->
      let rec find_boundary path =
        let ancestor = subterm_at_certificate_path term path in
        let hole_path = CList.skipn (List.length path) full_path in
        let lifted =
          match
            dependent_app2_hequality local_env equality ancestor hole_path
          with
          | Some (left, right, heterogeneous) ->
            Option.map
              (fun proof -> right, proof)
              (hequality_to_equality ~normalize:true local_env left right
                 heterogeneous)
          | None ->
            typed_context_equality local_env equality ancestor hole_path
        in
        match lifted with
        | Some (rewritten, proof) ->
          if debug then
            Printf.eprintf
              "[bool-certificate] typed boundary accepted depth=%d hole=%d\n%!"
              (List.length path) (List.length hole_path);
          Some (path, ancestor, rewritten, proof)
        | None -> (
          match List.rev path with
          | [] -> None
          | _ :: parent -> find_boundary (List.rev parent))
      in
      let initial_path =
        match List.rev full_path with
        | [] -> []
        | _ :: parent -> List.rev parent
      in
      (match find_boundary initial_path with
      | None ->
        let heterogeneous =
          match
            dependent_app2_hequality local_env equality term full_path
          with
          | Some _ as result -> result
          | None ->
            dependent_context_hequality ?replacement ?replacement_domain
              local_env equality term full_path
        in
        Option.map
          (fun (left, right, proof) -> left, right, proof, false)
          heterogeneous
      | Some (boundary, _, right, proof) ->
          let rec lift boundary right proof =
            match boundary with
            | [] -> Some (term, right, proof, true)
            | _ ->
              let find_parent candidate =
                let parent_term =
                  subterm_at_certificate_path term candidate
                in
                let hole_path =
                  CList.skipn (List.length candidate) boundary
                in
                let lifted =
                  match
                    dependent_app2_hequality local_env proof parent_term
                      hole_path
                  with
                  | Some (left, right, heterogeneous) ->
                    Option.map
                      (fun equality -> right, equality)
                      (hequality_to_equality ~normalize:true local_env left
                         right heterogeneous)
                  | None ->
                    typed_context_equality local_env proof parent_term
                      hole_path
                in
                match lifted with
                | Some (rewritten_parent, parent_proof) ->
                  if debug then
                    Printf.eprintf
                      "[bool-certificate] typed boundary lifted depth=%d hole=%d\n%!"
                      (List.length candidate) (List.length hole_path);
                  Some (candidate, rewritten_parent, parent_proof)
                | None ->
                  Option.bind
                    (dependent_context_hequality local_env proof parent_term
                       hole_path)
                    (fun (left, right, heterogeneous) ->
                      Option.map
                        (fun equality -> candidate, right, equality)
                        (hequality_to_equality ~normalize:true local_env left
                           right heterogeneous))
              in
              let first_parent =
                match List.rev boundary with
                | [] -> []
                | _ :: parent -> List.rev parent
              in
              (match find_parent first_parent with
              | Some (parent, rewritten_parent, parent_proof) ->
                lift parent rewritten_parent parent_proof
              | None ->
                Option.map
                  (fun (left, right, proof) ->
                    left, right, proof, false)
                  (dependent_context_hequality local_env proof term boundary))
          in
          lift boundary right proof)
  in
  let localized_bool_rewrite ?replacement ?replacement_domain local_env
      equality term path =
    dependent_rewrite := false;
    let close term path =
      let known_endpoint_rewrite =
        match replacement with
        | None -> None
        | Some _ ->
          Option.bind
            (dependent_context_hequality ?replacement ?replacement_domain
               local_env equality term path)
            (fun (left, right, heterogeneous) ->
              Option.map
                (fun proof ->
                  dependent_rewrite := true;
                  left, right, proof)
                (hequality_to_equality local_env left right heterogeneous))
      in
      match known_endpoint_rewrite with
      | Some _ as result -> result
      | None ->
        Option.bind
          (typed_localized_bool_rewrite ?replacement ?replacement_domain
             local_env equality term path)
          (fun (left, right, proof, homogeneous) ->
            if homogeneous then Some (left, right, proof)
            else
              Option.map
                (fun equality -> left, right, equality)
                (hequality_to_equality ~normalize:true local_env left right
                   proof))
    in
    (* Shared contexts are deliberately nondependent functions [A -> Bool].
       Do not send their applications back through the general dependent
       zipper: that can normalize the compact constant to its large lambda
       body and cause a fresh wrapper to be introduced on the next step.
       Instead, descend through consecutive shared applications, obtain one
       checked equality at the actual redex, and lift it back with ordinary
       congruence.  This preserves the compact heads across constructor and
       unfold equations as well as primitive rewrites. *)
    let rec under_shared_context term path =
      let head, arguments = Constr.decompose_app term in
      let shared =
        match Constr.kind head with
        | Const (constant, _) ->
          List.exists
            (fun known -> Environ.QConstant.equal local_env constant known)
            !shared_bool_contexts
        | _ -> false
      in
      let hole_index = Array.length arguments - 1 in
      match shared, path with
      | true, AppArgument index :: rest
        when Array.length arguments > 0 && index = hole_index ->
        let inner =
          let saved = !defer_dependent_sharing in
          defer_dependent_sharing := true;
          match under_shared_context arguments.(hole_index) rest with
          | result ->
            defer_dependent_sharing := saved;
            result
          | exception exn ->
            defer_dependent_sharing := saved;
            raise exn
        in
        Option.bind
          inner
          (fun (inner_left, inner_right, proof) ->
            try
              let shared_env = refresh_local_env local_env in
              let shared_evd = Evd.from_env shared_env in
              let domain =
                Retyping.get_type_of shared_env shared_evd
                  (EConstr.of_constr inner_right)
                |> EConstr.Unsafe.to_constr
              in
              let level =
                match atomic_type_level shared_env shared_evd inner_right with
                | Some level -> level
                | None -> raise Not_found
              in
              let context =
                if hole_index = 0 then head
                else rebuild_app head (Array.sub arguments 0 hole_index)
              in
              let left = Constr.mkApp (context, [| inner_left |]) in
              let right = Constr.mkApp (context, [| inner_right |]) in
              let proof =
                Constr.mkApp
                  ( registered_ref_at_level
                      "lean.BoolEquality_replace_def" level,
                    [|
                      domain;
                      context;
                      inner_left;
                      inner_right;
                      proof;
                    |] )
              in
              let proof_type = equality_type shared_env left right in
              ignore
                (Typing.check shared_env shared_evd (EConstr.of_constr proof)
                   (EConstr.of_constr proof_type));
              let proof =
                share_opaque_proof "_lean_import_bool_segment" shared_env
                  proof_type proof
              in
              Some (left, right, proof)
            with exn ->
              if debug then
                Printf.eprintf
                  "[bool-certificate] shared context congruence rejected args=%d hole=%d (%s)\n%!"
                  (Array.length arguments) hole_index
                  (Printexc.to_string exn);
              close term path)
      | _ -> close term path
    in
    under_shared_context term path
  in
  let _share_bool_equality left right proof =
    let checkpoint_started = Unix.gettimeofday () in
    let source_proof_shape = debug_head_shape proof in
    incr equality_checkpoints;
    collect_certificate_garbage_if_needed ();
    (* A localized equality proof mentions its (often large) Bool endpoints in
       the types of every congruence and transitivity node.  Opaqueness stops
       later unfolding, but storing the unchecked tree verbatim still repeats
       those endpoints many times.  Bind them once with local definitions and
       abstract all exact occurrences in the proof.  The resulting theorem
       has the same type after zeta reduction, while the kernel sees a compact
       proof DAG whose large inputs occur only in the two let values. *)
    let proof_type =
      if !plain_equality_checkpoint then begin
        plain_equality_checkpoint := false;
        equality_type env left right
      end else equality_type env left right
    in
    (* Collect the endpoints of every transitivity node in this chunk.  A
       shared Boolean context hides the large values one level below its
       compact application, so bind those arguments rather than the outer
       applications.  With a multi-edge chunk this is ordinary proof-DAG
       common-subexpression elimination: every intermediate state is checked
       once in the opaque declaration instead of once as each neighbour's
       right endpoint and again as the next neighbour's left endpoint. *)
    let rec collect_endpoints collected candidate =
      let head, arguments = Constr.decompose_app candidate in
      let collected =
        if
          ref_matches env head "lean.BoolEquality_trans"
          && Array.length arguments = 5
        then
          arguments.(0) :: arguments.(1) :: arguments.(2) :: collected
        else collected
      in
      Constr.fold collect_endpoints collected candidate
    in
    let endpoints = collect_endpoints [ right; left ] proof in
    let local_env = refresh_local_env env in
    let local_evd = Evd.from_env local_env in
    let binding_of_endpoint endpoint =
      let head, arguments = Constr.decompose_app endpoint in
      let under_shared_context =
        Array.length arguments > 0
        &&
        match Constr.kind head with
        | Const (constant, _) ->
          List.exists
            (fun known -> Environ.QConstant.equal env constant known)
            !shared_bool_contexts
        | _ -> false
      in
      if under_shared_context then
        let value = arguments.(Array.length arguments - 1) in
        let types =
          Retyping.get_type_of local_env local_evd (EConstr.of_constr value)
          |> EConstr.Unsafe.to_constr
        in
        value, types
      else endpoint, registered_ref "lean.Bool"
    in
    let bindings =
      List.fold_left
        (fun bindings endpoint ->
          let value, types = binding_of_endpoint endpoint in
          if List.exists (fun (known, _) -> Constr.equal known value) bindings
          then bindings
          else bindings @ [ value, types ])
        [] endpoints
    in
    let binding_count = List.length bindings in
    let lifted_bindings =
      List.mapi
        (fun index (value, _) ->
          Vars.lift binding_count value, binding_count - index)
        bindings
    in
    let rec abstract_endpoints binders term =
      match
        List.find_opt
          (fun (value, _) ->
            Constr.equal term (Vars.lift binders value))
          lifted_bindings
      with
      | Some (_, relative) -> Constr.mkRel (binders + relative)
      | None ->
        Constr.map_with_binders
          (fun binders -> binders + 1)
          abstract_endpoints binders term
    in
    let proof = abstract_endpoints 0 (Vars.lift binding_count proof) in
    let proof_type =
      abstract_endpoints 0 (Vars.lift binding_count proof_type)
    in
    let annot = Context.make_annot Anonymous Sorts.Relevant in
    let rec bind_endpoints depth bindings body =
      match bindings with
      | [] -> body
      | (value, types) :: rest ->
        Constr.mkLetIn
          ( annot,
            Vars.lift depth value,
            Vars.lift depth types,
            bind_endpoints (depth + 1) rest body )
    in
    let segment_type = bind_endpoints 0 bindings proof_type in
    let proof = bind_endpoints 0 bindings proof in
    let segment =
      share_opaque_proof "_lean_import_bool_segment" env segment_type proof
    in
    equality_checkpoint_seconds :=
      !equality_checkpoint_seconds
      +. (Unix.gettimeofday () -. checkpoint_started);
    if equation_debug then begin
      let elapsed = Unix.gettimeofday () -. checkpoint_started in
      if elapsed >= 1.0 then
        Printf.eprintf
          "[bool-certificate] slow equality checkpoint=%d seconds=%.3f left=(%s) right=(%s) proof=(%s)\n%!"
          !equality_checkpoints elapsed (debug_head_shape left)
          (debug_head_shape right) source_proof_shape;
      if !equality_checkpoints mod 10 = 0 then
        Printf.eprintf
          "[bool-certificate] equality checkpoints=%d checkpoint-seconds=%.3f\n%!"
          !equality_checkpoints !equality_checkpoint_seconds
    end;
    left, right, segment
  in
  let finish_and_share certificate_origin reduction_origin reductions term
      result =
    if debug then
      Printf.eprintf
        "[bool-certificate] finish reductions=%d origin=(%s) reduction=(%s) term=(%s)\n%!"
        (List.length reductions) (debug_head_shape certificate_origin)
        (debug_head_shape reduction_origin) (debug_head_shape term);
    let _ = reduction_origin, reductions in
    let result =
      if Constr.equal certificate_origin term then result
      else
        {
          bool_term = certificate_origin;
          bool_value = result.bool_value;
          bool_proof =
            cert_app "lean.BoolCertificate_of_eq"
              [
                certificate_origin;
                term;
                coq_bool result.bool_value;
                cert_app "lean.Bool_defeq" [ certificate_origin ];
                result.bool_proof;
              ];
        }
    in
    Some (share_certificate result)
  in
  let rec reify fuel certificate_origin reduction_origin segment_length
      step_equalities term =
    incr steps;
    if debug && (!steps mod 100 = 0 || !steps < 20) then
      Printf.eprintf "[bool-certificate] step=%d fuel=%d\n%!" !steps fuel;
    if fuel = 0 then None
    else
      match constructor_certificate_under_lets env term with
      | Some result ->
        finish_and_share certificate_origin reduction_origin step_equalities
          result.bool_term result
      | None -> (
        match primitive env 0 term with
        | Some result ->
          finish_and_share certificate_origin reduction_origin step_equalities
            term result
        | None ->
          let continue_reduction _path unpruned =
            let reduced = prune_dead_leading_lets unpruned in
            let valid =
              if not validate then true
              else
                try
                  ignore (Typing.type_of env evd (EConstr.of_constr reduced));
                  true
                with _ -> false
            in
            if not valid then (
              Printf.eprintf
                "[bool-certificate] invalid reduction step=%d %s -> %s\n%!"
                !steps (constr_kind_tag term) (constr_kind_tag reduced);
              None)
            else
              let checkpoint () =
                Option.bind
                  (reify (fuel - 1) reduced reduced 0 [] reduced)
                  (fun result ->
                    finish_and_share certificate_origin reduction_origin
                      step_equalities reduced result)
              in
              if not (Constr.equal unpruned reduced) || segment_length >= 7
              then checkpoint ()
              else
                reify (fuel - 1) certificate_origin reduction_origin
                  (segment_length + 1) step_equalities reduced
          in
          let rewrite_compact path value =
            incr exposures;
            if debug && (!exposures < 20 || !exposures mod 100 = 0) then
              Printf.eprintf
                "[bool-certificate] expose=%d nat=%s depth=%d (%s)\n%!"
                !exposures (Z.to_string value) (List.length path)
                (debug_head_shape term);
            let original = subterm_at_certificate_path term path in
            let value_term = n_int value in
            let original_proof =
              cert_app "lean.NatCertificate_of_N" [ value_term ]
            in
            let replacement, replacement_proof =
              if Z.equal value Z.zero then
                ( lean_nat_constructor 1,
                  registered_ref "lean.NatCertificate_zero" )
              else
                let predecessor = Z.pred value in
                let predecessor_term =
                  cert_app "lean.Nat_of_N" [ n_int predecessor ]
                in
                ( Constr.mkApp
                    (lean_nat_constructor 2, [| predecessor_term |]),
                  cert_app "lean.NatCertificate_succ"
                    [
                      predecessor_term;
                      n_int predecessor;
                      cert_app "lean.NatCertificate_of_N"
                        [ n_int predecessor ];
                    ] )
            in
            let rewritten =
              replace_certificate_path term path replacement
            in
            let reduced = prune_dead_leading_lets rewritten in
            Option.bind
              (reify (fuel - 1) reduced reduced 0 [] reduced)
              (fun result ->
                let result_proof =
                  if Constr.equal rewritten reduced then result.bool_proof
                  else
                    Constr.mkCast
                      ( result.bool_proof,
                        Constr.DEFAULTcast,
                        cert_app "lean.BoolCertificate"
                          [ rewritten; coq_bool result.bool_value ] )
                in
                let context_body =
                  replace_certificate_path (Vars.lift 1 term) path
                    (Constr.mkRel 1)
                in
                let context =
                  Constr.mkLambda
                    ( Context.make_annot Anonymous Sorts.Relevant,
                      registered_ref "lean.Nat",
                      context_body )
                in
                finish_and_share certificate_origin reduction_origin
                  step_equalities term
                  {
                    bool_term = term;
                    bool_value = result.bool_value;
                    bool_proof =
                      cert_app "lean.BoolCertificate_replace_nat"
                        [
                          context;
                          original;
                          replacement;
                          value_term;
                          coq_bool result.bool_value;
                          original_proof;
                          replacement_proof;
                          result_proof;
                        ];
                  })
          in
          let rewrite_bool_primitive path original =
            let replacement = lean_bool_constructor original.bool_value in
            let rewritten =
              replace_certificate_path term path replacement
            in
            if validate && not (checked_rewrite "Bool" rewritten) then None
            else
              let reduced = prune_dead_leading_lets rewritten in
              Option.bind
                (reify (fuel - 1) reduced reduced 0 [] reduced)
                (fun result ->
                let result_proof =
                  if Constr.equal rewritten reduced then result.bool_proof
                  else
                    Constr.mkCast
                      ( result.bool_proof,
                        Constr.DEFAULTcast,
                        cert_app "lean.BoolCertificate"
                          [ rewritten; coq_bool result.bool_value ] )
                in
                let context_body =
                  replace_certificate_path (Vars.lift 1 term) path
                    (Constr.mkRel 1)
                in
                let context =
                  Constr.mkLambda
                    ( Context.make_annot Anonymous Sorts.Relevant,
                      registered_ref "lean.Bool",
                      context_body )
                in
                let replacement_proof =
                  cert_app "lean.BoolCertificate_of_bool"
                    [ coq_bool original.bool_value ]
                in
                finish_and_share certificate_origin reduction_origin
                  step_equalities term
                  {
                    bool_term = term;
                    bool_value = result.bool_value;
                    bool_proof =
                      cert_app "lean.BoolCertificate_replace_bool"
                        [
                          context;
                          original.bool_term;
                          replacement;
                          coq_bool original.bool_value;
                          coq_bool result.bool_value;
                          original.bool_proof;
                          replacement_proof;
                          result_proof;
                        ];
                  })
          in
          let reduce_demanded () =
            let exception Primitive of
              certificate_path_step list * bool_certificate
            in
            let reduced_path = ref None in
            try
              match
                reduce_definitional_once
                  ~before:(fun local_env depth path candidate ->
                    match primitive local_env depth candidate with
                    | Some certificate ->
                      raise (Primitive (List.rev path, certificate))
                    | None -> ())
                  ~after:(fun _ _ path _ _ ->
                    reduced_path := Some (List.rev path))
                  env evd term
              with
              | Some reduced ->
                (match !reduced_path with
                | Some path -> `Reduced (path, reduced)
                | None -> `Stuck)
              | None -> `Stuck
            with Primitive (path, certificate) ->
              `Primitive (path, certificate)
          in
          match first_compact_nat_discriminator env evd term with
          | Some (path, value) -> rewrite_compact path value
          | None -> (
            match reduce_demanded () with
            | `Primitive (path, original) ->
              rewrite_bool_primitive path original
            | `Reduced (path, reduced) -> continue_reduction path reduced
            | `Stuck -> (
          match first_primitive term with
          | Some (path, original) -> rewrite_bool_primitive path original
          | None -> (
          match first_reifiable_nat env evd 0 term with
          | Some (path, original) ->
            if debug then
              Printf.eprintf
                "[bool-certificate] nat=%s path=%d\n%!"
                (Z.to_string original.nat_value) (List.length path);
            let canonical = cert_app "lean.Nat_of_N" [ n_int original.nat_value ] in
            let canonical_proof =
              cert_app "lean.NatCertificate_of_N"
                [ n_int original.nat_value ]
            in
            let equality =
              cert_app "lean.NatCertificate_equal"
                [
                  original.nat_term;
                  canonical;
                  n_int original.nat_value;
                  original.nat_proof;
                  canonical_proof;
                ]
            in
            Option.bind
              (localized_bool_rewrite env equality term path)
              (fun (left, rewritten, rewrite_proof) ->
                Option.bind
                  (reify (fuel - 1) rewritten rewritten 0 [] rewritten)
                  (fun result ->
                    finish_and_share certificate_origin reduction_origin
                      step_equalities left
                      {
                        bool_term = left;
                        bool_value = result.bool_value;
                        bool_proof =
                          cert_app "lean.BoolCertificate_of_eq"
                            [
                              left;
                              rewritten;
                              coq_bool result.bool_value;
                              rewrite_proof;
                              result.bool_proof;
                            ];
                      }))
          | None ->
            if debug then
              Printf.eprintf "[bool-certificate] stuck on %s (%s)\n%!"
                (constr_kind_tag term) (debug_head_shape term);
            None
          ))))
  in
  (* A proofless run of the same focused evaluator.  This is not a decision
      procedure and none of its answers enter a certificate: it only avoids
      constructing hundreds of dependent transports for a candidate whose
      demanded discriminator is ultimately symbolic.  A successful probe is
      followed by the ordinary proof-producing evaluator from the original
      term, so every accepted result remains kernel checked. *)
  let probe_forward original =
    let local_env = refresh_local_env env in
    let local_evd = Evd.from_env local_env in
    let exception Rewrite of
      certificate_path_step list * Constr.t * bool_probe_rewrite option in
    let transitions = ref [] in
    let probe_exhausted = ref false in
    let slow_heads =
      (current_reification_cache ()).cached_slow_bool_heads
    in
    let probe_head =
      let head, arguments = Constr.decompose_app original in
      match Constr.kind head with
      | Const (constant, instance) ->
        Some (constant, instance, Array.length arguments)
      | _ -> None
    in
    let same_head (left_constant, left_instance, left_arity)
        (right_constant, right_instance, right_arity) =
      left_arity = right_arity
      && Constant.UserOrd.equal left_constant right_constant
      && UVars.Instance.equal left_instance right_instance
    in
    let probe_budget =
      match probe_head with
      | Some head when List.exists (same_head head) !slow_heads -> 256
      | Some _ | None -> 1_024
    in
    let append_transition transition =
      transitions := transition :: !transitions
    in
    let record_definitional current next path =
      append_transition (BoolProbeDefinitional (current, next, path));
      next
    in
    let record_boolean current next path certificate =
      append_transition (BoolProbeBoolean (current, next, path, certificate));
      next
    in
    let record_equation current next path equality =
      append_transition (BoolProbeEquation (current, next, path, equality));
      next
    in
    let record_compact_nat current next path value =
      append_transition (BoolProbeCompactNat (current, next, path, value));
      next
    in
    let record_nat current next path certificate =
      append_transition (BoolProbeNat (current, next, path, certificate));
      next
    in
    let record_int current next path certificate =
      append_transition (BoolProbeInt (current, next, path, certificate));
      next
    in
    let finish_trace residual =
      {
        bool_probe_residual = residual;
        bool_probe_transitions = List.rev !transitions;
        bool_probe_exhausted = !probe_exhausted;
      }
    in
    let compact_nat value =
      if Z.equal value Z.zero then lean_nat_constructor 1
      else
        Constr.mkApp
          ( lean_nat_constructor 2,
            [| cert_app "lean.Nat_of_N" [ n_int (Z.pred value) ] |] )
    in
    let compact_int value =
      if Z.geq value Z.zero then
        Constr.mkApp
          ( lean_int_constructor 1,
            [| cert_app "lean.Nat_of_N" [ n_int value ] |] )
      else
        Constr.mkApp
          ( lean_int_constructor 2,
            [|
              cert_app "lean.Nat_of_N"
                [ n_int (Z.pred (Z.neg value)) ];
            |] )
    in
    let reported_demand = ref false in
    let probe_steps = ref 0 in
    let normalize_administrative term =
      Reductionops.whd_betaiotazeta local_env local_evd
        (EConstr.of_constr term)
      |> EConstr.Unsafe.to_constr
    in
    let normalize_administrative_at term path =
      try
        let contractum = subterm_at_certificate_path term path in
        let normalized = normalize_administrative contractum in
        if Constr.equal contractum normalized then term
        else replace_certificate_path term path normalized
      with _ -> term
    in
    let constant_argument constant instance arguments =
      match
        List.find_map
          (fun blocked ->
            if
              Constant.UserOrd.equal blocked.blocked_function constant
              && UVars.Instance.equal
                   blocked.blocked_function_instance instance
              && blocked.blocked_argument_count = Array.length arguments
              && blocked.blocked_argument >= 0
              && blocked.blocked_argument < Array.length arguments
            then Some blocked.blocked_argument
            else None)
          !blocked_equation_functions
      with
      | None -> None
      | Some index ->
        if summary_debug && not !reported_demand then begin
          reported_demand := true;
          Printf.eprintf
            "[bool-certificate] probe demand function=%s arg=%d/%d\n%!"
            (Constant.to_string constant) index (Array.length arguments)
        end;
        let head, _ = Constr.decompose_app arguments.(index) in
        (match Constr.kind head with
        | Construct _ -> None
        | _ -> Some index)
    in
    let rec evaluate fuel current =
      incr probe_steps;
      if summary_debug && !probe_steps mod 1000 = 0 then
        Printf.eprintf
          "[bool-certificate] probe progress steps=%d transitions=%d elapsed=%.3f current=(%s)\n%!"
          !probe_steps (List.length !transitions)
          (Unix.gettimeofday () -. certificate_started)
          (debug_head_shape current);
      if fuel = 0 then begin
        probe_exhausted := true;
        (match probe_head with
        | Some head when not (List.exists (same_head head) !slow_heads) ->
          slow_heads := head :: !slow_heads
        | Some _ | None -> ());
        `Stuck (finish_trace current)
      end
      else
        match bool_constructor_value env current with
        | Some value -> `Value (value, finish_trace current)
        | None -> (
          match primitive env 0 current with
          | Some certificate ->
            let replacement =
              lean_bool_constructor certificate.bool_value
            in
            let residual =
              record_boolean current replacement [] certificate
            in
            `Value (certificate.bool_value, finish_trace residual)
          | None -> (
            match first_compact_nat_discriminator env evd current with
            | Some (path, value) ->
              let replacement =
                replace_certificate_path current path (compact_nat value)
              in
              evaluate (fuel - 1)
                (record_compact_nat current replacement path value)
            | None -> (
              match first_reifiable_int ~unfold:false env evd 0 current with
              | Some (path, certificate) ->
                let replacement =
                  replace_certificate_path current path
                    (compact_int certificate.int_value)
                in
                evaluate (fuel - 1)
                  (record_int current replacement path certificate)
              | None ->
                let before index_prefix local_env depth path candidate =
                  match primitive local_env depth candidate with
                  | Some certificate ->
                    raise
                      (Rewrite
                         ( index_prefix @ List.rev path,
                           lean_bool_constructor certificate.bool_value,
                           Some (BoolProbeRewriteBoolean certificate) ))
                  | None -> (
                    match
                      constructor_equation ~generate:true ~check:false
                        ~demand_only:true local_env candidate
                    with
                    | Some (_, right, proof) ->
                      raise
                        (Rewrite
                           ( index_prefix @ List.rev path,
                             right,
                             Some (BoolProbeRewriteEquation proof) ))
                    | None -> ())
                in
                let reduced_path = ref None in
                try
                  match
                    reduce_definitional_once ~before:(before [])
                      ~after:(fun _ _ path _ _ ->
                        reduced_path := Some (List.rev path))
                      local_env ~constant_argument local_evd current
                  with
                  | Some reduced ->
                    let path =
                      match !reduced_path with
                      | Some path -> path
                      | None -> []
                    in
                    let reduced =
                      match !reduced_path with
                      | Some path ->
                        normalize_administrative_at reduced path
                      | None -> normalize_administrative reduced
                    in
                    evaluate (fuel - 1)
                      (record_definitional current reduced path)
                  | None -> (
                    match first_primitive current with
                    | Some (path, certificate) ->
                      let replacement =
                        replace_certificate_path current path
                          (lean_bool_constructor certificate.bool_value)
                      in
                      evaluate (fuel - 1)
                        (record_boolean current replacement path certificate)
                    | None -> (
                      match first_reifiable_nat ~unfold:false env evd 0 current with
                      | Some (path, certificate) ->
                        let replacement =
                          replace_certificate_path current path
                            (cert_app "lean.Nat_of_N"
                               [ n_int certificate.nat_value ])
                        in
                        evaluate (fuel - 1)
                          (record_nat current replacement path certificate)
                      | None -> `Stuck (finish_trace current)))
                with Rewrite (path, replacement, certificate) ->
                  let rewritten =
                    replace_certificate_path current path replacement
                  in
                  let next =
                    match certificate with
                    | Some (BoolProbeRewriteBoolean certificate) ->
                      record_boolean current rewritten path certificate
                    | Some (BoolProbeRewriteEquation equality) ->
                      record_equation current rewritten path equality
                    | None -> record_definitional current rewritten path
                  in
                  evaluate (fuel - 1) next)))
    in
    (* This is a speculative normalizer, not the certificate checker.  A
       symbolic computation can have a very large closed prefix before it
       finally reaches a neutral variable.  Return a certified partial
       residual after one bounded quantum; the two-sided caller either meets
       at that residual or continues its structural search. *)
    evaluate probe_budget original
  in
  let reify_forward original =
    let chunk_limit = 1 in
    let refl term = cert_app "lean.Bool_defeq" [ term ] in
    let defeq left right =
      Constr.mkCast
        (refl left, Constr.DEFAULTcast, equality_type env left right)
    in
    let trans left middle right first second =
      cert_app "lean.BoolEquality_trans"
        [ left; middle; right; first; second ]
    in
    let checkpoint segments chunk_origin chunk current =
      incr equality_checkpoints;
      collect_certificate_garbage_if_needed ();
      (chunk_origin, current, chunk) :: segments, current
    in
    let append_contiguous segments chunk_origin chunk chunk_length left right
        proof =
      (* A fresh chunk contains only [refl chunk_origin].  Building
         [trans refl proof] is logically harmless, but it makes the kernel
         reconvert both endpoints of [proof].  Those endpoints can contain a
         large dependent context even though [proof] has already been
         checked.  Keep the first real edge directly; use transitivity only
         once a chunk genuinely contains two edges. *)
      let chunk =
        if chunk_length = 0 && Constr.equal chunk_origin left then proof
        else trans chunk_origin left right chunk proof
      in
      let chunk_length = chunk_length + 1 in
      if chunk_length >= chunk_limit then
        let segments, current =
          checkpoint segments chunk_origin chunk right
        in
        segments, current, refl current, 0, current
      else segments, chunk_origin, chunk, chunk_length, right
    in
    let append_step segments chunk_origin chunk chunk_length current left right
        proof =
      let segments, chunk_origin, chunk, chunk_length, current =
        if Constr.equal current left then
          segments, chunk_origin, chunk, chunk_length, current
        else
          append_contiguous segments chunk_origin chunk chunk_length current
            left (defeq current left)
      in
      append_contiguous segments chunk_origin chunk chunk_length left right
        proof
    in
    let collect_edges segments chunk_origin chunk chunk_length current =
      let add_edge edges endpoint left right proof =
        let edges =
          if Constr.equal endpoint left then
            (left, right, proof) :: edges
          else
            (left, right, proof)
            :: (endpoint, left, defeq endpoint left)
            :: edges
        in
        edges, right
      in
      let edges, endpoint =
        List.fold_left
          (fun (edges, endpoint) (left, right, segment) ->
            add_edge edges endpoint left right segment)
          ([], original) (List.rev segments)
      in
      let edges, endpoint =
        if chunk_length = 0 then edges, endpoint
        else add_edge edges endpoint chunk_origin current chunk
      in
      if not (Constr.equal endpoint current) then raise Not_found;
      Array.of_list (List.map (fun edge -> Some edge) (List.rev edges))
    in
    let finish segments chunk_origin chunk chunk_length current result =
      (* Keep the pending reduction graph mutable.  Once a backwards
         certificate chunk has been sealed opaquely, none of its raw
         endpoints or equality proofs are needed any more.  Dropping them
         here is important: those terms retain the whole evaluator context,
         whereas the opaque constant retained by Rocq is compact. *)
      let edges =
        collect_edges segments chunk_origin chunk chunk_length current
      in
      let transport_certificate left right equality certificate =
        let ordinary_transport () =
          {
            bool_term = left;
            bool_value = certificate.bool_value;
            bool_proof =
              cert_app "lean.BoolCertificate_of_eq"
                [
                  left;
                  right;
                  coq_bool certificate.bool_value;
                  equality;
                  certificate.bool_proof;
                ];
          }
        in
        let replacement_shape equality =
          let head, arguments = Constr.decompose_app equality in
          let level =
            match Constr.kind head with
            | Const (_, instance) ->
              let _, levels = UVars.Instance.to_array instance in
              if Array.length levels = 0 then None else Some levels.(0)
            | _ -> None
          in
          match level with
          | Some level
            when
              ref_matches env head "lean.BoolEquality_replace_def"
              && Array.length arguments = 5 ->
            Some
              ( arguments.(0),
                arguments.(1),
                arguments.(2),
                arguments.(3),
                arguments.(4),
                level )
          | Some level
            when
              ref_matches env head "lean.Equality_replace_def"
              && Array.length arguments = 6 ->
            Some
              ( arguments.(0),
                arguments.(2),
                arguments.(3),
                arguments.(4),
                arguments.(5),
                level )
          | _ -> None
        in
        match replacement_shape equality with
        | Some (domain, context, source, target, local_equality, level) ->
          let contextual_source = Constr.mkApp (context, [| source |]) in
          let contextual_target = Constr.mkApp (context, [| target |]) in
          if
            not (Constr.equal left contextual_source)
            || not (Constr.equal right contextual_target)
          then ordinary_transport ()
          else begin
            let compose_context domain outer inner =
              let annot = anon_annot_for_type env evd domain in
              let inner_value =
                Constr.mkApp (Vars.lift 1 inner, [| Constr.mkRel 1 |])
              in
              Constr.mkLambda
                ( annot,
                  domain,
                  Constr.mkApp (Vars.lift 1 outer, [| inner_value |]) )
            in
            let rec flatten depth domain context source target local_equality
                level =
              match replacement_shape local_equality with
              | Some
                  ( inner_domain,
                    inner_context,
                    inner_source,
                    inner_target,
                    inner_equality,
                    inner_level ) ->
                let expected_source =
                  Constr.mkApp (inner_context, [| inner_source |])
                in
                let expected_target =
                  Constr.mkApp (inner_context, [| inner_target |])
                in
                if
                  Constr.equal source expected_source
                  && Constr.equal target expected_target
                then
                  flatten (depth + 1) inner_domain
                    (compose_context inner_domain context inner_context)
                    inner_source inner_target inner_equality inner_level
                else
                  depth, domain, context, source, target, local_equality,
                  level
              | None ->
                depth, domain, context, source, target, local_equality, level
            in
            let depth, domain, context, source, target, local_equality, level
                =
              flatten 1 domain context source target local_equality level
            in
            if debug then
              Printf.eprintf
                "[bool-certificate] fused contextual certificate transport depth=%d local=(%s)\n%!"
                depth (debug_head_shape local_equality);
            {
              bool_term = left;
              bool_value = certificate.bool_value;
              bool_proof =
                Constr.mkApp
                  ( registered_ref_at_level
                      "lean.BoolCertificate_replace_def" level,
                    [|
                      domain;
                      context;
                      source;
                      target;
                      coq_bool certificate.bool_value;
                      local_equality;
                      certificate.bool_proof;
                    |] );
            }
          end
        | None -> ordinary_transport ()
      in
      (* The value is only known at the end of evaluation.  Build the
         certificate chain backwards from that value instead of first
         composing one enormous equality.  Seal a bounded number of
         sequential transports per opaque declaration: one edge per
         declaration creates excessive global-environment overhead, while a
         transitive equality across distant endpoints makes conversion
         normalize the whole gap at once.  The bounded nested proof checks
         each original edge in sequence and avoids both extremes. *)
      (* Each opaque certificate type retains its complete left endpoint in
         the global environment.  One declaration per edge therefore repeats
         a large Boolean state even though the bodies are opaque.  Two
         sequential transports are still a small conversion problem, while
         reducing this persistent endpoint overhead.  Two is deliberately the
         smallest useful grouping: larger groups can make conversion retain
         several complete dependent contexts at once. *)
      let certificate_chunk_limit = 2 in
      let certificate = ref result in
      let high = ref (Array.length edges) in
      let chunks = ref 0 in
      if debug || summary_debug then
        Printf.eprintf "[bool-certificate] backward edges=%d elapsed=%.3f\n%!"
          (Array.length edges)
          (Unix.gettimeofday () -. certificate_started);
      while !high > 0 do
        let low = max 0 (!high - certificate_chunk_limit) in
        for index = !high - 1 downto low do
          let left, right, equality = Option.get edges.(index) in
          if debug then
            Printf.eprintf
              "[bool-certificate] certificate edge=%d left=(%s) right=(%s) proof=(%s)\n%!"
              index (debug_head_shape left) (debug_head_shape right)
              (debug_head_shape equality);
          if not (Constr.equal (!certificate).bool_term right) then
            raise Not_found;
          certificate :=
            transport_certificate left right equality !certificate
        done;
        certificate := share_certificate !certificate;
        for index = low to !high - 1 do
          edges.(index) <- None
        done;
        incr chunks;
        collect_certificate_garbage_if_needed ();
        high := low
      done;
      if not (Constr.equal (!certificate).bool_term original) then
        raise Not_found;
      if Array.length edges = 0 then
        Some (share_certificate !certificate)
      else Some !certificate
    in
    let finish_normalization segments chunk_origin chunk chunk_length current =
      let edges =
        collect_edges segments chunk_origin chunk chunk_length current
      in
      let edge_count = Array.length edges in
      if debug || summary_debug then
        Printf.eprintf
          "[bool-certificate] residual edges=%d elapsed=%.3f residual=(%s)\n%!"
          edge_count (Unix.gettimeofday () -. certificate_started)
          (debug_head_shape current);
      let segment_limit = 4 in
      let shared_segments = ref [] in
      let low = ref 0 in
      while !low < edge_count do
        let high = min edge_count (!low + segment_limit) in
        let first_left, first_right, first_proof =
          Option.get edges.(!low)
        in
        let segment_right = ref first_right in
        let segment_proof = ref first_proof in
        for index = !low + 1 to high - 1 do
          let left, right, proof = Option.get edges.(index) in
          if not (Constr.equal !segment_right left) then raise Not_found;
          segment_proof :=
            trans first_left left right !segment_proof proof;
          segment_right := right
        done;
        let left, right, proof =
          _share_bool_equality first_left !segment_right !segment_proof
        in
        shared_segments := (left, right, proof) :: !shared_segments;
        for index = !low to high - 1 do
          edges.(index) <- None
        done;
        low := high
      done;
      let shared_segments = List.rev !shared_segments in
      let proof =
        match shared_segments with
        | [] -> refl original
        | (first_left, first_right, first_proof) :: remaining ->
          if not (Constr.equal first_left original) then raise Not_found;
          let right, proof =
            List.fold_left
              (fun (middle, accumulated) (left, right, proof) ->
                if not (Constr.equal middle left) then raise Not_found;
                right, trans original left right accumulated proof)
              (first_right, first_proof) remaining
          in
          if not (Constr.equal right current) then raise Not_found;
          if remaining = [] then proof
          else
            let _, _, proof =
              _share_bool_equality original current proof
            in
            proof
      in
      {
        bool_normalization_source = original;
        bool_normalization_residual = current;
        bool_normalization_proof = proof;
      }
    in
    let rewrite_nat current path original_nat replacement value
        original_proof replacement_proof =
      let equality =
        cert_app "lean.NatCertificate_equal"
          [
            original_nat;
            replacement;
            value;
            original_proof;
            replacement_proof;
          ]
      in
      localized_bool_rewrite env equality current path
    in
    let canonical_int_certificate value =
      if Z.geq value Z.zero then
        let natural = cert_app "lean.Nat_of_N" [ n_int value ] in
        ( Constr.mkApp (lean_int_constructor 1, [| natural |]),
          cert_app "lean.IntCertificate_ofNat"
            [
              natural;
              n_int value;
              cert_app "lean.NatCertificate_of_N" [ n_int value ];
            ] )
      else
        let predecessor = Z.pred (Z.neg value) in
        let natural = cert_app "lean.Nat_of_N" [ n_int predecessor ] in
        ( Constr.mkApp (lean_int_constructor 2, [| natural |]),
          cert_app "lean.IntCertificate_negSucc"
            [
              natural;
              n_int predecessor;
              cert_app "lean.NatCertificate_of_N" [ n_int predecessor ];
            ] )
    in
    let rewrite_int current path certificate =
      let replacement, replacement_proof =
        canonical_int_certificate certificate.int_value
      in
      let equality =
        cert_app "lean.IntCertificate_equal"
          [
            certificate.int_term;
            replacement;
            z_int certificate.int_value;
            certificate.int_proof;
            replacement_proof;
          ]
      in
      localized_bool_rewrite ~replacement
        ~replacement_domain:(registered_ref "lean.Int") env equality current
        path
    in
    let rewrite_compact current path value =
      let original_nat = subterm_at_certificate_path current path in
      let value_term = n_int value in
      let original_proof =
        cert_app "lean.NatCertificate_of_N" [ value_term ]
      in
      let replacement, replacement_proof =
        if Z.equal value Z.zero then
          lean_nat_constructor 1, registered_ref "lean.NatCertificate_zero"
        else
          let predecessor = Z.pred value in
          let predecessor_term =
            cert_app "lean.Nat_of_N" [ n_int predecessor ]
          in
          ( Constr.mkApp
              (lean_nat_constructor 2, [| predecessor_term |]),
            cert_app "lean.NatCertificate_succ"
              [
                predecessor_term;
                n_int predecessor;
                cert_app "lean.NatCertificate_of_N" [ n_int predecessor ];
              ] )
      in
      rewrite_nat current path original_nat replacement value_term
        original_proof replacement_proof
    in
    let rewrite_bool current path certificate =
      let replacement = lean_bool_constructor certificate.bool_value in
      let replacement_proof =
        cert_app "lean.BoolCertificate_of_bool"
          [ coq_bool certificate.bool_value ]
      in
      let equality =
        cert_app "lean.BoolCertificate_equal"
          [
            certificate.bool_term;
            replacement;
            coq_bool certificate.bool_value;
            certificate.bool_proof;
            replacement_proof;
          ]
      in
      localized_bool_rewrite env equality current path
    in
    let reduce_demanded current =
      let current_env = refresh_local_env env in
      let current_evd = Evd.from_env current_env in
      let isolate_reduction = ref false in
      let normalize_contractum_at_path term path =
        try
          let contractum = subterm_at_certificate_path term path in
          let normalized =
            EConstr.of_constr contractum
            |> Reductionops.whd_betaiotazeta current_env current_evd
            |> EConstr.Unsafe.to_constr
            |> normalize_sprop_type_wrappers current_env current_evd
          in
          if Constr.equal contractum normalized then term
          else replace_certificate_path term path normalized
        with _ -> term
      in
      let reduce_equation_state local_env constant instance arguments =
        if
          List.exists
            (fun (known_constant, known_instance) ->
              Constant.UserOrd.equal known_constant constant
              && UVars.Instance.equal known_instance instance)
            !equation_states
        then
          try
            Some
              (beta_apply
                 (Environ.constant_value_in local_env
                    (constant, instance))
                 arguments)
          with Environ.NotEvaluableConst _ -> None
        else None
      in
      let constant_reduction constant instance arguments =
        match
          reduce_equation_state current_env constant instance arguments
        with
        | Some _ as result -> result
        | None ->
          if
            List.exists
              (fun shared ->
                Environ.QConstant.equal current_env constant shared)
              !shared_bool_nodes
          then
            try
              isolate_reduction := true;
              if equation_debug then
                Printf.eprintf
                  "[bool-certificate] atomically unwrap shared node %s args=%d\n%!"
                  (Constant.to_string constant) (Array.length arguments);
              Some
                (beta_apply
                   (Environ.constant_value_in current_env
                      (constant, instance))
                   arguments)
            with Environ.NotEvaluableConst _ -> None
          else None
      in
      let rec blocked_constant_argument constant instance argument_count =
        function
        | [] -> None
        | blocked :: remaining ->
          if
            Constant.UserOrd.equal blocked.blocked_function constant
            && UVars.Instance.equal blocked.blocked_function_instance
                 instance
            && blocked.blocked_argument_count = argument_count
          then Some blocked.blocked_argument
          else
            blocked_constant_argument constant instance argument_count
              remaining
      in
      let constant_argument constant instance arguments =
        match
          blocked_constant_argument constant instance
            (Array.length arguments) !blocked_equation_functions
        with
        | Some index when index >= 0 && index < Array.length arguments ->
          let head, _ = Constr.decompose_app arguments.(index) in
          (match Constr.kind head with
          | Construct _ -> None
          | _ -> Some index)
        | result -> result
      in
      let exception Primitive of
        certificate_path_step list * bool_certificate
      in
      let exception Compact of certificate_path_step list * Z.t in
      let exception Equation of
        certificate_path_step list * Constr.t * Constr.t * Constr.t
      in
      let definitional_equation local_env left right =
        let local_env = refresh_local_env local_env in
        let local_evd = Evd.from_env local_env in
        let domain =
          Retyping.get_type_of local_env local_evd
            (EConstr.of_constr right)
          |> EConstr.Unsafe.to_constr
        in
        let level =
          match atomic_type_level local_env local_evd right with
          | Some level -> level
          | None -> raise Not_found
        in
        let equality =
          Constr.mkApp
            ( registered_ref_at_level "lean.Eq" level,
              [| domain; left; right |] )
        in
        let reflexivity =
          Constr.mkApp
            ( registered_ref_at_level "lean.definitional_eq" level,
              [| domain; right |] )
        in
        domain, Constr.mkCast (reflexivity, Constr.DEFAULTcast, equality)
      in
      let trans_equation local_env left middle right first second =
        let local_env = refresh_local_env local_env in
        let local_evd = Evd.from_env local_env in
        let domain =
          Retyping.get_type_of local_env local_evd
            (EConstr.of_constr right)
          |> EConstr.Unsafe.to_constr
        in
        let level =
          match atomic_type_level local_env local_evd right with
          | Some level -> level
          | None -> raise Not_found
        in
        Constr.mkApp
          ( registered_ref_at_level "lean.Equality_trans" level,
            [| domain; left; middle; right; first; second |] )
      in
      let normalize_equation local_env application =
        let chain_steps = ref 0 in
        let rec loop fuel left current accumulated =
          if fuel = 0 then
            Option.map (fun (domain, proof) -> domain, current, proof)
              accumulated
          else
          let local_env = refresh_local_env local_env in
          let step =
            match constructor_equation local_env current with
            | Some _ as step -> step
            | None ->
              let head, arguments = Constr.decompose_app current in
              (match Constr.kind head with
              | Const (constant, instance) ->
                Option.map
                  (fun right ->
                    let domain, proof =
                      definitional_equation local_env current right
                    in
                    domain, right, proof)
                  (reduce_equation_state local_env constant instance
                     arguments)
              | _ -> None)
          in
          match step with
          | None ->
            if equation_debug && Option.has_some accumulated then
              Printf.eprintf
                "[bool-certificate] normalized equation chain steps=%d final=(%s)\n%!"
                !chain_steps (debug_head_shape current);
            Option.map (fun (domain, proof) -> domain, current, proof)
              accumulated
          | Some (domain, right, proof) ->
            (* An instantiated equation often ends in an applied lambda/let
               spine introduced by elaboration.  Contract that administrative
               spine while the equation endpoint is still local.  The same
               equation proof has the normalized endpoint by conversion, so
               no additional transport or trusted reduction rule is needed. *)
            let right =
              EConstr.of_constr right
              |> Reductionops.whd_betaiotazeta local_env
                   (Evd.from_env local_env)
              |> EConstr.Unsafe.to_constr
            in
            if Constr.equal current right then
              Option.map (fun (domain, proof) -> domain, current, proof)
                accumulated
            else
              let () = incr chain_steps in
              let accumulated =
                match accumulated with
                | None -> Some (domain, proof)
                | Some (first_domain, first) ->
                  Some
                    ( first_domain,
                      trans_equation local_env left current right first proof )
              in
              loop (fuel - 1) left right accumulated
        in
        (* Compose a short run of structural equations at the focused
           subterm before lifting it through the surrounding Boolean
           proposition.  The intermediate endpoints are local computation
           states, so this avoids rebuilding and checking the much larger
           dependent context once per constructor layer. *)
        loop 4 application application None
      in
      let before index_prefix local_env depth path candidate =
        match canonical_nat_value local_env evd candidate with
        | Some value ->
          raise (Compact (index_prefix @ List.rev path, value))
        | None ->
        match primitive local_env depth candidate with
        | Some certificate ->
          raise
            (Primitive
               (index_prefix @ List.rev path, certificate))
        | None -> (
          let equation =
            if
              List.exists
                (fun known -> Constr.equal known candidate)
                !untransportable_equations
            then None
            else normalize_equation local_env candidate
          in
          match equation with
          | Some (domain, right, proof) ->
            raise
              (Equation
                 (index_prefix @ List.rev path, domain, right, proof))
          | None -> ())
      in
      let reduce_shared_state () =
        let head, arguments = Constr.decompose_app current in
        match Constr.kind head with
        | Const ((constant, instance) as constant_instance)
          when List.exists
                 (fun shared ->
                   Environ.QConstant.equal current_env constant shared)
                 !shared_bool_states ->
          let body =
            Environ.constant_value_in current_env constant_instance
          in
          Some ([], beta_apply body arguments)
        | _ -> None
      in
      let reduce_shared_argument () =
        let head, arguments = Constr.decompose_app current in
        let is_shared_context =
          match Constr.kind head with
          | Const (constant, _) ->
            List.exists
              (fun shared ->
                Environ.QConstant.equal current_env constant shared)
              !shared_bool_contexts
          | _ -> false
        in
        if not is_shared_context then None
        else
          let rec reduce_argument index =
            if index = Array.length arguments then None
            else
              let reduced_path = ref None in
              match
                reduce_definitional_once
                  ~before:
                    (before [ AppArgument index ])
                  ~after:(fun _ _ path _ _ ->
                    reduced_path := Some (List.rev path))
                  ~constant_reduction
                  ~constant_argument
                  current_env current_evd arguments.(index)
              with
              | Some reduced_argument -> (
                match !reduced_path with
                | None -> reduce_argument (index + 1)
                | Some path ->
                  let reduced_argument =
                    normalize_contractum_at_path reduced_argument path
                  in
                  let rec reduce_argument_burst remaining count candidate =
                    if remaining = 0 || !isolate_reduction then
                      candidate, count
                    else
                      try
                        match
                          reduce_definitional_once
                            ~before:(before [ AppArgument index ])
                            ~constant_reduction ~constant_argument
                            current_env current_evd candidate
                        with
                        | Some next ->
                          reduce_argument_burst (remaining - 1) (count + 1)
                            next
                        | None -> candidate, count
                      with
                      | Compact _ | Primitive _ | Equation _ ->
                        candidate, count
                  in
                  (* Definitional reductions inside a shared Boolean context
                     all have the same compact outer boundary.  Batch a
                     sizeable burst before producing its single checked
                     equality; [before] still stops immediately at every
                     arithmetic primitive or explicit equation. *)
                  let reduced_argument, count =
                    reduce_argument_burst 15 1 reduced_argument
                  in
                  let reduced_arguments = Array.copy arguments in
                  reduced_arguments.(index) <- reduced_argument;
                  Some
                    ( (if count = 1 then AppArgument index :: path
                       else [ AppArgument index ]),
                      Constr.mkApp (head, reduced_arguments) ))
              | None -> reduce_argument (index + 1)
          in
          reduce_argument 0
      in
      let reduced_path = ref None in
      try
        before [] current_env 0 [] current;
        match reduce_shared_state () with
        | Some (path, reduced) ->
          `Reduced (path, reduced, !isolate_reduction)
        | None -> (
        match reduce_shared_argument () with
        | Some (path, reduced) ->
          `Reduced (path, reduced, !isolate_reduction)
        | None -> (
          match
            reduce_definitional_once
              ~before:(before [])
              ~after:(fun _ _ path _ _ ->
                reduced_path := Some (List.rev path))
              ~constant_reduction
              ~constant_argument
              current_env current_evd current
          with
          | Some reduced -> (
            match !reduced_path with
            | Some path ->
              let reduced = normalize_contractum_at_path reduced path in
              let rec reduce_burst remaining count candidate =
                if remaining = 0 || !isolate_reduction then
                  candidate, count
                else
                  try
                    match
                      reduce_definitional_once
                        ~before:(before [])
                        ~constant_reduction ~constant_argument
                        current_env current_evd candidate
                    with
                    | Some next ->
                      reduce_burst (remaining - 1) (count + 1) next
                    | None -> candidate, count
                  with
                  | Compact _ | Primitive _ | Equation _ ->
                    (* Handle the interception against [candidate] after the
                       accumulated definitional equality has been committed;
                       it will fire again on the next evaluator iteration. *)
                    candidate, count
              in
              let reduced, count = reduce_burst 0 1 reduced in
              let path = if count = 1 then path else [] in
              `Reduced (path, reduced, !isolate_reduction)
            | None -> `Stuck)
          | None -> `Stuck))
      with
      | Compact (path, value) -> `Compact (path, value)
      | Primitive (path, certificate) -> `Primitive (path, certificate)
      | Equation (path, domain, right, proof) ->
        `Equation (path, domain, right, proof)
    in
    let rec evaluate fuel segments chunk_origin chunk chunk_length current =
      if fuel = 0 then None
      else
        match bool_constructor_value env current with
        | Some value ->
          Option.map
            (fun certificate -> ReifiedBoolValue certificate)
            (finish segments chunk_origin chunk chunk_length current
               {
                 bool_term = current;
                 bool_value = value;
                 bool_proof =
                   cert_app "lean.BoolCertificate_of_bool" [ coq_bool value ];
               })
        | None -> (
          match primitive env 0 current with
          | Some result ->
            Option.map
              (fun certificate -> ReifiedBoolValue certificate)
              (finish segments chunk_origin chunk chunk_length current result)
          | None -> (
            let continue ?(isolated = false) left right proof =
              let segments, chunk_origin, chunk, chunk_length, current =
                append_step segments chunk_origin chunk chunk_length current
                  left right proof
              in
              let segments, chunk_origin, chunk, chunk_length, current =
                if not isolated then
                  segments, chunk_origin, chunk, chunk_length, current
                else if chunk_length <> 0 then
                  let segments, current =
                    checkpoint segments chunk_origin chunk current
                  in
                  segments, current, refl current, 0, current
                else
                  match !last_shared_bool_state with
                  | Some (known, shared) when known == current ->
                    segments, shared, refl shared, 0, shared
                  | _ ->
                    segments, chunk_origin, chunk, chunk_length, current
              in
              evaluate (fuel - 1) segments chunk_origin chunk chunk_length
                current
            in
            let continue_defeq reduced =
              continue current reduced (refl current)
            in
            let continue_rewrite ?isolated = function
              | Some (left, right, proof) ->
                let isolated =
                  match isolated with
                  | Some isolated -> isolated
                  | None -> !dependent_rewrite
                in
                continue ~isolated left right proof
              | None -> None
            in
            match first_compact_nat_discriminator env evd current with
            | Some (path, value) ->
              incr exposures;
              continue_rewrite ~isolated:true
                (rewrite_compact current path value)
            | None -> (
              match first_reifiable_int env evd 0 current with
              | Some (path, certificate) ->
                if debug then
                  Printf.eprintf
                    "[int-certificate] path=%d value-bits=%d\n%!"
                    (List.length path)
                    (Z.numbits (Z.abs certificate.int_value));
                continue_rewrite ~isolated:true
                  (rewrite_int current path certificate)
              | None -> (
              match reduce_demanded current with
              | `Compact (path, value) ->
                incr exposures;
                continue_rewrite ~isolated:true
                  (rewrite_compact current path value)
              | `Equation (path, domain, right, proof) ->
                if debug || equation_debug then
                  Printf.eprintf
                    "[bool-certificate] constructor equation path=%d right=(%s)\n%!"
                    (List.length path) (debug_head_shape right);
                let right_head, _ = Constr.decompose_app right in
                let exposes_eliminator =
                  match Constr.kind right_head with
                  | Case _ -> true
                  | _ -> false
                in
                let current_head, current_arguments =
                  Constr.decompose_app current
                in
                let under_shared_context =
                  Array.length current_arguments > 0
                  &&
                  match Constr.kind current_head with
                  | Const (constant, _) ->
                    List.exists
                      (fun shared ->
                        Environ.QConstant.equal env constant shared)
                      !shared_bool_contexts
                  | _ -> false
                in
                let rewritten =
                  if under_shared_context then
                    let candidate =
                      replace_certificate_path current path right
                    in
                    if checked_rewrite "shared equation" candidate then
                      Some (current, candidate, defeq current candidate)
                    else None
                  else if exposes_eliminator then None
                  else
                    localized_bool_rewrite ~replacement:right
                      ~replacement_domain:domain env proof current path
                in
                if equation_debug then
                  Printf.eprintf
                    "[bool-certificate] outer equation transport path=%s deferred=%b success=%b\n%!"
                    (string_of_certificate_path path)
                    exposes_eliminator
                    (Option.has_some rewritten);
                (match rewritten with
                | Some _ ->
                  if !dependent_rewrite then
                    plain_equality_checkpoint := true;
                  continue_rewrite rewritten
                | None ->
                  let redex =
                    subterm_at_certificate_path current path
                  in
                  if
                    not
                      (List.exists
                         (fun known -> Constr.equal known redex)
                         !untransportable_equations)
                  then
                    untransportable_equations :=
                      redex :: !untransportable_equations;
                  evaluate (fuel - 1) segments chunk_origin chunk
                    chunk_length current)
              | `Reduced (path, reduced, isolate_reduction) -> (
                if debug then (
                  let redex = subterm_at_certificate_path current path in
                  let contractum = subterm_at_certificate_path reduced path in
                  Printf.eprintf
                    "[bool-certificate] definitional step path=%d[%s] left=(%s) right=(%s) redex=(%s) contractum=(%s)\n%!"
                    (List.length path) (string_of_certificate_path path)
                    (debug_head_shape current)
                    (debug_head_shape reduced) (debug_head_shape redex)
                    (debug_head_shape contractum));
                let already_shared =
                  let head, arguments = Constr.decompose_app current in
                  Array.length arguments > 0
                  &&
                  match Constr.kind head with
                  | Const (constant, _) ->
                    List.exists
                      (fun shared ->
                        Environ.QConstant.equal env constant shared)
                      !shared_bool_contexts
                  | _ -> false
                in
                if already_shared then
                  continue ~isolated:true current reduced
                    (defeq current reduced)
                else
                let known_localized =
                  Option.bind
                    (local_definitional_equality env current reduced path)
                    (fun (domain, _, contractum, equality) ->
                      localized_bool_rewrite ~replacement:contractum
                        ~replacement_domain:domain env equality current path)
                in
                match known_localized with
                | Some (left, right, equality) ->
                  let isolated = isolate_reduction || !dependent_rewrite in
                  continue ~isolated left right equality
                | None ->
                let contextual =
                  _contextual_definitional_equality env current reduced path
                in
                match contextual with
                | Some equality ->
                  continue ~isolated:true equality.bool_equality_left
                    equality.bool_equality_right
                    equality.bool_equality_proof
                | None ->
                  let localized =
                    let equality_path =
                      if
                        List.exists
                          (function AppArgument 0 -> true | _ -> false)
                          path
                      then []
                      else path
                    in
                    Option.bind
                      (local_definitional_equality env current reduced
                         equality_path)
                      (fun (_, _, _, equality) ->
                        localized_bool_rewrite env equality current
                          equality_path)
                  in
                  (match localized with
                  | Some (left, right, equality) ->
                    let isolated =
                      isolate_reduction || !dependent_rewrite
                    in
                    continue ~isolated left right equality
                  | None ->
                    if debug then
                      Printf.eprintf
                        "[bool-certificate] localized definitional proof unavailable\n%!";
                    if isolate_reduction then
                      continue ~isolated:true current reduced (refl current)
                    else continue_defeq reduced))
              | `Primitive (path, certificate) ->
                continue_rewrite (rewrite_bool current path certificate)
              | `Stuck -> (
                match first_primitive current with
                | Some (path, certificate) ->
                  continue_rewrite (rewrite_bool current path certificate)
                | None -> (
                  match first_reifiable_nat env evd 0 current with
                  | Some (path, certificate) ->
                    let canonical =
                      cert_app "lean.Nat_of_N"
                        [ n_int certificate.nat_value ]
                    in
                    let canonical_proof =
                      cert_app "lean.NatCertificate_of_N"
                        [ n_int certificate.nat_value ]
                    in
                    continue_rewrite
                      (rewrite_nat current path certificate.nat_term canonical
                         (n_int certificate.nat_value) certificate.nat_proof
                         canonical_proof)
                  | None ->
                    if debug then
                      Printf.eprintf
                        "[bool-certificate] forward evaluator stuck on %s\n%!"
                        (debug_head_shape current);
                    Some
                      (ReifiedBoolResidual
                         (finish_normalization segments chunk_origin chunk
                            chunk_length current))))))))
    in
    evaluate 100_000 [] original (refl original) 0 original
  in
  let reify_probe_trace trace =
    let transition_left = function
      | BoolProbeDefinitional (left, _, _)
      | BoolProbeEquation (left, _, _, _)
      | BoolProbeBoolean (left, _, _, _)
      | BoolProbeCompactNat (left, _, _, _)
      | BoolProbeNat (left, _, _, _)
      | BoolProbeInt (left, _, _, _) -> left
    in
    let transition_right = function
      | BoolProbeDefinitional (_, right, _)
      | BoolProbeEquation (_, right, _, _)
      | BoolProbeBoolean (_, right, _, _)
      | BoolProbeCompactNat (_, right, _, _)
      | BoolProbeNat (_, right, _, _)
      | BoolProbeInt (_, right, _, _) -> right
    in
    let () =
      let current = ref term in
      List.iter
        (fun transition ->
          if not (Constr.equal !current (transition_left transition)) then
            raise Not_found;
          current := transition_right transition)
        trace.bool_probe_transitions;
      if not (Constr.equal !current trace.bool_probe_residual) then
        raise Not_found
    in
    let local_endpoints left right path =
      let local_left = subterm_at_certificate_path left path in
      let local_right = subterm_at_certificate_path right path in
      if
        not
          (Constr.equal
             (replace_certificate_path right path local_left)
             left)
      then raise Not_found;
      local_left, local_right
    in
    let rec definitional_endpoints left right path =
      try
        let local_left, local_right = local_endpoints left right path in
        local_left, local_right, path
      with Not_found ->
        match List.rev path with
        | [] -> raise Not_found
        | _ :: parent ->
          definitional_endpoints left right (List.rev parent)
    in
    let recipe_of_transition = function
      | BoolProbeDefinitional (left, right, path) ->
        let local_left, local_right, path =
          definitional_endpoints left right path
        in
        BoolProbeDefinitionalRecipe (local_left, local_right, path)
      | BoolProbeEquation (left, right, path, equality) ->
        let local_left, local_right = local_endpoints left right path in
        BoolProbeEquationRecipe (local_left, local_right, path, equality)
      | BoolProbeBoolean (left, right, path, certificate) ->
        let local_left, local_right = local_endpoints left right path in
        BoolProbeBooleanRecipe (local_left, local_right, path, certificate)
      | BoolProbeCompactNat (left, right, path, value) ->
        let local_left, local_right = local_endpoints left right path in
        BoolProbeCompactNatRecipe (local_left, local_right, path, value)
      | BoolProbeNat (left, right, path, certificate) ->
        let local_left, local_right = local_endpoints left right path in
        BoolProbeNatRecipe (local_left, local_right, path, certificate)
      | BoolProbeInt (left, right, path, certificate) ->
        let local_left, local_right = local_endpoints left right path in
        BoolProbeIntRecipe (local_left, local_right, path, certificate)
    in
    let residual = trace.bool_probe_residual in
    let recipes = List.map recipe_of_transition trace.bool_probe_transitions in
    let recipe_path = function
      | BoolProbeDefinitionalRecipe (_, _, path)
      | BoolProbeEquationRecipe (_, _, path, _)
      | BoolProbeBooleanRecipe (_, _, path, _)
      | BoolProbeCompactNatRecipe (_, _, path, _)
      | BoolProbeNatRecipe (_, _, path, _)
      | BoolProbeIntRecipe (_, _, path, _) -> path
    in
    let transition_from_right right recipe =
      let path = recipe_path recipe in
      let local_left, local_right =
        match recipe with
        | BoolProbeDefinitionalRecipe (left, right, _)
        | BoolProbeEquationRecipe (left, right, _, _)
        | BoolProbeBooleanRecipe (left, right, _, _)
        | BoolProbeCompactNatRecipe (left, right, _, _)
        | BoolProbeNatRecipe (left, right, _, _)
        | BoolProbeIntRecipe (left, right, _, _) -> left, right
      in
      if
        not
          (Constr.equal
             (subterm_at_certificate_path right path)
             local_right)
      then raise Not_found;
      let left = replace_certificate_path right path local_left in
      match recipe with
      | BoolProbeDefinitionalRecipe _ ->
        BoolProbeDefinitional (left, right, path)
      | BoolProbeEquationRecipe (_, _, _, equality) ->
        BoolProbeEquation (left, right, path, equality)
      | BoolProbeBooleanRecipe (_, _, _, certificate) ->
        BoolProbeBoolean (left, right, path, certificate)
      | BoolProbeCompactNatRecipe (_, _, _, value) ->
        BoolProbeCompactNat (left, right, path, value)
      | BoolProbeNatRecipe (_, _, _, certificate) ->
        BoolProbeNat (left, right, path, certificate)
      | BoolProbeIntRecipe (_, _, _, certificate) ->
        BoolProbeInt (left, right, path, certificate)
    in
    let transition_from_left left recipe =
      let path = recipe_path recipe in
      let local_left, local_right =
        match recipe with
        | BoolProbeDefinitionalRecipe (left, right, _)
        | BoolProbeEquationRecipe (left, right, _, _)
        | BoolProbeBooleanRecipe (left, right, _, _)
        | BoolProbeCompactNatRecipe (left, right, _, _)
        | BoolProbeNatRecipe (left, right, _, _)
        | BoolProbeIntRecipe (left, right, _, _) -> left, right
      in
      if
        not
          (Constr.equal
             (subterm_at_certificate_path left path)
             local_left)
      then raise Not_found;
      let right = replace_certificate_path left path local_right in
      match recipe with
      | BoolProbeDefinitionalRecipe _ ->
        BoolProbeDefinitional (left, right, path)
      | BoolProbeEquationRecipe (_, _, _, equality) ->
        BoolProbeEquation (left, right, path, equality)
      | BoolProbeBooleanRecipe (_, _, _, certificate) ->
        BoolProbeBoolean (left, right, path, certificate)
      | BoolProbeCompactNatRecipe (_, _, _, value) ->
        BoolProbeCompactNat (left, right, path, value)
      | BoolProbeNatRecipe (_, _, _, certificate) ->
        BoolProbeNat (left, right, path, certificate)
      | BoolProbeIntRecipe (_, _, _, certificate) ->
        BoolProbeInt (left, right, path, certificate)
    in
    let stage = ref "initialize" in
    let () =
      if summary_debug then
        Printf.eprintf
          "[bool-certificate] certify probe transitions=%d\n%!"
          (List.length recipes)
    in
    let refl term = cert_app "lean.Bool_defeq" [ term ] in
    let defeq left right =
      Constr.mkCast
        (refl left, Constr.DEFAULTcast, equality_type env left right)
    in
    let trans left middle right first second =
      cert_app "lean.BoolEquality_trans"
        [ left; middle; right; first; second ]
    in
    let checked_localized ?replacement ?replacement_domain left
        expected_right path equality =
      let localized =
        if path = [] then
          (* The dry trace has already verified both syntactic endpoints, and
             [certify_transition] constructs [equality] from a registered
             certificate theorem for exactly this whole term.  Retyping it
             here is redundant: the opaque segment (or final imported
             declaration) performs the authoritative kernel check.  More
             importantly, inference of the dependent result type can ask
             conversion to evaluate the original closed arithmetic before
             the certificate has had a chance to hide it. *)
          Some (left, expected_right, equality)
        else
          Option.bind
            (localized_bool_rewrite ?replacement ?replacement_domain env
               equality left path)
            (fun (actual_left, actual_right, proof) ->
              if
                Constr.equal actual_left left
                && Constr.equal actual_right expected_right
              then Some (left, expected_right, proof)
              else None)
      in
      match localized with
      | Some _ as result -> result
      | None ->
        (* A reflected operation may sit entirely in an [SProp]-irrelevant
           argument.  Replacing it is then already a Rocq conversion even
           though the operation itself was evaluated by reflection.  Ask the
           kernel before attempting to retain a transport through a
           dependent proof context. *)
        (try
          let proof = defeq left expected_right in
          ignore
            (Typing.check env evd (EConstr.of_constr proof)
               (EConstr.of_constr (equality_type env left expected_right)));
          Some (left, expected_right, proof)
        with _ -> None)
    in
    let canonical_int_certificate value =
      if Z.geq value Z.zero then
        let natural = cert_app "lean.Nat_of_N" [ n_int value ] in
        ( Constr.mkApp (lean_int_constructor 1, [| natural |]),
          cert_app "lean.IntCertificate_ofNat"
            [
              natural;
              n_int value;
              cert_app "lean.NatCertificate_of_N" [ n_int value ];
            ] )
      else
        let predecessor = Z.pred (Z.neg value) in
        let natural = cert_app "lean.Nat_of_N" [ n_int predecessor ] in
        ( Constr.mkApp (lean_int_constructor 2, [| natural |]),
          cert_app "lean.IntCertificate_negSucc"
            [
              natural;
              n_int predecessor;
              cert_app "lean.NatCertificate_of_N" [ n_int predecessor ];
            ] )
    in
    let certify_transition = function
      | BoolProbeDefinitional (left, right, path) ->
        if path = [] then Some (left, right, defeq left right)
        else
          Option.bind
            (local_definitional_equality env left right path)
            (fun (_, _, _, equality) ->
              checked_localized left right path equality)
      | BoolProbeEquation (left, right, path, equality) ->
        checked_localized left right path equality
      | BoolProbeBoolean (left, right, path, certificate) ->
        let replacement = lean_bool_constructor certificate.bool_value in
        let replacement_proof =
          cert_app "lean.BoolCertificate_of_bool"
            [ coq_bool certificate.bool_value ]
        in
        let equality =
          cert_app "lean.BoolCertificate_equal"
            [
              certificate.bool_term;
              replacement;
              coq_bool certificate.bool_value;
              certificate.bool_proof;
              replacement_proof;
            ]
        in
        checked_localized ~replacement
          ~replacement_domain:(registered_ref "lean.Bool") left right path
          equality
      | BoolProbeCompactNat (left, right, path, value) ->
        let original = subterm_at_certificate_path left path in
        let value_term = n_int value in
        let original_proof =
          cert_app "lean.NatCertificate_of_N" [ value_term ]
        in
        let replacement, replacement_proof =
          if Z.equal value Z.zero then
            lean_nat_constructor 1, registered_ref "lean.NatCertificate_zero"
          else
            let predecessor = Z.pred value in
            let natural = cert_app "lean.Nat_of_N" [ n_int predecessor ] in
            ( Constr.mkApp (lean_nat_constructor 2, [| natural |]),
              cert_app "lean.NatCertificate_succ"
                [
                  natural;
                  n_int predecessor;
                  cert_app "lean.NatCertificate_of_N" [ n_int predecessor ];
                ] )
        in
        let equality =
          cert_app "lean.NatCertificate_equal"
            [
              original;
              replacement;
              value_term;
              original_proof;
              replacement_proof;
            ]
        in
        checked_localized ~replacement
          ~replacement_domain:(registered_ref "lean.Nat") left right path
          equality
      | BoolProbeNat (left, right, path, certificate) ->
        let replacement =
          cert_app "lean.Nat_of_N" [ n_int certificate.nat_value ]
        in
        let replacement_proof =
          cert_app "lean.NatCertificate_of_N"
            [ n_int certificate.nat_value ]
        in
        let equality =
          cert_app "lean.NatCertificate_equal"
            [
              certificate.nat_term;
              replacement;
              n_int certificate.nat_value;
              certificate.nat_proof;
              replacement_proof;
            ]
        in
        checked_localized ~replacement
          ~replacement_domain:(registered_ref "lean.Nat") left right path
          equality
      | BoolProbeInt (left, right, path, certificate) ->
        let replacement, replacement_proof =
          canonical_int_certificate certificate.int_value
        in
        let equality =
          cert_app "lean.IntCertificate_equal"
            [
              certificate.int_term;
              replacement;
              z_int certificate.int_value;
              certificate.int_proof;
              replacement_proof;
            ]
        in
        checked_localized ~replacement
          ~replacement_domain:(registered_ref "lean.Int") left right path
          equality
    in
    let transition_left = function
      | BoolProbeDefinitional (left, _, _)
      | BoolProbeEquation (left, _, _, _)
      | BoolProbeBoolean (left, _, _, _)
      | BoolProbeCompactNat (left, _, _, _)
      | BoolProbeNat (left, _, _, _)
      | BoolProbeInt (left, _, _, _) -> left
    in
    let transition_right = function
      | BoolProbeDefinitional (_, right, _)
      | BoolProbeEquation (_, right, _, _)
      | BoolProbeBoolean (_, right, _, _)
      | BoolProbeCompactNat (_, right, _, _)
      | BoolProbeNat (_, right, _, _)
      | BoolProbeInt (_, right, _, _) -> right
    in
    let transition_kind = function
      | BoolProbeDefinitional _ -> "definitional"
      | BoolProbeEquation _ -> "equation"
      | BoolProbeBoolean _ -> "Boolean"
      | BoolProbeCompactNat _ -> "compact Nat"
      | BoolProbeNat _ -> "Nat"
      | BoolProbeInt _ -> "Int"
    in
    let transition_path = function
      | BoolProbeDefinitional (_, _, path) -> path
      | BoolProbeEquation (_, _, path, _)
      | BoolProbeBoolean (_, _, path, _)
      | BoolProbeCompactNat (_, _, path, _)
      | BoolProbeNat (_, _, path, _)
      | BoolProbeInt (_, _, path, _) -> path
    in
    let verify_trace () =
      let current = ref term in
      List.iter
        (fun recipe ->
          let transition = transition_from_left !current recipe in
          current := transition_right transition)
        recipes;
      if not (Constr.equal !current residual) then
        raise Not_found
    in
    let certify_value value =
      let certificate =
        ref
          {
            bool_term = residual;
            bool_value = value;
            bool_proof =
              cert_app "lean.BoolCertificate_of_bool" [ coq_bool value ];
          }
      in
      let chunk = ref 0 in
      let transport certificate transition =
        let generic () =
          let left, right, equality =
            match certify_transition transition with
            | Some edge -> edge
            | None -> raise Not_found
          in
          if not (Constr.equal certificate.bool_term right) then
            raise Not_found;
          {
            bool_term = left;
            bool_value = value;
            bool_proof =
              cert_app "lean.BoolCertificate_of_eq"
                [
                  left;
                  right;
                  coq_bool value;
                  equality;
                  certificate.bool_proof;
                ];
          }
        in
        match transition with
        | BoolProbeDefinitional (left, right, path) when path <> [] ->
          (match local_definitional_equality env left right path with
          | Some (domain, _, contractum, equality) ->
            (match
               dependent_context_hequality ~replacement:contractum
                 ~replacement_domain:domain env equality left path
             with
            | Some (actual_left, actual_right, heterogeneous)
              when Constr.equal actual_left left
                   && Constr.equal actual_right right ->
              if not (Constr.equal certificate.bool_term right) then
                raise Not_found;
              {
                bool_term = left;
                bool_value = value;
                bool_proof =
                  cert_app "lean.BoolCertificate_of_hequality"
                    [
                      left;
                      right;
                      coq_bool value;
                      heterogeneous;
                      certificate.bool_proof;
                    ];
              }
            | Some _ | None -> generic ())
          | None -> generic ())
        | _ -> generic ()
      in
      let current_right = ref residual in
      List.iteri
        (fun index recipe ->
          let transition = transition_from_right !current_right recipe in
          current_right := transition_left transition;
          let reflected_boolean =
            match transition with BoolProbeBoolean _ -> true | _ -> false
          in
          if reflected_boolean && !chunk > 0 then begin
            certificate := share_certificate !certificate;
            chunk := 0
          end;
          stage :=
            Printf.sprintf "certify value transition %d (%s path=%s)" index
              (transition_kind transition)
              (string_of_certificate_path (transition_path transition));
          certificate := transport !certificate transition;
          incr chunk;
          if reflected_boolean then begin
            certificate := share_certificate !certificate;
            chunk := 0
          end)
        (List.rev recipes);
      if
        not (Constr.equal !current_right term)
        || not (Constr.equal (!certificate).bool_term term)
      then
        raise Not_found;
      ReifiedBoolValue !certificate
    in
    let certify_residual () =
      let current = ref term in
      let edges =
        List.mapi
          (fun index recipe ->
            let transition = transition_from_left !current recipe in
            current := transition_right transition;
            stage :=
              Printf.sprintf
                "certify residual transition %d (%s path=%s)" index
                (transition_kind transition)
                (string_of_certificate_path (transition_path transition));
            match certify_transition transition with
            | Some edge -> edge
            | None -> raise Not_found)
          recipes
      in
      (* Seal a bounded number of adjacent reductions at a time.  A balanced
         pair tree creates one opaque declaration for almost every probe
         transition, and each declaration retains two large symbolic
         endpoints.  Four-edge segments keep each kernel conversion small
         while making the final composition operate only on opaque constant
         references. *)
      let edges = Array.of_list edges in
      let segment_limit = 4 in
      let segments = ref [] in
      let low = ref 0 in
      while !low < Array.length edges do
        let high = min (Array.length edges) (!low + segment_limit) in
        let first_left, first_right, first_proof = edges.(!low) in
        let segment_right = ref first_right in
        let segment_proof = ref first_proof in
        for index = !low + 1 to high - 1 do
          let left, right, proof = edges.(index) in
          if not (Constr.equal !segment_right left) then raise Not_found;
          segment_proof :=
            trans first_left left right !segment_proof proof;
          segment_right := right
        done;
        segments :=
          _share_bool_equality first_left !segment_right !segment_proof
          :: !segments;
        low := high
      done;
      let segments = List.rev !segments in
      let left, right, proof =
        match segments with
        | [] -> term, term, refl term
        | (first_left, first_right, first_proof) :: remaining ->
          let final_right, final_proof =
            List.fold_left
              (fun (middle, accumulated) (left, right, proof) ->
                if not (Constr.equal middle left) then raise Not_found;
                right,
                trans first_left left right accumulated proof)
              (first_right, first_proof) remaining
          in
          if remaining = [] then first_left, final_right, final_proof
          else
            _share_bool_equality first_left final_right final_proof
      in
      if
        not (Constr.equal left term)
        || not (Constr.equal right residual)
      then raise Not_found;
      ReifiedBoolResidual
        {
          bool_normalization_source = left;
          bool_normalization_residual = right;
          bool_normalization_proof = proof;
        }
    in
    try
      stage := "verify trace";
      verify_trace ();
      let result =
        match bool_constructor_value env residual with
        | Some value ->
          stage := "certify value";
          certify_value value
        | None ->
          stage := "certify residual";
          certify_residual ()
      in
      if summary_debug then
        Printf.eprintf
          "[bool-certificate] certified probe transitions=%d\n%!"
          (List.length recipes);
      Some result
    with exn ->
      if summary_debug then
        Printf.eprintf
          "[bool-certificate] rejected probe transitions=%d stage=%s (%s)\n%!"
          (List.length recipes) !stage
          (Printexc.to_string exn);
      None
  in
  let result =
    if
      not (Vars.closedn (Environ.nb_rel env) term)
      || not (is_bool_type env evd term)
    then None
    else
      (* Partial evaluation is useful under a theorem telescope as well as on
         globally closed terms.  The reducer only commits steps for which it
         constructs a checked equality, and opaque sharing abstracts the
         ambient local context.  If a demanded discriminator is genuinely
         symbolic, the evaluator retains a checked equality to that residual
         form so another side of the same proof boundary can meet it there. *)
      if proofless then begin
        let context_key = bool_probe_context_key env in
        let cache = (current_reification_cache ()).cached_bool_probes in
        match
          List.find_map
            (fun (cached_context, cached_term, cached_result) ->
              if
                Constr.equal cached_term term
                && equal_bool_probe_context cached_context context_key
              then Some cached_result
              else None)
            !cache
        with
        | Some result ->
          if summary_debug then
            Printf.eprintf "[bool-certificate] reused probe term=(%s)\n%!"
              (debug_head_shape term);
          result
        | None ->
          incr bool_probe_count;
          let probe_started = Unix.gettimeofday () in
          let probe = probe_forward term in
          let probe_elapsed = Unix.gettimeofday () -. probe_started in
          collect_certificate_garbage_if_needed ();
          if summary_debug && probe_elapsed >= 1.0 then begin
            let stats = Gc.stat () in
            Printf.eprintf
              "[bool-certificate] probe heap live=%.1fMiB heap=%.1fMiB\n%!"
              (float_of_int stats.Gc.live_words *. 8.0 /. 1048576.0)
              (float_of_int stats.Gc.heap_words *. 8.0 /. 1048576.0)
          end;
          if summary_debug then
            Printf.eprintf
              "[bool-certificate] probe result=%s elapsed=%.3f term=(%s)\n%!"
              (match probe with
              | `Value _ -> "value"
              | `Stuck trace ->
                if trace.bool_probe_exhausted then "partial" else "stuck"
              | `Timeout -> "timeout")
              probe_elapsed (debug_head_shape term);
          let result =
            match probe with
            | `Value (value, trace) ->
              Some (ProbedBoolValue (value, trace))
            | `Stuck trace -> Some (ProbedBoolResidual trace)
            | `Timeout -> None
          in
          if probe_elapsed >= 0.25 then begin
            let rec take count = function
              | _ when count = 0 -> []
              | [] -> []
              | entry :: entries -> entry :: take (count - 1) entries
            in
            cache :=
              (context_key, term, result) :: take 15 !cache
          end;
          result
      end
      else
        let context_key = bool_probe_context_key env in
        let normalization_cache =
          (current_reification_cache ()).cached_bool_normalizations
        in
        let rec drop count entries =
          if count = 0 then Some entries
          else
            match entries with
            | [] -> None
            | _ :: entries -> drop (count - 1) entries
        in
        let cached_normalization =
          List.find_map
            (fun (cached_context, cached_term, cached_normalization) ->
              let weakening =
                List.length context_key - List.length cached_context
              in
              if weakening < 0 then None
              else
                Option.bind (drop weakening context_key)
                  (fun context_suffix ->
                    if
                      equal_bool_probe_context cached_context context_suffix
                      && Constr.equal term (Vars.lift weakening cached_term)
                    then
                      Some
                        {
                          bool_normalization_source = term;
                          bool_normalization_residual =
                            Vars.lift weakening
                              cached_normalization.bool_normalization_residual;
                          bool_normalization_proof =
                            Vars.lift weakening
                              cached_normalization.bool_normalization_proof;
                        }
                    else None))
            !normalization_cache
        in
        (match cached_normalization with
        | Some normalization ->
          if summary_debug then
            Printf.eprintf
              "[bool-certificate] reused weakened normalization term=(%s)\n%!"
              (debug_head_shape term);
          Some (ReifiedBoolResidual normalization)
        | None ->
          let full_reify () =
            match Sys.getenv_opt "ROCQ_LEAN_LEGACY_CERT" with
            | Some _ ->
              Option.map
                (fun certificate -> ReifiedBoolValue certificate)
                (reify 100_000 term term 0 [] term)
            | None -> reify_forward term
          in
          let result =
            match probe_trace with
            | Some trace -> (
              match reify_probe_trace trace with
              | Some _ as result -> result
              | None -> full_reify ())
            | None -> full_reify ()
          in
          (match result with
          | Some (ReifiedBoolResidual normalization) ->
            let rec take count = function
              | _ when count = 0 -> []
              | [] -> []
              | entry :: entries -> entry :: take (count - 1) entries
            in
            normalization_cache :=
              (context_key, term, normalization)
              :: take 31 !normalization_cache
          | _ -> ());
          result)
  in
  let certificate_elapsed = Unix.gettimeofday () -. certificate_started in
  if
    debug
    || (summary_debug
       && (certificate_elapsed >= 1.0 || Option.has_some result))
  then begin
    let _, summary_arguments = Constr.decompose_app term in
    let summary_arguments =
      Array.to_list summary_arguments
      |> List.mapi (fun index argument ->
             Printf.sprintf "%d:%s" index (debug_head_shape argument))
      |> String.concat ";"
    in
    Printf.eprintf
      "[bool-certificate] done steps=%d exposures=%d success=%b elapsed=%.3f closed=%b term=(%s) arguments=[%s]\n%!"
      !steps !exposures (Option.has_some result)
      certificate_elapsed (Vars.closed0 term) (debug_head_shape term)
      summary_arguments
  end;
  Option.map
    (function
      | ReifiedBoolValue certificate ->
        ReifiedBoolValue (share_certificate certificate)
      | ReifiedBoolResidual normalization ->
        ReifiedBoolResidual normalization
      | ProbedBoolValue (value, trace) -> ProbedBoolValue (value, trace)
      | ProbedBoolResidual trace -> ProbedBoolResidual trace)
    result

let rec first_certified_bool_difference env evd path actual expected =
  if Constr.equal actual expected then None
  else
    let descend () =
      match Constr.kind actual, Constr.kind expected with
      | Prod (_, actual_domain, actual_body),
        Prod (_, expected_domain, expected_body) -> (
        match
          first_certified_bool_difference env evd (ProdDomain :: path)
            actual_domain expected_domain
        with
        | Some _ as result -> result
        | None ->
          first_certified_bool_difference env evd (ProdCodomain :: path)
            actual_body expected_body)
      | Lambda (_, actual_domain, actual_body),
        Lambda (_, expected_domain, expected_body) -> (
        match
          first_certified_bool_difference env evd (LambdaDomain :: path)
            actual_domain expected_domain
        with
        | Some _ as result -> result
        | None ->
          first_certified_bool_difference env evd (LambdaBody :: path)
            actual_body expected_body)
      | LetIn (_, actual_value, actual_type, actual_body),
        LetIn (_, expected_value, expected_type, expected_body) -> (
        match
          first_certified_bool_difference env evd (LetValue :: path)
            actual_value expected_value
        with
        | Some _ as result -> result
        | None -> (
          match
            first_certified_bool_difference env evd (LetType :: path)
              actual_type expected_type
          with
          | Some _ as result -> result
          | None ->
            first_certified_bool_difference env evd (LetBody :: path)
              actual_body expected_body))
      | App _, App _ ->
        let actual_head, actual_args = Constr.decompose_app actual in
        let expected_head, expected_args = Constr.decompose_app expected in
        if
          not (Constr.equal actual_head expected_head)
          || Array.length actual_args <> Array.length expected_args
        then None
        else
          let rec scan index =
            if index = Array.length actual_args then None
            else
              match
                first_certified_bool_difference env evd
                  (AppArgument index :: path)
                  actual_args.(index) expected_args.(index)
              with
              | Some _ as result -> result
              | None -> scan (index + 1)
          in
          scan 0
      | _ -> None
    in
    let probe_trace = function
      | Some (ProbedBoolValue (_, trace))
      | Some (ProbedBoolResidual trace) -> Some trace
      | _ -> None
    in
    let certify_reified actual_probe expected_probe =
      let actual_trace = probe_trace actual_probe in
      let expected_trace = probe_trace expected_probe in
      match reify_bool ?probe_trace:actual_trace env evd actual with
      | None -> None
      | Some left -> (
        match reify_bool ?probe_trace:expected_trace env evd expected with
        | Some (ReifiedBoolValue right) -> (
          match left with
          | ReifiedBoolValue left
            when Bool.equal left.bool_value right.bool_value ->
            let value = coq_bool left.bool_value in
            Some
              ( List.rev path,
                {
                  certified_bool_left = actual;
                  certified_bool_right = expected;
                  certified_bool_proof =
                    cert_app "lean.BoolCertificate_equal"
                      [
                        actual;
                        expected;
                        value;
                        left.bool_proof;
                        right.bool_proof;
                      ];
                } )
          | _ -> None)
        | Some (ReifiedBoolResidual right) -> (
          match left with
          | ReifiedBoolResidual left
            when
              Constr.equal left.bool_normalization_source actual
              && Constr.equal right.bool_normalization_source expected
              && Constr.equal left.bool_normalization_residual
                   right.bool_normalization_residual ->
            let residual = left.bool_normalization_residual in
            let reverse_motive =
              Constr.mkLambda
                ( Context.make_annot Anonymous Sorts.Relevant,
                  registered_ref "lean.Bool",
                  Constr.mkApp
                    ( registered_ref_at_level "lean.Eq" Level.set,
                      [|
                        registered_ref "lean.Bool";
                        Constr.mkRel 1;
                        Vars.lift 1 expected;
                      |] ) )
            in
            let reverse_right =
              cert_app "lean.Bool_transport_sprop"
                [
                  reverse_motive;
                  expected;
                  residual;
                  right.bool_normalization_proof;
                  cert_app "lean.Bool_defeq" [ expected ];
                ]
            in
            Some
              ( List.rev path,
                {
                  certified_bool_left = actual;
                  certified_bool_right = expected;
                  certified_bool_proof =
                    cert_app "lean.BoolEquality_trans"
                      [
                        actual;
                        residual;
                        expected;
                        left.bool_normalization_proof;
                        reverse_right;
                      ];
                } )
          | _ -> None)
        | _ -> None)
    in
    let certify () =
      let actual_probe = reify_bool ~proofless:true env evd actual in
      let expected_probe = reify_bool ~proofless:true env evd expected in
      let compatible =
        match actual_probe, expected_probe with
        | Some (ProbedBoolValue (left, _)),
          Some (ProbedBoolValue (right, _)) ->
          Bool.equal left right
        | Some (ProbedBoolResidual left),
          Some (ProbedBoolResidual right) ->
          Constr.equal left.bool_probe_residual right.bool_probe_residual
        | None, _ | _, None ->
          (* Fuel exhaustion is inconclusive.  Preserve completeness by
             falling back to the checked evaluator. *)
          true
        | _ -> false
      in
      if compatible then certify_reified actual_probe expected_probe else None
    in
    let structurally_aligned =
      match Constr.kind actual, Constr.kind expected with
      | Prod _, Prod _ | Lambda _, Lambda _ | LetIn _, LetIn _ -> true
      | App _, App _ ->
        let actual_head, actual_args = Constr.decompose_app actual in
        let expected_head, expected_args = Constr.decompose_app expected in
        Constr.equal actual_head expected_head
        && Array.length actual_args = Array.length expected_args
      | _ -> false
    in
    if structurally_aligned then
      match descend () with Some _ as result -> result | None -> certify ()
    else
      match certify () with Some _ as result -> result | None -> descend ()

let is_sprop_type env evd ty =
  let sort =
    Retyping.get_type_of env evd (EConstr.of_constr ty)
    |> Reductionops.whd_all env evd |> EConstr.Unsafe.to_constr
  in
  match Constr.kind sort with Sort sort -> Sorts.is_sprop sort | _ -> false

let proof_boundary_debug_count = ref 0
let transport_attempt_debug_count = ref 0

let debug_uncertified_proof_boundary env evd actual expected =
  if
    Option.has_some (Sys.getenv_opt "ROCQ_LEAN_BOUNDARY_DEBUG")
    && is_sprop_type env evd actual
    && !proof_boundary_debug_count < 32
  then (
    incr proof_boundary_debug_count;
    let _, actual_args = Constr.decompose_app actual in
    let _, expected_args = Constr.decompose_app expected in
    Printf.eprintf "[proof-boundary] actual=(%s) expected=(%s)\n%!"
      (debug_head_shape actual) (debug_head_shape expected);
    let count = min (Array.length actual_args) (Array.length expected_args) in
    for index = 0 to count - 1 do
      if not (Constr.equal actual_args.(index) expected_args.(index)) then
        Printf.eprintf "[proof-boundary] arg%d actual=(%s) expected=(%s)\n%!"
          index (debug_head_shape actual_args.(index))
          (debug_head_shape expected_args.(index))
    done;
    if
      Option.has_some (Sys.getenv_opt "ROCQ_LEAN_BOUNDARY_DUMP")
      && !proof_boundary_debug_count = 9
    then
      Feedback.msg_info
        Pp.(
          str "proof boundary actual:" ++ fnl ()
          ++ Printer.pr_constr_env env evd actual ++ fnl ()
          ++ str "proof boundary expected:" ++ fnl ()
          ++ Printer.pr_constr_env env evd expected))

let well_typed_transport_motive env evd motive =
  try
    ignore (Typing.type_of env evd (EConstr.of_constr motive));
    true
  with _ -> false

let application_argument_has_dependent_successor env evd application index =
  try
    let head, arguments = Constr.decompose_app application in
    if index < 0 || index >= Array.length arguments - 1 then false
    else
      let expose_product ty =
        let ty =
          EConstr.of_constr ty |> Reductionops.whd_all env evd
          |> EConstr.Unsafe.to_constr
        in
        match Constr.kind ty with
        | Prod (_, domain, codomain) -> domain, codomain
        | _ -> raise Not_found
      in
      let rec reach_argument current ty =
        let _, codomain = expose_product ty in
        if current = index then codomain
        else
          reach_argument (current + 1)
            (Vars.subst1 arguments.(current) codomain)
      in
      let codomain =
        Retyping.get_type_of env evd (EConstr.of_constr head)
        |> EConstr.Unsafe.to_constr |> reach_argument 0
      in
      let rec later_domain_depends relative_index remaining ty =
        if remaining = 0 then false
        else
          let domain, codomain = expose_product ty in
          (not (Vars.noccurn relative_index domain))
          || later_domain_depends (relative_index + 1) (remaining - 1)
               codomain
      in
      later_domain_depends 1 (Array.length arguments - index - 1) codomain
  with _ -> true

(** A one-hole transport motive is automatically well-formed in ordinary
    covariant term positions.  It needs checking when the hole changes a
    binder domain, or when it is an argument on which the type of a later
    already-supplied argument depends.  The latter test follows the function
    telescope syntactically, so nondependent arithmetic applications do not
    pay for retyping the complete surrounding proposition. *)
let transport_motive_requires_validation env evd term path =
  let rec scan env term = function
    | [] -> false
    | step :: rest ->
      let validate_here =
        match step with
        | ProdDomain | LambdaDomain | LetType -> true
        | AppArgument index ->
          application_argument_has_dependent_successor env evd term index
        | ProdCodomain | LambdaBody | LetValue | LetBody | AppFunction
        | CaseScrutinee | ProjectionScrutinee -> false
      in
      if validate_here then true
      else
        let child_env =
          match step, Constr.kind term with
          | ProdCodomain, Prod (annot, domain, _)
          | LambdaBody, Lambda (annot, domain, _) ->
            Environ.push_rel (RelDecl.LocalAssum (annot, domain)) env
          | LetBody, LetIn (annot, value, types, _) ->
            Environ.push_rel
              (RelDecl.LocalDef (annot, value, types)) env
          | _ -> env
        in
        scan child_env (subterm_at_certificate_path term [ step ]) rest
  in
  scan env term path

let transport_closed_nat env evd actual expected argument =
  if not (is_sprop_type env evd actual) then None
  else
    let actual = normalize_sprop_type_wrappers env evd actual in
    let expected = normalize_sprop_type_wrappers env evd expected in
    let debug =
      Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CONSTRUCTOR_DEBUG")
    in
    if debug then
      Printf.eprintf "[nat-transport] normalized actual=(%s) expected=(%s)\n%!"
        (debug_head_shape actual) (debug_head_shape expected);
    if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_DECLARE_DUMP") then
      Feedback.msg_info
        Pp.(
          str "normalized constructor proof actual:" ++ fnl ()
          ++ Printer.pr_constr_env env evd actual ++ fnl ()
          ++ str "normalized constructor proof expected:" ++ fnl ()
          ++ Printer.pr_constr_env env evd expected);
    let rec transport fuel actual argument =
      if Constr.equal actual expected then Some argument
      else if fuel = 0 then None
      else
        match first_certified_nat_difference env evd [] actual expected with
        | None ->
          if debug then
            Printf.eprintf "[nat-transport] no certified difference\n%!";
          debug_uncertified_proof_boundary env evd actual expected;
          None
        | Some (path, left, right) ->
          if debug then
            Printf.eprintf
              "[nat-transport] certified difference path=%s value=%s\n%!"
              (string_of_certificate_path path) (Z.to_string left.nat_value);
          let canonical = n_int left.nat_value in
          let equality =
            cert_app "lean.NatCertificate_equal"
              [
                left.nat_term;
                right.nat_term;
                canonical;
                left.nat_proof;
                right.nat_proof;
              ]
          in
          let motive_body =
            replace_certificate_path (Vars.lift 1 actual) path (Constr.mkRel 1)
          in
          let motive =
            Constr.mkLambda
              ( Context.make_annot Anonymous Sorts.Relevant,
                registered_ref "lean.Nat",
                motive_body )
          in
          if
            transport_motive_requires_validation env evd actual path
            && not (well_typed_transport_motive env evd motive)
          then None
          else
            let argument =
              cert_app "lean.Nat_transport_sprop"
                [ motive; left.nat_term; right.nat_term; equality; argument ]
            in
            let actual = replace_certificate_path actual path right.nat_term in
            transport (fuel - 1) actual argument
    in
    transport 16 actual argument

let transport_closed_int env evd actual expected argument =
  if
    Option.has_some (Sys.getenv_opt "ROCQ_LEAN_DISABLE_INT_CERT")
    || not (is_sprop_type env evd actual)
  then None
  else
    let actual = normalize_sprop_type_wrappers env evd actual in
    let expected = normalize_sprop_type_wrappers env evd expected in
    let rec transport fuel actual argument =
      if Constr.equal actual expected then Some argument
      else if fuel = 0 then None
      else
        match first_certified_int_difference env evd [] actual expected with
        | None -> None
        | Some (path, left, right) ->
          let equality =
            cert_app "lean.IntCertificate_equal"
              [
                left.int_term;
                right.int_term;
                z_int left.int_value;
                left.int_proof;
                right.int_proof;
              ]
          in
          let motive_body =
            replace_certificate_path (Vars.lift 1 actual) path (Constr.mkRel 1)
          in
          let motive =
            Constr.mkLambda
              ( Context.make_annot Anonymous Sorts.Relevant,
                registered_ref "lean.Int",
                motive_body )
          in
          if
            transport_motive_requires_validation env evd actual path
            && not (well_typed_transport_motive env evd motive)
          then None
          else
            let argument =
              cert_app "lean.Int_transport_sprop"
                [ motive; left.int_term; right.int_term; equality; argument ]
            in
            let actual = replace_certificate_path actual path right.int_term in
            transport (fuel - 1) actual argument
    in
    transport 16 actual argument

let transport_closed_bool env evd actual expected argument =
  if not (is_sprop_type env evd actual) then None
  else
    let actual = normalize_sprop_type_wrappers env evd actual in
    let expected = normalize_sprop_type_wrappers env evd expected in
    let rec transport fuel actual argument =
      if Constr.equal actual expected then Some argument
      else if fuel = 0 then None
      else
        match first_certified_bool_difference env evd [] actual expected with
        | None -> None
        | Some (path, equality) ->
          let motive_body =
            replace_certificate_path (Vars.lift 1 actual) path (Constr.mkRel 1)
          in
          let motive =
            Constr.mkLambda
              ( Context.make_annot Anonymous Sorts.Relevant,
                registered_ref "lean.Bool",
                motive_body )
          in
          if
            transport_motive_requires_validation env evd actual path
            && not (well_typed_transport_motive env evd motive)
          then None
          else
            let argument =
              cert_app "lean.Bool_transport_sprop"
                [
                  motive;
                  equality.certified_bool_left;
                  equality.certified_bool_right;
                  equality.certified_bool_proof;
                  argument;
                ]
            in
            let actual =
              replace_certificate_path actual path
                equality.certified_bool_right
            in
            transport (fuel - 1) actual argument
    in
    transport 16 actual argument

let rec try_transport_to_expected ?(eager_reduce = false) env evd expected
    argument =
  let profile = Option.has_some (Sys.getenv_opt "ROCQ_LEAN_APP_PROFILE") in
  if profile then
    Printf.eprintf
      "[application-profile] transport-enter term=%s\n%!"
      (debug_head_shape argument);
  let actual =
    Retyping.get_type_of env evd (EConstr.of_constr argument)
    |> EConstr.Unsafe.to_constr
  in
  let expose_beta_iota_zeta term =
    EConstr.of_constr term
    |> Reductionops.whd_betaiotazeta env evd
    |> EConstr.Unsafe.to_constr
  in
  let actual = expose_beta_iota_zeta actual in
  let expected = expose_beta_iota_zeta expected in
  if profile then
    Printf.eprintf
      "[application-profile] transport-typed actual=%s expected=%s\n%!"
      (debug_head_shape actual) (debug_head_shape expected);
  if Constr.equal actual expected then Some argument
  else if
    eager_reduce
    && Option.has_some (Sys.getenv_opt "ROCQ_LEAN_DISABLE_CERT")
  then None
  else
    let pointwise_transport =
      match Constr.kind actual, Constr.kind expected with
      | Prod (annot, actual_domain, actual_body),
        Prod (_, expected_domain, expected_body)
        when Constr.equal actual_domain expected_domain ->
        (try
          if profile then
            Printf.eprintf "[application-profile] pointwise-enter\n%!";
          let local_env =
            Environ.push_rel
              (RelDecl.LocalAssum (annot, actual_domain)) env
          in
          let applied =
            Constr.mkApp
              (Vars.lift 1 argument, [| Constr.mkRel 1 |])
          in
          match
            try_transport_to_expected ~eager_reduce local_env evd
              expected_body applied
          with
          | Some transported ->
            Some (Constr.mkLambda (annot, actual_domain, transported))
          | None -> None
        with _ -> None)
      | _ -> None
    in
    match pointwise_transport with
    | Some argument -> Some argument
    | None -> (
      if profile then
        Printf.eprintf "[application-profile] nat-transport-enter\n%!";
      match transport_closed_nat env evd actual expected argument with
      | Some argument -> Some argument
      | None -> (
        if profile then
          Printf.eprintf "[application-profile] int-transport-enter\n%!";
        match transport_closed_int env evd actual expected argument with
        | Some argument -> Some argument
        | None -> (
          let () =
            if
              Option.has_some
                (Sys.getenv_opt "ROCQ_LEAN_TRANSPORT_ATTEMPT_DUMP")
              && !transport_attempt_debug_count < 32
            then begin
              incr transport_attempt_debug_count;
              Feedback.msg_info
                Pp.(
                  str "transport attempt "
                  ++ int !transport_attempt_debug_count ++ str " actual:"
                  ++ fnl () ++ Printer.pr_constr_env env evd actual
                  ++ fnl () ++ str "transport expected:" ++ fnl ()
                  ++ Printer.pr_constr_env env evd expected)
            end
          in
          if profile then
            Printf.eprintf "[application-profile] bool-transport-enter\n%!";
          match transport_closed_bool env evd actual expected argument with
          | Some argument ->
            if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_CERT_DEBUG") then
              Printf.eprintf "[bool-certificate] transport constructed\n%!";
            Some argument
          | None ->
            debug_uncertified_proof_boundary env evd actual expected;
            None)))

let maybe_transport_to_expected ?(eager_reduce = false) env evd expected
    argument =
  match
    try_transport_to_expected ~eager_reduce env evd expected argument
  with
  | Some transported -> transported
  | None -> argument

let maybe_transport_application ?(eager_reduce = false) env evd function_term
    argument =
  let function_type =
    Retyping.get_type_of env evd (EConstr.of_constr function_term)
    |> Reductionops.whd_all env evd |> EConstr.Unsafe.to_constr
  in
  match Constr.kind function_type with
  | Prod (_, expected, _) ->
    maybe_transport_to_expected ~eager_reduce env evd expected argument
  | _ -> argument

(** The caller carries the function telescope through the complete
    application spine, so neither the growing partial application nor its
    result type has to be retyped at every argument.  Only irrelevant proof
    arguments need an explicit transport here.  Relevant data arguments stay
    definitionally equal to their Lean translations; recursively normalizing
    each of them at every enclosing proof application repeatedly traverses
    completed proof subterms and causes quadratic allocation.  Declaration
    types, SProp binder types, and constructor parameters are canonicalized at
    their own translation boundaries. *)
let irrelevant_proof_argument_profile_count = ref 0

let normalize_proof_application_argument env evd ~application_is_proof
    ~expected_relevance ~expected argument =
  if not application_is_proof then argument
  else
    match expected_relevance with
    | Sorts.Irrelevant ->
      let profile =
        Option.has_some (Sys.getenv_opt "ROCQ_LEAN_APP_PROFILE")
      in
      incr irrelevant_proof_argument_profile_count;
      let count = !irrelevant_proof_argument_profile_count in
      let started = Unix.gettimeofday () in
      if profile then
        Printf.eprintf
          "[application-profile] irrelevant-start=%d term=%s\n%!"
          count (debug_head_shape argument);
      let result = maybe_transport_to_expected env evd expected argument in
      if profile then
        Printf.eprintf
          "[application-profile] irrelevant-done=%d elapsed=%.3fs\n%!"
          count (Unix.gettimeofday () -. started);
      result
    | Sorts.Relevant | Sorts.RelevanceVar _ ->
      let argument =
        normalize_relevant_wrapper_spine env evd argument
      in
      let head, _ = Constr.decompose_app argument in
      (match Constr.kind head with
      | Rel _ | Lambda _ | Prod _ | LetIn _ -> argument
      | _ -> normalize_sprop_type_wrappers env evd argument)

let translation_application_profile_count = ref 0
let translation_application_head_time = ref 0.
let translation_application_typing_time = ref 0.
let translation_application_product_time = ref 0.
let translation_application_normalize_time = ref 0.
let translation_application_transport_time = ref 0.
let translation_application_constructor_time = ref 0.
let translation_projection_application_count = ref 0
let translation_mutual_recursor_application_count = ref 0
let translation_nested_recursor_application_count = ref 0
let translation_constant_count = ref 0
let translation_constant_time = ref 0.

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
    | Const (n, univs) ->
      (fun uconv ->
        let started = Unix.gettimeofday () in
        let result = instantiate n univs uconv in
        if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_APP_PROFILE") then begin
          incr translation_constant_count;
          translation_constant_time :=
            !translation_constant_time
            +. (Unix.gettimeofday () -. started);
          if !translation_constant_count mod 100 = 0 then
            Printf.eprintf
              "[application-profile] constant-count=%d elapsed=%.3fs\n%!"
              !translation_constant_count !translation_constant_time
        end;
        result)
    | App (function_expr, argument_expr)
      when Option.has_some
             (Sys.getenv_opt "ROCQ_LEAN_LEGACY_APPLICATION_PROFILE") ->
      to_constr env function_expr >>= fun function_ ->
      to_constr env argument_expr >>= fun argument ->
      (match argument_expr with
      | expression when is_eager_reduce_application expression ->
        get_uconv >>= fun uconv ->
        let argument =
          with_env_evm env uconv
            (fun env evd () ->
              maybe_transport_application ~eager_reduce:true env evd
                function_ argument)
            ()
        in
        ret (mkApp (function_, [| argument |]))
      | Bound _ ->
        get_uconv >>= fun uconv ->
        let argument =
          with_env_evm env uconv
            (fun env evd () ->
              maybe_transport_application env evd function_ argument)
            ()
        in
        ret (mkApp (function_, [| argument |]))
      | _ -> ret (mkApp (function_, [| argument |])))
    | (App _ as app_expr) -> (
      let head, args = decompose_lean_app [] app_expr in
      match head with
      | Const (n, univs) when N.Map.mem n !projection_aliases ->
        if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_APP_PROFILE") then begin
          incr translation_projection_application_count;
          if !translation_projection_application_count mod 100 = 0 then
            Printf.eprintf
              "[application-profile] projection-count=%d\n%!"
              !translation_projection_application_count
        end;
        (fun uconv ->
          let alias = find_projection_alias_for_universes uconv n univs in
          let uconv, translated_args =
            CList.fold_left_map
              (fun uconv arg -> to_constr env arg uconv)
              uconv args
          in
          let apply_arguments uconv function_ arguments =
            List.fold_left
              (fun function_ (argument_expr, argument) ->
                let argument =
                  with_env_evm env uconv
                    (fun env evd () ->
                      canonicalize_nat_constructor_parameter env evd argument)
                    ()
                in
                let argument =
                  match argument_expr with
                  | expression when is_eager_reduce_application expression ->
                    with_env_evm env uconv
                      (fun env evd () ->
                        maybe_transport_application ~eager_reduce:true env evd
                          function_ argument)
                      ()
                  | Bound _ ->
                    with_env_evm env uconv
                      (fun env evd () ->
                        maybe_transport_application env evd function_ argument)
                      ()
                  | _ -> argument
                in
                Constr.mkApp (function_, [| argument |]))
              function_ arguments
          in
          let translated = List.combine args translated_args in
          match alias with
          | Some alias ->
            let mib = Global.lookup_mind (fst alias.projection_ind) in
            let nparams = mib.mind_nparams in
            if List.length translated_args < nparams + 1 then
              let uconv, function_ = instantiate n univs uconv in
              (uconv, apply_arguments uconv function_ translated)
            else
              let target = List.nth translated_args nparams in
              let projection, relevance =
                Declareops.inductive_make_projection alias.projection_ind mib
                  ~proj_arg:alias.projection_field
              in
              let projected =
                Constr.mkProj
                  (Projection.make projection false, relevance, target)
              in
              let extra =
                List.filteri
                  (fun index _ -> index > nparams)
                  translated
              in
              (uconv, apply_arguments uconv projected extra)
          | None ->
            let uconv, function_ = instantiate n univs uconv in
            (uconv, apply_arguments uconv function_ translated))
      | Const (n, univs) when N.Map.mem n !mutual_nested_rec_info ->
        if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_APP_PROFILE") then begin
          incr translation_mutual_recursor_application_count;
          if !translation_mutual_recursor_application_count mod 100 = 0 then
            Printf.eprintf
              "[application-profile] mutual-recursor-count=%d\n%!"
              !translation_mutual_recursor_application_count
        end;
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
          | Some term -> uconv, term
          | None ->
            let recursor_index =
              match info.focus with
              | MutualMain index -> index
              | MutualAux _ -> 0
            in
            let term =
              List.fold_left
                (fun f x -> Constr.mkApp (f, [| x |]))
                (List.nth recursors recursor_index) args
            in
            uconv, term)
      | Const (n, univs) when N.Map.mem n !nested_array_rec_info ->
        if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_APP_PROFILE") then begin
          incr translation_nested_recursor_application_count;
          if !translation_nested_recursor_application_count mod 100 = 0 then
            Printf.eprintf
              "[application-profile] nested-recursor-count=%d\n%!"
              !translation_nested_recursor_application_count
        end;
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
          | Some term -> uconv, term
          | None ->
            let term =
              List.fold_left
                (fun f x -> Constr.mkApp (f, [| x |]))
                recursor args
            in
            uconv, term)
      | _ ->
        let application_profile =
          Option.has_some (Sys.getenv_opt "ROCQ_LEAN_APP_PROFILE")
        in
        incr translation_application_profile_count;
        let application_id = !translation_application_profile_count in
        let application_started = Unix.gettimeofday () in
        if application_profile && application_id mod 100 = 0 then begin
          let gc = Gc.quick_stat () in
          Printf.eprintf
            "[application-profile] count=%d head=%.3fs typing=%.3fs constructor=%.3fs product=%.3fs normalize=%.3fs transport=%.3fs major=%d compact=%d heap=%.1fMiB\n%!"
            application_id !translation_application_head_time
            !translation_application_typing_time
            !translation_application_constructor_time
            !translation_application_product_time
            !translation_application_normalize_time
            !translation_application_transport_time
            gc.Gc.major_collections gc.Gc.compactions
            (float_of_int gc.Gc.heap_words
            *. float_of_int (Sys.word_size / 8) /. 1048576.)
        end;
        let head_started = Unix.gettimeofday () in
        to_constr env head >>= fun function_ ->
        translation_application_head_time :=
          !translation_application_head_time
          +. (Unix.gettimeofday () -. head_started);
        (fun uconv ->
          let arguments_started = Unix.gettimeofday () in
          let uconv, translated_args =
            CList.fold_left_map
              (fun uconv argument -> to_constr env argument uconv)
              uconv args
          in
          let arguments_elapsed =
            Unix.gettimeofday () -. arguments_started
          in
          if application_profile && arguments_elapsed >= 0.05 then
            Printf.eprintf
              "[application-profile] arguments=%d elapsed=%.3fs\n%!"
              application_id arguments_elapsed;
          let typing_started = Unix.gettimeofday () in
          let function_type, application_is_proof =
            with_env_evm env uconv
              (fun env evd () ->
                let function_type =
                  Retyping.get_type_of env evd (EConstr.of_constr function_)
                  |> EConstr.Unsafe.to_constr
                in
                let relevance =
                  Retyping.relevance_of_term env evd
                    (EConstr.of_constr function_)
                  |> EConstr.Unsafe.to_relevance
                in
                function_type,
                match relevance with
                | Sorts.Irrelevant -> true
                | Sorts.Relevant | Sorts.RelevanceVar _ -> false)
              ()
          in
          let typing_elapsed = Unix.gettimeofday () -. typing_started in
          translation_application_typing_time :=
            !translation_application_typing_time +. typing_elapsed;
          if application_profile && typing_elapsed >= 0.05 then
            Printf.eprintf
              "[application-profile] function-type=%d elapsed=%.3fs\n%!"
              application_id typing_elapsed;
          let constructor_started = Unix.gettimeofday () in
          let constructor_info =
            let constructor, applied = Constr.decompose_app function_ in
            match Constr.kind constructor with
            | Construct (((inductive, _), _) as constructor) ->
              let mib = Global.lookup_mind (fst inductive) in
              Some (constructor, mib, Array.length applied)
            | _ -> None
          in
          translation_application_constructor_time :=
            !translation_application_constructor_time
            +. (Unix.gettimeofday () -. constructor_started);
          let is_rfl =
            match head with
            | Const (name, _) -> N.equal name rfl_name
            | _ -> false
          in
          let rec apply_arguments index telescope applied_rev = function
            | [], [] -> constr_app function_ (List.rev applied_rev)
            | argument_expr :: argument_exprs, argument :: arguments ->
              let product_started = Unix.gettimeofday () in
              let product =
                Option.bind telescope (fun (function_type, substitutions) ->
                    with_env_evm env uconv
                      (fun env evd (function_type, substitutions) ->
                        try
                          match Constr.kind function_type with
                          | Prod (annot, expected, codomain) ->
                            let expected =
                              Vars.substl substitutions expected
                            in
                            Some
                              ( annot,
                                expected,
                                codomain,
                                substitutions )
                          | _ ->
                            let function_type =
                              Vars.substl substitutions function_type
                              |> EConstr.of_constr
                              |> Reductionops.whd_all env evd
                              |> EConstr.Unsafe.to_constr
                            in
                            (match Constr.kind function_type with
                            | Prod (annot, expected, codomain) ->
                              Some (annot, expected, codomain, [])
                            | _ -> None)
                        with _ -> None)
                      (function_type, substitutions))
              in
              translation_application_product_time :=
                !translation_application_product_time
                +. (Unix.gettimeofday () -. product_started);
              let normalize_started = Unix.gettimeofday () in
              let argument =
                with_env_evm env uconv
                  (fun env evd argument ->
                    let argument =
                      canonicalize_nat_constructor_parameter env evd argument
                    in
                    let argument =
                      if is_rfl then
                        normalize_sprop_type_wrappers env evd argument
                      else argument
                    in
                    match product with
                    | Some (annot, expected, _, _)
                      when not
                             (is_eager_reduce_application argument_expr) ->
                      normalize_proof_application_argument env evd
                        ~application_is_proof
                        ~expected_relevance:annot.Context.binder_relevance
                        ~expected argument
                    | Some _ | None -> argument)
                  argument
              in
              translation_application_normalize_time :=
                !translation_application_normalize_time
                +. (Unix.gettimeofday () -. normalize_started);
              let transport_started = Unix.gettimeofday () in
              let argument =
                with_env_evm env uconv
                  (fun env evd argument ->
                    let transport ?(eager_reduce = false) argument =
                      match product with
                      | Some (_, expected, _, _) ->
                        maybe_transport_to_expected ~eager_reduce env evd
                          expected argument
                      | None -> argument
                    in
                    match argument_expr with
                    | expression
                      when is_eager_reduce_application expression ->
                      transport ~eager_reduce:true argument
                    | Bound _ -> transport argument
                    | _ -> (
                      match constructor_info with
                      | Some (_, mib, initially_applied) ->
                        (* Constructor telescopes are dependent: a proof field
                           can be well-typed only up to a large closed
                           arithmetic conversion determined by earlier data
                           fields.  Materialize that conversion as a small
                           checked transport before handing the completed
                           constructor to Rocq's kernel. *)
                        let applied = initially_applied + index in
                        let is_parameter = applied < mib.mind_nparams in
                        let original_argument = argument in
                        let argument =
                          if is_parameter then
                            canonicalize_nat_constructor_parameter env evd
                              argument
                          else transport argument
                        in
                        let () =
                          if
                            Option.has_some
                              (Sys.getenv_opt "ROCQ_LEAN_CONSTRUCTOR_DEBUG")
                          then
                            let actual =
                              Retyping.get_type_of env evd
                                (EConstr.of_constr argument)
                              |> EConstr.Unsafe.to_constr
                            in
                            Feedback.msg_info
                              Pp.(
                                str "constructor argument: applied="
                                ++ int applied ++ str " nparams="
                                ++ int mib.mind_nparams ++ str " parameter="
                                ++ bool is_parameter ++ fnl ()
                                ++ str "before:" ++ fnl ()
                                ++ Printer.pr_constr_env env evd
                                     original_argument
                                ++ fnl () ++ str "after:" ++ fnl ()
                                ++ Printer.pr_constr_env env evd argument
                                ++
                                match product with
                                | Some (_, expected, _, _) ->
                                  fnl () ++ str "constructor expected:"
                                  ++ fnl ()
                                  ++ Printer.pr_constr_env env evd expected
                                  ++ fnl () ++ str "constructor actual:"
                                  ++ fnl ()
                                  ++ Printer.pr_constr_env env evd actual
                                | None -> mt ())
                        in
                        argument
                      | None -> argument))
                  argument
              in
              translation_application_transport_time :=
                !translation_application_transport_time
                +. (Unix.gettimeofday () -. transport_started);
              let telescope =
                Option.bind product
                  (fun (_, _, codomain, substitutions) ->
                    Some (codomain, argument :: substitutions))
              in
              apply_arguments (index + 1) telescope
                (argument :: applied_rev)
                (argument_exprs, arguments)
            | _ -> assert false
          in
          let applying_started = Unix.gettimeofday () in
          let result =
            apply_arguments 0 (Some (function_type, [])) []
              (args, translated_args)
          in
          let result =
            expose_registered_primitive_projection_application result
          in
          let applying_elapsed = Unix.gettimeofday () -. applying_started in
          let application_elapsed =
            Unix.gettimeofday () -. application_started
          in
          if application_profile && applying_elapsed >= 0.05 then
            Printf.eprintf
              "[application-profile] apply=%d elapsed=%.3fs\n%!"
              application_id applying_elapsed;
          if application_profile && application_elapsed >= 0.05 then
            Printf.eprintf
              "[application-profile] done=%d elapsed=%.3fs\n%!"
              application_id application_elapsed;
          uconv, result))
    | Let { name; ty; v; rest } ->
      to_constr env ty >>= fun ty ->
      to_annot env name ty >>= fun name ->
      to_constr env v >>= fun v ->
      to_constr (push_rel (LocalDef (name, v, ty)) env) rest >>= fun rest ->
      ret (mkLetIn (name, v, ty, rest))
    | Lam (_bk, n, a, b) ->
      to_constr env a >>= fun a ->
      get_uconv >>= fun uconv ->
      let a =
        with_env_evm env uconv
          (fun env evd () ->
            if is_sprop_type_expression env evd a then
              normalize_sprop_type_wrappers env evd a
            else a)
          ()
      in
      to_annot env n a >>= fun n ->
      to_constr (push_rel (LocalAssum (n, a)) env) b >>= fun b ->
      ret (mkLambda (n, a, b))
    | Pi (_bk, n, a, b) ->
      to_constr env a >>= fun a ->
      get_uconv >>= fun uconv ->
      let a =
        with_env_evm env uconv
          (fun env evd () ->
            if is_sprop_type_expression env evd a then
              normalize_sprop_type_wrappers env evd a
            else a)
          ()
      in
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
      let nat_of_n =
        with_env_evm env uconv
          (fun env evd () ->
            let _, p =
              Evd.fresh_global env evd (Rocqlib.lib_ref "lean.Nat_of_N")
            in
            EConstr.to_constr evd p)
          ()
      in
      ret (nat_int nat nat_of_n i)
    | String s ->
      (* instantiate (N.append N.anon "Char") [] >>= fun char -> *)
      (* let (_, charu) = Constr.destInd char in *)
      instantiate (N.append N.anon "String") [] >>= fun _string ->
      let string_mk = N.append (N.append N.anon "String") "mk" in
      let string_of_list = N.append (N.append N.anon "String") "ofList" in
      let string_of_chars =
        if N.Map.mem string_mk !entries || not (N.Map.mem string_of_list !entries)
        then string_mk
        else string_of_list
      in
      instantiate string_of_chars [] >>= fun string_of_chars ->
      get_uconv >>= fun uconv ->
      let list, char =
        with_env_evm env uconv
          (fun env evd () ->
            let ty =
              Retyping.get_type_of env evd (EConstr.of_constr string_of_chars)
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
              Evd.fresh_global env evd (lookup_char_prim_ref ())
            in
            EConstr.to_constr evd mkChar)
          ()
      in
      ret (mk_string char list UVars.Instance.empty mkChar string_of_chars s)

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

and declare_def { name = n; ty; body; univs; } i =
  let declare_debug =
    Option.has_some (Sys.getenv_opt "ROCQ_LEAN_DECLARE_DEBUG")
  in
  let time_stage label f =
    if not declare_debug then f ()
    else
      let started = Unix.gettimeofday () in
      Feedback.msg_info Pp.(str "declare " ++ N.pp n ++ str ": " ++ str label);
      let result = f () in
      Feedback.msg_info
        Pp.(
          str "declare " ++ N.pp n ++ str ": " ++ str label ++ str " done in "
          ++ str (Printf.sprintf "%.3fs" (Unix.gettimeofday () -. started)));
      result
  in
  let ref, algs =
    match get_predeclared_def_some n i with
    | Some
        ( ( UInt32_size
          | Decidable_decide
          | Bool_and
          | Add
          | Mult
          | Pow
          | Pred
          | Sub
          | Beq
          | Ble
          | Blt
          | Nat_decEq
          | Nat_isValidChar
          | IsValidChar_UInt32
          | IsValidChar_UInt32_match_1_1
          | Char_ofNatAux
          | Char_ofNat ),
          _,
          (def_name, c) ) ->
      (* Hack to let the user predeclare some constants
         TODO make a more general Register-like API? *)
      Feedback.msg_info Pp.(Id.print def_name ++ str " is predeclared");
      (GlobRef.ConstRef c, [])
    | None ->
      let (uconv, ty, body), generated_direct =
        with_reification_cache (fun () ->
            capture_generated_universe_levels (fun () ->
                let uconv = start_uconv univs i in
                let uconv, ty =
                  time_stage "translate type" (fun () ->
                      to_constr empty_env ty uconv)
                in
                let ty =
                  time_stage "normalize proof type" (fun () ->
                      with_env_evm empty_env uconv
                        (fun env evd () ->
                          normalize_sprop_type_wrappers env evd ty)
                        ())
                in
                let uconv, body =
                  time_stage "translate body" (fun () ->
                      to_constr empty_env body uconv)
                in
                let body =
                  time_stage "transport body" (fun () ->
                      with_env_evm empty_env uconv
                        (fun env evd () ->
                          maybe_transport_to_expected env evd ty body)
                        ())
                in
                let body =
                  time_stage "eta-expand primitive record" (fun () ->
                      with_env_evm empty_env uconv
                        (fun env evd () ->
                          eta_expand_primitive_record_definition env evd ty
                            body)
                        ())
                in
                (uconv, ty, body)))
      in
      (* Translation records direct uses while traversing the Lean syntax, but
         a proof-producing post-pass may introduce fresh polymorphic constant
         applications afterwards.  Their constructors record those levels
         incrementally, avoiding a potentially exponential traversal of the
         completed shared proof term. *)
      let direct =
        time_stage "collect universes" (fun () ->
            Level.Set.union uconv.direct generated_direct)
      in
      let uconv = { uconv with direct } in
      let univs, algs =
        time_stage "build universe entry" (fun () -> univ_entry uconv univs)
      in
      let () =
        if Option.has_some (Sys.getenv_opt "ROCQ_LEAN_DECLARE_DUMP") then
          let env = Global.env () in
          let evd = Evd.from_env env in
          Feedback.msg_info
            Pp.(
              str "declare " ++ N.pp n ++ str " type:" ++ fnl ()
              ++ Printer.pr_constr_env env evd ty ++ fnl ()
              ++ str "declare " ++ N.pp n ++ str " body:" ++ fnl ()
              ++ Printer.pr_constr_env env evd body)
      in
      let ref =
        try
          time_stage "declare/check definition" (fun () ->
              quickdef ~name:(name_for n i) ~types:(Some ty) ~univs body)
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
      (ref, algs)
  in
  let () =
    let c = match ref with ConstRef c -> c | _ -> assert false in
    if expands_at_head body then begin
      Global.set_strategy (Conv_oracle.EvalConstRef c) Conv_oracle.Expand;
      expand_head_cache := N.Set.add n !expand_head_cache
    end
    else
      let height = height n body in
      Global.set_strategy (Conv_oracle.EvalConstRef c) (Level (-height))
  in
  let inst =
    match find_projection_alias n i with
    | Some alias ->
      if is_projection_wrapper alias.projection_record alias.projection_field body
      then alias.projection_inst
      else
        CErrors.user_err
          Pp.(
            str "Generated field " ++ N.pp n
            ++ str " is not the expected primitive-record projection")
    | None -> { ref; algs }
  in
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
  let uint32_is_legacy =
    declared_as (N.append N.anon "UInt32") 0 "lean.UInt32.legacy"
  in
  let mind, algs, ind_name, cnames, univs, squashy, projection_aliases =
    match get_predeclared_ind_some ~ctors ~uint32_is_legacy n i with
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
      ( mind,
        identity_algs (non_sprop_univ_count 1 i),
        ind_name,
        [ cname ],
        univs,
        squashy,
        [] )
    | Some
        ( ( ( False
            | Decidable
            | Bool
            | Nat
            | Int
            | Nat_le
            | Or
            | And
            | Fin
            | UInt32 _
            | BitVec
            | Char _ ) as k ),
          _,
          (ind_name, mind) ) ->
      (* Hack to let the user predeclare various types before running Lean Import
         TODO make a more general Register-like API? *)
      (* this case is for the ones without universes*)
      Feedback.msg_info Pp.(Id.print ind_name ++ str " is predeclared");
      let cnames = get_predeclared_cnames k n in
      let squashy = N.Map.get n !squash_info in
      (mind, [], ind_name, cnames, UContext.empty, squashy, [])
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
      let record, fields, ctys, field_names =
        match (indices, ctys) with
        | [], [ cty ] ->
          cty
          |> with_env_evm env_ind_params uconv (fun env evm cty ->
                 let fields, codom =
                   Reductionops.whd_decompose_prod env evm
                     (EConstr.of_constr cty)
                 in
                 let field_names =
                   List.rev_map
                     (fun (annot, _) ->
                       match annot.Context.binder_name with
                       | Names.Anonymous -> None
                       | Names.Name id ->
                         Some (N.append n (Names.Id.to_string id)))
                     fields
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
                 | [], true, _ -> (None, [], ctys, [])
                 | _ :: _, false, false ->
                   if
                     List.exists
                       (fun (na, _) ->
                         na.Context.binder_relevance
                         == EConstr.ERelevance.relevant)
                       fields
                   then
                     ( Some (Some [| default_proj_id |]),
                       fields,
                       [ cty' ],
                       field_names )
                   else (None, [], ctys, [])
                 | [], false, _ -> (None, [], ctys, [])
                 | _ :: _, true, false ->
                   if
                     List.for_all
                       (fun (na, _) ->
                         na.Context.binder_relevance
                         == EConstr.ERelevance.irrelevant)
                       fields
                   then
                     ( Some (Some [| default_proj_id |]),
                       fields,
                       [ cty' ],
                       field_names )
                   else (None, [], ctys, [])
                 | _ :: _, _, true -> (None, [], ctys, []))
        | _ -> (None, [], ctys, [])
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
            ~schemes (entry finite)
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
          | [] -> ()
          | _ :: _ ->
            let nested_shape =
              List.find_map
                (fun cty ->
                  let binders, _ = Term.decompose_prod cty in
                  List.find_map
                    (fun (_, binder_ty) ->
                      let head, args = Constr.decompose_app binder_ty in
                      match Constr.kind head with
                      | Ind ((mind, _), _)
                        when
                          List.exists
                            (MutInd.UserOrd.equal mind) !array_minds ->
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
                    N.Map.add name
                      { base_rec; nparams; nctors; focus; shape }
                      !nested_array_rec_info
                in
                add base_rec FocusMain;
                add (N.append n "rec_1") FocusArray;
                add (N.append n "rec_2") FocusList;
                match shape with
                | ArraySelf -> ()
                | ArrayProdSecond -> add (N.append n "rec_3") FocusProd)
              nested_shape
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
      let projection_aliases =
        let rec collect field projections names aliases =
          match projections, names with
          | [], [] -> List.rev aliases
          | projection :: projections, name :: names ->
            let aliases =
              match name, projection with
              | Some name,
                { Structures.Structure.proj_body = Some constant; _ } ->
                ( name,
                  {
                    projection_inst =
                      { ref = GlobRef.ConstRef constant; algs };
                    projection_record = n;
                    projection_ind = (mind, 0);
                    projection_field = field;
                  } )
                :: aliases
              | _ -> aliases
            in
            collect (field + 1) projections names aliases
          | _ ->
            CErrors.user_err
              Pp.(str "Primitive-record fields and projections differ")
        in
        collect 0 projections field_names []
      in
      let () =
        if N.equal n array_name then
          declare_array_all_scheme mind ind_name univs fields projections
        else if N.equal n prod_name then
          declare_prod_second_all_scheme mind ind_name univs projections
        else if
          last_projection_returns_only_parameter mind univs projections
        then declare_last_field_all_scheme mind ind_name univs projections
      in
      (mind, algs, ind_name, cnames, univs, squashy, projection_aliases)
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
  let () =
    List.iter
      (fun (name, alias) ->
        add_declared name i alias.projection_inst;
        add_projection_alias name i alias)
      projection_aliases
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
    let env = Environ.push_context ~strict:true univs (Global.env ()) in
    let env =
      match u with
      | LSProp -> env
      | Level u ->
        Environ.push_context_set ~strict:false (Univ.ContextSet.singleton u) env
    in
    let inst, uentry =
      let inst = UContext.instance univs in
      let csts = UContext.constraints univs in
      let { quals = qnames; univs = unames} = UContext.names univs in
      let uentry =
        match u with
        | LSProp -> UState.Polymorphic_entry univs
        | Level u ->
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
    let () =
      match (Global.lookup_mind mind).mind_packets.(0).mind_record, elim.ref with
      | Declarations.PrimRecord _, GlobRef.ConstRef constant ->
        Global.set_strategy (Conv_oracle.EvalConstRef constant)
          Conv_oracle.Expand;
        expand_head_cache := N.Set.add nrec !expand_head_cache
      | _ -> ()
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
                let _, head =
                  Reduction.whd_decompose_prod_decls env arg_ty
                in
                let head, _ = Constr.decompose_app head in
                match Constr.kind head with
                | Constr.Ind ((arg_mind, _), _) ->
                  not (MutInd.UserOrd.equal mind arg_mind)
                | _ -> true)
            ctor_args)
        packet.mind_nf_lc
    in
    if nested_recursive && not (N.Map.mem base_rec !nested_array_rec_info) then
      let info focus =
        { base_recs = [ base_rec ]; mind; nparams = List.length params; focus }
      in
      mutual_nested_rec_info :=
        N.Map.add base_rec (info (MutualMain 0)) !mutual_nested_rec_info;
      for aux = 0 to 31 do
        let aux_rec = N.append n ("rec_" ^ string_of_int (aux + 1)) in
        mutual_nested_rec_info :=
          N.Map.add aux_rec (info (MutualAux aux)) !mutual_nested_rec_info
      done
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
          uconv, (ind, ty, sort))
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
                uconv, (ctor_name, ctor_ty))
              uconv ind.ctors
          in
          let ctor_names, ctor_types = List.split ctors in
          ( (current + 1, uconv),
            (ind, ty, ctor_names, ctor_types) ))
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
          ~schemes:DeclareInd.None (entry finite)
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
      lean_scheme env ~dep:true (mind, ind_index) inst u, uentry
    in
    List.iteri
      (fun ind_index (ind, _ty, _ctor_names, _ctor_types) ->
        let squashy = N.Map.get ind.name !squash_info in
        let elims =
          if squashy.lean_squashes then [ "_indl", SchemeSProp ]
          else [ "_recl", SchemeType; "_indl", SchemeSProp ]
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
                :: List.map (UnivSubst.subst_univs_universe liftu) algs
            in
            let instance = { ref = elim; algs = scheme_algs } in
            let scheme_index =
              if squashy.lean_squashes then i
              else if sort = SchemeType then 2 * i
              else (2 * i) + 1
            in
            add_declared (N.append ind.name "rec") scheme_index instance)
          elims)
      packets;
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

let process_pending state ch = function
  | None -> Some state
  | Some (line_no, raw, inds) ->
    let first = List.hd inds in
    process_effect state ch ~line_no ~raw ~name:first.name (fun () ->
        match inds with
        | [ ind ] -> add_entry (Ind ind)
        | _ -> add_mutual_entries inds)

let rec do_input_pending state ~from ~until ~pending ch =
  if until = Some !lcnt then begin
    match process_pending state ch pending with
    | None -> state
    | Some state ->
      close_in ch;
      finish state;
      state
  end
  else
    match input_line ch with
    | exception End_of_file ->
      (match process_pending state ch pending with
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
    | line ->
      let pstate, oentry = do_line state.pstate line in
      let state = { state with pstate } in
      (match (just_parse (), oentry) with
      | false, Some (Entry (Ind ind)) ->
        let pending =
          match pending with
          | None -> Some (!lcnt, line, [ ind ])
          | Some (line_no, raw, inds) ->
            Some (line_no, raw, inds @ [ ind ])
        in
        incr lcnt;
        do_input_pending state ~from ~until ~pending ch
      | _ ->
        match process_pending state ch pending with
        | None -> state
        | Some state ->
          let state_opt =
            match (just_parse (), oentry) with
            | true, _ | false, None | false, Some (Nota _) -> Some state
            | false, Some (Entry entry) ->
              process_effect state ch ~line_no:!lcnt ~raw:line
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
  let cache (pstatev, setsv, declaredv, entriesv, squash_infov, heightv) =
    pstate := pstatev;
    sets := setsv;
    declared := declaredv;
    entries := entriesv;
    squash_info := squash_infov;
    height_cache := heightv;
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
  (* Proof-producing conversion creates opaque helper certificates while the
     import command is executing.  Join their checking futures before the
     command state is recorded; otherwise a large import can leave the safe
     environment ahead of the opaque summary restored by the vernacular
     transaction, and [.vo] serialization quite rightly rejects the
     unjoined environment. *)
  Opaques.Summary.join ();
  Lib.add_leaf (lean_obj (pstatev, !sets, !declared, !entries, !squash_info, !height_cache))
