# Validate representation changes in fresh checkpoint generations

Base: `review/chunked-import`.

A changed importer/foundation cannot silently reuse old stored terms. Freeze
its tested foundation, bind a new toolchain manifest and create an unseeded
chain. Stage and hash relative Rocq Load dependencies; never copy old test .vo
files. Run the complete regression gate before full compilation.

Unit tests use temporary fixtures. The opt-in systemd test requires a configured
experimental toolchain. The live harness passed 58 Rocq stages on 2026-09-08;
this split does not rerun them or vendor bulk generated exports. Provisioned
work/*-repro fixtures and both toolchain checkouts remain required for that gate.

The active repair and running supervisor are unchanged by this review split.
