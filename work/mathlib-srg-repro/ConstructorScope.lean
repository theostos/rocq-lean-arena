universe u v

-- Analysing this non-recursive field still reduces the uniform arguments
-- of Eq. The transport's type comparison needs all constructor parameters.
structure ParameterScope (α : Type u) (F : α → Type v) (a b : α)
    (h : a = b) (x : F a) (y : F b) : Prop where
  card : Eq.ndrec (motive := F) x h = y

-- The field analysis must also retain earlier fields, not just parameters.
structure FieldScope (α : Type u) (F : α → Type v) (a b : α) (h : a = b) where
  value : F a
  target : F b
  card : Eq.ndrec (motive := F) value h = target

-- Reordering of multiple recursive hypotheses must remain unchanged.
inductive RecursiveScope (α : Type u) where
  | leaf : α → RecursiveScope α
  | node : RecursiveScope α → α → RecursiveScope α → RecursiveScope α

def scopeSize {α : Type u} : RecursiveScope α → Nat
  | .leaf _ => 1
  | .node left _ right => scopeSize left + scopeSize right + 1

theorem scopeSize_example :
    scopeSize (.node (.leaf 7) 8 (.leaf 9)) = 3 := rfl
