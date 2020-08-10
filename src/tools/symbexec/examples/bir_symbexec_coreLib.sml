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

  fun compute_val_and_resolve_deps vals (besubst, besubst_vars) =
    let
      fun find_symbval_f bv = if is_bvar_init bv then (SymbValBE (F, Redblackset.add(symbvalbe_dep_empty,bv))) else
                            find_val vals bv "compute_val_and_resolve_deps";
      fun find_deps bv = case find_symbval_f bv of
                            SymbValBE (_,deps) => deps
                          | _ => raise ERR "compute_val_and_resolve_deps"
                                           ("expect bir expression for variable: " ^ (term_to_string bv));

      val deps_l2 = List.foldr (Redblackset.union)
                               symbvalbe_dep_empty
                               (List.map find_deps besubst_vars);
    in
      if List.all (not o is_bvar_init) besubst_vars andalso
         Redblackset.numItems deps_l2 = 0 andalso
         length besubst_vars = 1 andalso
         (case find_symbval_f (hd besubst_vars) of SymbValBE (exp,_) => is_BExp_Const exp | _ => false)
      then
        let
          val bv_dep = hd besubst_vars;
          val symbv_dep = find_symbval_f bv_dep;
          val exp = case symbv_dep of
                       SymbValBE (exp,_) => exp
                     | _ => raise ERR "compute_val_and_resolve_deps" "cannot happen";
        in
          SymbValBE (subst_exp (bv_dep, exp, besubst), symbvalbe_dep_empty)
        end
      else
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

  fun insert_bvfrexp bv_fr exp syst =
    let
      val vals = SYST_get_vals syst;

      val vals' = Redblackmap.insert (vals, bv_fr, exp);
    in
      (SYST_update_vals vals') syst
    end;

  fun insert_valbe bv_fr be syst =
    insert_bvfrexp bv_fr (compute_valbe be syst) syst;

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

        val cnd_bv = bir_envSyntax.mk_BVar_string ("assign_cnd", ``BType_Bool``);
        val cnd_bv_1 = get_bvar_fresh cnd_bv;
        val cnd_bv_2 = get_bvar_fresh cnd_bv;
      in
        List.concat [
          (update_state (bv, be1) o
           SYST_update_pred ((cnd_bv_1)::(SYST_get_pred syst)) o
           insert_valbe cnd_bv_1 cnd
          ) syst
         ,
          (update_state (bv, be2) o
           SYST_update_pred ((cnd_bv_2)::(SYST_get_pred syst)) o
           insert_valbe cnd_bv_2 (bslSyntax.bnot cnd)
          ) syst
        ]
      end
    else
    let
      val env  = SYST_get_env  syst;

      val bv_fresh = (get_bvar_fresh) bv;

      val env'  = Redblackmap.insert (env, bv, bv_fresh);
    in
      [(SYST_update_env  env' o
        insert_valbe bv_fresh be
      ) syst]
    end;
end (* local *)

end (* struct *)
