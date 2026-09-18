open LeanExpr
module N = LeanName
module Json = Yojson.Safe
module RRange = LeanParseShared.RRange

let err ~lcnt msg =
  CErrors.user_err Pp.(str "NDJSON parse error at line " ++ int lcnt ++ str ": " ++ str msg)

module Table = struct
  type 'a t = { dense : 'a RRange.t; sparse : 'a Int.Map.t }

  let empty = { dense = RRange.empty; sparse = Int.Map.empty }
  let singleton x = { empty with dense = RRange.singleton x }
  let length t = RRange.length t.dense + Int.Map.cardinal t.sparse

  let get t i =
    if i < 0 then raise Not_found
    else if i < RRange.length t.dense then RRange.get t.dense i
    else Int.Map.find i t.sparse

  let add ~lcnt kind i x t =
    let next = RRange.length t.dense in
    if i < 0 || i < next || Int.Map.mem i t.sparse then
      err ~lcnt ("invalid or duplicate " ^ kind ^ " id " ^ string_of_int i);
    if i = next then { t with dense = RRange.append t.dense x }
    else { t with sparse = Int.Map.add i x t.sparse }
end

type parsing_state = {
  names : N.t Table.t;
  exprs : expr Table.t;
  univs : U.t Table.t;
  seen_meta : bool;
}

let empty_state =
  {
    names = Table.singleton N.anon;
    exprs = Table.empty;
    univs = Table.singleton U.Prop;
    seen_meta = false;
  }

let is_ndjson_line l =
  let l = String.trim l in
  String.length l > 0 && l.[0] = '{'

let member ~lcnt name = function
  | `Assoc fields ->
    (match List.filter (fun (key, _) -> key = name) fields with
    | [] -> None
    | [ _, value ] -> Some value
    | _ -> err ~lcnt ("duplicate field " ^ name))
  | _ -> None

let require_member ~lcnt name json =
  match member ~lcnt name json with
  | Some v -> v
  | None -> err ~lcnt ("missing field " ^ name)

let require_string ~lcnt name json =
  match require_member ~lcnt name json with
  | `String s -> s
  | _ -> err ~lcnt ("field " ^ name ^ " must be a string")

let require_int ~lcnt name json =
  match require_member ~lcnt name json with
  | `Int i when i >= 0 -> i
  | _ -> err ~lcnt ("field " ^ name ^ " must be a non-negative integer")

let require_bool ~lcnt name json =
  match require_member ~lcnt name json with
  | `Bool b -> b
  | _ -> err ~lcnt ("field " ^ name ^ " must be a boolean")

let forbid_member ~lcnt name json =
  match member ~lcnt name json with
  | Some _ -> err ~lcnt ("unexpected field " ^ name)
  | None -> ()

let require_list ~lcnt name json =
  match require_member ~lcnt name json with
  | `List xs -> xs
  | _ -> err ~lcnt ("field " ^ name ^ " must be an array")

let as_int ~lcnt = function
  | `Int i when i >= 0 -> i
  | _ -> err ~lcnt "expected non-negative integer"

