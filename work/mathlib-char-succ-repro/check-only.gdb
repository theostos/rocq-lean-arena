# Diagnostic only: reaching this point requires do_input to finish checking
# every requested declaration. No output artifact is produced or certified.
set breakpoint pending on
break camlLean_import__Lean__pack_lean_state_8573
commands
  silent
  printf "[diagnostic completed checking; stopped before checkpoint pack]\n"
  quit 0
end
source /home/theo/Documents/github/rocq-lean-typechecker/scripts/mathlib_ndjson_trace.gdb
