structure InterInference = struct

  structure CST = CoreSyntaxTree
  structure S = Space
  structure VS = ValueSpace
  structure TS = TypeSpace
  structure SS = StructureSpace
  structure LM = LabBinaryMap
  structure IS = IdentifierStatus
  structure IM = IntBinaryMapAux
  structure IC = InterClosure
  structure IP = InterProgram

  structure VIS = ValueIndexSet

  datatype scon      = datatype CST.scon
  datatype atexp     = datatype CST.atexp
  datatype exp       = datatype CST.exp
  datatype dec       = datatype CST.dec
  datatype valbind   = datatype CST.valbind
  datatype exbindele = datatype CST.exbindele
  datatype atpat     = datatype CST.atpat
  datatype pat       = datatype CST.pat
  datatype ty        = datatype CST.ty
  datatype lab       = datatype Lab.lab
  datatype value     = datatype Value.value

  datatype code  = datatype InterInstruction.code

  val locNull = (~1,~1)
  val locArg = (~1,~1)
  val locThis = (~1,~1)

  val valOf = Option.valOf
  val isSome = Option.isSome
  val toLoc = Value.toLoc

  datatype closty = F | T
  type clostk = (closty * int * int ref) list

  val labref = ref 0
  val clostkref  = ref ([] : clostk)
  val closidref = ref 0
  val progref = ref (IM.empty : IP.program)
  val zip = ListPair.zip

  fun inc r = r := !r + 1

  fun newclosid () = (inc closidref; ! closidref)

  fun newloc () = let
    val (_, closid, locref) = hd (! clostkref) in
    inc locref; (closid, ! locref) end

  fun popclos () = let
    val (ty, closid, locref) = hd (! clostkref) in
    clostkref := tl (! clostkref);
    (ty, closid, ! locref) end

  fun newclos ty = let
    val newclos = (ty, newclosid (), ref ~1) in
    (clostkref := newclos :: (! clostkref); ! closidref) end

  fun popAdd code = let
    val (ty, closid, locmax) = popclos ()
    val locset = IntBinarySetAux.tabulate ((locmax + 1), (fn x => x))
    val newprog  = case ty of
      F =>  IP.insert ((! progref), closid, 
        IC.FCN ((#2 o hd) (! clostkref), locset, (code, ! labref)))
    | T =>  IP.insert ((! progref), closid,
        IC.TOP (locset, (code, ! labref))) in
    progref := newprog end

  fun init () = (
    closidref := ~1;
    clostkref := [];
    labref    := ~1;
    newclos T;
    progref := IM.empty)

  fun infScon scon = let
    val loc = newloc () in
    ([NEWSCN (loc, scon)], loc)  end

  fun infAtexp spa (SCON_ATEXP scon) = infScon scon
    | infAtexp spa (LVID_ATEXP lvid) = let
    val value = valOf (S.getValstr spa lvid) in
    ([], toLoc value) end
    | infAtexp spa (EXP_ATEXP exp) = infExp spa exp
    | infAtexp spa (RCD_ATEXP exprow) = let
    val (code, data) = List.foldl (fn ((lab, exp), (code, loclabls)) => let
      val (expCode, expLoc) = infExp spa exp in
      (code @ expCode, loclabls @ [(expLoc, Lab.toString lab)]) end)
      ([],[]) exprow
    val nloc = newloc ()
    val code = code @ [NEWRCD (nloc, data)] in (code, nloc) end

  and infExp spa (AT_EXP atexp) = infAtexp spa atexp
    | infExp spa (APP_EXP (exp, atexp)) = let
    val (codeAtexp, locAtexp) = infAtexp spa atexp
    val (codeExp, locExp) = infExp spa exp
    val loc = newloc ()
    val code = codeAtexp @ codeExp @ [CALL (loc, locExp, locAtexp)] in
    (code, loc) end
    | infExp spa (FN_EXP match) = let
      val fid = newclos F
      val code = infMatch spa match
      val _ = popAdd code
      val nloc = newloc () in
      ([NEWFCN (nloc, fid)], nloc) end

  and infMrule spa (pat, exp) = let
    val _ = inc labref
    val (patCode, patVs) = infPat spa (! closidref, ~1) pat
    val newspa = S.modifyValspa spa patVs
    val (expCode, expLoc) = infExp newspa exp in
    (patCode @ expCode @ [RETURN expLoc, LABEL (! labref)]) end

  and infMatch spa match = List.foldl (fn (mrule, code) =>
    code @ (infMrule spa mrule)) [] match

  and infDec spa (VAL_DEC (_, valbd)) = let
    val (code, vs) = infValbind spa valbd
    val s = S.fromValspa vs in (code, s) end

    | infDec spa (SEQ_DEC (dec1, dec2)) = let
    val (code1, spa1) = infDec spa dec1
    val spaMod = S.modify spa spa1
    val (code2, spa2) = infDec spaMod dec2
    val s = S.modify spa1 spa2 in
    (code1 @ code2, s) end

    | infDec spa (DAT_DEC (datbd)) = let
    val (code, vs, ts) = infDatbind datbd
    val s = Value.SPA (SS.empty, ts, vs) in
    (code, s) end

  and infValbind spa (NRE_VALBIND (vrow)) =
    infVrow spa vrow
    | infValbind spa (REC_VALBIND (vrow)) = let
    val (patCodes, patVs, patLocs) = List.foldl
    (fn ((pat , _), (code, vs, loc)) => let
      val nloc = newloc ()
      val (patCode, patVs) = infPat spa nloc pat
      val code = code @ [patCode]
      val vs = VS.modify vs patVs
      val loc = loc @ [nloc] in
      (code, vs, loc) end) ([], VS.empty, []) vrow

    val recspa = S.modifyValspa spa patVs

    val (expCodes, expLocs) = List.foldl
    (fn ((_, exp), (code, loc)) => let
      val (expCode, expLoc) = infExp recspa exp
      val code = code @ [expCode]
      val loc  = loc @ [expLoc] in
      (code, loc) end) ([], []) vrow

    val data = zip(zip (expCodes, expLocs), zip (patCodes, patLocs))

    val code = List.foldl (fn (((expCode, expLoc),(patCode, patLoc)), code) =>
      code @ expCode @ [MOV (patLoc, expLoc)] @ patCode) [] data in
    (code, patVs) end

  and infDatbind datbd = let
    val (code, vs, ts) = List.foldl (fn ((_, tycon, cb), (code, vs, ts)) => let
      val (cbCode, cbVs) = infConbind cb
      val cbTs = TS.fromListPair [(tycon, cbVs)]
      val vs = VS.modify vs cbVs
      val ts = TS.modify ts cbTs
      val code = code @ cbCode in (code, vs, ts) end)
      ([], VS.empty, TS.empty) datbd in (code, vs, ts) end

  and infConbind conbd = let
    val (code, vs, _) = List.foldl (fn ((vid, tyop), (code, vs, cid)) =>
    if isSome tyop then let
      val fid = newclos F
      val retloc = newloc ()
      val fcnCode = [NEWCON (retloc, (fid, ~1), cid), RETURN retloc]
      val _ = popAdd fcnCode;
      val conLoc = newloc ()
      val conCode = [NEWFCN (conLoc, fid)]
      val conVs = VS.fromListPair [(vid, CON (conLoc,cid))]
      val code = code @ conCode
      val vs = VS.modify vs conVs in
      (code, vs, cid + 1) end else let
      val conLoc = newloc ()
      val conCode = [NEWCON (conLoc, (~1, ~1), cid)]
      val conVs = VS.fromListPair [(vid, CON (conLoc,cid))]
      val code = code @ conCode
      val vs = VS.modify vs conVs in
      (code, vs, cid + 1) end) ([], VS.empty, 0) conbd in (code, vs) end

  and infVrow spa vrow = let
    val (vs, code) = List.foldl (fn ((pat, exp), (vs, code)) => let
      val (codeExp, locExp) = infExp spa exp
      val (codePat, vsPat) = infPat spa locExp pat
      val nvs = VS.modify vs vsPat
      val ncode = code @ codeExp @ codePat in
      (nvs, ncode) end) (VS.empty, []) vrow in (code, vs) end

  and infAtpat spa loc (LVID_ATPAT ([], vid)) = let
    val value = valOf (S.getValstr spa ([], vid))
      handle Option => (VAL (~1, ~1)) in
    case value of
        VAL _ => let
        val vs = VS.fromListPair [(vid, VAL loc)] in
        ([], vs) end
      | CON (_, tag) =>
        ([GETCON ((~1, ~1), loc, tag,! labref)], VS.empty) end
    | infAtpat spa loc (PAT_ATPAT pat) = infPat spa loc pat
    | infAtpat spa loc (WILD_ATPAT) = ([], VS.empty)
    | infAtpat spa loc (RCD_ATPAT (patrow, _)) = let
    val (code, vs) = List.foldl (fn ((lab, pat), (code, vs)) => let
      val patLoc = newloc ()
      val (patCode, patVs) = infPat spa patLoc pat
      val code = code @
        [GETRCD (patLoc, loc, Lab.toString lab, ! labref)] @ patCode
      val vs = VS.modify vs patVs in (code, vs) end)
      ([], VS.empty) patrow in (code, vs) end
    | infAtpat spa loc (SCON_ATPAT scon) = case scon of
      INT_SCON i => ([GETINT (loc, i, ! labref)], VS.empty)

  and infPat spa loc (AT_PAT atpat) = infAtpat spa loc atpat
    | infPat spa loc (CON_PAT (lvid, atpat)) = let
    val atpatLoc = newloc ()
    val (atpatCode, atpatVs) = infAtpat spa atpatLoc atpat
    val (CON (loc, cid)) = valOf (S.getValstr spa lvid)
    val code = [GETCON (atpatLoc, loc, cid, ! labref)] @ atpatCode in
    (code, atpatVs) end

  fun infProg prog = let
    val () = init ()
    val (code, spa) = infDec S.empty prog
    val () = popAdd code in
    ! progref end

end

