let rec compare_under budget e1 c1 e2 c2 =
  if !budget <= 0 then false else begin
  decr budget;
  (c1 == c2 && eq_usubs_fast e1 e2)
  ||
  match Constr.kind c1, Constr.kind c2 with
  | Cast (c1, _, _), _ -> compare_under budget e1 c1 e2 c2
  | _, Cast (c2, _, _) -> compare_under budget e1 c1 e2 c2
  | Rel i, Rel j -> begin
      match Esubst.expand_rel i (fst e1), Esubst.expand_rel j (fst e2) with
      | Inl _, Inl _ ->
        CClosure.equal_compact_peano_rel e1 i e2 j ||
        (match CClosure.inspect_substituted_rel e1 i,
               CClosure.inspect_substituted_rel e2 j with
        | Some _, Some _ ->
          fast_test_under budget el_id (mk_clos e1 c1) el_id (mk_clos e2 c2)
        | _ -> false)
      | Inr (k, _), Inr (k', _) -> Int.equal k k'
      | (Inl _ | Inr _), _ -> false
    end
  | Meta m1, Meta m2 -> Int.equal m1 m2
  | Var id1, Var id2 -> Id.equal id1 id2
  | Int i1, Int i2 -> Uint63.equal i1 i2
  | Float f1, Float f2 -> Float64.equal f1 f2
  | String s1, String s2 -> Pstring.equal s1 s2
  | Sort s1, Sort s2 ->
    let subst_instance_sort u s =
      if UVars.Instance.is_empty u then s else UVars.subst_instance_sort u s
    in
    let s1 = subst_instance_sort (snd e1) s1
    and s2 = subst_instance_sort (snd e2) s2 in
    Sorts.equal s1 s2
  | Prod (_,t1,c1), Prod (_,t2,c2) ->
    compare_under budget e1 t1 e2 t2
    && compare_under budget (usubs_lift e1) c1 (usubs_lift e2) c2
  | Lambda (_,t1,c1), Lambda (_,t2,c2) ->
    compare_under budget e1 t1 e2 t2
    && compare_under budget (usubs_lift e1) c1 (usubs_lift e2) c2
  | LetIn (_,b1,_,c1), LetIn (_,b2,_,c2) ->
    (* don't care about types when bodies are equal *)
    compare_under budget e1 b1 e2 b2
    && compare_under budget (usubs_lift e1) c1 (usubs_lift e2) c2
  | App (c1, l1), App (c2, l2) ->
    let len = Array.length l1 in
    Int.equal len (Array.length l2)
    && compare_under budget e1 c1 e2 c2
    && Array.equal_norefl (fun c1 c2 -> compare_under budget e1 c1 e2 c2) l1 l2
  | Proj (p1,_,c1), Proj (p2,_,c2) ->
    Projection.UserOrd.equal p1 p2 && compare_under budget e1 c1 e2 c2
  | Evar _, Evar _ -> false
  | Const (c1,u1), Const (c2,u2) ->
    (* The args length currently isn't used but may as well pass it. *)
    Constant.UserOrd.equal c1 c2 && eq_universes e1 e2 u1 u2
  | Ind (c1,u1), Ind (c2,u2) -> Ind.UserOrd.equal c1 c2 && eq_universes e1 e2 u1 u2
  | Construct (c1,u1), Construct (c2,u2) ->
    Construct.UserOrd.equal c1 c2 && eq_universes e1 e2 u1 u2
  | Case (ci1, u1, pms1, ((nas1, p1), _), _, s1, br1),
    Case (ci2, u2, pms2, ((nas2, p2), _), _, s2, br2)
    when Option.has_some (Sys.getenv_opt "ROCQ_EXPERIMENTAL_DEEP_FAST_TEST") ->
    Ind.UserOrd.equal ci1.ci_ind ci2.ci_ind
    && eq_universes e1 e2 u1 u2
    && Array.equal_norefl (fun c1 c2 -> compare_under budget e1 c1 e2 c2) pms1 pms2
    && Int.equal (Array.length nas1) (Array.length nas2)
    && compare_under budget (usubs_liftn (Array.length nas1) e1) p1
         (usubs_liftn (Array.length nas2) e2) p2
    && compare_under budget e1 s1 e2 s2
    && Array.equal_norefl (fun (nas1, b1) (nas2, b2) ->
         Int.equal (Array.length nas1) (Array.length nas2)
         && compare_under budget (usubs_liftn (Array.length nas1) e1) b1
              (usubs_liftn (Array.length nas2) e2) b2) br1 br2
  | Fix ((ln1, i1), (_, tl1, bl1)), Fix ((ln2, i2), (_, tl2, bl2))
    when Option.has_some (Sys.getenv_opt "ROCQ_EXPERIMENTAL_DEEP_FAST_TEST") ->
    Int.equal i1 i2 && Array.equal Int.equal ln1 ln2
    && Array.equal_norefl (fun c1 c2 -> compare_under budget e1 c1 e2 c2) tl1 tl2
    && (let n = Array.length tl1 in
        Array.equal_norefl (fun c1 c2 ->
          compare_under budget (usubs_liftn n e1) c1 (usubs_liftn n e2) c2) bl1 bl2)
  | CoFix (i1, (_, tl1, bl1)), CoFix (i2, (_, tl2, bl2))
    when Option.has_some (Sys.getenv_opt "ROCQ_EXPERIMENTAL_DEEP_FAST_TEST") ->
    Int.equal i1 i2
    && Array.equal_norefl (fun c1 c2 -> compare_under budget e1 c1 e2 c2) tl1 tl2
    && (let n = Array.length tl1 in
        Array.equal_norefl (fun c1 c2 ->
          compare_under budget (usubs_liftn n e1) c1 (usubs_liftn n e2) c2) bl1 bl2)
  | Array(_,t1,def1,ty1), Array(_,t2,def2,ty2) ->
    Array.equal_norefl (fun c1 c2 -> compare_under budget e1 c1 e2 c2) t1 t2
    && compare_under budget e1 def1 e2 def2
    && compare_under budget e1 ty1 e2 ty2
  | (Rel _ | Meta _ | Var _ | Sort _ | Prod _ | Lambda _ | LetIn _ | App _
    | Proj _ | Evar _ | Const _ | Ind _ | Construct _ | Case _ | Fix _
    | CoFix _ | Int _ | Float _ | String _ | Array _), _ -> false

  end

and fast_test_under budget lft1 term1 lft2 term2 =
  if !budget <= 0 then false else begin
  decr budget;
  match fterm_of term1, fterm_of term2 with
  | FLIFT (i, term1), _ -> fast_test_under budget (el_shft i lft1) term1 lft2 term2
  | _, FLIFT (j, term2) -> fast_test_under budget lft1 term1 (el_shft j lft2) term2
  | FCLOS (c1, (e1,u1)), FCLOS (c2, (e2,u2)) ->
    eq_lift lft1 lft2 &&
    compare_under budget (e1, u1) c1 (e2, u2) c2
  | FFix (fix1, e1), FFix (fix2, e2) ->
    eq_lift lft1 lft2 &&
    compare_under budget e1 (mkFix fix1) e2 (mkFix fix2)
  | FCoFix (fix1, e1), FCoFix (fix2, e2) ->
    eq_lift lft1 lft2 &&
    compare_under budget e1 (mkCoFix fix1) e2 (mkCoFix fix2)
  | FRel n1, FRel n2 ->
    Int.equal (reloc_rel n1 lft1) (reloc_rel n2 lft2)
  | FFlex (ConstKey (c1, u1)), FFlex (ConstKey (c2, u2)) ->
    Constant.UserOrd.equal c1 c2 && UVars.Instance.equal u1 u2
  | FFlex (VarKey x1), FFlex (VarKey x2) -> Id.equal x1 x2
  | FFlex (RelKey n1), FFlex (RelKey n2) ->
    Int.equal n1 n2 && eq_lift lft1 lft2
  | FAtom a1, FAtom a2 -> Constr.equal a1 a2
  | FInd (ind1, u1), FInd (ind2, u2) ->
    Ind.UserOrd.equal ind1 ind2 && UVars.Instance.equal u1 u2
  | FConstruct ((ctor1, u1), a1), FConstruct ((ctor2, u2), a2) ->
    Construct.UserOrd.equal ctor1 ctor2 && UVars.Instance.equal u1 u2 &&
    Array.equal_norefl (fun t1 t2 ->
      fast_test_under budget lft1 t1 lft2 t2) a1 a2
  | FApp (f1, a1), FApp (f2, a2) ->
    fast_test_under budget lft1 f1 lft2 f2 &&
    Array.equal_norefl (fun t1 t2 ->
      fast_test_under budget lft1 t1 lft2 t2) a1 a2
  | FProj (p1, _, c1), FProj (p2, _, c2) ->
    Projection.UserOrd.equal p1 p2 &&
    fast_test_under budget lft1 c1 lft2 c2
  | FLambda (n1, ds1, b1, e1), FLambda (n2, ds2, b2, e2) ->
    Int.equal n1 n2 && eq_lift lft1 lft2 &&
    let lambda ds body =
      List.fold_right (fun (na, ty) body -> mkLambda (na, ty, body)) ds body
    in compare_under budget e1 (lambda ds1 b1) e2 (lambda ds2 b2)
  | FInt n1, FInt n2 -> Uint63.equal n1 n2
  | FFloat n1, FFloat n2 -> Float64.equal n1 n2
  | FString s1, FString s2 -> Pstring.equal s1 s2
  | FPeanoNat n1, FPeanoNat n2 ->
    Ind.UserOrd.equal n1.peano_ind n2.peano_ind &&
    CClosure.PeanoNatValue.equal n1.peano_value n2.peano_value
  | FIrrelevant, FIrrelevant -> true
  | _ -> false
  end

let fast_test lft1 term1 lft2 term2 =
  fast_test_under (ref 1024) lft1 term1 lft2 term2

