structure Type = struct

  open TypeName

  structure LM = LabBinaryMap
  structure IS = IntBinarySetAux
  structure LA = ListAux
  structure LPA = ListPairAux
  structure TN = TypeName
  structure VS = VartySet
  structure AS = IntBinarySetAux
  structure IM = IntBinaryMapAux

  datatype ty =
    VARTY of varty |
    ROWTY of rowty |
    FUNTY of funty |
    CONTY of conty |
    ASSTY of assty
  withtype rowty = ty LM.map
  and funty = ty * ty
  and tyseq = ty list
  and conty = tyseq * tyname
  and assty = int
  and varty = int

  type sub = ty * ty
  type ins = assty * ty
  type bnd = varty * ty
  type subseq = sub list
  type insseq = ins list
  type bndseq = bnd list
  type vartyset = VS.set

  exception WrongTypeForm of string
  exception UnifyFail of string

  fun toString (VARTY v) = Varty.toString v
    | toString (ROWTY r) =
    "{" ^ (LM.toString r Lab.toString toString "=" ",") ^ "}"
    | toString (CONTY (ts, n)) =
      (LA.toString ts toString ",") ^ "." ^ (TN.toString n)
    | toString (FUNTY (t1, t2)) = (toString t1) ^ "->" ^ (toString t2)
    | toString (ASSTY t) = Assty.toString t

  fun printUnifyFail t1 t2 = let
    val st1 = toString t1
    val st2 = toString t2 in
    print ("UNIFY FAILED BETWEEN \n" ^ st1 ^ "\n" ^ st2) end

  fun printWrongTypeForm t = let
    val st = toString t in
    print ("WRONG TYPE FORM \n" ^ st) end

  fun getVartyset (VARTY v) = VS.singleton v
    | getVartyset (ROWTY r) =
    LM.foldl (fn (t, s) => VS.union ((getVartyset t), s)) VS.empty r
    | getVartyset (FUNTY (t1, t2)) =
    VS.union ((getVartyset t1), (getVartyset t2))
    | getVartyset (CONTY (ts, n)) =
    List.foldl (fn (t, s) => VS.union ((getVartyset t), s)) VS.empty ts
    | getVartyset (ASSTY _) = VS.empty

  fun getAsstyset (VARTY _) = AS.empty
    | getAsstyset (ROWTY r) =
    LM.foldl (fn (t, s) => AS.union ((getAsstyset t), s)) AS.empty r
    | getAsstyset (FUNTY (t1, t2)) =
    AS.union ((getAsstyset t1), (getAsstyset t2))
    | getAsstyset (CONTY (ts, n)) =
    List.foldl (fn (t, s) => AS.union ((getAsstyset t), s)) AS.empty ts
    | getAsstyset (ASSTY a) = AS.singleton a

  fun sub (VARTY vt) (VARTY vt', ty) = if vt' = vt then ty else (VARTY vt)
    | sub (VARTY v) (ASSTY a, _) = VARTY v
    | sub (ASSTY a) (ASSTY a', ty) = if a' = a then ty else (ASSTY a)
    | sub (ASSTY a) (VARTY v, _) = ASSTY a
    | sub (ROWTY rowty) s = ROWTY (LM.map (fn ty => sub ty s) rowty)
    | sub (FUNTY (argty, resty)) s = FUNTY (sub argty s, sub resty s)
    | sub (CONTY (tyseq, tyname)) s =
    CONTY (List.map (fn ty => sub ty s) tyseq, tyname)
    | sub t1 (t2, t3) = raise WrongTypeForm "WRONG SUB FORM"

  fun ins (VARTY vt) _ = VARTY vt
    | ins (ASSTY at) (at', ty) = if at' = at then ty else (ASSTY at)
    | ins (ROWTY rowty) i = ROWTY (LM.map (fn ty => ins ty i) rowty)
    | ins (FUNTY (argty, resty)) i = FUNTY (ins argty i, ins resty i)
    | ins (CONTY (tyseq, tyname)) i =
    CONTY (List.map (fn ty => ins ty i) tyseq, tyname)

  fun bnd (VARTY vt) (vt', ty) = if vt' = vt then ty else (VARTY vt)
    | bnd (ASSTY a) _ = ASSTY a
    | bnd (ROWTY rowty) s = ROWTY (LM.map (fn ty => bnd ty s) rowty)
    | bnd (FUNTY (argty, resty)) s = FUNTY (bnd argty s, bnd resty s)
    | bnd (CONTY (tyseq, tyname)) s =
    CONTY (List.map (fn ty => bnd ty s) tyseq, tyname)

  (* substitute the varty in an order *)
  fun substitute ty subseq = List.foldl (fn (s, ty) => sub ty s) ty subseq

  (* substitute the assty in an order *)
  fun instantiate ty insseq = List.foldl (fn (i, ty) => ins ty i) ty insseq

  (* check loop *)
  fun mapInstantiate (VARTY vt) im = VARTY vt
    | mapInstantiate (ASSTY a) im = let
    val insop = IM.find (im, a) in
    if Option.isSome insop then let 
      val ins = Option.valOf insop in 
      mapInstantiate ins im end else 
      (ASSTY a) end
    | mapInstantiate (ROWTY rowty) im = 
    ROWTY (LM.map (fn ty => mapInstantiate ty im) rowty)
    | mapInstantiate (FUNTY (argty, resty)) im =
    FUNTY (mapInstantiate argty im, mapInstantiate resty im)
    | mapInstantiate (CONTY (tyseq, tyname)) im =
    CONTY (List.map (fn ty => mapInstantiate ty im) tyseq, tyname)

  fun bind ty bndseq = List.foldl (fn (b, ty) => bnd ty b) ty bndseq

  fun isBnd (VARTY _, _) = true
    | isBnd (ASSTY _, _) = false
    | isBnd (_, _) = raise WrongTypeForm "WRONG SUB FORM"

  fun isIns (VARTY _, _) = false
    | isIns (ASSTY _, _) = true
    | isIns (_, _) = raise WrongTypeForm "WRONG SUB FORM"

  fun bndseqFromSubseq subs = let
    val sbnd = List.filter isBnd subs
    fun aux (VARTY a, b) = (a, b)
      | aux (_, _) = raise WrongTypeForm "WRONG SUB FORM" in
    map aux sbnd end

  fun insseqFromSubseq subs = let
    val sins = List.filter isIns subs
    fun aux (ASSTY a, b) = (a, b)
      | aux (_, _) = raise WrongTypeForm "WRONG SUB FORM" in
    map aux sins end


  (* check a type contains a varty or assty *)
  fun ctva (VARTY v') (VARTY v) = v = v'
    | ctva (ASSTY _) (VARTY _) = false
    | ctva (VARTY _) (ASSTY _) = false
    | ctva (ASSTY a') (ASSTY a) = a = a'
    | ctva (ROWTY r) v =
    LM.foldl (fn (t, b) =>  b orelse (ctva t v)) false r
    | ctva (CONTY (ts, n)) v =
    List.foldl (fn (t ,b) => b orelse (ctva t v)) false ts
    | ctva (FUNTY (t1, t2)) v = (ctva t1 v) orelse (ctva t2 v)
    | ctva _ _ = raise WrongTypeForm "WRONG CTVA FORM"

  (* generate subseq and insseq for unification *)
  local
  fun aux cs (VARTY v1) (VARTY v2) s true =
    if v1 = v2 then s else
      if IS.member (cs, v1)
      then (VARTY v1, VARTY v2) :: s else
        if IS.member (cs, v2)
        then (VARTY v2, VARTY v1) :: s
        else raise UnifyFail "OPEN VARTY PAIR"

    | aux cs (VARTY v) (ASSTY a) s true =
    if IS.member (cs, v)
    then (VARTY v, ASSTY a) :: s
    else (ASSTY a, VARTY v) :: s

    | aux cs (ASSTY a) (VARTY v) s true =
    aux cs (VARTY v) (ASSTY a) s true

    | aux cs (ASSTY a1) (ASSTY a2) s true =
    if a1 = a2 then s else (ASSTY a1, ASSTY a2) :: s

    | aux cs (VARTY v) ty s true =
    if ctva ty (VARTY v)
    then raise UnifyFail "CIRCULAR VARTY" else
      if IS.member (cs, v)
      then (VARTY v, ty) :: s
      else raise UnifyFail "OPEN VARTY"

    | aux cs (ASSTY a) ty s true =
    if ctva ty (ASSTY a)
    then raise UnifyFail "CIRCULAR ASSTY"
    else (ASSTY a, ty) :: s

    | aux cs ty (VARTY v) s true =
    aux cs (VARTY v) ty s true

    | aux cs ty (ASSTY a) s true =
    aux cs (ASSTY a) ty s true

    | aux cs (FUNTY (a1, r1)) (FUNTY (a2, r2)) s d = let
      val s' = aux cs a1 a2 s false
      val s'' = aux cs r1 r2 s' false
    in s'' @ (s' @ s) end

    | aux cs (ROWTY r1) (ROWTY r2) s d =
    if LM.numItems r1 = LM.numItems r2
    then LM.foldli (fn (k, t1, s) => let
        val t2 = Option.valOf (LM.find (r2, k))
          handle Option.Option => (
          printUnifyFail (ROWTY r1) (ROWTY r2);
          raise UnifyFail "LAB NOT FOUND")
      in (aux cs t1 t2 s false) @ s end) s r1
    else raise UnifyFail "ROWTY DIFFERENCE SIZE"

    | aux cs (CONTY (ts1, n1)) (CONTY (ts2, n2)) s d =
    if TN.equal n1 n2 andalso
       TN.arity n1 = length ts1 andalso TN.arity n2 = length ts2
    then let val tp = ListPair.zip (ts1, ts2) in
      List.foldl (fn ((t1, t2), s) =>
        (aux cs t1 t2 s false) @ s) s tp end
    else raise UnifyFail "TYNAME DIFFERENT OR ERROR APPLY"

    | aux cs t1 t2 s false = let
      val t1' = substitute t1 (List.rev s)
      val t2' = substitute t2 (List.rev s)
    in aux cs t1' t2' s true end

    | aux _ _ _ _ true = raise UnifyFail "NO RULE APPLY" in

  fun gs cs t1 t2 = List.rev (aux cs t1 t2 [] true) end

  (* generate type instantiation from substitution sequence*)
  (*fun ifs ((ASSTY a, ty) :: ss) =*)
    (*(a, substitute ty ss) :: (ifs ss)*)
    (*| ifs (_ :: ss) = ifs ss*)
    (*| ifs [] = []*)

  (* TODO: This function should never apply to instantiate as it removes linkage *)
  (* truncate the substitution, make them immediate and so separatable*)
  fun truncateSubseq ((t1, t2) :: ss) =
    (t1, substitute t2 ss) :: (truncateSubseq ss)
    | truncateSubseq [] = []

  fun subseqToString seq = ListAux.toString seq (fn (a, b) => (toString a)
    ^ (toString b)) "||"

  fun unify cs t1 t2 = let
    val subseq = gs cs t1 t2
    (* ERROR!!!!!!! *)
    val tsubseq = truncateSubseq subseq
    val insseq = insseqFromSubseq tsubseq
    val bndseq = bndseqFromSubseq tsubseq
    val t = bind t1 bndseq
  in (t, insseq) end
  handle UnifyFail s => (
    TIO.println s;
    TIO.println (toString t1);
    TIO.println (toString t2);
    raise UnifyFail s
  )


end
