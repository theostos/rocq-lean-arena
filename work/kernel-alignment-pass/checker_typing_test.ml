open Constr
open Names
open Declarations

module Check = Reviewed_mod_checking

let () =
  let env = Environ.empty_env in
  let env = Environ.set_typing_flags
    { (Environ.typing_flags env) with unfold_dep_heuristic = true } env in
  let na = Context.anonR in
  let infer body =
    let cb = snd (Constant_typing.infer_definition ~sec_univs:None env
      Entries.{ definition_entry_body = body;
                definition_entry_secctx = None;
                definition_entry_type = None;
                definition_entry_universes = Monomorphic_entry;
                definition_entry_inline_code = false }) in
    { cb with const_body_code = Vmemitcodes.BCuncompiled } in
  let kn = Constant.make2
    (ModPath.MPfile (DirPath.make [Id.of_string "CheckerTyping"]))
    (Id.of_string "test") in
  let check cb =
    ignore (Check.check_constant_declaration env Check.empty_state kn cb false) in
  let reject cb =
    try check cb; failwith "checker accepted an ill-typed constant"
    with Type_errors.TypeError _ -> () in
  let identity = infer
    (mkLambda (na, mkSort Sorts.type1,
      mkLambda (na, mkRel 1, mkRel 1))) in
  check identity;
  (* Both the replacement type and the body are individually well-typed.
     Only their final comparison must reject this forged declaration. *)
  reject { identity with const_type = mkSort Sorts.type1 };
  let sort = infer (mkSort Sorts.type1) in
  check sort;
  (* Cumulativity must not silently reverse the universe inequality. *)
  reject { sort with const_type = mkSort Sorts.type1 };
  (* A larger declared universe remains a valid cumulative check. *)
  let prop = infer (mkSort Sorts.prop) in
  check { prop with const_type = sort.const_type };
  (* The optimized final comparison must not bypass body inference. *)
  reject { identity with const_body =
    Def (mkApp (mkSort Sorts.type1, [|mkSort Sorts.prop|])) };
  print_endline "independent checker typing: PASS (body, final type, cumulative direction)"
