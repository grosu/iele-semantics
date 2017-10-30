type iele_opcode = [
  `STOP
| `ADD
| `MUL
| `SUB
| `DIV
| `EXP
| `MOD
| `ADDMOD
| `MULMOD
| `EXPMOD
| `SIGNEXTEND
| `TWOS
| `LT
| `GT
| `EQ
| `ISZERO
| `AND
| `OR
| `XOR
| `NOT
| `BYTE
| `SHA3
| `ADDRESS
| `BALANCE
| `ORIGIN
| `CALLER
| `CALLVALUE
| `CALLDATALOAD
| `CALLDATASIZE
| `CALLDATACOPY
| `CODESIZE
| `CODECOPY
| `GASPRICE
| `EXTCODESIZE
| `EXTCODECOPY
| `RETURNDATASIZE
| `RETURNDATACOPY
| `BLOCKHASH
| `COINBASE
| `TIMESTAMP
| `NUMBER
| `DIFFICULTY
| `GASLIMIT
| `MLOAD8
| `MLOAD256
| `MLOAD
| `MSTORE8
| `MSTORE256
| `MSTORE
| `SLOAD
| `SSTORE
| `PC
| `MSIZE
| `GAS
| `MOVE
| `LOADPOS
| `LOADNEG
| `JUMP of int
| `JUMPI of int
| `JUMPDEST of int
| `REGISTERS of int
| `LOG of int
| `CREATE
| `CALL of int * int
| `CALLCODE of int * int
| `DELEGATECALL of int * int
| `STATICCALL of int * int
| `LOCALCALL of int * int * int
| `RETURN of int
| `LOCALRETURN of int
| `REVERT of int
| `INVALID
| `SELFDESTRUCT
]

type iele_op =
| Nop
| Op of iele_opcode * int * int list
| VoidOp of iele_opcode * int list
| CallOp of iele_opcode * int list * int list
| LiOp of iele_opcode * int * Z.t

let asm_iele_opcode op = match op with
| `STOP -> "\x00"
| `ADD -> "\x01"
| `MUL -> "\x02"
| `SUB -> "\x03"
| `DIV -> "\x04"
| `MOD -> "\x06"
| `EXP -> "\x07"
| `ADDMOD -> "\x08"
| `MULMOD -> "\x09"
| `EXPMOD -> "\x0a"
| `SIGNEXTEND -> "\x0b"
| `TWOS -> "\x0c"
| `LT -> "\x10"
| `GT -> "\x11"
| `EQ -> "\x14"
| `ISZERO -> "\x15"
| `AND -> "\x16"
| `OR -> "\x17"
| `XOR -> "\x18"
| `NOT -> "\x19"
| `BYTE -> "\x1a"
| `SHA3 -> "\x20"
| `ADDRESS -> "\x30"
| `BALANCE -> "\x31"
| `ORIGIN -> "\x32"
| `CALLER -> "\x33"
| `CALLVALUE -> "\x34"
| `CODESIZE -> "\x38"
| `CODECOPY -> "\x39"
| `GASPRICE -> "\x3a"
| `EXTCODESIZE -> "\x3b"
| `EXTCODECOPY -> "\x3c"
| `RETURNDATASIZE -> "\x3d"
| `RETURNDATACOPY -> "\x3e"
| `BLOCKHASH -> "\x40"
| `COINBASE -> "\x41"
| `TIMESTAMP -> "\x42"
| `NUMBER -> "\x43"
| `DIFFICULTY -> "\x44"
| `GASLIMIT -> "\x45"
| `MLOAD8 -> "\x50"
| `MLOAD256 -> "\x51"
| `MLOAD -> "\x52"
| `MSTORE8 -> "\x53"
| `MSTORE256 -> "\x54"
| `MSTORE -> "\x55"
| `SLOAD -> "\x56"
| `SSTORE -> "\x57"
| `PC -> "\x58"
| `MSIZE -> "\x59"
| `GAS -> "\x5a"
| `MOVE -> "\x60"
| `LOADPOS -> "\x61"
| `LOADNEG -> "\x62"
| `REGISTERS i -> "\x63" ^ (IeleUtil.string_of_char (Char.chr i))
| `JUMP i -> "\x64" ^ (IeleUtil.be_int_width (Z.of_int i) 16)
| `JUMPI i -> "\x65" ^ (IeleUtil.be_int_width (Z.of_int i) 16)
| `JUMPDEST i -> "\x66" ^ (IeleUtil.be_int_width (Z.of_int i) 16)
| `LOG(n) ->
  let byte = 0xa0 + n in
  let ch = Char.chr byte in
  IeleUtil.string_of_char ch
| `CREATE -> "\xf0"
| `CALL(nargs,nreturn) -> "\xf1" ^ (IeleUtil.be_int_width (Z.of_int nargs) 16) ^ (IeleUtil.be_int_width (Z.of_int nreturn) 16)
| `CALLCODE(nargs,nreturn) -> "\xf2" ^ (IeleUtil.be_int_width (Z.of_int nargs) 16) ^ (IeleUtil.be_int_width (Z.of_int nreturn) 16)
| `DELEGATECALL(nargs,nreturn) -> "\xf3" ^ (IeleUtil.be_int_width (Z.of_int nargs) 16) ^ (IeleUtil.be_int_width (Z.of_int nreturn) 16)
| `STATICCALL(nargs,nreturn) -> "\xf4" ^ (IeleUtil.be_int_width (Z.of_int nargs) 16) ^ (IeleUtil.be_int_width (Z.of_int nreturn) 16)
| `RETURN(nreturn) -> "\xf5" ^ (IeleUtil.be_int_width (Z.of_int nreturn) 16)
| `REVERT(nreturn) -> "\xf6" ^ (IeleUtil.be_int_width (Z.of_int nreturn) 16)
| `LOCALCALL (call,nargs,nreturn) -> "\xf7" ^ (IeleUtil.be_int_width (Z.of_int call) 16) ^ (IeleUtil.be_int_width (Z.of_int nargs) 16) ^ (IeleUtil.be_int_width (Z.of_int nreturn) 16)
| `LOCALRETURN(nreturn) -> "\xf5" ^ (IeleUtil.be_int_width (Z.of_int nreturn) 16)
| `INVALID -> "\xfe"
| `SELFDESTRUCT -> "\xff"
| `LOCALCALLI _ | `CALLDATALOAD | `CALLDATASIZE | `CALLDATACOPY -> invalid_arg "needs postprocessing"

let asm_iele_regs regs buf nregs =
  let z = List.fold_right (fun reg accum -> Z.add (Z.shift_left accum nregs) (Z.of_int reg)) regs Z.zero in
  Buffer.add_string buf (IeleUtil.be_int_width z (List.length regs * nregs))

let asm_iele_op op buf nregs = match op with
| Nop -> ()
| Op(opcode,reg,regs) -> 
  Buffer.add_string buf (asm_iele_opcode opcode);
  asm_iele_regs (reg::regs) buf nregs
| VoidOp(opcode,regs) -> 
  Buffer.add_string buf (asm_iele_opcode opcode);
  asm_iele_regs regs buf nregs
| CallOp(opcode,regs1,regs2) ->
  Buffer.add_string buf (asm_iele_opcode opcode);
  asm_iele_regs (regs1 @ regs2) buf nregs
| LiOp(opcode,r,payload) ->
  Buffer.add_string buf (asm_iele_opcode opcode);
  asm_iele_regs [r] buf nregs;
  let payload_be = IeleUtil.be_int payload in
  Buffer.add_string buf (IeleUtil.rlp_encode_string payload_be)

let rec asm_iele_aux ops buf nregs = match ops with
| [] -> ()
| op :: ops -> asm_iele_op op buf nregs; asm_iele_aux ops buf nregs

let asm_iele ops =
  let nregs = match ops with
  | VoidOp(`REGISTERS n,[]) :: tail -> n
  | _ -> 5
  in
  let buf = Buffer.create ((List.length ops) * 2) in
  asm_iele_aux ops buf nregs;
  Buffer.contents buf
