# Tutorial Gaps

Result with `rocq-lean-import` pinned to upstream `master`:

```text
correct:   125 / 133
incorrect:   8 / 133
```

The eight mismatches are:

```text
052_reduceCtorParam.mk
084_projProp1
086_projProp3
102_unitEta1
103_unitEta2
109_etaRuleK
113_reduceCtorParamRefl.mk
114_reduceCtorParamRefl2.mk
```

## Errors

### `052_reduceCtorParam.mk`

```text
Error at line 79 (for reduceCtorParam): #IND 1 12 8 1 13 23
Dependent induction is not allowed for reduceCtorParam.
Primitive records must have eta conversion to allow dependent elimination.
```

### `084_projProp1`

```text
Error at line 142 (for projProp1): #DEF 30 100 102
TODO projection for non record Prop inductive
```

### `086_projProp3`

```text
Error at line 142 (for projProp3): #DEF 30 100 102
TODO projection for non record Prop inductive
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

### `113_reduceCtorParamRefl.mk`

```text
Error at line 87 (for reduceCtorParamRefl): #IND 1 12 8 1 13 23
Dependent induction is not allowed for reduceCtorParamRefl.
Primitive records must have eta conversion to allow dependent elimination.
```

### `114_reduceCtorParamRefl2.mk`

```text
Error at line 87 (for reduceCtorParamRefl2): #IND 1 12 8 1 13 23
Dependent induction is not allowed for reduceCtorParamRefl2.
Primitive records must have eta conversion to allow dependent elimination.
```
