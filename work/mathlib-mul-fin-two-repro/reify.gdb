set pagination off
set confirm off
set debuginfod enabled off
set print thread-events off
set $reify_samples = 0
break kernel/cClosure.ml:872
commands
  silent
  set $reify_samples = $reify_samples + 1
  printf "[irrelevant reification] sample=%d\n", $reify_samples
  bt 45
  if $reify_samples >= 100
    disable 1
  end
  continue
end
run
