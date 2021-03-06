structure InterInference = struct

  structure IST = IntermediateSyntaxTree
  structure S = Space
  structure VS = ValueSpace
  structure TS = TypeSpace
  structure SS = StructureSpace
  structure LM = LabBinaryMap
  structure IS = InitialSpace
  structure IM = IntBinaryMapAux
  structure IC = InterClosure
  structure IP = InterProgram
  structure II = InterInstruction

  structure VIS = ValueIndexSet

  datatype scon      = datatype IST.scon
  datatype atexp     = datatype IST.atexp
  datatype exp       = datatype IST.exp
  datatype dec       = datatype IST.dec
  datatype valbind   = datatype IST.valbind
  datatype atpat     = datatype IST.atpat
  datatype pat       = datatype IST.pat
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
  (* closure type, id, maxloc, nexts*)
  type clostk = (closty * int * (int ref) * ((int list) ref)) list

  val labref = ref 0
  val excref = ref 0
  val clostkref  = ref ([] : clostk)
  val closidref = ref 0
  val progref = ref (IM.empty : IP.program)
  val zip = ListPair.zip

  fun sortedRcdLoc locLabList = List.map (fn (d, l) => d) (ListMergeSort.sort 
    (fn ((d1, l1), (d2, l2)) => (LabKey.compare (l1, l2) = GREATER)) locLabList)

  fun getLabOrdMap labList = let
    val sorted = (ListMergeSort.sort 
      (fn (l1, l2) => (LabKey.compare (l1, l2) = GREATER)) labList) in
    #1 (List.foldl (fn (l, (lm, c)) => (LM.insert (lm, l, c), c + 1))
      (LM.empty, 0) labList) end
    
  fun inc r = r := !r + 1

  fun newclosid () = (inc closidref; ! closidref)

  fun newlab () = (inc labref; ! labref)

  fun newloc () = let
    val (_, closid, locref, _) = hd (! clostkref) in
    inc locref; (closid, ! locref) end

  fun popclos () = let
    val (ty, closid, locref, childrenref) = hd (! clostkref) in
    clostkref := tl (! clostkref);
    if not (List.null (! clostkref)) then
    let val childrenref = #4 (hd (! clostkref)) in 
      childrenref := closid :: (! childrenref) end else ();
    (ty, closid, ! locref, ! childrenref) end

  fun topCid () = let
    val (ty, closid, locref, childrenref) = hd (! clostkref) in closid end

  fun pushclos entry = clostkref := entry :: (! clostkref)

  fun newclos ty = let
    val newclos = (ty, newclosid (), ref 0, ref []) in
    (clostkref := newclos :: (! clostkref); ! closidref) end

  fun popAdd code = let
    val (ty, closid, locmax, children) = popclos ()
    val newprog  = case ty of
      F =>  IP.insert ((! progref), closid,
        IC.FCN ((#2 o hd) (! clostkref), children, locmax, code))
    | T =>  IP.insert ((! progref), closid,
        IC.TOP (children,locmax, code)) in
    progref := newprog end

  fun init () = (
    closidref := ~1;
    clostkref := [];
    labref    := ~1;
    newclos T;
    progref := IM.empty)

  val closnewed = ref false

  fun infScon scon = let
    val loc = newloc () in
    ([NEWSCN (loc, scon)], loc)  end

  fun infAtexp spa (SCON_ATEXP scon) = infScon scon

    | infAtexp spa (LVID_ATEXP lvid) = let
    val value = valOf (S.getValstr spa lvid)
      handle Option => (TIO.println "LVID not found";
      TIO.println (#2 lvid); raise Option) in
    ([], toLoc value) end

    | infAtexp spa (EXP_ATEXP (exp, ts)) = infExp spa exp

    | infAtexp spa (RCD_ATEXP exprow) = let
    val (code, data) = List.foldl (fn ((lab, (exp, ts)), (code, loclabls)) => let
      val (expCode, expLoc) = infExp spa exp in
      (code @ expCode, loclabls @ [(expLoc, lab)]) end)
      ([],[]) exprow
    val data = sortedRcdLoc data
    val nloc = newloc ()
    val code = code @ [NEWRCD (nloc, data)] in (code, nloc) end

    | infAtexp spa (LET_ATEXP (dec, (exp, ts))) = let
    val (decCode, decSpa) = infDec spa dec
    val modspa = S.modify spa decSpa
    val (expCode, locCode) = infExp modspa exp
    val code = decCode @ expCode in (code, locCode) end

  and infExp spa (AT_EXP (atexp, ts)) = infAtexp spa atexp

    | infExp spa (APP_EXP ((FN_EXP match, ts), (atexp, ts'))) = let
    val (codeAtexp, locAtexp) = infAtexp spa atexp
    val (codeApp, locApp) = infAppMatch spa match locAtexp
    val code = codeAtexp @ codeApp in
    (code, locApp) end

    | infExp spa (APP_EXP ((exp, ts), (atexp, ts'))) = let
    val (codeAtexp, locAtexp) = infAtexp spa atexp
    val loc = newloc ()
    val code = case exp of 
        AT_EXP (LVID_ATEXP lvid, _) => let
          val tagop = Value.getTag (valOf (S.getValstr spa lvid)) in
          if isSome tagop then
            codeAtexp @ [NEWTAG (loc,locAtexp,valOf tagop)]
          else let
            val (codeExp, locExp) = infExp spa exp in
            codeAtexp @ codeExp @ [CALL (loc, locExp, locAtexp)] end end
      | _ => let
        val (codeExp, locExp) = infExp spa exp in
        codeAtexp @ codeExp @ [CALL (loc, locExp, locAtexp)] end in
    (code, loc) end

    | infExp spa (FN_EXP match) = let
      val fid = newclos F
      val code = infMatch spa match
      val _ = popAdd code
      val nloc = newloc () in
      ([NEWFCN (nloc, fid)], nloc) end

    | infExp spa (RAS_EXP (exp, ts)) = let
      val (codeExp, locExp) = infExp spa exp in
      ([RAISE locExp], (~1, ~1)) end

    (*| infExp spa (HAND_EXP ((exp, ts), match)) = let*)
      (*val (codeExp, locExp) = infExp spa exp in*)
      (*(codeExp, locExp) end*)

  (* for val rec *)
  and infFn spa (FN_EXP match) closidop = let
    val fid = if isSome closidop then
        (pushclos (F, valOf closidop, ref 0, ref []); valOf closidop) else newclos F
    val code = infMatch spa match
    val _ = popAdd code
    val nloc = newloc () in
    ([NEWFCN (nloc, fid)], nloc) end

  and infMrule spa ((pat, ts), (exp, ts')) = let
    val nextlab = newlab ()
    val (patCode, patVs) = infPat spa (topCid (), ~1) nextlab pat
    val newspa = S.modifyValspa spa patVs
    val (expCode, expLoc) = infExp newspa exp in
    (patCode @ expCode @ [RETURN expLoc, LABEL (nextlab)]) end

  (* for (fn ...) e *)

  and infAppMatch spa (match, comp) inloc = let
    val retlab = newlab ()
    val outloc = newloc ()
    val code = List.foldl (fn (((pat, ts), (exp, ts')), code) => let
      val nextlab = newlab ()
      val (patCode, patVs) = infPat spa inloc nextlab pat
      val newspa = S.modifyValspa spa patVs
      val (expCode, expLoc) = infExp newspa exp 
      val expMrule = patCode @ expCode @ [MOV (outloc, expLoc), GOTO retlab] in
      code @ expMrule @ [LABEL nextlab] end) [] match in
    (code @ (if comp then [] else [RAISE IS.matchLoc]) @ [LABEL retlab], outloc) end

  and infMatch spa (match, comp) = let
    val front = ListAux.front match
    val last  = ListAux.last match
    val frontCode = List.foldl (fn (mrule, code) =>
    code @ (infMrule spa mrule)) [] front
    val lastCode = infMrule spa last in
    frontCode @ lastCode @ (if comp then [] else [RAISE IS.matchLoc]) end

  and infDec spa (VAL_DEC valbd) = let
    val lab = newlab ()
    val lab2 = newlab ()
    val (code, vs, comp) = infValbind spa lab valbd
    val code = code @ (if comp then [] else 
      [GOTO lab2, LABEL lab, RAISE IS.bindLoc, LABEL lab2])
    val s = S.fromValspa vs in 
    (code, s) end

    (*| infDec spa (SEQ_DEC (dec1, dec2)) = let*)
    (*val (code1, spa1) = infDec spa dec1*)
    (*val spaMod = S.modify spa spa1*)
    (*val (code2, spa2) = infDec spaMod dec2*)
    (*val s = S.modify spa1 spa2 in*)
    (*(code1 @ code2, s) end*)

    | infDec spa (SEQ_DEC decs) = let
    val (code, spa, rspa) = List.foldl (fn (dec, (code, spa, rspa)) => let
      val (cDec, sDec) = infDec spa dec
      val spa' = S.modify spa sDec
      val rspa' = S.modify rspa sDec
      val code' = code @ cDec in (code', spa', rspa') end) ([], spa, S.empty) decs in
    (code, rspa) end

    | infDec spa (DAT_DEC datbd) = let
    val (code, vs, ts) = infDatbind datbd
    val s = Value.SPA (SS.empty, ts, vs) in
    (code, s) end

    | infDec spa (EXC_DEC exbd) = let
    val (ebCode, ebVs, nexttag) = infConbind exbd false (! excref) in
    excref := nexttag;
    (ebCode, Value.SPA (SS.empty, TS.empty, ebVs)) end

  and infValbind spa lab (NRE_VALBIND (vrow, comp)) = let
    val (vs, code) = List.foldl (fn (((pat, ts), (exp, ts')), (vs, code)) => let
      val (codeExp, locExp) = infExp spa exp
      val (codePat, vsPat) = infPat spa locExp lab pat
      val nvs = VS.modify vs vsPat
      val ncode = code @ codeExp @ codePat in
      (nvs, ncode) end) (VS.empty, []) vrow in (code, vs, comp) end

    | infValbind spa lab (REC_VALBIND (vrow, comp)) = let
    val vidcidpl = List.map (
    fn ((AT_PAT ((LVID_ATPAT ([], vid), ts)),ts'), (exp, ts'')) =>
      (vid, newclosid ())
      | _ => raise Match) vrow
    val recvs = VS.fromListPair (List.map (fn (vid, cid)=> (vid, VAL (cid, 0))) vidcidpl)
    val recspa = S.modifyValspa spa recvs
    val cidvrow = ListPair.zip (vidcidpl, vrow)
    val (vs, code) = List.foldl (fn (((vid, cid),((pat, ts), (exp, ts'))), (vs, code)) => let
      val (codeExp, locExp) = infFn recspa exp (SOME cid)
      val vsPat = VS.fromListPair [(vid, VAL (locExp))]
      val nvs = VS.modify vs vsPat
      val ncode = code @ codeExp in
    (nvs, ncode) end) (VS.empty, []) cidvrow in (code, vs, comp) end

  and infDatbind datbd = let
    val (code, vs, ts) = List.foldl (fn (cb, (code, vs, ts)) => let
      val (cbCode, cbVs, _) = infConbind cb true 0
      val cbTs = TS.fromListPair [("", cbVs)]
      val vs = VS.modify vs cbVs
      val ts = TS.modify ts cbTs
      val code = code @ cbCode in (code, vs, ts) end)
      ([], VS.empty, TS.empty) datbd in (code, vs, ts) end

  and infConbind conbd isCon stag = let
    val (code, vs, nexttag) = List.foldl (fn ((vid, isfun), (code, vs, cid)) =>
    if isfun then let
      val fid = newclos F
      val retloc = newloc ()
      val fcnCode = [NEWTAG (retloc, (fid, ~1), cid), RETURN retloc]
      val _ = popAdd fcnCode;
      val conLoc = newloc ()
      val conCode = [NEWFCN (conLoc, fid)]
      val conVs = VS.fromListPair [(vid, (if isCon then CON else EXC) (conLoc,cid))]
      val code = code @ conCode
      val vs = VS.modify vs conVs in
      (code, vs, cid + 1) end
    else let
      val conLoc = newloc ()
      val conCode = [NEWTAG (conLoc, (~1, ~1), cid)]
      val conVs = VS.fromListPair [(vid, (if isCon then CON else EXC) (conLoc,cid))]
      val code = code @ conCode
      val vs = VS.modify vs conVs in
      (code, vs, cid + 1) end) ([], VS.empty, 0) conbd in (code, vs, nexttag) end

  and infAtpat spa loc lab (LVID_ATPAT ([], vid)) = let
    val value = valOf (S.getValstr spa ([], vid))
      handle Option => (VAL (~1, ~1)) in
    case value of
        VAL _ => let
        val vs = VS.fromListPair [(vid, VAL loc)] in
        ([], vs) end
      | CON (_, tag) =>
        ([MATTAG ((~1, ~1), loc, tag, lab)], VS.empty) end

    | infAtpat spa loc lab (PAT_ATPAT (pat, ts)) = infPat spa loc lab pat

    | infAtpat spa loc lab (WILD_ATPAT) = ([], VS.empty)

    | infAtpat spa loc lab (RCD_ATPAT patrow) = let
    val (code, vs) = List.foldl (fn ((l, (pat, ts)), (code, vs)) => let
      val patLoc = newloc ()
      val (patCode, patVs) = infPat spa patLoc lab pat
      val labOrdMap = getLabOrdMap (List.map (fn (lab, (pat, ts)) => lab) patrow)
      val code = code @
        [MATRCD (patLoc, loc, valOf (LM.find (labOrdMap, l)))] @ patCode
      val vs = VS.modify vs patVs in (code, vs) end)
      ([], VS.empty) patrow in (code, vs) end
    | infAtpat spa loc lab (SCON_ATPAT scon) = case scon of
      INT_SCON i => ([MATINT (loc, i, lab)], VS.empty)

  and infPat spa loc lab (AT_PAT (atpat, ts)) = infAtpat spa loc lab atpat

    | infPat spa loc lab (CON_PAT ((lvid, ts'), (atpat, ts))) = let
    val atpatLoc = newloc ()
    val (atpatCode, atpatVs) = infAtpat spa atpatLoc lab atpat
    val (CON (_, cid)) = valOf (S.getValstr spa lvid)
      handle Option => (TIO.println "CON not found"; raise Option)
    val code = [MATTAG (atpatLoc, loc, cid, lab)] @ atpatCode in
    (code, atpatVs) end

  fun infProg prog = let
    val () = init ()
    val (code, spa) = infDec InitialSpace.space prog
    val () = popAdd (code @ [EXIT]) in
    (spa, ! progref, ! labref) end

  val inference = infProg

end

