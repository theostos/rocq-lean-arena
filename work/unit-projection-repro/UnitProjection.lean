theorem projected_identity {α : Type} (z : PUnit × α) :
    (fun k : PUnit => k) = (fun _ : PUnit => z.1) := rfl

theorem two_projections (x y : PUnit × Nat) : x.1 = y.1 := rfl
theorem nested_projection (x : (PUnit × Nat) × Nat) (u : PUnit) : x.1.1 = u := rfl
theorem applied_projection (x : (Nat → PUnit) × Nat) (n : Nat) (u : PUnit) :
    x.1 n = u := rfl
