(* Read-only metadata diagnostic for the current Rocq summary_disk format.
   No library bodies or proofs are unmarshaled. *)
type summary = {
  name : Names.DirPath.t;
  deps : (Names.DirPath.t * Safe_typing.vodigest) array;
  ocaml : string;
  info : Library_info.t;
}

let summary_segment : summary ObjFile.id = ObjFile.make_id "summary"
let library_segment : unit ObjFile.id = ObjFile.make_id "library"

let inspect file =
  let input = ObjFile.open_in ~file in
  Fun.protect ~finally:(fun () -> ObjFile.close_in input) (fun () ->
    let summary, _ = ObjFile.marshal_in_segment input ~segment:summary_segment in
    let library = ObjFile.get_segment input ~segment:library_segment in
    Printf.printf "%s\n  %s library=%s\n" file
      (Names.DirPath.to_string summary.name) (Digest.to_hex library.hash);
    Array.iter (fun (name, Safe_typing.Dvo_or_vi digest) ->
      Printf.printf "  requires %s %s\n"
        (Names.DirPath.to_string name) (Digest.to_hex digest)) summary.deps)

let () = Array.iteri (fun index file -> if index > 0 then inspect file) Sys.argv