let tagged ~lcnt ~what keys json =
  match json with
  | `Assoc fields ->
    (match List.filter (fun (key, _) -> List.mem key keys) fields with
    | [ tag ] -> tag
    | _ -> err ~lcnt ("bad " ^ what ^ " record"))
  | _ -> err ~lcnt ("bad " ^ what ^ " record")

let get_name ~lcnt state i =
  try Table.get state.names i
  with Not_found -> err ~lcnt ("unknown name id " ^ string_of_int i)

let get_expr ~lcnt state i =
  try Table.get state.exprs i
  with Not_found -> err ~lcnt ("unknown expression id " ^ string_of_int i)

let get_univ ~lcnt state i =
  try Table.get state.univs i
  with Not_found -> err ~lcnt ("unknown level id " ^ string_of_int i)

let binders ~lcnt = function
  | "default" -> NotImplicit
  | "implicit" -> Maximal
  | "strictImplicit" -> NonMaximal
  | "instImplicit" -> Typeclass
  | b -> err ~lcnt ("unknown Lean binderInfo " ^ b)

let parse_name ~lcnt state json =
  let next = require_int ~lcnt "in" json in
  let base p = get_name ~lcnt state (require_int ~lcnt "pre" p) in
  let name =
    match tagged ~lcnt ~what:"name" [ "str"; "num" ] json with
    | "str", p -> N.append (base p) (require_string ~lcnt "str" p)
    | "num", p -> N.raw_append (base p) (string_of_int (require_int ~lcnt "i" p))
    | _ -> err ~lcnt "bad name record"
  in
  ({ state with names = Table.add ~lcnt "name" next name state.names }, None)

let parse_level ~lcnt state json =
  let next = require_int ~lcnt "il" json in
  let univ j = get_univ ~lcnt state (as_int ~lcnt j) in
  let level =
    match tagged ~lcnt ~what:"level" [ "succ"; "max"; "imax"; "param" ] json with
    | "succ", `Int base -> U.Succ (get_univ ~lcnt state base)
    | "max", `List [ a; b ] -> U.Max (univ a, univ b)
    | "imax", `List [ a; b ] -> U.IMax (univ a, univ b)
    | "param", `Int n -> U.UNamed (get_name ~lcnt state n)
    | _ -> err ~lcnt "bad level record"
  in
  ({ state with univs = Table.add ~lcnt "level" next level state.univs }, None)

let parse_nat_lit ~lcnt = function
  | `String n ->
    let n =
      try Z.of_string n
      with Invalid_argument _ | Failure _ -> err ~lcnt "bad natural literal"
    in
    if Z.sign n < 0 then err ~lcnt "natural literal must be non-negative";
    n
  | `Int n ->
    let n = Z.of_int n in
    if Z.sign n < 0 then err ~lcnt "natural literal must be non-negative";
    n
  | _ -> err ~lcnt "bad natural literal"

let parse_expr ~lcnt state json =
  let next = require_int ~lcnt "ie" json in
  let int_at p k = require_int ~lcnt k p in
  let name_at p k = get_name ~lcnt state (int_at p k) in
  let expr_at p k = get_expr ~lcnt state (int_at p k) in
  let abstraction p =
    ( binders ~lcnt (require_string ~lcnt "binderInfo" p),
      name_at p "name",
      expr_at p "type",
      expr_at p "body" )
  in
  let expr =
    match
      tagged ~lcnt ~what:"expression"
        [ "bvar"; "sort"; "const"; "app"; "lam"; "forallE"; "letE"; "proj";
          "natVal"; "strVal"; "mdata" ]
        json
    with
    | "bvar", n -> Bound (as_int ~lcnt n)
    | "sort", `Int u -> Sort (get_univ ~lcnt state u)
    | "const", p ->
      let us =
        require_list ~lcnt "us" p
        |> List.map (fun u -> get_univ ~lcnt state (as_int ~lcnt u))
      in
      Const (name_at p "name", us)
    | "app", p -> App (expr_at p "fn", expr_at p "arg")
    | "lam", p ->
      let bk, nm, ty, body = abstraction p in
      Lam (bk, nm, ty, body)
    | "forallE", p ->
      let bk, nm, ty, body = abstraction p in
      Pi (bk, nm, ty, body)
    | "letE", p ->
      Let
        {
          name = name_at p "name";
          ty = expr_at p "type";
          v = expr_at p "value";
          rest = expr_at p "body";
        }
    | "proj", p -> Proj (name_at p "typeName", int_at p "idx", expr_at p "struct")
    | "natVal", n -> Nat (parse_nat_lit ~lcnt n)
    | "strVal", `String s -> String s
    | "mdata", p -> expr_at p "expr"
    | _ -> err ~lcnt "bad expression record"
  in
  ({ state with exprs = Table.add ~lcnt "expression" next expr state.exprs }, None)

let level_params ~lcnt state payload =
  require_list ~lcnt "levelParams" payload
  |> List.map (fun n -> get_name ~lcnt state (as_int ~lcnt n))

let line_msg ~lcnt name =
  Feedback.msg_info Pp.(str "line " ++ int lcnt ++ str ": " ++ N.pp name)

let parse_axiom ~lcnt state payload =
  ignore (require_bool ~lcnt "isUnsafe" payload);
  let name = get_name ~lcnt state (require_int ~lcnt "name" payload) in
  line_msg ~lcnt name;
  let ty = get_expr ~lcnt state (require_int ~lcnt "type" payload) in
  let univs = level_params ~lcnt state payload in
  (state, Some (Entry (Ax { name; ty; univs })))

let reducibility_hint ~lcnt payload =
  match require_member ~lcnt "hints" payload with
  | `String "opaque" -> OpaqueHint
  | `String "abbrev" -> AbbrevHint
  | `Assoc [ "regular", `Int n ] when n >= 0 -> RegularHint n
  | _ -> err ~lcnt "field hints must be opaque, abbrev, or regular"

let require_safety ~lcnt payload =
  match require_member ~lcnt "safety" payload with
  | `String ("unsafe" | "safe" | "partial") -> ()
  | _ -> err ~lcnt "field safety must be unsafe, safe, or partial"

let parse_deflike_common ~hint ~kernel_opaque ~lcnt state payload =
  let name = get_name ~lcnt state (require_int ~lcnt "name" payload) in
  line_msg ~lcnt name;
  let ty = get_expr ~lcnt state (require_int ~lcnt "type" payload) in
  let body = get_expr ~lcnt state (require_int ~lcnt "value" payload) in
  let univs = level_params ~lcnt state payload in
  (state, Some (Entry (Def { name; ty; body; univs; hint; kernel_opaque })))

let validate_mutual_group ~lcnt state payload =
  require_list ~lcnt "all" payload
  |> List.iter (fun n -> ignore (get_name ~lcnt state (as_int ~lcnt n)))

let parse_def ~lcnt state payload =
  forbid_member ~lcnt "isUnsafe" payload;
  let hint = reducibility_hint ~lcnt payload in
  require_safety ~lcnt payload;
  validate_mutual_group ~lcnt state payload;
  parse_deflike_common ~hint ~kernel_opaque:false ~lcnt state payload

let parse_thm ~lcnt state payload =
  forbid_member ~lcnt "isUnsafe" payload;
  forbid_member ~lcnt "safety" payload;
  validate_mutual_group ~lcnt state payload;
  parse_deflike_common ~hint:OpaqueHint ~kernel_opaque:true ~lcnt state payload

let parse_opaque ~lcnt state payload =
  ignore (require_bool ~lcnt "isUnsafe" payload);
  validate_mutual_group ~lcnt state payload;
  parse_deflike_common ~hint:OpaqueHint ~kernel_opaque:true ~lcnt state payload

let parse_quot ~lcnt state payload =
  let kind = require_string ~lcnt "kind" payload in
  let expected = match kind with
    | "type" -> ["Quot"]
    | "ctor" -> ["Quot"; "mk"]
    | "lift" -> ["Quot"; "lift"]
    | "ind" -> ["Quot"; "ind"]
    | _ -> err ~lcnt "unknown quotient kind"
  in
  let name = get_name ~lcnt state (require_int ~lcnt "name" payload) in
  if not (N.equal name (N.append_list N.anon expected)) then
    err ~lcnt "quotient name does not match its kind";
  ignore (get_expr ~lcnt state (require_int ~lcnt "type" payload));
  ignore (level_params ~lcnt state payload);
  if kind <> "type" then (state, None)
  else begin
    line_msg ~lcnt name;
    (state, Some (Entry (Quot name)))
  end

let parse_ctor_val ~lcnt state ctor_json =
  let name = get_name ~lcnt state (require_int ~lcnt "name" ctor_json) in
  let ty = get_expr ~lcnt state (require_int ~lcnt "type" ctor_json) in
  (name, ty)

let parse_ind_param_shape ~lcnt f =
  try f ()
  with Assert_failure _ ->
    err ~lcnt "inductive parameter count does not match exported type"

let parse_ind_val ~lcnt state ind_json ctor_jsons =
  let name = get_name ~lcnt state (require_int ~lcnt "name" ind_json) in
  line_msg ~lcnt name;
  let nparams = require_int ~lcnt "numParams" ind_json in
  let univs = level_params ~lcnt state ind_json in
  let ctor_names = require_list ~lcnt "ctors" ind_json
    |> List.map (as_int ~lcnt) |> Array.of_list in
  if Array.length ctor_names <> List.length ctor_jsons then
    err ~lcnt "constructor count does not match inductive";
  List.iteri (fun i ctor ->
    if require_int ~lcnt "name" ctor <> ctor_names.(i) ||
       require_int ~lcnt "induct" ctor <> require_int ~lcnt "name" ind_json ||
       require_int ~lcnt "cidx" ctor <> i ||
       require_int ~lcnt "numParams" ctor <> nparams ||
       level_params ~lcnt state ctor <> univs then
      err ~lcnt "constructor does not match inductive") ctor_jsons;
  let ty0 = get_expr ~lcnt state (require_int ~lcnt "type" ind_json) in
  let params, ty =
    parse_ind_param_shape ~lcnt (fun () -> LeanParseShared.pop_params nparams ty0)
  in
  let ctors =
    ctor_jsons
    |> List.map (parse_ctor_val ~lcnt state)
    |> List.map (fun (ctor_name, ctor_ty) ->
      (ctor_name, parse_ind_param_shape ~lcnt (fun () ->
        LeanParseShared.fix_ctor name nparams ctor_ty)))
  in
  Entry (Ind { name; params; ty; ctors; univs })

let parse_inductive ~lcnt state payload =
  let types = require_list ~lcnt "types" payload in
  let ctors = require_list ~lcnt "ctors" payload in
  match types with
  | [ ind_json ] -> (state, Some (parse_ind_val ~lcnt state ind_json ctors))
  | _ -> err ~lcnt "mutual inductive groups are not supported by the current importer model"

let parse_meta ~lcnt state json =
  if state.seen_meta then err ~lcnt "duplicate metadata object";
  let meta = require_member ~lcnt "meta" json in
  let format = require_member ~lcnt "format" meta in
  let version = require_string ~lcnt "version" format in
  if version <> "3.1.0" then err ~lcnt ("unsupported export format " ^ version);
  ({ state with seen_meta = true }, None)

let do_line ?(skip_declarations = false) ~lcnt state l =
  let l = String.trim l in
  if l = "" then (state, None)
  else
    let json =
      try Json.from_string l
      with Yojson.Json_error msg -> err ~lcnt msg
    in
    let tag, payload = tagged ~lcnt ~what:"NDJSON"
      ["meta"; "in"; "il"; "ie"; "axiom"; "def"; "thm"; "opaque"; "quot"; "inductive"] json
    in
    match tag with
    | "meta" -> parse_meta ~lcnt state json
    | _ when not state.seen_meta -> err ~lcnt "expected metadata object before export records"
    | "in" -> parse_name ~lcnt state json
    | "il" -> parse_level ~lcnt state json
    | "ie" -> parse_expr ~lcnt state json
    | _ when skip_declarations -> (state, None)
    | "axiom" -> parse_axiom ~lcnt state payload
    | "def" -> parse_def ~lcnt state payload
    | "thm" -> parse_thm ~lcnt state payload
    | "opaque" -> parse_opaque ~lcnt state payload
    | "quot" -> parse_quot ~lcnt state payload
    | "inductive" -> parse_inductive ~lcnt state payload
    | _ -> assert false

let pp_state state =
  let open Pp in
  str "- " ++ int (Table.length state.univs) ++ str " universe expressions" ++ fnl () ++
  str "- " ++ int (Table.length state.names) ++ str " names" ++ fnl () ++
  str "- " ++ int (Table.length state.exprs) ++ str " expression nodes" ++ fnl ()
