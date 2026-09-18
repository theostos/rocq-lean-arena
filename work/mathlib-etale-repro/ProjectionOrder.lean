namespace ProjectionOrder

structure Ops where
  run : Nat → Nat

def duplicate : Nat → Nat
  | 0 => 0
  | n + 1 => duplicate n + duplicate n

def method : Nat → Nat → Nat
  | 0 => fun _ => 0
  | _ + 1 => fun _ => 0

def wrapper (n : Nat) : Ops := ⟨method n⟩

-- Explicit proof endpoint retains the projected expression for the kernel.
theorem forward : (wrapper 0).run (duplicate 30) = (wrapper 1).run 0 :=
  Eq.refl ((wrapper 1).run 0)

theorem backward : (wrapper 1).run 0 = (wrapper 0).run (duplicate 30) :=
  Eq.refl ((wrapper 0).run (duplicate 30))

theorem underBinder (x : Nat) :
    (fun _ : Nat => (wrapper 0).run (duplicate 30)) x = (wrapper 1).run 0 :=
  Eq.refl ((wrapper 1).run 0)

end ProjectionOrder
