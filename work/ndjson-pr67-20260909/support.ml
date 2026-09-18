open LeanExpr
module P = LeanParseNdjson
module J = Yojson.Safe

let failures = ref 0
let count = ref 0
let check condition message = if not condition then failwith message
let test name f =
  incr count;
  try f (); Printf.printf "PASS\t%s\n%!" name
  with exn ->
    incr failures;
    let reason = match exn with
      | CErrors.UserError pp -> Pp.string_of_ppcmds pp
      | _ -> Printexc.to_string exn
    in
    Printf.printf "FAIL\t%s\t%s\n%!" name reason

let finish () =
  Printf.printf "TOTAL\t%d\tPASS\t%d\tFAIL\t%d\n%!"
    !count (!count - !failures) !failures;
  if !failures > 0 then exit 1

let meta = {|{"meta":{"exporter":{"name":"lean4export","version":"3.1.0"},"format":{"version":"3.1.0"},"lean":{"version":"4.30.0","githash":"test"}}}|}
let parse state line = P.do_line ~lcnt:17 state line
let add state line = fst (parse state line)
let ready () = add P.empty_state meta
let state lines = List.fold_left add (ready ()) lines
let reject state line =
  let rejected = try ignore (parse state line); false with CErrors.UserError _ -> true in
  check rejected "record was accepted instead of producing a parser error"

let assoc xs = `Assoc xs
let int n = `Int n
let str s = `String s
let list xs = `List xs
let member key json = J.Util.member key json
let set key value = function
  | `Assoc fields -> `Assoc ((key, value) :: List.remove_assoc key fields)
  | _ -> failwith "test fixture object expected"
let name id pre text = J.to_string (assoc ["in", int id; "str", assoc ["pre", int pre; "str", str text]])
let ax ?(name=1) ?(ty=0) () = J.to_string (assoc ["axiom", assoc [
  "name", int name; "type", int ty; "levelParams", list []; "isUnsafe", `Bool false]])
let base () = state [name 1 0 "example"; {|{"ie":0,"sort":0}|}; {|{"ie":1,"natVal":"42"}|}]
let definition ?(tag="def") ?(hints=`String "abbrev") () =
  let common = ["name", int 1; "type", int 0; "value", int 1;
    "levelParams", list []; "all", list [int 1]] in
  let fields = match tag with
    | "def" -> ("hints", hints) :: ("safety", str "safe") :: common
    | "opaque" -> ("isUnsafe", `Bool false) :: common
    | "thm" -> common
    | _ -> failwith "invalid test declaration tag"
  in
  J.to_string (assoc [tag, assoc fields])
let get_def ?tag ?hints state = match snd (parse state (definition ?tag ?hints ())) with
  | Some (Entry (Def value)) -> value
  | _ -> failwith "definition action expected"

let fixture_lines filename =
  let channel = open_in (Filename.concat Sys.argv.(1) filename) in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    let rec read acc = match input_line channel with
      | line -> read (line :: acc)
      | exception End_of_file -> List.rev acc
    in read [])

let fixture_inductive () =
  let rec find state = function
    | [] -> failwith "inductive fixture absent"
    | line :: rest ->
      let json = J.from_string line in
      if member "inductive" json <> `Null then state, json
      else find (add state line) rest
  in find P.empty_state (fixture_lines "bin_tree.ndjson")

let mutate_ctor field value json =
  let payload = member "inductive" json in
  let ctors = match member "ctors" payload with
    | `List (first :: rest) -> `List (set field value first :: rest)
    | _ -> failwith "constructors expected"
  in set "inductive" (set "ctors" ctors payload) json

let quot_state () = state [name 1 0 "Quot"; name 2 1 "mk";
  name 3 1 "lift"; name 4 1 "ind"; name 5 0 "Wrong"; {|{"ie":0,"sort":0}|}]
let quot kind name = J.to_string (assoc ["quot", assoc [
  "kind", str kind; "name", int name; "type", int 0; "levelParams", list []]])
