# Tutorial Gaps

Result with `rocq-lean-import` pinned to upstream `master`
(`38fb4791bc7a3bc49995526448778c6e5555aaf1`):

```text
correct:   129 / 133
incorrect:   4 / 133
```

The four remaining mismatches are:

```text
089_projProp6
102_unitEta1
103_unitEta2
109_etaRuleK
```

## Errors

### `089_projProp6`

No Rocq error is returned. This is a false accept:

```text
line 25: PUnit
line 74: Eq
Eq is predeclared
line 133: PropStructure
line 133: PropStructure.(field).aFinalProof
line 133: PropStructure.(field).aProofAboutData
line 133: PropStructure.(field).someMoreData
line 133: PropStructure.(field).aSecondProof
line 133: PropStructure.(field).someData
line 133: PropStructure.(field).aProof
line 142: projProp6
line 142: PropStructure_inst1.(field).aFinalProof
line 142: PropStructure_inst1.(field).aProofAboutData
line 142: PropStructure_inst1.(field).someMoreData
line 142: PropStructure_inst1.(field).aSecondProof
line 142: PropStructure_inst1.(field).someData
line 142: PropStructure_inst1.(field).aProof

Done!
- 4 entries (9 possible instances).
- 5 universe expressions
- 32 names
- 103 expression nodes
Max universe instance length 2.
0 inductives have non syntactically arity types.
```

### `102_unitEta1`

```text
Error at line 115 (for unitEta1): #DEF 21 71 76
The term
 "fun x____at___Tutorial1036685737__hygCtx__hyg14 _ : Unit =>
  rfl Unit x____at___Tutorial1036685737__hygCtx__hyg14"
has type
 "forall x____at___Tutorial1036685737__hygCtx__hyg14 : Unit,
  Unit ->
  eq x____at___Tutorial1036685737__hygCtx__hyg14
    x____at___Tutorial1036685737__hygCtx__hyg14"
while it is expected to have type "forall x y : Unit, eq x y".
```

### `103_unitEta2`

```text
Error at line 108 (for unitEta2): #DEF 20 67 72 2
The term
 "fun x____at___Tutorial1006014971__hygCtx__hyg14 _ : PUnit =>
  rfl PUnit x____at___Tutorial1006014971__hygCtx__hyg14"
has type
 "forall x____at___Tutorial1006014971__hygCtx__hyg14 : PUnit,
  PUnit ->
  eq x____at___Tutorial1006014971__hygCtx__hyg14
    x____at___Tutorial1006014971__hygCtx__hyg14"
while it is expected to have type "forall x y : PUnit, eq x y".
```

### `109_etaRuleK`

No Rocq error is returned. This is a false accept:

```text
line 59: Eq
Eq is predeclared
line 85: Bool
line 120: etaRuleK

Done!
- 3 entries (4 possible instances).
- 4 universe expressions
- 30 names
- 85 expression nodes
Max universe instance length 1.
0 inductives have non syntactically arity types.
```
