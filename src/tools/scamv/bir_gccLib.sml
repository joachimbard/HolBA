structure bir_gccLib :> bir_gccLib =
struct

local
  open bir_scamv_helpersLib;

  val libname = "bir_gccLib"
  val ERR = Feedback.mk_HOL_ERR libname
  val wrap_exn = Feedback.wrap_exn libname
in

  fun gcc_prefix env_var () =
      case Option.mapPartial (fn p => if p <> "" then SOME p else NONE)
                             (OS.Process.getEnv(env_var)) of
          NONE => raise ERR "scamv_gcc_prefix" ("the environment variable " ^ env_var ^ " is not set")
        | SOME p => p;


(*
val lines = "";
*)
  fun bir_gcc_assemble_disassemble arch_str input_code =
    let
      val (env_var, flags) =
        case arch_str of
            "arm8" => ("HOLBA_GCC_ARM8_CROSS", " ")
          | "m0" => ("HOLBA_GCC_ARM_CROSS", " -mcpu=cortex-m0 -mthumb ")
          | _ => raise ERR "bir_gcc_assemble_disassemble" ("architecture \"" ^ arch_str ^ "\" unknown");
      val gcc_prefix = gcc_prefix env_var ();

      val path_asm_s  = get_simple_tempfile "asm.s";
      val path_asm_o  = get_simple_tempfile "asm.o";
      val path_asm_da = get_simple_tempfile "asm.da";

      val _ = write_to_file path_asm_s input_code;

      val commandline = (gcc_prefix ^ "gcc" ^ flags ^ "-o " ^ path_asm_o ^ " -c " ^ path_asm_s ^
                         " && " ^
                         gcc_prefix ^ "objdump -d " ^ path_asm_o ^ " > " ^ path_asm_da);
      (* val _ = print("command: " ^ commandline ^ "\n"); *)
      val _ = if OS.Process.isSuccess (OS.Process.system commandline) then ()
              else raise ERR "bir_gcc_assemble_disassemble" "compilation failed somehow";
    in
      path_asm_da
    end;

end (* local *)

end (* struct *)
