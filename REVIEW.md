# Make orchestration unit tests independent of saved runs

Base: `review/checkpoint-cleanup`.

Use temporary mock toolchains, plans and stage sources instead of reading
the operator's compiled foundation or 15M checkpoint sources. Keep real shell
orchestration and refusal checks; the compiler and model remain mocked.

The historical-source range assertion is removed from the launcher test:
generated interval coverage belongs to `test_chunked_import.py`.

Validation from this isolated worktree:

```sh
env -u GENERATION_SYSTEMD_TEST -u CSLIB_LOOP_SYSTEMD_TEST \
  python3 -B -m unittest discover -s scripts/tests
```

171 tests: 169 passed, two opt-in systemd integration tests skipped.
No Rocq compilation, model call or live service mutation is involved.
