signature bir_gccLib = sig

  (*
     takes a list of assembly instructions
     it produces a disassembly file for the lifter
     and returns its path in the temporary directory.
   *)
  val bir_gcc_assemble_disassemble : string -> string -> string

end
