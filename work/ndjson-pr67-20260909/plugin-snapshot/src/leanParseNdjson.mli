open LeanExpr

type parsing_state

val empty_state : parsing_state
val is_ndjson_line : string -> bool
val do_line : ?skip_declarations:bool -> lcnt:int -> parsing_state -> string -> parsing_state * action option
val pp_state : parsing_state -> Pp.t
