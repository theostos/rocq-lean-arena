structure Wrap (α : Type) where
  val : α
structure Arrow where
  left : Wrap PUnit
def StructuredArrow := Arrow
def Hom (x y : Wrap PUnit) := PLift (x.val = y.val)
def identity (x : Wrap PUnit) : Hom x x := ⟨rfl⟩

example (f g : Arrow) : Hom f.left g.left := identity f.left
example (f g : StructuredArrow) : Hom f.left g.left := identity f.left
