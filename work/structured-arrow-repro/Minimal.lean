structure Wrap (α : Type) where
  val : α

example (x y : PUnit) : x = y := rfl
example (x y : Wrap PUnit) : x.val = y.val := rfl

structure Arrow where
  left : Wrap PUnit

def Hom (x y : Wrap PUnit) := PLift (x.val = y.val)
def identity (x : Wrap PUnit) : Hom x x := ⟨rfl⟩
example (f g : Arrow) : Hom f.left g.left := identity f.left
