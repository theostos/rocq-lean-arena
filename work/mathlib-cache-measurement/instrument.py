#!/usr/bin/env python3
"""Print an apply_patch patch; instrumentation does not change cache policy."""
import difflib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
path = ROOT / "_worktrees/rocq/compact-peano-view/kernel/environ.ml"
original = (HERE / "environ.original.ml").read_text()
assert path.read_text() == original
module = r'''
module DependencyProfile = struct
  let enabled = Sys.getenv_opt "ROCQ_MEASURE_DEPENDENCIES" = Some "1"
  let queries = ref 0
  let hits = ref 0
  let misses = ref 0
  let uncached = ref 0
  let builds = ref 0
  let interrupted_queries = ref 0
  let interrupted_builds = ref 0
  let query_cpu = ref 0.
  let build_cpu = ref 0.
  let build_depth = ref 0
  let last_report = ref 0.

  let report stage =
    let now = Sys.time () in
    last_report := now;
    Printf.eprintf
      "[dependency profile] stage=%s cpu=%.6f query_cpu=%.6f build_cpu=%.6f queries=%d hits=%d misses=%d uncached=%d builds=%d interrupted_queries=%d interrupted_builds=%d build_depth=%d\n%!"
      stage now !query_cpu !build_cpu !queries !hits !misses !uncached
      !builds !interrupted_queries !interrupted_builds !build_depth

  let query f =
    incr queries;
    let started = Sys.time () in
    let finish () =
      let stopped = Sys.time () in
      query_cpu := !query_cpu +. stopped -. started;
      if stopped -. !last_report >= 1. then report "sample"
    in
    match f () with
    | value -> finish (); value
    | exception error ->
      let error = Exninfo.capture error in
      incr interrupted_queries;
      finish ();
      Exninfo.iraise error

  let build f =
    let outer = !build_depth = 0 in
    let started = if outer then Sys.time () else 0. in
    if outer then incr builds;
    incr build_depth;
    let finish () =
      decr build_depth;
      if outer then build_cpu := !build_cpu +. Sys.time () -. started
    in
    match f () with
    | value -> finish (); value
    | exception error ->
      let error = Exninfo.capture error in
      if outer then incr interrupted_builds;
      finish ();
      Exninfo.iraise error

  let () = if enabled then begin report "start"; at_exit (fun () -> report "exit") end
end

'''
updated = original.replace("module DepCache :\n", module + "module DepCache :\n", 1)
updated = updated.replace("| None -> Inr ignore\n", "| None ->\n  if DependencyProfile.enabled then incr DependencyProfile.uncached;\n  Inr ignore\n", 1)
updated = updated.replace("  | None -> Inr (fun s -> cache := Cmap_env.add kn s !cache)\n  | Some s -> Inl s\n",
    "  | None ->\n    if DependencyProfile.enabled then incr DependencyProfile.misses;\n    Inr (fun s -> cache := Cmap_env.add kn s !cache)\n  | Some s ->\n    if DependencyProfile.enabled then incr DependencyProfile.hits;\n    Inl s\n", 1)
start = updated.index("  | Inr set ->\n", updated.index("let rec constant_dependencies_with_cache"))
end = updated.index("\nlet constant_dependencies env kn", start)
body = updated[start:end]
body = body.replace("  | Inr set ->\n", "  | Inr set ->\n    let compute () =\n", 1)
body = body.rstrip() + "\n    in\n    if DependencyProfile.enabled then DependencyProfile.build compute else compute ()\n"
updated = updated[:start] + body + updated[end:]
updated = updated.replace("  Cset_env.mem cst2 (constant_dependencies env cst1)\n",
    "  let compute () = Cset_env.mem cst2 (constant_dependencies env cst1) in\n  if DependencyProfile.enabled then DependencyProfile.query compute else compute ()\n", 1)
print("*** Begin Patch\n*** Update File: " + str(path))
for line in list(difflib.unified_diff(original.splitlines(True), updated.splitlines(True)))[2:]:
    print("@@" if line.startswith("@@") else line.rstrip("\n"))
print("*** End Patch")
