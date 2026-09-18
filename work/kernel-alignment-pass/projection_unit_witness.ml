open Names
open Constr
open Entries

let () =
  let id = Id.of_string in
  let binder = Context.make_annot (Name (id "A")) Sorts.Relevant in
  let proof_binder = { binder with Context.binder_relevance = Sorts.Irrelevant } in
  let proof_type = mkProd (binder, mkSProp,
      mkProd (proof_binder, mkRel 1, mkRel 2)) in
  let proof_value = mkLambda (binder, mkSProp,
      mkLambda (proof_binder, mkRel 1, mkRel 1)) in
  let entry = {
    mind_entry_record = Some (Some [|id "self"|]);
    mind_entry_finite = Declarations.BiFinite;
    mind_entry_params = [Context.Rel.Declaration.LocalAssum (binder, mkSet)];
    mind_entry_inds = [{
      mind_entry_typename = id "EtaUnit";
      mind_entry_arity = mkSet;
      mind_entry_consnames = [id "eta_unit"];
      mind_entry_lc = [mkProd (proof_binder, proof_type,
        mkApp (mkRel 3, [|mkRel 2|]))];
    }];
    mind_entry_universes = Monomorphic_ind_entry;
    mind_entry_variance = None;
    mind_entry_private = None;
  } in
  let _, safe = Safe_typing.start_library (DirPath.make [id "ProjectionWitness"])
      Safe_typing.empty_environment in
  (* This profile models the importer's conditional elimination relaxation.
     Default Rocq gives this relevant, proof-only record NoEta; the strict
     checker separately rejects the relaxed serialized flags. *)
  let typing_flags = { (Environ.typing_flags (Safe_typing.env_of_safe_env safe))
      with Declarations.check_eliminations = false } in
  let (mind, _), safe = Safe_typing.add_mind ~typing_flags (id "EtaUnit") entry safe in
  let safe = Safe_typing.register_unit_like (mind, 0) safe in
  let unit_at value = mkApp (mkIndU ((mind, 0), UVars.Instance.empty), [|value|]) in
  let holder = { entry with mind_entry_inds = [{
    mind_entry_typename = id "Holder";
    mind_entry_arity = mkSet;
    mind_entry_consnames = [id "holder"];
    mind_entry_lc = [mkProd (binder, unit_at (mkRel 1),
      mkApp (mkRel 3, [|mkRel 2|]))];
  }]} in
  let (holder_mind, _), safe = Safe_typing.add_mind (id "Holder") holder safe in
  let env = Safe_typing.env_of_safe_env safe in
  let mib = Environ.lookup_mind holder_mind env in
  let repr, relevance = Declareops.inductive_make_projection (holder_mind, 0) mib
      ~proj_arg:0 in
  let var name = mkVar (id name) in
  let assume name typ env = Environ.push_named Environ.ProofVar
      (Context.Named.Declaration.LocalAssum
        (Context.make_annot (id name) Sorts.Relevant, typ)) env in
  let env = env |> assume "A" mkSet |> assume "B" mkSet
      |> assume "r" (mkApp (mkIndU ((holder_mind, 0), UVars.Instance.empty), [|var "A"|]))
      |> assume "x" (unit_at (var "A")) in
  let projected = mkProj (Projection.make repr false, relevance, var "r") in
  let ctor name = mkApp (mkConstructU (((mind, 0), 1), UVars.Instance.empty),
      [|var name; proof_value|]) in
  List.iter (fun term -> ignore (Typeops.infer env term))
      [projected; ctor "A"; ctor "B"];
  assert (Reviewed_conversion.is_eta_record env ((mind, 0), UVars.Instance.empty));
  assert (Reviewed_conversion.default_conv Reviewed_conversion.CONV env projected (ctor "A") = Ok ());
  let conv = Reviewed_conversion.gen_conv ~typed:true Reviewed_conversion.CONV
      ~reds:TransparentState.empty env in
  assert (conv projected (ctor "A") = Ok ());
  assert (conv (ctor "A") projected = Ok ());
  let bad = conv projected (ctor "B") = Ok () in
  Printf.printf "opaque projection/unit constructor incompatible types accepted: %b\n%!" bad;
  assert (not bad);
  assert (conv (ctor "B") projected = Error ());
  let partial = mkApp (mkConstructU (((mind, 0), 1), UVars.Instance.empty), [|var "A"|]) in
  ignore (Typeops.infer env partial);
  let partial_bad = Reviewed_conversion.conv env partial (var "x") = Ok () in
  Printf.printf "partial unit constructor accepted as inhabitant: %b\n%!" partial_bad;
  assert (not partial_bad);
  assert (Reviewed_conversion.conv env (var "x") partial = Error ());
  assert (Reviewed_conversion.default_conv Reviewed_conversion.CONV env partial (var "x") = Error ());
  assert (Reviewed_conversion.default_conv Reviewed_conversion.CONV env (var "x") partial = Error ());

  let holder_at value = mkApp (mkIndU ((holder_mind, 0), UVars.Instance.empty), [|value|]) in
  let projection source = mkProj (Projection.make repr false, relevance, source) in
  let lambda body = mkLambda (binder, holder_at (var "A"), body) in
  let projected_lambda = lambda (projection (mkRel 1)) in
  assert (conv projected_lambda (lambda (ctor "A")) = Ok ());
  assert (conv (lambda (ctor "A")) projected_lambda = Ok ());
  assert (conv projected_lambda (lambda (ctor "B")) = Error ());
  assert (conv (lambda (ctor "B")) projected_lambda = Error ());
  let env = env |> assume "f" (mkProd (binder, var "A", holder_at (var "A")))
      |> assume "a" (var "A") in
  let projected_call = projection (mkApp (var "f", [|var "a"|])) in
  ignore (Typeops.infer env projected_call);
  let conv = Reviewed_conversion.gen_conv ~typed:true Reviewed_conversion.CONV
      ~reds:TransparentState.empty env in
  assert (conv projected_call (ctor "A") = Ok ());
  assert (conv projected_call (ctor "B") = Error ());
  print_endline "projection unit type witness: PASS"
