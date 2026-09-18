open LeanExpr
open Support

let () =
  List.iter (fun filename -> test ("real fixture: " ^ filename) (fun () ->
    let _, actions = List.fold_left (fun (state, actions) line ->
      let state, action = parse state line in
      state, actions + (if action = None then 0 else 1))
      (P.empty_state, 0) (fixture_lines filename) in
    check (actions > 0) "real fixture emitted no declarations"))
    ["bin_tree.ndjson"; "list.ndjson"];
  test "repeated metadata" (fun () -> reject (ready ()) meta);
  test "duplicate meta keys" (fun () -> reject P.empty_state
    {|{"meta":{"format":{"version":"3.1.0"}},"meta":{"format":{"version":"3.1.0"}}}|});
  test "duplicate expression tags" (fun () -> reject (ready ()) {|{"ie":0,"bvar":0,"bvar":1}|});
  test "duplicate index keys" (fun () -> reject (ready ()) {|{"ie":0,"ie":1,"sort":0}|});
  test "mixed expression tags" (fun () -> reject (ready ()) {|{"ie":0,"bvar":0,"sort":0}|});
  test "mixed metadata and expression records" (fun () -> reject P.empty_state
    {|{"meta":{"format":{"version":"3.1.0"}},"ie":0,"sort":0}|});
  test "mixed name and expression records" (fun () -> reject (ready ())
    {|{"in":1,"str":{"pre":0,"str":"x"},"ie":0,"sort":0}|});
  test "mixed name and level records" (fun () -> reject (ready ())
    {|{"in":1,"str":{"pre":0,"str":"x"},"il":1,"succ":0}|});
  test "mixed declaration tags" (fun () ->
    let json = J.from_string (ax ()) in
    let json = set "def" (member "def" (J.from_string (definition ()))) json in
    reject (base ()) (J.to_string json));
  test "duplicate declaration tags" (fun () ->
    let payload = J.to_string (member "axiom" (J.from_string (ax ()))) in
    reject (base ()) ("{\"axiom\":" ^ payload ^ ",\"axiom\":" ^ payload ^ "}"));
  test "duplicate nested payload fields" (fun () -> reject (ready ())
    {|{"in":1,"str":{"pre":0,"str":"x","str":"y"}}|});
  List.iter (fun (label, line) -> test label (fun () -> reject (base ()) line)) [
    "negative name id", {|{"in":-1,"str":{"pre":0,"str":"x"}}|};
    "negative name parent", {|{"in":2,"str":{"pre":-1,"str":"x"}}|};
    "negative numeric name", {|{"in":2,"num":{"pre":1,"i":-1}}|};
    "negative level id", {|{"il":-1,"succ":0}|};
    "negative level reference", {|{"il":1,"succ":-1}|};
    "negative expression id", {|{"ie":-1,"sort":0}|};
    "negative expression reference", {|{"ie":2,"app":{"fn":-1,"arg":0}}|};
    "negative bvar", {|{"ie":2,"bvar":-1}|};
    "negative projection index", {|{"ie":2,"proj":{"typeName":1,"idx":-1,"struct":0}}|};
    "negative natural literal", {|{"ie":2,"natVal":"-1"}|};
    "mdata forward reference", {|{"ie":2,"mdata":{"expr":3}}|};
    "duplicate expression id", {|{"ie":0,"sort":0}|}
  ];
  test "sparse and out-of-order valid ids" (fun () ->
    let state = state [name 41 0 "Sparse"; name 2 41 "child";
      {|{"il":9,"succ":0}|}; {|{"il":2,"succ":9}|};
      {|{"ie":20,"sort":9}|}; {|{"ie":3,"const":{"name":2,"us":[2]}}|}] in
    match snd (parse state (ax ~name:2 ~ty:3 ())) with
    | Some (Entry (Ax {name; ty=Const (_, [U.Succ (U.Succ U.Prop)]); _})) ->
      check (LeanName.to_lean_string name = "Sparse.child") "sparse name changed"
    | _ -> failwith "sparse indexed declaration changed");
  test "mdata preserves referenced expression" (fun () ->
    let state = add (base ()) {|{"ie":2,"mdata":{"expr":1}}|} in
    match snd (parse state (ax ~ty:2 ())) with
    | Some (Entry (Ax {ty=Nat value; _})) -> check (Z.equal value (Z.of_int 42)) "mdata changed expression"
    | _ -> failwith "mdata did not retain expression");
  test "four quotient kinds emit exactly one Quot" (fun () ->
    let _, actions = List.fold_left (fun (state, actions) (kind, name) ->
      let state, action = parse state (quot kind name) in
      state, (match action with None -> actions | Some action -> action :: actions))
      (quot_state (), []) ["type",1; "ctor",2; "lift",3; "ind",4] in
    match actions with
    | [Entry (Quot name)] -> check (LeanName.to_lean_string name = "Quot") "wrong quotient name"
    | _ -> failwith (Printf.sprintf "expected one quotient action, got %d" (List.length actions)));
  List.iter (fun (label, kind, name) -> test label (fun () -> reject (quot_state ()) (quot kind name))) [
    "unknown quotient kind", "bogus", 1;
    "wrong quotient type name", "type", 5;
    "wrong quotient constructor name", "ctor", 3;
    "wrong quotient lift name", "lift", 2;
    "wrong quotient induction name", "ind", 2;
    "unknown quotient name id", "type", 99
  ];
  List.iter (fun (label, field, value) -> test label (fun () ->
    let state, json = fixture_inductive () in
    reject state (J.to_string (mutate_ctor field value json)))) [
      "invalid constructor owner", "induct", int 1;
      "invalid constructor cidx", "cidx", int 1;
      "negative constructor cidx", "cidx", int (-1);
      "invalid constructor parameter count", "numParams", int 0;
      "negative constructor parameter count", "numParams", int (-1)
    ];
  test "invalid constructor ordering" (fun () ->
    let state, json = fixture_inductive () in
    let payload = member "inductive" json in
    let ctors = match member "ctors" payload with `List xs -> `List (List.rev xs) | _ -> assert false in
    reject state (J.to_string (set "inductive" (set "ctors" ctors payload) json)));
  test "mismatched inductive constructor name list" (fun () ->
    let state, json = fixture_inductive () in
    let payload = member "inductive" json in
    let types = match member "types" payload with
      | `List [ind] -> `List [set "ctors" (list [int 6; int 5]) ind]
      | _ -> assert false in
    reject state (J.to_string (set "inductive" (set "types" types payload) json)));
  finish ()
