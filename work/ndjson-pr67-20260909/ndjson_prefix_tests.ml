open LeanExpr
open Support

let skip state line =
  let state, action = P.do_line ~skip_declarations:true ~lcnt:23 state line in
  check (action = None) "prefix scan emitted a declaration";
  state

let reject_skip state line =
  let rejected = try ignore (skip state line); false with CErrors.UserError _ -> true in
  check rejected "prefix scan accepted malformed dictionary record"

let sparse_def = {|{"def":{"name":2,"type":20,"value":3,"levelParams":[],"all":[2],"safety":"safe","hints":{"regular":7}}}|}
let prefix_state () = List.fold_left skip P.empty_state [
  meta; name 20 0 "Context"; name 2 20 "child";
  {|{"il":9,"succ":0}|}; {|{"il":2,"succ":9}|};
  {|{"ie":20,"sort":9}|}; {|{"ie":3,"const":{"name":2,"us":[2]}}|};
  ax ~name:2 ~ty:20 (); sparse_def
]

let interleaved () = state [
  name 1 0 "first"; name 5 0 "sparse"; name 2 5 "second";
  name 3 2 "third"; name 4 3 "fourth"; name 6 5 "sixth";
  {|{"il":1,"succ":0}|}; {|{"il":5,"succ":1}|};
  {|{"il":2,"succ":5}|}; {|{"il":3,"succ":2}|};
  {|{"il":4,"succ":3}|}; {|{"il":6,"succ":4}|};
  {|{"ie":0,"natVal":0}|}; {|{"ie":5,"natVal":50}|};
  {|{"ie":1,"natVal":10}|}; {|{"ie":2,"natVal":20}|};
  {|{"ie":3,"natVal":30}|}; {|{"ie":4,"natVal":40}|};
  {|{"ie":6,"sort":6}|}
]

let () =
  test "prefix dictionaries retain names levels expressions" (fun () ->
    match snd (parse (prefix_state ()) sparse_def) with
    | Some (Entry (Def value)) ->
      check (LeanName.to_lean_string value.name = "Context.child") "prefix name missing";
      check (value.ty = Sort (U.Succ U.Prop)) "prefix level missing";
      check (value.body = Const (value.name, [U.Succ (U.Succ U.Prop)])) "prefix expression missing";
      check (value.hint = RegularHint 7) "post-prefix definition hint changed"
    | _ -> failwith "definition after prefix was not emitted");
  test "prefix scan handles entire real fixture" (fun () ->
    ignore (List.fold_left skip P.empty_state (fixture_lines "bin_tree.ndjson")));
  test "prefix scan leaves quotient type declaration available" (fun () ->
    let state = skip (quot_state ()) (quot "type" 1) in
    match snd (parse state (quot "type" 1)) with
    | Some (Entry (Quot _)) -> ()
    | _ -> failwith "prefix scan consumed quotient declaration");
  test "prefix scan rejects records before metadata" (fun () ->
    reject_skip P.empty_state (name 1 0 "x"));
  test "prefix scan rejects repeated metadata" (fun () -> reject_skip (ready ()) meta);
  test "prefix scan rejects invalid name reference" (fun () ->
    reject_skip (ready ()) (name 1 99 "x"));
  test "prefix scan rejects invalid universe reference" (fun () ->
    reject_skip (ready ()) {|{"il":1,"succ":99}|});
  test "prefix scan rejects mdata forward reference" (fun () ->
    reject_skip (ready ()) {|{"ie":0,"mdata":{"expr":1}}|});
  test "prefix scan rejects mixed declaration tags" (fun () ->
    reject_skip (ready ()) {|{"axiom":{},"def":{}}|});
  test "dense sparse interleaving preserves all entries" (fun () ->
    let state = interleaved () in
    List.iter (fun (id, expected) -> match snd (parse state (ax ~name:5 ~ty:id ())) with
      | Some (Entry (Ax {name; ty=Nat value; _})) ->
        check (LeanName.to_lean_string name = "sparse") "sparse name overwritten";
        check (Z.equal value (Z.of_int expected)) "interleaved expression overwritten"
      | _ -> failwith "interleaved expression was lost") [0,0;1,10;2,20;3,30;4,40;5,50];
    match snd (parse state (ax ~name:6 ~ty:6 ())) with
    | Some (Entry (Ax {name; ty=Sort level; _})) ->
      check (LeanName.to_lean_string name = "sparse.sixth") "post-gap name lost";
      let rec height = function U.Prop -> 0 | U.Succ u -> 1 + height u | _ -> -100 in
      check (height level = 6) "interleaved levels changed"
    | _ -> failwith "post-gap expression lost");
  List.iter (fun (label, line) -> test label (fun () -> reject (interleaved ()) line)) [
    "interleaved duplicate dense name", name 2 0 "replacement";
    "interleaved duplicate sparse name", name 5 0 "replacement";
    "interleaved duplicate dense level", {|{"il":2,"succ":0}|};
    "interleaved duplicate sparse level", {|{"il":5,"succ":0}|};
    "interleaved duplicate dense expression", {|{"ie":2,"natVal":99}|};
    "interleaved duplicate sparse expression", {|{"ie":5,"natVal":99}|}
  ];
  finish ()
