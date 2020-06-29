structure binariesCfgLib =
struct
local

open binariesLib;
open binariesDefsLib;

open bir_programSyntax;
open bir_valuesSyntax;
open bir_immSyntax;
open optionSyntax;
open wordsSyntax;
open listSyntax;


in (* local *)

datatype cfg_target =
    CFGT_DIR   of term
  | CFGT_INDIR of term;

(* Unknown: if not determined yet *)
(* Halt, Basic, Jump, CondJump can be determined from BIR code for direct jumps *)
(* indirect jumps as well as Call and Return are fixed semi-automatically *)
datatype cfg_node_type =
    CFGNT_Unknown
  | CFGNT_Halt
  | CFGNT_Basic
  | CFGNT_Jump
  | CFGNT_CondJump
  | CFGNT_Call
  | CFGNT_Return;

(* cfg nodes correspond to BIR blocks *)
type cfg_node = {
  (* id: BIR label term *)
  CFGN_lbl_tm : term,
  (* meta information from binary *)
  CFGN_descr  : string,
  CFGN_succ   : term option,
  (* flow information exported from BIR, and fixed afterwards *)
  CFGN_goto   : cfg_target list,
  (* type can be unknown and filled in by later passes *)
  CFGN_type   : cfg_node_type
};

type cfg_graph = {
  CFGG_name  : string,
  CFGG_entry : term,
  CFGG_nodes : cfg_node list
};


(*
=================================================================================================
=================================================================================================
*)
  local

