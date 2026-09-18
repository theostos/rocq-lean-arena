open LeanExpr
open Support

let () =
  List.iter (fun (label, tag, hints, expected_hint, expected_opacity) -> test label (fun () ->
    let value = get_def ~tag ~hints (base ()) in
    check (value.hint = expected_hint) "reducibility hint changed";
    check (value.kernel_opaque = expected_opacity) "kernel opacity changed";
    check (LeanName.to_lean_string value.name = "example") "definition name changed";
    match value.ty, value.body with
    | Sort U.Prop, Nat n -> check (Z.equal n (Z.of_int 42)) "definition body changed"
    | _ -> failwith "definition type/body lost")) [
      "regular height zero preserved", "def", assoc ["regular",int 0], RegularHint 0, false;
      "regular height preserved", "def", assoc ["regular",int 123], RegularHint 123, false;
      "abbreviation hint preserved", "def", str "abbrev", AbbrevHint, false;
      "opaque hint remains transparent declaration", "def", str "opaque", OpaqueHint, false;
      "opaque declaration genuinely opaque", "opaque", str "opaque", OpaqueHint, true;
      "theorem declaration genuinely opaque", "thm", str "opaque", OpaqueHint, true
    ];
  test "legacy parser still emits LegacyHint" (fun () ->
    let state = List.fold_left (fun state line -> fst (LeanParse.do_line ~lcnt:1 state line))
      LeanParse.empty_state ["1 #NS 0 example"; "0 #ES 0"; "1 #ELN 42"] in
    match snd (LeanParse.do_line ~lcnt:2 state "#DEF 1 0 1") with
    | Some (Entry (Def value)) ->
      check (value.hint = LegacyHint) "legacy hint changed";
      check (not value.kernel_opaque) "legacy declaration became opaque"
    | _ -> failwith "legacy definition missing");
  finish ()
