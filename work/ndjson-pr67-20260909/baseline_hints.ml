open Support

let () =
  test "baseline regular height preserved" (fun () ->
    check ((get_def ~hints:(assoc ["regular", int 123]) (base ())).height = Some 123)
      "regular height changed");
  test "abbreviation and opaque hints distinguishable" (fun () ->
    let state = base () in
    let abbrev = get_def ~hints:(str "abbrev") state in
    let opaque = get_def ~hints:(str "opaque") state in
    check (abbrev <> opaque) "abbrev and opaque collapse to identical definitions (height=None)");
  test "opaque declaration distinct from opaque hint" (fun () ->
    let state = base () in
    let hint = get_def ~hints:(str "opaque") state in
    let declaration = get_def ~tag:"opaque" state in
    check (hint <> declaration) "genuine opaque declaration and transparent opaque hint collapse");
  test "theorem declaration distinct from transparent definition" (fun () ->
    let state = base () in
    check (get_def ~tag:"thm" state <> get_def state)
      "theorem and transparent definition collapse");
  finish ()
