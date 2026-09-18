universe u v

structure Payload (α : Type u) (β : α → Type v) where
  key : α
  value : β key

structure QuotBox (α : Type u) (r : α → α → Prop) where
  inner : Quot r

structure DepQuotBox (α : Type u) (β : α → Type v)
    (r : Payload α β → Payload α β → Prop) where
  inner : Quot r

structure FamilyBox (β : Nat → Type u) where
  value : β 0

structure NestedFamilyBox (α : Type u) where
  value : FamilyBox (fun _ => α)

example (α : Type u) (r : α → α → Prop) (x : α) :
    (QuotBox.mk (Quot.mk r x)).inner = Quot.mk r x := rfl
