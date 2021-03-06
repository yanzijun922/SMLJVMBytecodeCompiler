structure TypeName = struct

  structure LTYC = LongTypeConstructor

  type arity = int
  type equality = bool
  type tyname = LTYC.ltycon * arity * equality

  fun equal (c1, a1 ,e1) (c2, a2 ,e2) =
    (c1 = c2) andalso (a1 = a2) andalso (e1 = e2)

  fun equality (c, a ,e) = e

  fun arity (c, a ,e) = a

  fun ltycon (c, a ,e) = c

  fun toString (c, a ,e) = (LTYC.toString c) ^ (Int.toString a)

  fun compare ((t1, _, _), (t2, _, _)) = LTYC.compare (t1, t2)

end

structure TypeNameKey = struct

  structure LTYC = LongTypeConstructor

  type ord_key = TypeName.tyname

  val compare = TypeName.compare

end

structure TypeNameBinarySet = OrdSetAuxFn (BinarySetFn (TypeNameKey))

structure LongTypeConstructorKey = struct

  structure LTYC = LongTypeConstructor

  type ord_key = LTYC.ltycon

  val compare = LTYC.compare

end

structure TypeNameSet = struct

  open TypeNameBinarySet

  type typenameset = set

  fun prefixSid set sid = map (fn ((p,v), a, e) => ((sid :: p, v), a, e)) set

end

structure LongTypeConstructorMap = OrdMapAuxFn (BinaryMapFn (LongTypeConstructorKey))

structure TypeNameEnvironment = struct

  open LongTypeConstructorMap

  structure TS = TypeNameBinarySet

  type tynameenv = TypeName.tyname map

  fun fromTynameset tnset = TS.foldl (fn (tn as (ltycon, _, _), map) =>
    insert (map, ltycon, tn)) empty tnset

end
