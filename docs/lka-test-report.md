# LKA rocq-lean-import report

Generated: 2026-07-08 11:59:47 CEST

Configuration:
- opam switch: `rocq93_dev`
- no-stdout-progress timeout: `600s` (`ROCQLKA_PROGRESS_TIMEOUT`, default)
- checker: `checkers/rocq-lean-import/scripts/run.sh`
- raw logs: `_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/logs`

Summary:
- expected `accept`, observed `accept`, verdict `ok`: 91
- expected `accept`, observed `reject`, verdict `fail`: 4
- expected `accept`, observed `timeout`, verdict `fail`: 4
- expected `reject`, observed `accept`, verdict `fail`: 2
- expected `reject`, observed `decline`, verdict `fail`: 1
- expected `reject`, observed `reject`, verdict `ok`: 47

| test | expected | observed | verdict | time | last progress / detail |
|---|---:|---:|---:|---:|---|
| `bogus1` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 197 (for thm): #DEF 43 142 121 / The term "True_intro" has type "True" while it is expected to have type / "OfNat_ofNat_inst1 Nat 0 (instOfNatNat 0) = |
| `constlevels` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 282 (for _test): #DEF 63 203 37 / Anomaly "in retyping: Not a sort." / Please report at http://rocq-prover.org/bugs/. |
| `init-prelude` | `accept` | `reject` | `fail` | 10.5s | Error: / Error at line 21420 (for Lean.Syntax.casesOn): #DEF 2936 17853 17887 6 / Illegal application: / The term "Lean_Syntax_recl" of type |
| `k-rec-conv` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 242 (for bad): #DEF 61 164 166 / The term "eq_refl t1" has type "t1 = t1" while it is expected to have type / "t1 = t2". |
| `large-elim-param` | `reject` | `decline` | `fail` | 0.1s | Declining: unsupported NDJSON export for rocq-lean-import adapter. / Keeping temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-t... |
| `level-imax-leq` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 75 (for down): #DEF 11 41 42 12 13 / The term "fun x : Type => x" has type "Type@{Var(3)} -> Type@{Var(3)}" / while it is expected to have type "Type@{Var(3)} -> Type@{Var(2)}". |
| `level-imax-normalization` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 76 (for down): #DEF 11 41 42 12 / The term "fun x : Type => x" has type "Type@{Var(1)} -> Type@{Var(1)}" / while it is expected to have type "Type@{Var(1)} -> Type@{Var(0)}". |
| `level-index-out-of-order` | `accept` | `accept` | `ok` | 5.1s | line 5: foo |
| `nat-rec-rules` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 127 (for proof_of_false): #DEF 16 7 91 / Illegal application: / The term "Nat_indl" of type |
| `proj-of-prop` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 55 (for badFalse): #DEF 15 1 34 / Illegal application: / The term "Wrapper_mk" of type "False -> Wrapper" |
| `sparse-name-index` | `accept` | `accept` | `ok` | 5.1s | line 3: foo |
| `tutorial/bad/002_badDef.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 5 (for badDef): #DEF 1 0 1 / The term "Type" has type "Type" while it is expected to have type "SProp". |
| `tutorial/bad/009_forallSortBad.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 25 (for forallSortBad): #DEF 5 7 13 / Anomaly "in retyping: Not a sort." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/010_nonTypeType.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: Error at line 20 (for nonTypeType): #DEF 9 6 7 / The term "constType" has type "Type -> Type -> Type" / which should be Set, Prop or Type. |
| `tutorial/bad/011_nonPropThm.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.yIfDbc / reject: theorem type is a universe, not a ... |
| `tutorial/bad/016_tut06_bad01.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 7 (for tut06_bad01): #DEF 1 0 1 2 2 / Anomaly "Uncaught exception AcyclicGraph.Make(Point).AlreadyDeclared." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/043_inductBadNonSort.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 19 (for inductBadNonSort): #IND 0 9 6 0 / Anomaly "Uncaught exception Reduction.NotArity." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/044_inductBadNonSort2.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 7 (for inductBadNonSort2): #IND 0 2 1 0 / Anomaly "Uncaught exception Reduction.NotArity." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/045_inductLevelParam.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 6 (for inductLevelParam): #IND 0 1 0 0 2 2 / Anomaly "Uncaught exception AcyclicGraph.Make(Point).AlreadyDeclared." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/046_inductTooFewParams.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Anomaly / "File "src/leanParse.ml", line 100, characters 11-17: Assertion failed." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/047_inductWrongCtorParams.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 15 (for inductWrongCtorParams): #IND 1 2 2 1 4 6 / Last occurrence of "inductWrongCtorParams" must have / "x" as 1st argument in "inductWrongCtorParams aProp". |
| `tutorial/bad/048_inductWrongCtorResParams.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 18 (for inductWrongCtorResParams): #IND 2 1 3 1 4 10 / Last occurrence of "inductWrongCtorResParams" must have / "y" as 2nd argument in "inductWrongCtorResParams y x". |
| `tutorial/bad/049_inductWrongCtorResLevel.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.6mTj9v / reject: constructor 6 result universe para... |
| `tutorial/bad/050_inductInIndex.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 13 (for inductInIndex): #IND 0 2 1 1 4 5 / Non strictly positive occurrence of "inductInIndex" in / "inductInIndex (inductInIndex aProp)". |
| `tutorial/bad/051_indNeg.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.j0iJRv / reject: constructor 2 has a negative occur... |
| `tutorial/bad/053_reduceCtorType.mk.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.LGDCnm / reject: constructor 6 result does not have... |
| `tutorial/bad/054_indNegReducible.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.fQwNHe / reject: constructor 11 has a negative occu... |
| `tutorial/bad/058_typeWithTooHighTypeField.mk.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 10 (for typeWithTooHighTypeField): #IND 0 1 0 1 2 2 / Missing universe constraint declared for inductive type: / Type@{Lean.Set+1.0+1} <= Type@{Lean.Set+1.0} |
| `tutorial/bad/082_projOutOfRange.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 66 (for projOutOfRange): #DEF 12 43 47 / Anomaly "inductive_make_projection: invalid proj_arg." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/083_projNotStruct.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 63 (for projNotStruct): #DEF 20 2 37 / Anomaly "File "src/lean.ml", line 1061, characters 13-19: Assertion failed." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/085_projProp2.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 142 (for projProp2): #DEF 30 100 102 / Incorrect elimination of "x" in the inductive type "PropStructure_inst1": / the return type has sort "Type" while it should be SProp. |
| `tutorial/bad/087_projProp4.ndjson` | `reject` | `reject` | `ok` | 5.2s | Error: / Error at line 142 (for projProp4): #DEF 30 100 102 / Incorrect elimination of "x" in the inductive type "PropStructure_inst1": / the return type has sort "Type" while it should be SProp. |
| `tutorial/bad/088_projProp5.ndjson` | `reject` | `reject` | `ok` | 5.2s | Error: / Error at line 147 (for projProp5): #DEF 30 105 107 / Illegal application (Non-functional construction): / The expression "Set" of type "Type" |
| `tutorial/bad/089_projProp6.ndjson` | `reject` | `accept` | `fail` | 5.2s | line 142: PropStructure_inst1.(field).aProof |
| `tutorial/bad/091_projIndexData.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 110 (for projIndexData): #DEF 30 68 71 / The term "fun (x : N) (x0 : ProjDataIndex x) => p _ x0" has type / "forall x : N, ProjDataIndex x -> True" |
| `tutorial/bad/092_projIndexData2.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 110 (for projIndexData2): #DEF 30 68 71 / Anomaly "inductive_make_projection: invalid proj_arg." / Please report at http://rocq-prover.org/bugs/. |
| `tutorial/bad/095_ruleKbad.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 120 (for ruleKbad): #DEF 21 77 82 / The term "fun (_ : eq Bool_true Bool_false) (a : Bool) => eq_refl a" has type / "eq Bool_true Bool_false -> forall a : Bool, eq a a" |
| `tutorial/bad/096_ruleKAcc.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 237 (for ruleKAcc): #DEF 30 180 188 2 / The term / "fun (_UU03b1_ : Type) (p : _UU03b1_ -> _UU03b1_ -> SProp) |
| `tutorial/bad/100_proofIrrelevanceBad.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 92 (for proofIrrelevanceBad): #DEF 16 60 66 / The term "fun (p : Type) (h1 _ : p) => rfl p h1" has type / "forall (p : Type) (h1 : p), p -> eq h1 h1" |
| `tutorial/bad/108_funEtaBad.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 96 (for funEtaBad): #DEF 15 56 63 / The term / "fun |
| `tutorial/bad/109_etaRuleK.ndjson` | `reject` | `accept` | `fail` | 5.1s | line 120: etaRuleK |
| `tutorial/bad/110_etaCtor.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 147 (for etaCtor): #DEF 33 99 103 / The term "fun x : True -> T => eq_refl x" has type / "forall x : True -> T, eq x x" |
| `tutorial/bad/111_reflOccLeft.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.bzos38 / reject: constructor 13 has a negative occu... |
| `tutorial/bad/112_reflOccInIndex.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 65 (for reflOccInIndex): #IND 0 12 36 1 14 43 / Illegal application: / The term "reflOccInIndex" of type "Type -> Type" |
| `tutorial/bad/119_accRecNoEta.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 243 (for accRecNoEta): #DEF 30 186 194 / The term / "fun (_UU03b1_ : Type) (r : _UU03b1_ -> _UU03b1_ -> SProp) |
| `tutorial/bad/126_dup_defs.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.UTJNDU / reject: duplicate declaration name for def... |
| `tutorial/bad/127_dup_ind_def.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.hAfesx / reject: duplicate declaration name for ind... |
| `tutorial/bad/128_dup_ctor_def.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.xRAYoO / reject: duplicate declaration name for con... |
| `tutorial/bad/129_dup_rec_def.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.ARvVNj / reject: duplicate declaration name for rec... |
| `tutorial/bad/130_misnamed_rec_user.ndjson` | `reject` | `reject` | `ok` | 5.1s | Error: / Error at line 32 (for misnamed_rec_user): #DEF 3 16 17 9 / missing misnamed_rec.not_rec |
| `tutorial/bad/131_dup_rec_def2.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.H8O0cc / reject: declaration uses canonical recurso... |
| `tutorial/bad/132_dup_ctor_rec.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.RjkaNW / reject: duplicate declaration name for rec... |
| `tutorial/bad/133_DupConCon.ndjson` | `reject` | `reject` | `ok` | 0.1s | Temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.aHAaFe / reject: duplicate declaration name for con... |
| `tutorial/good/001_basicDef.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 5: basicDef |
| `tutorial/good/003_arrowType.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 11: arrowType |
| `tutorial/good/004_dependentType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 6: dependentType |
| `tutorial/good/005_constType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 16: constType |
| `tutorial/good/006_betaReduction.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 26: betaReduction |
| `tutorial/good/007_betaReduction2.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 27: betaReduction2 |
| `tutorial/good/008_forallSortWhnf.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 24: forallSortWhnf |
| `tutorial/good/012_levelComp1.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 6: levelComp1 |
| `tutorial/good/013_levelComp2.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 7: levelComp2 |
| `tutorial/good/014_levelComp3.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 8: levelComp3 |
| `tutorial/good/015_levelParams.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 28: levelParams |
| `tutorial/good/017_levelComp4.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 7: levelComp4 |
| `tutorial/good/018_levelComp5.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 7: levelComp5 |
| `tutorial/good/019_imax1.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 15: imax1 |
| `tutorial/good/020_imax2.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 16: imax2 |
| `tutorial/good/021_levelMaxComm.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 11: levelMaxComm |
| `tutorial/good/022_levelMaxAssoc.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 15: levelMaxAssoc |
| `tutorial/good/023_levelMaxIdem.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 8: levelMaxIdem |
| `tutorial/good/024_levelMaxAbsorb.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 11: levelMaxAbsorb |
| `tutorial/good/025_inferVar.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 11: inferVar |
| `tutorial/good/026_defEqLambda.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 25: defEqLambda |
| `tutorial/good/027_peano1.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 72: peano1 |
| `tutorial/good/028_peano2.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 89: peano2 |
| `tutorial/good/029_peano3.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 97: peano3 |
| `tutorial/good/030_letType.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 8: letType |
| `tutorial/good/031_letTypeDep.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 25: letTypeDep |
| `tutorial/good/032_letRed.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 11: letRed |
| `tutorial/good/033_empty.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 19: empty |
| `tutorial/good/034_boolType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 36: boolType |
| `tutorial/good/035_twoBool.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 64: twoBool |
| `tutorial/good/036_andType.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 56: andType |
| `tutorial/good/037_prodType.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 75: Prod_inst3.(field).fst0 |
| `tutorial/good/038_pprodType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 74: pprodType |
| `tutorial/good/039_pUnitType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 30: pUnitType |
| `tutorial/good/040_eqType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 61: eqType |
| `tutorial/good/041_natDef.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 60: natDef |
| `tutorial/good/042_rbTreeDef.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 295: rbTreeDef |
| `tutorial/good/052_reduceCtorParam.mk.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 79: reduceCtorParam.(field).x |
| `tutorial/good/055_predWithTypeField.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 31: predWithTypeField |
| `tutorial/good/056_typeWithTypeField.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 35: typeWithTypeField |
| `tutorial/good/057_typeWithTypeFieldPoly.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 37: typeWithTypeFieldPoly |
| `tutorial/good/059_emptyRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 20: emptyRec |
| `tutorial/good/060_boolRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 52: boolRec |
| `tutorial/good/061_twoBoolRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 77: twoBoolRec |
| `tutorial/good/062_andRec.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 57: andRec |
| `tutorial/good/063_prodRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 78: prodRec |
| `tutorial/good/064_pprodRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 77: pprodRec |
| `tutorial/good/065_punitRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 38: punitRec |
| `tutorial/good/066_eqRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 62: eqRec |
| `tutorial/good/067_nRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 60: nRec |
| `tutorial/good/068_rbTreeRef.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 302: rbTreeRef |
| `tutorial/good/069_boolPropRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 33: boolPropRec |
| `tutorial/good/070_existsRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 65: existsRec |
| `tutorial/good/071_sortElimPropRec.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 96: sortElimPropRec |
| `tutorial/good/072_sortElimProp2Rec.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 113: sortElimProp2Rec |
| `tutorial/good/073_boolRecEqns.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 198: boolRecEqns |
| `tutorial/good/074_prodRecEqns.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 204: Prod_inst3.(field).fst0 |
| `tutorial/good/075_nRecReduction.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 237: nRecReduction |
| `tutorial/good/076_listRecReduction.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 334: listRecReduction |
| `tutorial/good/077_RBTree.id_spec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 1005: RBTree.id_spec |
| `tutorial/good/078_And.right.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 73: And.right |
| `tutorial/good/079_Prod.snd.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 82: Prod.snd |
| `tutorial/good/080_PProd.snd.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 82: PProd.snd |
| `tutorial/good/081_PSigma.snd.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 95: PSigma.snd |
| `tutorial/good/084_projProp1.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 142: PropStructure_inst1.(field).aProof |
| `tutorial/good/086_projProp3.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 142: PropStructure_inst1.(field).aProof |
| `tutorial/good/090_projDataIndexRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 110: projDataIndexRec |
| `tutorial/good/093_projRed.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 176: Prod_inst3.(field).fst0 |
| `tutorial/good/094_ruleK.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 120: ruleK |
| `tutorial/good/097_aNatLit.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 53: aNatLit |
| `tutorial/good/098_natLitEq.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 113: natLitEq |
| `tutorial/good/099_proofIrrelevance.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 99: proofIrrelevance |
| `tutorial/good/101_proofIrrelevanceWhnf.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 111: proofIrrelevanceWhnf |
| `tutorial/good/102_unitEta1.ndjson` | `accept` | `reject` | `fail` | 5.1s | Error: / Error at line 115 (for unitEta1): #DEF 21 71 76 / The term / "fun x____at___Tutorial1036685737__hygCtx__hyg14 _ : Unit => |
| `tutorial/good/103_unitEta2.ndjson` | `accept` | `reject` | `fail` | 5.1s | Error: / Error at line 108 (for unitEta2): #DEF 20 67 72 2 / The term / "fun x____at___Tutorial1006014971__hygCtx__hyg14 _ : PUnit => |
| `tutorial/good/104_unitEta3.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 110: unitEta3 |
| `tutorial/good/105_structEta.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 229: structEta |
| `tutorial/good/106_funEta.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 103: funEta |
| `tutorial/good/107_funEtaDep.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 105: funEtaDep |
| `tutorial/good/113_reduceCtorParamRefl.mk.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 87: reduceCtorParamRefl.(field).x |
| `tutorial/good/114_reduceCtorParamRefl2.mk.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 87: reduceCtorParamRefl2.(field).x |
| `tutorial/good/115_rTreeRec.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 90: rTreeRec |
| `tutorial/good/116_rtreeRecReduction.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 192: rtreeRecReduction |
| `tutorial/good/117_accRecType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 150: accRecType |
| `tutorial/good/118_accRecReduction.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 251: accRecReduction |
| `tutorial/good/120_quotMkType.ndjson` | `accept` | `accept` | `ok` | 5.2s | line 119: quotMkType |
| `tutorial/good/121_quotIndType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 120: quotIndType |
| `tutorial/good/122_quotLiftType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 120: quotLiftType |
| `tutorial/good/123_quotSoundType.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 137: quotSoundType |
| `tutorial/good/124_quotLiftReduction.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 149: quotLiftReduction |
| `tutorial/good/125_quotIndReduction.ndjson` | `accept` | `accept` | `ok` | 5.1s | line 147: quotIndReduction |
| `init` | `accept` | `timeout` | `fail` | 689.5s | Timed out after 600 seconds without rocq stdout progress. |
| `std` | `accept` | `timeout` | `fail` | 675.2s | Timed out after 600 seconds without rocq stdout progress. |
| `cedar` | `accept` | `reject` | `fail` | 85.3s | Error: / Error at line 21500 (for Cedar.Spec.Residual): #IND 0 3118 78 13 3119 16968 3120 16969 3121 16972 3122 16971 3123 16971 3124 16973 3125 16974 3126 16976 3127 16976 3128 16978 3129 16981 3130 16982 3131 16967 ... |
| `cslib` | `accept` | `timeout` | `fail` | 702.6s | Timed out after 600 seconds without rocq stdout progress. |
| `mathlib` | `accept` | `timeout` | `fail` | 672.6s | Timed out after 600 seconds without rocq stdout progress. |

Timeouts and failures:
- `init-prelude`: expected `accept`, observed `reject` after 10.5s.
  Last progress: `line 21420: Lean.Syntax.casesOn`
  Detail: Error: / Error at line 21420 (for Lean.Syntax.casesOn): #DEF 2936 17853 17887 6 / Illegal application: / The term "Lean_Syntax_recl" of type
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.TARxiR`
- `large-elim-param`: expected `reject`, observed `decline` after 0.1s.
  Detail: Declining: unsupported NDJSON export for rocq-lean-import adapter. / Keeping temporary checker directory: /home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.2TaEnU
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.2TaEnU`
- `tutorial/bad/089_projProp6.ndjson`: expected `reject`, observed `accept` after 5.2s.
  Last progress: `line 142: PropStructure_inst1.(field).aProof`
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.Fs4dPw`
- `tutorial/bad/109_etaRuleK.ndjson`: expected `reject`, observed `accept` after 5.1s.
  Last progress: `line 120: etaRuleK`
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.UoMEXI`
- `tutorial/good/102_unitEta1.ndjson`: expected `accept`, observed `reject` after 5.1s.
  Last progress: `line 115: unitEta1`
  Detail: Error: / Error at line 115 (for unitEta1): #DEF 21 71 76 / The term / "fun x____at___Tutorial1036685737__hygCtx__hyg14 _ : Unit =>
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.EsXTM4`
- `tutorial/good/103_unitEta2.ndjson`: expected `accept`, observed `reject` after 5.1s.
  Last progress: `line 108: unitEta2`
  Detail: Error: / Error at line 108 (for unitEta2): #DEF 20 67 72 2 / The term / "fun x____at___Tutorial1006014971__hygCtx__hyg14 _ : PUnit =>
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.L8Y3QC`
- `init`: expected `accept`, observed `timeout` after 689.5s.
  Last progress: `line 203264: Nat.Linear.ExprCnstr.denote_toNormPoly`
  Detail: Timed out after 600 seconds without rocq stdout progress.
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.fN77yz`
- `std`: expected `accept`, observed `timeout` after 675.2s.
  Last progress: `line 47231: Nat.Linear.ExprCnstr.denote_toNormPoly`
  Detail: Timed out after 600 seconds without rocq stdout progress.
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.qo9URN`
- `cedar`: expected `accept`, observed `reject` after 85.3s.
  Last progress: `line 21500: Cedar.Spec.Residual`
  Detail: Error: / Error at line 21500 (for Cedar.Spec.Residual): #IND 0 3118 78 13 3119 16968 3120 16969 3121 16972 3122 16971 3123 16971 3124 16973 3125 16974 3126 16976 3127 16976 3128 16978 3129 16981 3130 16982 3131 16967 / Anomaly "File "src/lean.ml", line 76, characters 9-15: Assertion failed." / Please report at http://rocq-prover.org/bugs/.
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.TQfy5h`
- `cslib`: expected `accept`, observed `timeout` after 702.6s.
  Last progress: `line 499590: Nat.Linear.ExprCnstr.denote_toNormPoly`
  Detail: Timed out after 600 seconds without rocq stdout progress.
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.q5YF8f`
- `mathlib`: expected `accept`, observed `timeout` after 672.6s.
  Last progress: `line 376778: Nat.Linear.ExprCnstr.denote_toNormPoly`
  Detail: Timed out after 600 seconds without rocq stdout progress.
  Temp dir: `/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/reports/rocq-lean-import-all-tests/tmp/rocq-lean-import.8RDI1N`

