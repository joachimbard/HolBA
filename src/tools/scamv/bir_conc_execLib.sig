signature bir_conc_execLib = sig

  datatype modelValues = memT of (string * (num*num) list)
		       | regT of (string * num)
  val conc_exec_program :  string -> int -> term -> (term -> term) option -> (num * num) list * term -> term

  val conc_exec_obs_extract : term -> (num * num) list * term -> term list

  val conc_exec_obs_compute : string -> term -> modelValues list -> term list * modelValues list
  val conc_exec_obs_compare : string -> term -> modelValues list * modelValues list -> bool * modelValues list list
end
