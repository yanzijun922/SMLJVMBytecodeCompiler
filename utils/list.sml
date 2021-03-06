structure ListAux = struct
  exception EmptyList

  fun last [l] = l
    | last (l :: ls) = last ls
    | last [] = raise Size

  fun front [l] = []
    | front (l :: ls) = l :: (front ls)
    | front [] = []

  fun max [x] = x
    | max [] = raise EmptyList
    | max (x :: xs) = (fn (a, b) => if a > b then a else b) (x, max xs)

  fun sub (x :: xs) (s, s') =
    if x = s then s' :: sub xs (s, s') else x :: sub xs (s, s')
    | sub [] (s, s') = []

  fun subsl xs subs = foldl (fn (sb, xs) => sub xs sb) xs subs
  fun subsr xs subs = foldr (fn (sb, xs) => sub xs sb) xs subs

  val substitute = subsl

  fun toString nil tostr splitStr = ""
    | toString ls tostr splitStr =
    List.foldr (fn (a, b) => (a ^ splitStr ^ b)) (tostr (List.last ls))
               (map tostr (List.take (ls, (length ls) - 1)))

  fun prependOption (ls, l) = case l of NONE => ls | SOME i => i :: ls
  fun fromOptionList (l :: ls) = (case l of 
      NONE => fromOptionList ls 
    | SOME i => i :: (fromOptionList ls))
    | fromOptionList [] = []

  fun enumerate 0 _ _ = []
    | enumerate n init succ =
    if n < 0 then raise Size else
      init :: (enumerate (n - 1) (succ init) succ)

  fun findIndexFrom (x :: xs) y c = 
    if x = y then SOME c else findIndexFrom xs y (c + 1)
    | findIndexFrom [] _ _ = NONE

  fun findIndex xs y = findIndexFrom xs y 0

  fun countElement l e = let
    fun aux (x :: xs) e c = aux xs e (c + (if e = x then 1 else 0))
      | aux [] e c = c in
    aux l e 0 end

  fun member (l :: ls, i) = l = i orelse member (ls, i)
    | member ([], _) = false

  fun rmDup [] = []
    | rmDup (i :: is) = if member (is, i) then 
        rmDup is else 
        i :: (rmDup is)
    
  fun uniqueElements ls = let 
    val dups = ref []
    fun aux (l :: ls) = 
      if member (! dups, l) then 
        aux ls
      else if member (ls, l) then
        (dups := l :: (! dups);
         aux ls)
      else l :: (aux ls)
      | aux [] = [] in
    aux ls end

  fun remove (l :: ls) e = if e = l then remove ls e else l :: (remove ls e)
    | remove [] e = []

end

structure ListPairAux = struct
  fun append (ls1, ls2) (ls1', ls2') = (ls1 @ ls1', ls2 @ ls2')
end
