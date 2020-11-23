signature bir_scamv_driverLib = sig
    include scamv_configLib 
    (* include bir_rel_synthLib *)
    (* datatype modelValues = memT of (string * (num*num) list) *)
    (* 		       | regT of (string * num) *)
  val symb_exec_phase : string -> term -> (term * (term * term * term) list option) list * term list
  val make_word_relation : term -> term list -> term
  val scamv_test_main : int -> (string * term) -> unit

  val scamv_test_single_file : string -> unit;

  val scamv_run : scamv_config -> unit
  val scamv_run_with_opts : unit -> unit

end
