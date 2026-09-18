open Constant_deps

exception MeasurementInterrupt

let () =
  let constants = Array.init 4000 (fun i -> name ("interrupt" ^ string_of_int i)) in
  let env = ref (add constants.(0) (Declarations.Undef None) Environ.empty_env) in
  for i = 1 to Array.length constants - 1 do
    env := add constants.(i) (Declarations.Def (term constants.(i - 1))) !env
  done;
  let previous = Sys.signal Sys.sigalrm (Sys.Signal_handle (fun _ -> raise MeasurementInterrupt)) in
  ignore (Unix.setitimer Unix.ITIMER_REAL { Unix.it_interval = 0.; it_value = 0.05 });
  let interrupted =
    try
      ignore (Environ.constant_depends_on !env constants.(3999) (name "absent_interrupt"));
      false
    with MeasurementInterrupt -> true
  in
  ignore (Unix.setitimer Unix.ITIMER_REAL { Unix.it_interval = 0.; it_value = 0. });
  Sys.set_signal Sys.sigalrm previous;
  assert interrupted;
  assert (Environ.constant_depends_on !env constants.(1) constants.(0));
  Printf.printf "Interrupted dependency query propagated; subsequent query passed.\n%!"
