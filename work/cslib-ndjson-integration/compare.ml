open LeanExpr

module Pairs = Hashtbl.Make (struct
  type t = expr * expr
  let equal (a, b) (c, d) = a == c && b == d
  let hash x = Hashtbl.hash_param 10 30 x
end)

let seen = Pairs.create 1024
let same x y = if x <> y then failwith "metadata mismatch"
let name x y = if not (LeanName.equal x y) then failwith "name mismatch"
let rec expr a b =
  if not (Pairs.mem seen (a, b)) then begin
    Pairs.add seen (a, b) ();
    match a, b with
    | Bound x, Bound y -> same x y
    | Sort x, Sort y -> same x y
    | Const (n, u), Const (m, v) -> name n m; same u v
    | App (f, x), App (g, y) -> expr f g; expr x y
    | Lam (k, n, t, v), Lam (l, m, u, w)
    | Pi (k, n, t, v), Pi (l, m, u, w) -> same k l; name n m; expr t u; expr v w
    | Let x, Let y -> name x.name y.name; expr x.ty y.ty; expr x.v y.v; expr x.rest y.rest
    | Proj (n, i, x), Proj (m, j, y) -> name n m; same i j; expr x y
    | Nat x, Nat y -> same x y
    | String x, String y -> same x y
    | _ -> failwith "expression mismatch"
  end

let entry a b = match a, b with
  | Def x, Def y ->
    name x.name y.name; same x.univs y.univs; same x.hint y.hint;
    same x.kernel_opaque y.kernel_opaque; expr x.ty y.ty; expr x.body y.body
  | Ax x, Ax y -> name x.name y.name; same x.univs y.univs; expr x.ty y.ty
  | Ind x, Ind y ->
    name x.name y.name; same x.univs y.univs;
    List.iter2 (fun (k,n,t) (l,m,u) -> same k l; name n m; expr t u) x.params y.params;
    expr x.ty y.ty;
    List.iter2 (fun (n,t) (m,u) -> name n m; expr t u) x.ctors y.ctors
  | Quot x, Quot y -> name x y
  | _ -> failwith "declaration kind mismatch"

let read parse initial path =
  let input = open_in path in
  Fun.protect ~finally:(fun () -> close_in input) (fun () ->
    let rec loop state line entries quot =
      match input_line input with
      | raw ->
        let state, action = parse ~lcnt:line state raw in
        let entries, quot = match action with
          | None | Some (Nota _) -> entries, quot
          | Some (Entry (Quot _)) when quot -> entries, quot
          | Some (Entry ((Quot _) as e)) -> e :: entries, true
          | Some (Entry e) -> e :: entries, quot
          | Some (MutualInd members) ->
            List.fold_left (fun entries ind -> Ind ind :: entries) entries members, quot
        in
        loop state (line + 1) entries quot
      | exception End_of_file -> List.rev entries
    in loop initial 1 [] false)

let () =
  try
    let direct = read LeanParseNdjson.do_line LeanParseNdjson.empty_state Sys.argv.(1) in
    let legacy = read LeanParse.do_line LeanParse.empty_state Sys.argv.(2) in
    List.iter2 entry direct legacy;
    Printf.printf "MATCH: %d declarations, %d expression pairs\n%!"
      (List.length direct) (Pairs.length seen)
  with exn ->
    Format.eprintf "%s\n%!" (Pp.string_of_ppcmds (CErrors.print exn));
    exit 1
