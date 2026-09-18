(* Diagnostic: reuse a previously checked library, then recheck precisely one
   stored proof using the checker's actual constant-checking function. This is
   NOT whole-library validation and never creates a production artifact. *)
open Names
open Coq_checklib

let () =
  let senv = Diagnostic_main.init_with_argv Sys.argv in
  let module_name = "MathlibTo35000000" in
  let label = Option.default "isIntegral_of_isIntegralElem_of_monic_of_natDegree_lt"
    (Sys.getenv_opt "ROCQ_RECHECK_LABEL") in
  let root = Diagnostic_library.try_locate_qualified_library
    (Diagnostic_library.LogicalFile {dirpath=[]; basename=module_name}) in
  let needed = List.rev (Diagnostic_library.intern_library
    ~intern_mode:Diagnostic_library.Root ~enable_VM:false
    Diagnostic_library.LibrarySet.empty root []) in
  let reused = List.fold_left (fun set (dir, _) ->
    Diagnostic_library.LibrarySet.add dir set) Diagnostic_library.LibrarySet.empty needed in
  let senv, _ = List.fold_left (Diagnostic_library.check_one_lib reused)
    (senv, Mod_checking.empty_opaques) needed in
  let env = Safe_typing.env_of_safe_env senv in
  let constant = Constant.make2 (ModPath.MPfile (DirPath.make [Id.of_string module_name]))
    (Id.of_string label) in
  let body = Environ.lookup_constant constant env in
  Reviewed_mod_checking.set_indirect_accessor Diagnostic_library.indirect_accessor;
  Printf.eprintf "[target begin] %s cpu=%.3f\n%!" label (Sys.time ());
  let started = Sys.time () in
  ignore (Reviewed_mod_checking.check_constant_declaration env
    Reviewed_mod_checking.empty_state constant body false);
  Printf.eprintf "[target checked] %s cpu_seconds=%.6f\n%!" label (Sys.time () -. started)
