structure bir_symbexec_stateLib =
struct

local
val ERR = Feedback.mk_HOL_ERR "bir_symbexec_stateLib"
val wrap_exn = Feedback.wrap_exn "bir_symbexec_stateLib"
in

(* symbolic values *)
datatype symb_value =
    SymbValBE    of (term * term Redblackset.set)
  | SymbValRange of (term * term)
                    (* TODO: generalize this later *)
                    (* memory layout: flash, globals, stack;
                                      start and size of middle portion (globals) *)
  | SymbValMem   of (((Arbnum.num -> Arbnum.num) * term * term) * (Arbnum.num * Arbnum.num));

val symbvalbe_dep_empty = Redblackset.empty Term.compare;


(* symbolic states *)
datatype symb_state =
  SymbState of {
      SYST_pc     : term,
      SYST_env    : (term, term) Redblackmap.dict,
      SYST_status : term,
      (* symbolic observation list: id, condition, value list, aggregation function *)
      SYST_obss   : (Arbnum.num * term * term list * term) list,
      (* path condition conjuncts *)
      SYST_pred   : term list,
      (* abstracted symbolic values for some "fresh" variables *)
      SYST_vals   : (term, symb_value) Redblackmap.dict
    };

val BST_Running_tm =
  ``BST_Running``;
val BST_AssertionViolated_tm =
  ``BST_AssertionViolated``;
val BST_AssumptionViolated_tm =
  ``BST_AssumptionViolated``;

fun SYST_get_pc     (SymbState systr) =
  #SYST_pc systr;
fun SYST_get_env    (SymbState systr) =
  #SYST_env systr;
fun SYST_get_status (SymbState systr) =
  #SYST_status systr;
fun SYST_get_obss   (SymbState systr) =
  #SYST_obss systr;
fun SYST_get_pred   (SymbState systr) =
  #SYST_pred systr;
fun SYST_get_vals   (SymbState systr) =
  #SYST_vals systr;

fun SYST_mk pc env status obss pred vals =
  SymbState {SYST_pc     = pc,
             SYST_env    = env,
             SYST_status = status,
             SYST_obss   = obss,
             SYST_pred   = pred,
             SYST_vals   = vals };