fun is_lbl_in_cfg_nodes lbl_tm (ns:cfg_node list) =
  List.exists (fn n => (#CFGN_lbl_tm n) = lbl_tm) ns;

(* val ble = (dest_BStmt_Jmp bbes) *)
fun BLE_to_cfg_target ble =
  if is_BLE_Label ble then
    CFGT_DIR (dest_BLE_Label ble)
  else if is_BLE_Exp ble then
    let
      val exp = dest_BLE_Exp ble;
      val res = (snd o dest_eq o concl o EVAL) ``bir_eval_exp ^exp (BEnv (\x. NONE))``;
    in
      if is_none res then
        CFGT_INDIR exp
      else if is_some res then
        CFGT_DIR ((mk_BL_Address o dest_BVal_Imm o dest_some) res)
      else
        raise ERR "BLE_to_cfg_target" "what happened here during trial evaluation?"
    end
  else
    raise ERR "BLE_to_cfg_target" "unknown BLE type";

fun bir_es_to_cfg_targets bbes = List.map BLE_to_cfg_target (
          if is_BStmt_Jmp bbes then
            [dest_BStmt_Jmp bbes]
          else if is_BStmt_CJmp bbes then
            ((fn (_, a, b) => [a, b]) (dest_BStmt_CJmp bbes))
          else if is_BStmt_Halt bbes then
            []
          else
            raise ERR "bir_es_to_bles"
                      ("unknown BStmt end stmt type: " ^
                       (term_to_string bbes)));

local
 fun list_split_pred_aux acc p [] = fail ()
    | list_split_pred_aux acc p (x::xs) =
      (if x = p then (List.rev acc, xs)
       else list_split_pred_aux (x::acc) p xs)

  fun list_split_pred p = list_split_pred_aux [] p
in
fun lbl_hc_tm_to_descr_succ lbl =
  let
    val _ = if is_BL_Address_HC lbl then ()
            else raise ERR "lbl_hc_tm_to_descr_succ"
                   ("we can only deal with output from the lifter, need BL_Address_HC: " ^
                    (term_to_string lbl));
    val (addr_tm, descr_tm) = dest_BL_Address_HC lbl;
    val descr = stringSyntax.fromHOLstring descr_tm;
    val addr = (dest_word_literal o dest_Imm32) addr_tm;

    val instrLen2 = (length o fst o (list_split_pred #" ") o explode) descr;
    val _ = if instrLen2 mod 2 = 0 then () else
            raise ERR "lbl_hc_tm_to_descr_succ"
                      ("something went wrong when trying to find the binary " ^
                       "instruction code: " ^
                       (term_to_string lbl));
    val instrLen = instrLen2 div 2;
    val _ = if instrLen = 2 orelse instrLen = 4 then () else
            raise ERR "lbl_hc_tm_to_descr_succ"
                      ("something went wrong when trying to find the binary " ^
                       "instruction code, wrong instruction length: " ^
                       (term_to_string lbl));

    val addr_succ = Arbnum.+ (addr, Arbnum.fromInt instrLen);
    val succ_lbl_tm = mk_lbl_tm addr_succ;
  in
    (descr, succ_lbl_tm)
  end;
end

fun determine_cfg_node_type cfg_t_l succ_tm_o =
  let
    val contains_indir = List.foldr (fn (x, b) => b orelse
                    (fn CFGT_INDIR _ => true | CFGT_DIR _ => false) x
                ) false cfg_t_l;
    val cfgn_type =
      if contains_indir then CFGNT_Unknown else
      case cfg_t_l of
          []  => CFGNT_Halt
        | [x] => if not (isSome succ_tm_o) then CFGNT_Jump else
                 if x = CFGT_DIR (valOf succ_tm_o) then CFGNT_Basic else
                   CFGNT_Jump
        | _   => CFGNT_CondJump;
  in
    cfgn_type
  end;

(*
val lbl_tm = hd prog_lbl_tms_;
List.map to_cfg_node prog_lbl_tms_;
*)
fun to_cfg_node lbl_tm =
  let
    val bl = case prog_get_block_ lbl_tm of SOME x => x
                    | NONE => raise ERR "to_cfg_nodes" ("label couldn't be found: " ^ (term_to_string lbl_tm));
    val (lbl, _, bbes) = dest_bir_block bl;

    val (descr, succ_lbl_tm) = lbl_hc_tm_to_descr_succ lbl;
    val succ_tm_o = if isSome (prog_get_block_ succ_lbl_tm) then SOME succ_lbl_tm else NONE;

    val cfg_t_l = bir_es_to_cfg_targets bbes;

    val cfgn_type = determine_cfg_node_type cfg_t_l succ_tm_o;

    val n = { CFGN_lbl_tm = lbl_tm,
              CFGN_descr  = descr,
              CFGN_succ   = succ_tm_o,
              CFGN_goto   = cfg_t_l,
              CFGN_type   = cfgn_type
            } : cfg_node;

  in n end;


(*
fun cfg_target_to_lbl_tm (CFGT_DIR   tm) = SOME tm
  | cfg_target_to_lbl_tm (CFGT_INDIR _ ) = NONE;
*)
fun cfg_targets_to_lbl_tms l = SOME (List.map (fn
         CFGT_DIR tm  => tm
       | CFGT_INDIR _ => raise ERR "cfg_targets_to_lbl_tms" "") l)
   handle HOL_ERR _ => NONE;

val BVarLR32_tm = ``BVar "LR" (BType_Imm Bit32)``;
fun is_Assign_LR tm =
  if is_BStmt_Assign tm then
    ((fst o dest_BStmt_Assign) tm) = BVarLR32_tm
  else
    false;

fun find_node (ns: cfg_node list) lbl_tm =
  valOf (List.find (fn n => (#CFGN_lbl_tm n) = lbl_tm) ns)
  handle Option => raise ERR "find_node" ("couldn't find node: " ^ (term_to_string lbl_tm));

(*
val ns = List.map to_cfg_node prog_lbl_tms_;
val n  = find_node ns lbl_tm;
val ns = List.map (update_node_guess_type_call o to_cfg_node) prog_lbl_tms_;
*)
fun update_node_guess_type_call n =
  if #CFGN_type n <> CFGNT_Jump then n else
  let
    val debug_on = false;

    val lbl_tm = #CFGN_lbl_tm n;
    val cfg_t_l = #CFGN_goto n;

    val _ = if not debug_on then () else
            print ((term_to_string lbl_tm) ^ "\n");

    val bl = case prog_get_block_ lbl_tm of SOME x => x
                    | NONE => raise ERR "to_cfg_nodes" ("label couldn't be found: " ^ (term_to_string lbl_tm));
    val (_, bbs, _) = dest_bir_block bl;

    val goto_tm = (((hd o valOf o cfg_targets_to_lbl_tms) cfg_t_l
        handle Empty => raise Option)
        handle Option => raise ERR "update_node_guess_type_call"
                                   "there should be exactly 1 direct jump");

    val isCall_lr  = List.exists is_Assign_LR ((fst o dest_list) bbs);
    val isCall_to_entry = ((length cfg_t_l = 1) andalso
                           (List.exists (fn x => x = goto_tm) prog_fun_entry_lbl_tms));

    val _ = if isCall_lr = isCall_to_entry then ()
            else raise ERR "update_node_guess_type_call"
                           "something in call detection is unexpected";
    val isCall = isCall_lr;

    val _ = if not (debug_on andalso isCall) then () else
            (print "call        ::: "; print (#CFGN_descr n); print "\t"; print_term lbl_tm);

    val new_type = if isCall then CFGNT_Call else #CFGN_type n;

    val new_n =
            { CFGN_lbl_tm = #CFGN_lbl_tm n,
              CFGN_descr  = #CFGN_descr n,
              CFGN_succ   = #CFGN_succ n,
              CFGN_goto   = #CFGN_goto n,
              CFGN_type   = new_type
            } : cfg_node;
  in
    new_n
  end;

(*
length ns

val ns = List.map (update_node_guess_type_call o to_cfg_node) prog_lbl_tms_;
val lbl_tm = mk_lbl_tm (Arbnum.fromInt 7936);
val n  = find_node ns lbl_tm;
val _ = List.map (update_node_guess_type_return o update_node_guess_type_call o to_cfg_node) prog_lbl_tms_;
*)
fun update_node_guess_type_return (n:cfg_node) =
  if #CFGN_type n <> CFGNT_Unknown then n else
  let
    val debug_on = false;

    val lbl_tm = #CFGN_lbl_tm n;
    val descr = #CFGN_descr n;

    val isReturn = ((String.isSubstring "pop {" descr) andalso
                    (String.isSubstring "pc}" descr))
                   orelse
                   (String.isSubstring "(bx lr)" descr);

    (* hack for hand inspected instructions *)
    val isReturn = isReturn orelse (
                   (lbl_tm = mk_lbl_tm (Arbnum.fromInt 0x1fc)) andalso
                   (String.isPrefix "4718 (" descr)
        );

    val _ = if not (debug_on andalso isReturn) then () else
            (print "return      ::: "; print descr; print "\t"; print_term lbl_tm);


    (* hack for indirect jumps (a.k.a. oracle) *)
    val hack_map_1
             = [(0x2bc8, "469F (mov pc, r3)", CFGNT_Jump, [
                         "542c0000",
                         "fe2b0000",
                         "fe2b0000",
                         "2c2d0000",
                         "fa2b0000",
                         "fa2b0000",
                         "222d0000",
                         "2c2d0000",
                         "fa2b0000",
                         "222d0000",
                         "fa2b0000",
                         "2c2d0000",
                         "302d0000",
                         "302d0000",
                         "302d0000",
                         "382d0000"
                       ]),
                    (0x2814, "4697 (mov pc, r2)", CFGNT_Jump, [
                         "2a290000",
                         "66280000",
                         "8a280000",
                         "28280000",
                         "8a280000",
                         "06290000",
                         "8a280000",
                         "28280000",
                         "66280000",
                         "66280000",
                         "06290000",
                         "28280000",
                         "5c290000",
                         "5c290000",
                         "5c290000",
                         "12290000"

                       ]),
                    (0x28ba, "4697 (mov pc, r2)", CFGNT_Jump, [
                         "66280000",
                         "66280000",
                         "8a280000",
                         "26280000",
                         "8a280000",
                         "06290000",
                         "8a280000",
                         "26280000",
                         "66280000",
                         "66280000",
                         "06290000",
                         "26280000",
                         "5c290000",
                         "5c290000",
                         "5c290000",
                         "10290000"
                       ])
                   ];
(* -0x428‬ *)
(*
 000033d4
 00003354
 00003394
*)
    val hack_map_2
             = [(0x27a0, "469F (mov pc, r3)", CFGNT_Jump, [
                         "282c0000",
                         "27d60000",
                         "27d60000",
                         "29040000",
                         "27d20000",
                         "27d20000",
                         "28fa0000",
                         "29040000",
                         "27d20000",
                         "28fa0000",
                         "27d20000",
                         "29040000",
                         "29080000",
                         "29080000",
                         "29080000",
                         "29100000"
                       ]),
                    (0x23ec, "4697 (mov pc, r2)", CFGNT_Jump, [
                         "25020000",
                         "243e0000",
                         "24620000",
                         "24000000",
                         "24620000",
                         "24de0000",
                         "24620000",
                         "24000000",
                         "243e0000",
                         "243e0000",
                         "24de0000",
                         "24000000",
                         "25340000",
                         "25340000",
                         "25340000",
                         "24ea0000"
                       ]),
                    (0x2492, "4697 (mov pc, r2)", CFGNT_Jump, [
                         "243e0000",
                         "243e0000",
                         "24620000",
                         "23fe0000",
                         "24620000",
                         "24de0000",
                         "24620000",
                         "23fe0000",
                         "243e0000",
                         "243e0000",
                         "24de0000",
                         "23fe0000",
                         "25340000",
                         "25340000",
                         "25340000",
                         "24e80000"
                       ])
                   ];
    val hack_map = hack_map_1@hack_map_2;
    val hackMatch = List.find (fn (loc_, descr_, _, _) =>
                                 descr = descr_ andalso
                                 dest_lbl_tm lbl_tm = Arbnum.fromInt loc_
                              ) hack_map;
    val isIndirJump = isSome hackMatch;
    (*
    val tl = ((fn (_, _, nt, tl) => tl) o hd) hack_map;
    val s = hd tl;
rev_hs_to_num (Arbnum.fromInt 0) s
Arbnum.toHexString (rev_hs_to_num (Arbnum.fromInt 0) s)
    *)
    val indirJumpUpdate = Option.map (fn (_, _, nt, tl) =>
        let
          val tl_unique = List.foldr (fn (x,l) => if List.exists (fn y => x=y) l then l else (x::l)) [] tl;
          fun split_string_byte s =
            let
              val _ = if (String.size s) mod 2 = 0 then () else
                        raise ERR "split_string_byte" "bug: string length is wrong";
              val len = (String.size s) div 2;
            in
              (Arbnum.fromHexString (String.substring(s, (len*2) - 2, 2)),
                                     String.substring(s, 0, (len*2) - 2))
            end;
          fun rev_hs_to_num acc "" = acc
	    | rev_hs_to_num acc s  =
                let
                  val sp = split_string_byte s;
                  val n  = Arbnum.+(Arbnum.*(acc, Arbnum.fromInt 256), fst sp);
                in
                  rev_hs_to_num n (snd sp)
                end;
        in
          (nt, List.map (rev_hs_to_num (Arbnum.fromInt 0)) tl_unique)
        end
      ) hackMatch;
(*
    val isIndirJump = String.isSubstring "(mov pc," descr;
*)
    val _ = if not (isReturn andalso isIndirJump) then () else
            raise ERR "update_node_guess_type_return" "cannot be both, weird.";

    val _ = if not (debug_on andalso isIndirJump) then () else
            (print "indirect J  ::: "; print descr; print "\t"; print_term lbl_tm);

    (* still unclear type... *)
    val _ = if (isReturn orelse isIndirJump) (* orelse (not debug_on) *) then ()
            else print ("update_node_guess_type_return :: " ^
                           "cannot determine type: " ^ descr ^
                            "\t" ^ (term_to_string lbl_tm) ^ "\n");


    val new_type = #CFGN_type n;
    val new_type = if isReturn    then CFGNT_Return else new_type;
    val new_type = if isIndirJump then ((fst o valOf) indirJumpUpdate) else new_type;

    val new_goto = if isIndirJump then (((List.map (CFGT_DIR o mk_lbl_tm)) o snd o valOf) indirJumpUpdate) else #CFGN_goto n;

    val new_n =
            { CFGN_lbl_tm = #CFGN_lbl_tm n,
              CFGN_descr  = #CFGN_descr n,
              CFGN_succ   = #CFGN_succ n,
              CFGN_goto   = new_goto,
              CFGN_type   = new_type
            } : cfg_node;
  in
    new_n
  end;


fun collect_node_callinfo (n:cfg_node) =
  let
    val rel_name = (valOf o mem_find_rel_symbol_by_addr_ o dest_lbl_tm o #CFGN_lbl_tm) n;
    val n_type   = #CFGN_type n;
    val n_succ   = #CFGN_succ n;
    val n_goto   = #CFGN_goto n;
  in
    if n_type <> CFGNT_Call then NONE else SOME (
     rel_name,
     List.map (fn CFGT_DIR t => (valOf o mem_find_rel_symbol_by_addr_ o dest_lbl_tm) t
                | CFGT_INDIR _ => raise ERR "collect_node_callinfo" "indirection not allowed here") n_goto,
     valOf n_succ
     handle Option => raise ERR "collect_node_callinfo" "no successor for a call node, something is wrong"
    )
  end;


fun lookup_calls_to ci to = List.foldr (fn ((_, tol, returnto), l) =>
    if List.exists (fn x => x = to) tol then
      (returnto)::l
    else
      l
  ) [] ci;

fun update_node_fix_return_goto lookup_calls_to_f n =
  if #CFGN_type n <> CFGNT_Return then n else
  let
    val debug_on = false;

    val rel_name = (valOf o mem_find_rel_symbol_by_addr_ o dest_lbl_tm o #CFGN_lbl_tm) n;

    val new_goto = ((List.map CFGT_DIR) o lookup_calls_to_f) rel_name;

    val new_n =
            { CFGN_lbl_tm = #CFGN_lbl_tm n,
              CFGN_descr  = #CFGN_descr n,
              CFGN_succ   = #CFGN_succ n,
              CFGN_goto   = new_goto,
              CFGN_type   = #CFGN_type n
            } : cfg_node;
  in
    new_n
  end;


fun cfg_targets_to_lbl_tms_exn l et =
    (valOf o cfg_targets_to_lbl_tms) l
    handle Option => raise ERR "cfg_targets_to_lbl_tms_exn" ("unexpected indirection: " ^ et);

fun cfg_targets_to_direct_lbl_tms l = List.foldr (fn
         (CFGT_DIR   tm, ls) => tm::ls
       | (CFGT_INDIR tm , ls) => (print ("unexpected indirection: " ^
                                        (term_to_string tm) ^ "\n"); ls)
  ) [] l;


(*
=================================================================================================
*)

val ns_ = List.map (update_node_guess_type_return o update_node_guess_type_call o to_cfg_node) prog_lbl_tms_;
val ci  = List.foldr (fn (n,l) => let val vo = collect_node_callinfo n in
                                 if isSome vo then (valOf vo)::l else l end) [] ns_;

val ns  = List.map (update_node_fix_return_goto (lookup_calls_to ci)) ns_;


(*
=================================================================================================
=================================================================================================
*)
  in (* local *)

val ns = ns;
val ci = ci;

val cfg_targets_to_lbl_tms = cfg_targets_to_lbl_tms;

fun find_node (ns:cfg_node list) lbl_tm =
  (valOf o List.find (fn n => #CFGN_lbl_tm n = lbl_tm)) ns
  handle Option => raise ERR "find_node" ("couldn't find node " ^ (term_to_string lbl_tm));


fun get_fun_cfg_walk_succ (n: cfg_node) =
  let
    val lbl_tm = #CFGN_lbl_tm n;
    val descr  = #CFGN_descr n;
    val n_type = #CFGN_type n;
    val n_goto = #CFGN_goto n;
    val debug_on = false;
    val _ = if not debug_on then () else
            print ("node: " ^ (term_to_string lbl_tm) ^ "\n" ^
                   " - " ^ descr ^ "\n");
  in
    case n_type of
        CFGNT_Unknown   => (if debug_on then print "UNRESOLVED NODE\n" else (); [])
      | CFGNT_Halt      => []
      | CFGNT_Basic     => cfg_targets_to_direct_lbl_tms n_goto
      | CFGNT_Jump      => cfg_targets_to_direct_lbl_tms n_goto
      | CFGNT_CondJump  => cfg_targets_to_direct_lbl_tms n_goto
      | CFGNT_Call      => (* this accounts for a walk that
                              doesn't follow call edges *)
                           [(valOf o #CFGN_succ) n]
      | CFGNT_Return    => [] (* this terminates returns *)
  end;


fun build_fun_cfg_nodes _  acc []                 = acc
  | build_fun_cfg_nodes ns acc (lbl_tm::lbl_tm_l) =
      let
        val n = find_node ns lbl_tm;
        val n_type = #CFGN_type n;

        val _ = if n_type <> CFGNT_Unknown then () else
                (print "indirection ::: in ";
                 print (prog_lbl_to_mem_rel_symbol lbl_tm);
                 print "\t"; print (#CFGN_descr n);
                 print "\t"; print_term lbl_tm);

        val new_node  = if n_type = CFGNT_Unknown then [] else [n];
        val new_nodes = new_node@acc;

        val next_tm_l      = List.filter (fn x => not ((is_lbl_in_cfg_nodes x new_nodes) orelse
                                                       (List.exists (fn y => x = y) lbl_tm_l)))
                                         (get_fun_cfg_walk_succ n);
        val new_lbl_tm_l   = next_tm_l@lbl_tm_l;
      in
        build_fun_cfg_nodes ns new_nodes new_lbl_tm_l
      end;

fun node_to_rel_symbol (n:cfg_node) =
  (valOf o mem_find_rel_symbol_by_addr_ o dest_lbl_tm) (#CFGN_lbl_tm n);

fun build_fun_cfg ns name =
  let
    val entry_lbl_tm = mem_symbol_to_prog_lbl name;
    val cfg_comp_ns = build_fun_cfg_nodes ns [] [entry_lbl_tm];
    val _ = print ("walked " ^ (Int.toString (length cfg_comp_ns)) ^
                   " nodes (" ^ name ^ ")\n");
    (* validate that all collected nodes belong to the function *)
    val ns_names   = List.map node_to_rel_symbol cfg_comp_ns
      handle Option => raise ERR "build_fun_cfg" "cannot find label for node address";
    val allAreName = List.foldr (fn (n,b) => b andalso (
           n = name
      )) true ns_names;
  in
    {
      CFGG_name  = name,
      CFGG_entry = entry_lbl_tm,
      CFGG_nodes = cfg_comp_ns
    } : cfg_graph
  end;


(*
=================================================================================================
*)

fun count_paths_to_ret_nexts follow_call ns lbl_tm =
  let
    val n = find_node ns lbl_tm;
    val n_type = #CFGN_type n;
    val nexts = (valOf o cfg_targets_to_lbl_tms o #CFGN_goto) n;
  in
    case n_type of
         CFGNT_Unknown => raise ERR "count_paths_to_ret_nexts" " unknown control flow"
       | CFGNT_Halt    => ([], [])
       | CFGNT_Call    => (if follow_call then nexts else
                           [(valOf o #CFGN_succ) n]
                           ,
                           if follow_call then [] else
                           List.map (valOf o mem_find_rel_symbol_by_addr_ o dest_lbl_tm) nexts)
       | CFGNT_Return  => (if follow_call then nexts else [], [])
       | _             => (nexts, [])
  end;

(* following calls doesn't work like this, we would need a call stack of course *)
fun count_paths_to_ret follow_call ns stop_at_l lbl_tm =
  if (List.exists (fn x => lbl_tm = x) stop_at_l) then (1, []) else
  let
    val (nexts, calls) = count_paths_to_ret_nexts follow_call ns lbl_tm;
    val summary = List.map (count_paths_to_ret follow_call ns stop_at_l) nexts;
  in
    if length nexts = 0 then (1, []) else
    List.foldr (fn ((i, l), (i_s, l_s)) => (i+i_s, l@l_s)) (0, calls) summary
  end;

fun to_histogram_proc (x, [])        = [(x,1)]
  | to_histogram_proc (x, (y, n)::l) =
      if x = y
      then ((y, n+1)::l)
      else (y, n)::(to_histogram_proc (x, l));

fun to_histogram sum_calls =
  List.foldr to_histogram_proc [] sum_calls;

(*
=================================================================================================
=================================================================================================
*)
  end (* local *)


end (* local *)
end (* struct *)
