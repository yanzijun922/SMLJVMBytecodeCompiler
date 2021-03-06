structure Value = struct

  structure SV = SpecialValue
  structure BV = BasicValue
  structure A = Address
  structure VID = ValueIdentifier
  structure LM = LabBinaryMap
  structure IM = IntBinaryMapAux
  structure SM = StringBinaryMap
  structure IDS = IdentifierStatus
  structure EN = ExceptionName
  structure SS = StringBinarySet
  structure L = Location

  type basval = BasicValue.basval
  datatype scon = datatype SpecialConstant.scon

  type cid = int
  type loc = int
  type closid = int

  datatype value =
    VAL of closid * loc |
    CON of (closid * loc) * int |
    EXC of (closid * loc) * int

  and space =
    SPA of strspa * tyspa * valspa

  withtype record = value LM.map
  and strspa = space SM.map
  and valspa = value SM.map
  and tyspa  = valspa SM.map

  fun toLoc (VAL (loc))    = loc
    | toLoc (CON (loc, _)) = loc
    | toLoc (EXC (loc, _)) = loc

  fun getTag (VAL (loc))    = NONE
    | getTag (CON (loc, t)) = SOME t
    | getTag (EXC (loc, t)) = SOME t

  fun toString (VAL (loc))    = (L.toString loc) ^ "v"
    | toString (CON (loc, _)) = (L.toString loc) ^ "c"
    | toString (EXC (loc, _)) = (L.toString loc) ^ "e"

end
