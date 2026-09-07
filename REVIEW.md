# Preserve Lean reducibility metadata in the arena converter

Base: `b7febb4cd2968812d8b5185b1d8d10b7f49bcfaf`. Compare against this base, not upstream.

Emit abbreviation, regular-height, opaque-hint and genuinely opaque records. This is the exporter counterpart to importer review/reducibility-hints. Copies the converter used by the current experiment out of the dependency checkout, with small marker/validation tests.

## Validation

Not rebuilt at this split head. Earlier checks cover the combined experimental sources, not this intermediate branch.

This is an experimental review branch, not a claim of a complete cslib check.
