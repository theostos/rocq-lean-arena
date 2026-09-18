(** Diagnostic prototype, not linked into the importer.
    [equal] has the same semantics as [Constr.equal], with bounded, temporary
    memoization of equal physical subterm pairs. It performs no reduction. *)
val equal : Constr.t -> Constr.t -> bool

(** [abstract_context ids term] is [Vars.substl (List.map Constr.mkMeta ids)
    term], with bounded memoization to preserve shared subterms. This is only
    for translation-cache keys, not a transformation of imported proofs. *)
val abstract_context : int list -> Constr.t -> Constr.t
