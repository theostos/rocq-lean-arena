structure Wrap (α : Type) where
  val : α

def WrappedUnit := Wrap PUnit

example (x y : Wrap PUnit) : x.val = y.val := rfl
example (x y : WrappedUnit) : x.val = y.val := rfl