fun SYST_update_pc pc' (SymbState systr) =
  SYST_mk (pc')
          (#SYST_env    systr)
          (#SYST_status systr)
          (#SYST_obss   systr)
          (#SYST_pred   systr)
          (#SYST_vals   systr);
fun SYST_update_env env' (SymbState systr) =
  SYST_mk (#SYST_pc     systr)
          (env')
          (#SYST_status systr)
          (#SYST_obss   systr)
          (#SYST_pred   systr)
          (#SYST_vals   systr);
fun SYST_update_status status' (SymbState systr) =
  SYST_mk (#SYST_pc     systr)
          (#SYST_env    systr)
          (status')
          (#SYST_obss   systr)
          (#SYST_pred   systr)
          (#SYST_vals   systr);
fun SYST_update_obss obss' (SymbState systr) =
  SYST_mk (#SYST_pc     systr)
          (#SYST_env    systr)
          (#SYST_status systr)
          (obss')
          (#SYST_pred   systr)
          (#SYST_vals   systr);
fun SYST_update_pred pred' (SymbState systr) =
  SYST_mk (#SYST_pc     systr)
          (#SYST_env    systr)
          (#SYST_status systr)
          (#SYST_obss   systr)
          (pred')
          (#SYST_vals   systr);
fun SYST_update_vals vals' (SymbState systr) =
  SYST_mk (#SYST_pc     systr)
          (#SYST_env    systr)
          (#SYST_status systr)
          (#SYST_obss   systr)
          (#SYST_pred   systr)
          (vals');


(* fresh variables and initial state variables *)
local
  open bir_envSyntax;
  open bir_expSyntax;
  val freshvarcounter_ = ref (0:int);
  fun get_fresh_var_counter () =
    let val i = !freshvarcounter_; in
    (freshvarcounter_ := i + 1; i) end;
in
  fun get_bvar_fresh bv =
    let
      val (s, bty) = dest_BVar_string bv;
      val new_s = "fr_" ^ (Int.toString (get_fresh_var_counter ())) ^ "_" ^ s;
    in
      mk_BVar_string (new_s, bty)
    end;

  fun get_bvar_init bv =
    let
      val (s, bty) = dest_BVar_string bv;
      val new_s = "sy_" ^ s;
    in
      mk_BVar_string (new_s, bty)
    end;

  fun is_bvar_init bv =
    let
      val (s, _) = dest_BVar_string bv;
    in
      String.isPrefix "sy_" s
    end;
end


(* initial state *)
local
  open bir_envSyntax;
in
  fun init_state lbl_tm prog_vars =
    let
      val envlist_progvars = List.map (fn bv => (bv, get_bvar_init bv)) prog_vars;
    in
      SYST_mk lbl_tm
              (Redblackmap.fromList Term.compare envlist_progvars)
              BST_Running_tm
              []
              []
              (Redblackmap.fromList Term.compare [])
    end;
end


(* state update primitives *)
(* TODO: better names *)
fun insert_bvfrexp bv_fresh symbv syst =
  let
    val vals  = SYST_get_vals syst;
    val vals' = Redblackmap.insert (vals, bv_fresh, symbv);
  in
    (SYST_update_vals vals') syst
  end;

fun update_env bv bv_fresh syst =
  let
    val env   = SYST_get_env  syst;

    val _     = if (isSome o Redblackmap.peek) (env, bv) then () else
                raise ERR
                   "update_env"
                   ("can only update existing state variables, tried to update: " ^ (term_to_string bv));
    val env'  = Redblackmap.insert (env, bv, bv_fresh);
  in
    (SYST_update_env env') syst
  end;


(* state updates *)
(* TODO: generalize this a bit more - to general state updates - move this to core lib
          ??? including state update primitives ??? *)
fun init_state_set_const bv bimm syst =
  let
    val bv_fresh = get_bvar_fresh bv;
    val symbv_init = SymbValBE (``BExp_Const ^bimm``, symbvalbe_dep_empty);
  in
    (update_env bv bv_fresh o
     insert_bvfrexp bv_fresh symbv_init
    ) syst
  end;


(* helper functions *)
fun find_val vals bv err_src_string =
      (valOf o Redblackmap.peek) (vals,bv)
      handle Option => raise ERR
                             err_src_string
                             ("coudln't find value for " ^ (term_to_string bv));


(* symbval dependencies *)
fun deps_of_symbval symbv err_src_string =
  case symbv of
          SymbValBE (_,deps) => deps
        | _ => raise ERR err_src_string "cannot handle symbolic value type to find dependencies";

fun union_deps vals (bv, deps) =
  let
    val symbv = find_val vals bv "union_deps";
    val deps_delta = deps_of_symbval symbv "union_deps";
  in
    Redblackset.union (deps_delta, deps)
  end;

fun find_symbval_deps err_src_string vals bv =
  if is_bvar_init bv then Redblackset.add(symbvalbe_dep_empty,bv) else (
    deps_of_symbval (find_val vals bv err_src_string) err_src_string
    handle e => raise wrap_exn ("find_symbval_deps::expect bir expression for variable: " ^ (term_to_string bv)) e
  );


(* tidy up states *)
fun tidyup_state_vals syst =
  let
    val pred = SYST_get_pred syst;
    val env  = SYST_get_env  syst;
    val vals = SYST_get_vals syst;

    val entry_vars = symbvalbe_dep_empty;
    val entry_vars = Redblackset.addList(entry_vars, pred);
    val entry_vars = Redblackset.addList(entry_vars, (List.map snd o Redblackmap.listItems) env);
    val entry_vars = Redblackset.filter (not o is_bvar_init) entry_vars;

    val deps = Redblackset.foldl (union_deps vals) symbvalbe_dep_empty entry_vars;

    val keep_vals = Redblackset.filter (not o is_bvar_init) (Redblackset.union(entry_vars, deps));

    val num_vals = Redblackmap.numItems vals;
    val num_keep_vals = Redblackset.numItems keep_vals;

    val num_diff = num_vals - num_keep_vals;

    val _ = if num_diff = 0 then () else
            if num_diff < 0 then
              raise ERR "tidyup_state_vals" "this shouldn't be negative"
            else
              print ("TIDIED UP " ^ (Int.toString num_diff) ^ " VALUES.\n");

    val vals' = Redblackset.foldl
                (fn (bv,vals_) => Redblackmap.insert(vals_, bv, find_val vals bv "tidyup_state_vals"))
                (Redblackmap.mkDict Term.compare)
                keep_vals;
  in
    (SYST_update_vals vals') syst
  end;


(* check feasibility of states *)
local
  open bir_expSyntax;
  open bir_envSyntax;
  open bir_smtLib;

  val BIExp_Equal_tm = ``BIExp_Equal``;

  fun proc_preds (vars, asserts) pred =
    List.foldr (fn (exp, (vl1,al)) =>
      let val (_,vl2,a) = bexp_to_smtlib [] vl1 exp in
        (vl2, a::al)
      end) (vars, asserts) pred;

  fun symbval_eq_to_bexp (bv, symbv) =
       case symbv of
          SymbValBE (exp,_) =>
            mk_BExp_BinPred (BIExp_Equal_tm, mk_BExp_Den bv, exp)
        | _ => raise ERR "symbval_eq_to_bexp" "cannot handle symbolic value type";

  fun collect_pred_expsdeps vals (bv, (exps, deps)) =
    let
      val symbv = find_val vals bv "collect_pred_expsdeps";
      val (exp, deps_delta) =
       case symbv of
          SymbValBE x => x
        | _ => raise ERR "collect_pred_expsdeps" "cannot handle symbolic value type";
    in
      (exp::exps, Redblackset.union(deps_delta, deps))
    end;

in (* local *)
  fun check_feasible syst =
    let
      val vals  = SYST_get_vals syst;
      val pred_bvl = SYST_get_pred syst;

      val (pred_conjs, pred_deps) =
        List.foldr (collect_pred_expsdeps vals) ([], symbvalbe_dep_empty) pred_bvl;

      val pred_depsl_ = Redblackset.listItems pred_deps;
      val pred_depsl = List.filter (not o is_bvar_init) pred_depsl_;

      val valsl = List.map (fn bv => (bv, find_val vals bv "check_feasible"))
                           pred_depsl;
      val vals_eql =
        List.map symbval_eq_to_bexp valsl;

      (* memory accesses should not end up here (actually only SymbValBE should be relevant),
         ignore this detail for now *)

      (* start with no variable and no assertions *)
      val vars    = Redblackset.empty smtlib_vars_compare;
      val asserts = [];

      (* process the predicate conjuncts *)
      val (vars, asserts) = proc_preds (vars, asserts) pred_conjs;

      (* process the symbolic values *)
      val (vars, asserts) = proc_preds (vars, asserts) vals_eql;

      val result = querysmt bir_smtLib_z3_prelude vars asserts;

      val _ = if result = BirSmtSat orelse result = BirSmtUnsat then () else
              raise ERR "check_feasible" "smt solver couldn't determine feasibility"

      val resultvalue = result <> BirSmtUnsat;

      val _ = if resultvalue then () else
              print "FOUND AN INFEASIBLE PATH...\n";
    in
      resultvalue
    end;
end (* local *)

end (* outermost local *)

end (* struct *)
