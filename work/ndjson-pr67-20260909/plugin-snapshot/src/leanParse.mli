type parsing_state

val empty_state : parsing_state

val do_line : lcnt:int -> parsing_state -> string ->
  parsing_state * LeanExpr.action option

val pp_state : parsing_state -> Pp.t
