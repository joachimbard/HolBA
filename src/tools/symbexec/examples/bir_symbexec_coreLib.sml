structure bir_symbexec_coreLib =
struct

local
  open bir_symbexec_stateLib;

  open bir_constpropLib;
  open bir_envSyntax;
  open bir_expSyntax;
  open bir_exp_helperLib;
in (* local *)

  fun subst_fun env (bev, (e, vars)) =
    let
      val bv_ofvars = find_val env bev "subst_fun";
    in
      (subst_exp (bev, mk_BExp_Den bv_ofvars, e),
       bv_ofvars::vars)
    end;

  fun compute_val_try vals (besubst, besubst_vars) deps_l2 =
    let
      val all_deps_const = List.all (fn bv =>
             (not o is_bvar_init) bv andalso
             (case find_val vals bv "compute_val_try" of
                 SymbValBE (exp,_) => is_BExp_Const exp
               | _ => false)
           ) besubst_vars;
    in
      if all_deps_const then
        if List.null besubst_vars then NONE else
        let
          val _ = if Redblackset.isEmpty deps_l2 then () else
                  raise ERR "compute_val_try" "deps_l2 is not empty. Unexpected here.";

          fun subst_fun_symbvalbe vals (bv_dep, e) =
            let
              val symbv_dep = find_val vals bv_dep "compute_val_try";
              val exp = case symbv_dep of
                           SymbValBE (exp,_) => exp
                         | _ => raise ERR "compute_val_and_resolve_deps" "cannot happen";
            in
              subst_exp (bv_dep, exp, e)
            end;

          val becomp = List.foldr (subst_fun_symbvalbe vals) besubst besubst_vars;
        in
          SOME (SymbValBE (becomp, symbvalbe_dep_empty))
        end
      else
        NONE
    end;

  fun compute_val_and_resolve_deps vals (besubst, besubst_vars) =
    let
      val deps_l2 = List.foldr (Redblackset.union)
                               symbvalbe_dep_empty
                               (List.map (find_symbval_deps "compute_val_and_resolve_deps" vals) besubst_vars);
    in
      case compute_val_try vals (besubst, besubst_vars) deps_l2 of
         SOME x => x
       | NONE   =>
          let
            val deps = Redblackset.addList(deps_l2, besubst_vars);
            val be_new_val = SymbValBE (besubst, deps);
          in
            be_new_val
          end
    end;

  fun compute_valbe be syst =
    let
      val env  = SYST_get_env  syst;
      val vals = SYST_get_vals syst;

      val be_vars = get_birexp_vars be;
      (* TODO: this is a quickfix, should be handled in bir smtlib exporter: probably together with all other syntactic sugar!!!! *)
      val be_ = (snd o dest_eq o concl o REWRITE_CONV [bir_bool_expTheory.bir_exp_false_def, bir_bool_expTheory.bir_exp_true_def]) be
                handle UNCHANGED => be;
      val besubst_with_vars = List.foldr (subst_fun env) (be_, []) be_vars;

      val be_new_val = compute_val_and_resolve_deps vals besubst_with_vars;
    in
      be_new_val
    end;

  fun insert_valbe bv_fr be syst =
    insert_bvfrexp bv_fr (compute_valbe be syst) syst;

  fun branch_state str_prefix cnd f_bt f_bf syst =
    let
        val cnd_bv = bir_envSyntax.mk_BVar_string (str_prefix ^ "_cnd", ``BType_Bool``);
        val cnd_bv_t = get_bvar_fresh cnd_bv;
        val cnd_bv_f = get_bvar_fresh cnd_bv;
    in
        List.concat [
          (f_bt o
           SYST_update_pred ((cnd_bv_t)::(SYST_get_pred syst)) o
           insert_valbe cnd_bv_t cnd
          ) syst
         ,
          (f_bf o
           SYST_update_pred ((cnd_bv_f)::(SYST_get_pred syst)) o
           insert_valbe cnd_bv_f (bslSyntax.bnot cnd)
          ) syst
        ]
    end;

  fun branch_state_simp str_prefix cnd f_bt f_bf syst =
      branch_state str_prefix cnd (fn s => [f_bt s]) (fn s => [f_bf s]) syst

  (*
  val syst = init_state prog_vars;
  val SymbState systr = syst;
  val s = ``BStmt_Assign (BVar "R5" (BType_Imm Bit32)) (BExp_Den (BVar "R4" (BType_Imm Bit32)))``;
  val (bv, be) = dest_BStmt_Assign s
  *)
  fun update_state (bv, be) syst =
    if is_BExp_IfThenElse be then
      let
        val (cnd, be1, be2) = dest_BExp_IfThenElse be;
      in
        branch_state "assign"
                     cnd
                     (update_state (bv, be1))
                     (update_state (bv, be2))
                     syst
      end
    else
    let
      val bv_fresh = (get_bvar_fresh) bv;
    in
      [(update_env bv bv_fresh o
        insert_valbe bv_fresh be
      ) syst]
    end;
end (* local *)

end (* struct *)
