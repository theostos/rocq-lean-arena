
# 13 "/home/theo/Documents/github/rocq-lean-typechecker/work/ndjson-standalone-PV3AqH3u/source/src/g_lean.mlg"
 
open Stdarg
let init () = ()

# 8 "/home/theo/Documents/github/rocq-lean-typechecker/work/ndjson-standalone-PV3AqH3u/source/src/g_lean.ml"

let () = Vernacextend.static_vernac_extend ~plugin:(Some "coq-lean-import.plugin") ~command:"LeanImport" ~classifier:(fun ~atts:_ _ -> Vernacextend.classify_as_sideeff) ~ignore_kw:false ?entry:None 
         [(Vernacextend.TyML
         (false,
          Vernacextend.TyTerminal
          ("Lean",
           Vernacextend.TyTerminal
           ("Import",
            Vernacextend.TyNonTerminal (Extend.TUentry (Genarg.get_arg_tag wit_string),
            Vernacextend.TyNonTerminal (Extend.TUopt (Extend.TUentry (Genarg.get_arg_tag wit_int)),
            Vernacextend.TyNonTerminal (Extend.TUopt (Extend.TUentry (Genarg.get_arg_tag wit_int)),
            Vernacextend.TyNil))))),
          (let coqpp_body f from until () =
            Vernactypes.vtdefault (fun () -> 
# 19 "/home/theo/Documents/github/rocq-lean-typechecker/work/ndjson-standalone-PV3AqH3u/source/src/g_lean.mlg"
                                                                  Lean.import f ~from ~until 
# 25 "/home/theo/Documents/github/rocq-lean-typechecker/work/ndjson-standalone-PV3AqH3u/source/src/g_lean.ml"
) in
            fun f from until ?loc ~atts () ->
            coqpp_body f from until (Attributes.unsupported_attributes atts)),
          None))]

