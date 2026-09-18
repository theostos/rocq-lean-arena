universe u v

structure Rel (α : Type u) (x y : α) : Prop where
  property : True

structure Trigger (α : Type u) where
  inner : Quot (Rel α)

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

theorem quotient_projection (α : Type u) (r : α → α → Prop) (x : α) :
    (QuotBox.mk (Quot.mk r x)).inner = Quot.mk r x := rfl
