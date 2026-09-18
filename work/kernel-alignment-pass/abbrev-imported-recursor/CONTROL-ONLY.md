This run manually set Stdlib `nat_rect` to Expand. It is a diagnostic control,
not approval of the regular-priority generated-recursor path. The initial
comment claiming that the importer expands all generated recursors was wrong:
`lean.ml:4290` does so only for primitive-record eliminators.

The checked-in fixture no longer adds that annotation. It must be rerun with
the new constructor-scrutinee unfolding preference before promotion.
