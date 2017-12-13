# Gas Model

This document describes a proposal for the gas model of IELE.

## General considerations

The gas model needs to ensure that:

* Miners are rewarded for their work (and thus have an incentive for doing it).
  * Note that if miners are rewarded for all their work, as far as they are
    concerned, there are no DOS attacks.

* Clients are reasonably charged for the resources used by their contracts
  and so they have an incentive to use IELE.

* Costs are simple enough that clients (and, potentially, miners) can perform
  accurate cost estimates prior to execution.

Although not a part of the Gas costs, the constraints above require that all
programs execution paths are fully defined and there are no external exceptions,
such as the miner running out of memory.

To satisfy the above constraints, the following costs must be considered:

1. CPU usage
1. Memory usage over time
   * Note that memory maintenance can be part of the CPU usage
1. Permanent storage usage over time
1. Permanent storage access

One important design decision which fundamentally impacts the Gas model is the
fact that IELE integers are arbitrarily large, which has implication to both
the CPU usage / operation and memory/storage costs.

### CPU usage

A good (over)approximation of the actual CPU costs must be computed for each
instruction.

Generally, we would like the cost associated to an operation to be a polynomial
(preferably linear) in the size of the input operands.

Notable exceptions to the above include multiplication, division, modulo, and
exponentiation.

### Memory

We would like to prevent clients from allocating more than the available memory
of a miner.  To achieve that, a miner needs to impose either a soft or a hard
limit.  The limit can be either a lump amount, or user specified:

1. The EVM way: each contract has a default amount of memory within which to
   execute.
1. Each contract must declare the amount of memory required for its execution.
The limits can be enforced in several ways:

1. Hard limit approach:  going over the limit triggers an exception
1. The EVM approach: memory over the limit incurs a quadratic/cubic/exponential
   allocation cost.

Charging for memory usage:

1. Require payment only at allocation time
   * There is a risk of having unprofitable long executions
1. Pay for the total time the memory is allocated
1. Memory costs are included in CPU cost through the gas model
   * works well for a model with a default memory limit
1. Free market approach: memory costs are included in CPU cost by the miner.
   * For a gas model with declared limits
   * no memory charges up to the limit
   * miners, especially those with low gas costs can reject contracts they deem
   unprofitable.

The current choices in IELE are similar to those taken in EVM:

* each contract has a default amount of memory within which to execute;
* memory over the limit incurs a quadratic allocation cost
* memory is charged only at allocation time

### Storage

For now, we assume similar costs for storage as EVM does.

## Differences from EVM

### Values are arbitrarily large

One change from EVM to IELE is that integers are no longer limited to 256 bits,
being allowed to grow arbitrarily large.
Therefore, the memory required for their storage might become non-negligible;
for example, numbers could effectively be used to encode sequential memory.

Another change brought upon by arbitrary length integers is that operations
manipulating these values need to take into account the size of the operands.

### Registers and memory/storage cells need to hold arbitrarily large values

Moreover, IELE allows registers and memory cells to refer to these arbitrarily
large numbers.  To address that, we will assume registers and memory cells
do not (usually) hold actual numbers, but metadata information such as sign,
length in *limbs*, zeroness, and a reference to the memory representation.
At the cost of one extra level of indirection, this would allow for better
memory representation (using allocation pools) and better computation and
resources accounting.
If another value needs to be stored into a register/memory cell, a
memory region large enough to hold the value can be reserved, the memory region
holding the current value can be marked as free, and the metadata structure
could be updated accordingly.
One could even conceive implementations where small enough numbers would be
directly stored in the register/memory cell with indirection being used only
for larger numbers.

To align with the above, the storage representation of a number will consist of
the metadata information followed by the number representation.

### Register and memory/storage cells must resize to fit data

Another difference from EVM is that the amount of memory/storage required for
representing the value of a register or memory/storage cell, instead of being
fixed at 256 bits, now varies during its usage.  This was previously only
considered for permanent storage (resetting a stored value to 0 would generate
a refund).

To address this variance, we track the current amount of allocated memory
throughout the execution of the contract.  Note that, unlike EVM, this includes
decreasing memory usage when memory cells are deallocated or resized.

### Registers vs Stack

IELE is register-based with an unbounded number of registers stored in memory
instead of stack-based with a bounded stack separated from memory.

Since registers are stored in memory, their allocation adds up to the memory
costs.  To address the fact that the usage of stack in EVM did not incur any
gas costs, a memory allowance is given to each contract call.

## High level view of the gas model

For each operation there are two costs (for computation and memory),
similarly to the EVM gas model.
* the computation cost --- abstracting the amount of hardware computation
  required to perform the given computation.
* the memory cost --- if the operation accesses/affects memory

Additionally, we also track the variation of the total amount of memory
required store the registers in use.
* the register stack variation --- if the operation saves results to registers,
  these might need to be reallocated, increasing or reducing the
  total amount of memory required for registers.

The memory variation introduced by updating the register *r* with value *v*
```
  registerDelta(r, v) = limbLength(v) - registerSize(r)
```

The current amount of memory is maintained by the semantics and updated using
functions like the *registerDelta* function above.

The peak memory level is also maintained and increased to match the
current memory level whenever needed.

If the peak level passes the memory allowance for the current contract call,
the difference between the two is considered as memory cost and gas is
computed for it, accordingly.

### Expressions

For an arithmetic operation we distinguish two variations:
* the gas cost reflecting the complexity of the computation; and
* the variation of memory due to updating the result register.

To make sure that the user has enough gas for storing the result of the
operation, we estimate the result size (*estimatedResultSize*) and, prior to
executing, we require that there are enough resources to contain that size.

#### Bitwise arithmetic
* `REG = not W`
  - Computation requires all words of `wREG` to be processed, so
    ```hs
    computationCost(NOT rREG wREG) =
      (constNot1) * registerSize(wREG) + constNot2
    ```
* `AND RREG wREG1 wREG2`
  - Computation requires pairwise AND of the registers' words so:
    ```hs
    computationCost(AND rREG wREG1 wREG2) =
      (constBit1) * m + constBit2
    ```
* `OR RREG wREG1 wREG2`
  - Computation requires pairwise OR of the registers' words so:
    ```hs
    computationCost(OR rREG wREG1 wREG2) =
      (constBit1) * m constBit2
    ```
* `XOR RREG wREG1 wREG2`
  - Computation requires pairwise XOR of the registers' words so:
    ```hs
    computationCost(XOR rREG wREG1 wREG2) =
      (constBit1) * m constBit2
    ```
#### Comparison operators
* `ISZERO rREG wREG`
  - Computation requires inspecting just one bit of `wREG`:
    ```hs
    computationCost(ISZERO rREG wREG) =
      constIsZero
    ````
* `CMP RREG wREG1 wREG2` where `CMP` in `[LT, GT, EQ]`
  - Computation requires pairwise comparison of the registers' words so:
    ```hs
    computationCost(CMP rREG wREG1 wREG2) =
      constCmp1 * m + constCmp2
      where m = min (registerSize wREG1) (registerSize wREG2)
    ```

#### Regular arithmetic
* `ADD RREG wREG1 wREG2`
  - Computation requires pairwise addition of the registers' words, so:
    ```hs
    computationCost(ADD rREG wREG1 wREG2) =
      addCost1 * m + addCost2

    ```
* `SUB rREG wREG1 wREG2`
  - Subtraction has the same complexity as addition
    ```hs
    computationCost(SUB rREG wREG1 wREG2) =
      computationCost(ADD rREG wREG1 wREG2)
    ```
* `MUL rREG wREG1 wREG2`
  -  Multiplication complexity depends on the algorithm used.
    ```hs
    computationCost(MUL rREG wREG1 wREG2)
      | isZero wREG1 || isZero wREG2    = 2 * limbTestCost + registerMaintenanceCost1
      | otherWise                       = 2 * limbTestCost + mulCost l1 l2
      where l1 = registerSize wREG1
            l2 = registerSize wREG2
    ```
* `DIV rREG wREG1 wREG2`
  - if the value of `wREG2` is 0, or the second is larger than the first,
    then result is 0; otherwise, we approximate the cost to that of the
    basecase division method.
    ```hs
    computationCost(DIV rREG wREG1 wREG2)
      | isZero wREG2 = limbTestCost + registerMaintenanceCost1 -- TODO: this might change
      | l2 > l1      = limbTestCost + limbComparisonTest + registerMaintenanceCost1
      | otherwise    = limbTestCost + limbComparisonTest + registerMaintenanceCost + divModCost l1 l2
      where l1 = registerSize wREG1
            l2 = registerSize wREG2
    ```
* `MOD rREG wREG1 wREG2`
  - The complexity of `MOD` is similar to that of `DIV`
    ```hs
    computationCost(MOD rREG wREG1 wREG2) =
      computationCost(DIV rREG wREG1 wREG2)
      where l1 = registerSize wREG1
            l2 = registerSize wREG2
    ```
* `EXP rREG wBASE wEXPONENT`
  - Exponentiation is done by repeatedly squaring `wBASE` and multiplying those
    intermediate results for the non-zero bits of `wEXPONENT`.
    This leads to a result of size `lb*e` where `lb` is the length of `wBASE`
    and `e` is the value of `wEXPONENT`.
    TODO:  redo
    ```hs
    computationCost(EXP rREG wBASE wEXPONENT)
      = constExp * wordCost * (0.5 * approxKara lb * (approxKara e - 1) + 2 * lb * (e - 1)))
      where lb = registerSize wBASE
            e = value wEXPONENT
    ```

#### Modular arithmetic

* `ADDMOD RREG wREG1 wREG2 wREG3`
  - Computation requires an addition possibly followed by a subtraction.
    ```hs
    computationCost(ADDMOD rREG wREG1 wREG2 wREG3) =
      registerMaintenanceCost +
      computationCost(ADD rREG wREG1 wREG2) + divModCost (m + 1) l3
    ```
* `MULMOD rREG wREG1 wREG2 wREG3`
  -  Multiplication can be done by first modulo-ing the arguments;
     then multiplying the results and taking modulo again.
    ```hs
    computationCost(MULMOD rREG wREG1 wREG2 wREG3)
      | isZero wREG1 || isZero wREG2 =
        2 * wordTestCost + registerMaintenanceCost1
      | l1 + l2 < 2*l3 = mulCost l1 l2 + dmCost l3 + mulModConst0
      | otherwise      =
        divModCost l1 l3 + divModCost l2 l3 +
        mulCost ml1 ml2 + dmCost l3 + mulModConst0
    ```
* `EXPMOD rREG wREG1 wREG2 wREG3`
  - Exponentiation is done by repeatedly squaring `WREG1` and multiplying those
    intermediate results for the non-zero bits of `WREG2`, all modulo `WREG3`.
    Modulo is taken by computing the `(2^limbSize)^(2*l3) / (value wREG3)` once,
    then performing division by multiplying with the inverse (see `mulModCost0`).
    ```hs
    computationCost(EXPMOD rREG wBASE wEXP wMOD)
      | isZero wREG2 = wordTestCost + registerMaintenanceCost1
      | otherwise    =
        divModCost lBASE lMOD + lMOD * wordCopyCost + dmCost lMOD +
        2 * blEXP * (mulModCost0 lMOD + constInnerLoop) + constExpMod
      where lBASE = registerSize wBASE
            blEXP = limbSize * registerSize wEXP
            lMOD = registerSize wMOD
            constExpMod = wordTestCost +
                          registerMaintenanceCost +  -- for the final result
                          registerMaintenanceCost +  -- for the first div
                          ...
            constInnerLoop =
              forIterationManagement + 2 * registerMaintenanceCost
    ```

#### SHA3
* `SHA3 rREG wMEMINDEX`
  - Computation cost is the similar as for EVM
    ```hs
    computationCost(SHA3 rREG wMEMINDEX) =
      constSHA3  + constSHA3Word * size(localMem[wMEMINDEX])
    ```
  - Result size is 256 bits
    ```hs
    estimatedResultSize(SHA3 rREG wMEMINDEX) = 256 `div` limbSize
    ```
  - Memory expansion is the same as for EVM

#### Byte access
* `BYTE rREG wINDEX w`
  - Getting a byte is done by a simple lookup and some word manipulation
    ```hs
    computationCost(BYTE rREG wINDEX w) = constByte
    ```
* `TWOS rREG wN wREG`
  - Both operation process a maximum of `2^wN` bits
    ```hs
    computationCost(TWOS rREG wN wREG) =
      constSign1 * l2N + constSign2
    ```
* `SEXT rREG wN wREG`
  - Both operation process a maximum of `2^wN` bits
    ```hs
    computationCost(SEXT rREG wN wREG) =
    computationCost(TWOS rREG wN wREG)
    ```

#### Local State
We assume that all operations interrogating the local state have complexity
*localStateCost* and their result fits a machine word.

* `LOCALOP rREG`, where `LOCALOP` in `[PC, GAS, GASPRICE, GASLIMIT, NUMBER, MSIZE, CODESIZE]`
    ```hs
    computationCost(LOCALOP rREG) = constWordRead
    ```
* `LOCALADDROP rREG`, where `LOCALOP` in `[COINBASE, ADDRESS, ORIGIN, CALLER]`
    ```hs
    computationCost(LOCALADDROP rREG) =
      constAddressRead
    ```
* `TIMESTAMP rREG`
    ```hs
    computationCost(TIMESTAMP rREG) =
      constQuadWordRead
    ```
* `DIFFICULTY rREG`
    ```hs
    computationCost(DIFFICULTY rREG) =
      constQuadWordRead
    ```
* `CALLVALUE rREG`
    ```hs
    computationCost(CALLVALUE rREG) =
      constQuadWordRead
    ```
* `BLOCKHASH rREG wN`
  - Computation cost is a constant; result size is *blockHashSize*
    ```hs
    computationCost(BLOCKHASH rREG) =
      constBlockhash
    ```

#### JUMPs

* `JUMPDEST`
    ```hs
    computationCost(JUMPDEST(_)) = 0
    ```
* `JUMP`
    ```hs
    computationCost(JUMP(_)) = jumpCost
    ```
* `JUMPI`
    ```hs
    computationCost(JUMPI(_) cREG) = jumpiCost
    ```
* `LOCALCALL`
  Save the local context (including the current register stack memory
  requirements), copy the arguments into the new context and jump to
  the call site.

  We're assuming that, in an efficient implementation, saving the caller's
  registers is a small constant time operation. One way or another, an
  efficient implementation will, in the general case, hold the actual register
  data in memory, while, maybe, using machine registers for the machine
  metadata. Regardless of how these optimizations are done, saving the caller
  context and creating the callee context takes
  constantTime + someConstant * registerCount, and a similar amount of memory.

  ```hs
  computationCost(LOCALCALL(_, nARGS, _) _ rARGS) =
    constLocalCall1 * REGISTERS +
    constCopyCost * sum [ registerSize(rARGS) ] + constLocalCall2
  memoryDelta(LOCALCALL(_, nARGS, _) _ rARGS) =
    constReg1 * REGISTERS + sum [ registerSize(rARGS) ] + constLocalCall3
  ```

  `REGISTERS` is the maximum number of registers as declared in the contract
  prefix. TODO: Use the caller's actual register count or callee's max register
  count instead.

* `RETURN`
  Copy values from return registers to caller locations restore local context,
  including (the current register stack memory requirements), mark registers'
  data for reclaiming, and jump back to call site. Note that, since the
  callee registers' data will be reclaimed, copying the return data in the
  callers' registers is not needed; just metadata needs to be copied.
  ```hs
  computationCost(RETURN(nRETURNS) rVALUES) =
    constReturn1 * nRETURNS + constReturn2
  memoryDelta(RETURN(nRETURNS) rVALUES) = - constReg1 * REGISTERS - constLocalCall3
    - sum [ registerSize(callee) ] + sum [ registerSize(rVALUES) ] - sum [ registerSize(getReturns()) ]
  ```
    where getReturns() = return registers of caller's call instruction

#### `RETURN` (account call version), `REVERT`, `INVALID` and exceptions

A `RETURN` is returning from an account call if the call stack is empty.

`INVALID` generates an exception in the callee, which consumes all
remaining gas passed by the caller.

For `RETURN` and `REVERT`, the costs of returning to the calling contract
have been prepaid by the caller.

* `INVALID` and exceptions in general
  ```hs
  computationCost(INVALID|exception) = 0
  ```
 * `REVERT`
  ```hs
  computationCost(REVERT rVALUE) = 0
  ```
* `RETURN`
  ```hs
  computationCost(RETURN(nRETURNS) rVALUES) = 0
  ```

#### `CALL` and `STATICCALL`
* `CALL` and `STATICCALL`
  A call is split in several parts. There are some checks which are done before
  everything else (account ammount and call depth), which may finish everything
  with an exception. These (including the exception) have an O(1) cost. Here the
  execution splits in three cases:
  * The called account does not exist -> we continue executing an empty code,
     which has only an empty "deposit" function, without any
     end/return/whatever. TODO: What happens when executing an empty function?
  * The account exists, but the code is not loaded. The code is assumed to be
     in a format suitable for execution. This has a cost in O(code size).
  * There are some special accounts with 'precompiled' code. Calls to these
     accounts are likely to resolve to native calls. These are not handled
     below because they are likely to have completely different cost structure.
     TODO: handle precompiled code.

  After loading the code there are more checks and setup work. The checks
  (the function exists and the argument count matches) can end with an
  exception. These checks are done at the end in the semantics, but I am
  assuming that they can be moved earlier.

  Here are the parameters relevant to `CALL` with a bit more detail than needed.
  * `REG` is the error code.
  * `REGS` are the return registers.
  * `ARGS` are the arguments.
  * `GCAP` is the gas limit.
  * `VALUE` is the amount to transfer.
  * `ACCTFROM` is the current account, by default making the call and making the
               payments.
  * `ACCTO` is explained below.

Here are the differences between the various calls.

* `CALL` loads the code from `ACCTO`, runs it as `ACCTO` and pays `ACCTO`.
* `STATICCALL` loads the code from `ACCTO`, runs it as `ACCTO` and pays `0` to
               `ACCTO`. `APPVALUE` is also `0`.

Below I'll assume that no payment actually happens for `STATICCALL`.
I'll also assume that calls to an inexistent
account (which will be created) are executed without an actual call, since
the only available function is an empty 'deposit'.

If the contract code contains a function index when stored, then one does not
need to load the entire code in order to fail with a function check. However,
we should not optimize for the error case, so the question becomes what is
more efficient for the non-error case. That is not trivial to answer, but for
now we can "hide" this cost in the codeLoadingCost/codeByteLoadingCost values,
and we'll make the error case less efficient.
TODO: Clarify codeLoadingCost/codeByteLoadingCost.

Although the caller pays for code loading one way or another, one may argue
that this should be paid from the `GCAP`. However, it seems conceptually easier
to consider that `GCAP` pays for the running cost of the contract, so it will
not include the code loading cost.

Also, it may seem counterintuitive to pay for the code loading cost, one may
expect to pay a flat fee as in the EVM model. A flat fee is usually less
efficient, so we're using a size-based fee. There is a similar memory
consumption associated with loading the code which, arguably, might be included
in a flat-fee cost.

For an external call there is no general way to estimate the size of the return
values, so memory costs are applied after the results are returned.

  ```hs
  -- CALLOP in [CALL, STATICCALL]

  computationCost(REG, REGS = CALL _ at ACCTTO (ARGS) send VALUE, gaslimit GCAP) =
     constCosts + costGas(gavail()-constCosts,GCAP) +
       constMove*length(REGS)
       constCopy*sum[registerSize(ARGS)]
    where
     constCosts = costCall + costTransfer if transferring + costNew if transferring to empty account
     costGas(remaining, limit)
      | remaining >= 0 = min(limit, remaining*63/64)
      | remaining < 0 = limit
  memoryDelta(REG, REGS = CALL _ at ACCTTO (ARGS) send VALUE, gaslimit GCAP) =
     sum [ registerSize(getReturnedValues()) ] - sum [ registerSize(REG:REGS) ]
  ```

  The callee starts with a memory usage of memorySizeCallee (absolute, not a
  delta). There is a free memory allowance for each new contract call, equal to
  the maximum EVM stack size, that will be taken into account separately.

  `constantMemorySize` is the size of whatever is part of the saved state
  except for the code and callData (calldepth, callValue, id, gas, caller,
  static)

TODO: I (virgil) think that these costs are more reasonable than some costs
      which follow the semantics in detail. However, we should be able to use
      them inside the semantics, so we should make sure that this is possible.

TODO: CALL loads some data in `<callData>`, but that's not used anywhere.
      Above I included a possible definition (`callDataSetupCost`), but we
      should find out what happens to that and include the right cost.

TODO: Is the callFeeCost fixed or based on the stack size?

TODO: Returning can be either implicit or explicit, should take that into
      account

#### Builtin calls costs

Certain operations are provided as functions on the contract at address 1.
These generally expect arguments of a fixed size.
The amount of gaslimit that must be provided to successfully call these
operations on well-formed inputs will be documented.
These values are from corresponding operations in EVM, in their gas units.

* `ECREC` - ECDSA public key recovery. http://www.secg.org/sec1-v2.pdf section
  4.1.6

  ```hs
  computationCost(ECREC) = costECREC -- 3000 for EVM
  ```
* `SHA256`
  ```hs
  -- 60 + 12 * upper(len(data)/32) for EVM
  computationCost(SHA256(LEN, DATA)) =
    sha256ConstantCost + sha256ChunkCost * upper(max(len, log256(data))/32)
  ```
  TODO: can `len` be less than `log256(data)`?
* `RIP160`
  ```hs
  -- 600 + 120 * upper(len(data)/32) for EVM
  computationCost(RIP160(LEN, DATA)) =
    rip160ConstantCost + rip160ChunkCost * upper(max(len, log256(data))/32)
  ```
* `ID`
  ```
  -- 15 + 3 * upper(len(data)/32) for EVM
  computationCost(ID(DATA)) = 0
  ```
* `ECADD`
  ```
  -- 500 in the Byzantium EVM semantics
  computationCost(ECADD(X,Y,Z)) =
    ecAddComputationCost
  ```
* `ECMUL`
  ```
  -- 40000 in the Byzantium EVM semantics
  computationCost(ECMUL(X,Y,Z)) =
    ecMulComputationCost
  ```
* `ECPAIRING`
  ```
  -- 100000 +Int (#sizeWordStack(DATA) /Int 192) *Int 80000  in the Byzantium EVM semantics
  computationCost(ECPAIRING(LEN,DATA)) =
    ecPairingConstantCost + upper(max(LEN,log256(DATA))/192) * ecPairingChunkCost
  ```

#### Logging
We use the same schema from the yellow paper, but taking into account the size
of the logged registers.

* `LOG`
  ```hs
  computationCost(LOG0 rMEMINDEX) =
    logCost + size(localMem[rMEMINDEX]) * logDataCost
  computationCost(LOG1 rMEMINDEX rW0) =
    logCost + size(localMem[rMEMINDEX]) * logDataCost + 1 * logTopicWordCost
  computationCost(LOG2 rMEMINDEX rw0 rW1) =
    logCost + size(localMem[rMEMINDEX]) * logDataCost + 2 * logTopicWordCost
  computationCost(LOG3 rMEMINDEX rw0 rW1 rW2) =
    logCost + size(localMem[rMEMINDEX]) * logDataCost + 3 * logTopicWordCost
  computationCost(LOG4 rMEMINDEX rw0 rW1 rW2 rW3) =
    logCost + size(localMem[rMEMINDEX]) * logDataCost + 4 * logTopicWordCost
  ```

#### Memory operations

* `MLOAD` In order to load the data from the memory, we first need to inspect
  the metadata to make sure we have enough gas to load it.  Hence, we will need
  to check the amount of gas in two steps, first doing work that can be paid for
  by mLoadCost to find the memory cell and access the metadata, before a second
  check that we have enough remaining gas after taking into account the memory cell size.
  ```hs
  computationCost(MLOAD rREG wINDEX) = mLoadCost + mloadWordCost * memoryCellSize(value wIndex)
  ```
* `MLOADN`
  This extends the size of the memory cell to include the entire segment read,
  which will be zero-filled if it was previously past the end of the cell.
  ```hs
  computationCost(MLOADN rREG, wINDEX1, wINDEX2, wWIDTH) =
    mLoadNCost + mLoadWordCost * wWIDTH
  ```
* `MSTORE` when we store a new value over an old one, we compute the difference
  in size between the two values.  Similar to changes to registers, this difference is used to update the
  current memory requirements, and, if it increases, it might update the top
  memory requirement and thus require extra gas
  charge for extra memory.
  ```hs
  computationCost(MSTORE wVALUE wINDEX) =
    mStoreCost + mStoreWordCost * registerSize wVALUE
  ```
* `MSTOREN`
  ```hs
  computationCost(MSTOREN wVALUE wINDEX1 wINDEX2 wWIDTH) =
    mStoreNCost +
    mStoreWordCost * wWIDTH
  ```

#### Register manipulations
* `MOVE` copies a value from one register to another
  ```hs
  computationcost(MOVE(destREG, sourceREG)) =
      wordCopyCost * registerSize(sourceREG)
  estimatedSize(MOVE(destREG, sourceREG)) =
      registerSize(sourceREG)
  ```
  (perhaps we should also have a SWAP whose memoryDelta would always be 0)
* `LOADPOS` loads an immediate (positive) value into a register
  ```hs
  computationcost(LOADPOS(destREG, SOURCE)) =
      wordCopyCost * registerSize(SOURCE)
  estimatedSize(LOADPOS(destREG, SOURCE)) =
      registerSize(SOURCE)
  ```
* `LOADNEG` loads an immediate (positive) value into a register, negating it
  first.

  This assumes either a sign + number representation or a two's complement
  with the source already in that form.

  ```hs
  computationcost(LOADPOS(destREG, SOURCE)) =
      wordCopyCost * registerSize(SOURCE) + wordCost
  estimatedSize(LOADPOS(destREG, SOURCE)) =
      registerSize(SOURCE)
  ```

#### Account operations

* `BALANCE`
  ```hs
  computationCost(BALANCE) = balanceCost
  estimatedResultSize(BALANCE) = balanceSize
  ```
* `EXTCODESIZE`
  ```hs
  computationCost(EXTCODESIZE) = extCodeSizeCost
  estimatedResultSize(EXTCODESIZE) = extCodeSizeSize
  ```
* `SLOAD` In order to load the data from the storage, we first need to inspect
  the metadata to make sure we have enough gas to load it.  As with loading
  from memory, the gas usage will have to be checked in two phases.
  ```hs
  computationCost(SLOAD rREG wINDEX) = sLoadCost
      + storageLookupCost * registerSize(wINDEX)
      + sloadWordCost * storeCellSize(value wIndex)
  estimatedResultSize(SLOAD rREG wINDEX) = storeCellSize(value wIndex)
  ```
* `SSTORE` when we store a new value over an old one, we compute the difference
  in size between the two values and based on it we decide whether to
  charge for extra storage (if it's positive) or to refund (if it's negative).
  ```hs
  computationCost(SSTORE wINDEX wVALUE) = sStoreCost
      + storageLookupCost * registerSize wINDEX
      + sStoreWordCost * registerSize wVALUE
      + storeCellKeyCost * registerSize wINDEX if storage cell was empty
      + max(0,refundableStoreCost * (registerSize wVALUE - storeCellSize(value wIndex)))
  refund(SSTORE wINDEX wVALUE) =
    max(0, -refundableStoreCost * (registerSize wVALUE - storeCellSize(value wIndex)))
  ```
  (should there be a refund of key storage costs?)

#### Account creation and destruction

* `CREATE`
  ```hs
  computationCost(STATUS,ADDR = CREATE contract (ARGS) send AMOUNT) =
    createCost + constCopy*sum[registerSize(ARGS)] + gavail()*63/64
  memoryDelta(STATUS,ADDR = CREATE contract (ARGS) send AMOUNT) =
    registerSize(returnedStatus()) - registerSize(STATUS)
    + addressSize - registerSize(ADDR)
  ```
* `COPYCREATE`
  TODO: There may be a difference in costs, but it's hard to check before
  Dwight finishes his fix for the case when there is no ACCTCODE.
  The only difference is that the map lookup for the code above is replaced by
  the ACCTCODE lookup, and the lookup failure case may be different.
  ```hs
  computationCost(STATUS,ADDR = COPYCREATE ADDR (ARGS) send AMOUNT) =
    costCopyCreate + constCopy*sum[registerSize(ARGS)] + gavail()*63/64
  memoryDelta(STATUS,ADDR = COPYCREATE contract (ARGS) send AMOUNT) =
    registerSize(returnedStatus()) - registerSize(STATUS)
    + addressSize - registerSize(ADDR)
  ```
* `SELFDESTRUCT`
  ```hs
  computationCost(SELFDESTRUCT) =
    costSelfDestruct + costNew if transferring to empty account and balance nonzero
  refund(SELFDESTRUCT) =
    refundSelfDestruct
  ```

## Definitions

* *limbSize* - size in bits of a machine word
  (e.g., 32 for 32-bit architectures, 64 for 64-bit architectures)

* *limbLength(v) = ceil(log(limbSize)(v+1))* - the minimum number
  of machine words required to represent value *v*

* *registerMetadataSize* - size in machine words required for the structure
  holding metadata information for registers
  (e.g., size, sign, pointer to location)

* *registerSize(r)* - machine words allocated for the value of register *r*
  If *r* was not previously used, *registerSize(r) = registerMetadataSize* to
  reflect that, upon allocation, that amount of memory would be additionally
  required.

* *blockHashSize* is the size in machine words of a block hash (256/limbSize)

* *callValueSize()* - the size in machine words of the call value

### Multiplication, division, exponentiation, modulo

#### Multiplication

The complexity for most multiplication operations is based on the
[Karatsuba method](http://mathworld.wolfram.com/KaratsubaMultiplication.html),
described below.

##### Base case: `x` and `y` of same size

Input: `x` and `y` of size `2*n`

* Split the numbers
  `x = b^n * x1 + x0,  y = b^n * y1 + y0`
* Then `x * y = (b^n * x1 + x0) * (b^n * y1 + y0)`, leading to
  `x * y  = b^2n * x1 * y1 + b^n * (x1 * y0 + x2 * y0) + x0 * y0`
* Note that `x1 * y0 + x0 * y1 = (x1 + x0) * (y1 + y0) - x1 * y1 - x0 * y0`
* Let `z0 = x0 * y0`, `z2 = x1 * y1`, `t = (x1 + x0) * (y1 + y0)`, and
  `z1 = t - z0 - z2`.
* Suppose `mul x` is the cost of computing the multiplication of two numbers
  of `x` limbs and `add x` is the cost of computing the addition of two
  numbers of size `x`. Then,
  * `time z0 = time z2 = mul n`, and `size z0 = size z2 = 2 * n`
  * `time (x1 + x0) = time (y1 + y0) = add n` and
    `size (x1 + x0) = size (y1 + y0) = n + 1`
  * `time t = 2 * add n + mul (n + 1)` and `size t = 2 * n + 2`
  * `time z1 = time t + 2 * add (2 * n + 2)` and `size z1 = 2 * n + 2`
  * Since the shifting is done by limbs, we can aggregate the cost for shifting
    into that for addition, and have:

    ```hs
    mul (2*n) = time (x * y) = time z0 + time z1 + time z2 + 2 * add (4 * n) + const0
               = 2 * mul n + mul (n + 1) + 2 * add n + 2 * add (2 * n + 2) + 2 * add (4 * n) + const0
    size x * y = 4 * n
    ```

  * Using that add is linear, we can assume constants `cAdd1` and `cAdd0` s.t.
    `add x = cAdd1 * x + cAdd0`, we can rewrite `mul (2*n)` to:

    `mul (2*n) = 2 * mul n + mul (n + 1) + 2 * (cAdd1 * n + cAdd0) + 2 * (cAdd1 * (2 * n + 2) + cAdd0) + 2 * (cAdd1 * 4 * n + cAdd0) + const0`, which simplifies to
    ```hs
    mul n = 2 * mul (nd2 1)  + mul (nd2 1 + 1) + n * cAdd1 * 7 + const1
       where nd2 k = ceiling (n / 2 ^ k)
             const1 = const0 +  cAdd0 * 6 + cAdd1 * 4
    ```

    Now, to simplify computation, we approximate `mul (nd2 1)` with `mul (nd2 1 + 1)`,
    and `ceiling ((nd2 1 + 1) / 2)` with `nd2 2`
    ```hs
    mul n = 3 * mul (nd2 1 + 1) + 7 * cAdd1 * n + const1
          = 3 * (3 * mul (nd2 2 + 1) + 7 * cAdd1 * (nd2 1 + 1) + const1) + 7 * cAdd1 * n + const1
    ```
    Let `const2 = 7 * cAdd1 + const1`. Then we can replace `const1` by `const2 - 7 * cAdd1`
    ```hs
    mul n = - 7 * cAdd1 + 7 * cAdd1 * n + const2
                       + (7 * cAdd1 * nd2 1 + const2) * 3 ^ 1
                       + (7 * cAdd1 * nd2 2 + const2) * 3 ^ 2 +
                       .................
                       + (7 * cAdd1 * nd2 k + const2) * 3 ^ k
      where k = log n / log 2
    ```
    By computing the sums, we obtain
    ```hs
    mul n = -7 * cAdd1 + 7 * cAdd1 * n * ((3/2)^(k+1) -1)(3/2 - 1) + const2*(3 ^ (k+1) -1) / 2
    ```
    Considering that `2^k = n` and `3 ^ k = n ^ constKara`, we reduce to
    ```hs
    mul n = 14 * cAdd1 * n * (3/2 * n ^ constKara / n - 1) + const2/2 * (3 * n^constKara - 1) - 7 * cAdd1
          = 21 * n ^ constKara + 3/2 * const2 * n^constKara - 14 * cAdd1 * n - 7 * cAdd1 - const2/2
          = mMul2 * n ^ constKara + mMul1 * n + mMul0
      where mMul2 = 21 + 3 * const2 / 2 = 21 + 3 / 2 * (11 * cAdd1 + 6 * cAdd0 + const0)
            mMul1 = -14 * cadd1
            mMul0 = -7*cAdd1 - const2 / 2 = -1/2 * (25 * cAdd1 + 6 * cAdd0 + const0)
            const2 = 11 * cAdd1 + 6 * cAdd0 + const0
    ```

##### `x` and `y` of different sizes

Suppose size of `x` is larger than that of `y`.  Then divide `x` in blocks of
the same size as `y`, multiply those blocks (using the algorithm above),
and add and shift the results.

1. initialize result `r` with `0`
1. for the index `i` of each block `bi` of size `|y|` of `|x|`,
   starting from the right (`i=0`):
  1. Invariant: `|r| <= i* |y| + |y| + 1`
  1. let `cd = r` such that `|d| = i * |y|`
    * Note: `|c| <= |y| + 1`
  1. compute `b * y = e` using the algorithm above
    * Note: `|e| <= 2*|y|`
  1. let `f = e + c`
    * Note: `|f| <= 2*|y| + 1`
  1. let `r = fd`
    * Invariant is preserved: `|r| = |f| + |d| <= (i + 1)*|y| + |y| + 1`

Complexity: `|x|/|y| * (mul (|y| / 2) + add(2 * |y|))`

##### Multiplication cost function *mulCost*.
  ```hs
  mulCost l1 l2 =
    constMul2 * max12 * min12^(constKara - 1) + constMul1 * max12 + constMul0
    where max12 = max l1 l2
          min12 = min l1 l2

  ```

#### Division and modulo

For division and modulo we will use as a base a divide and conquer method.
For further reading about the method, check [the relevant GMP webpage](https://gmplib.org/manual/Divide-and-Conquer-Division.html#Divide-and-Conquer-Division) and the references therein.

The base case for the divide and conquer method would be a standard long
division which is linear if the difference between the operands does not
depend on their size.

##### `x divmod y` when size of `x` is larger than the size of `y` by a constant

`divModStandard(x,y)` where `|x| = |y| + k`, `k` constant

1. if `x < y` return `(0,x)`
1. let `x = ab` such that `|a| = |y|`
1. if `a < y`:
   1. let `x = ab` such that `|a| = |y| + 1`
1. Binary search between `1` and `maxLimb` for maximal `c` such that
   `c * y <= a`
   * Note: this can be HEAVILY further optimized, (it is enough to consider
     only the first two limbs of `y` to obtain `c` approximated by `1`, but
     there are other large optimizations to be considered).
     but it won't affect the asymptotic complexity.
   * `d = a - c * y`
1. `(q,r) = divModStandard(db, y)`
1. return `(cq, r)`

###### Complexity analysis

```hs
divModStandardCost lx ly = limbSize * O(ly) * (lx - ly)
                         = O(ly * (lx - ly))
                         = dmStdConst1 * ly * (lx - ly) + dmStdConst0
```

##### `x divmod y` when size of `x` is (about) twice the size of `y`

Note: in the algorithm below, when writing a multidigit number,
we let `(0x)` denote as many digits of `0` as the size of number `x`.

`divmod0(abcd, ef)` where `|a|=|b|=|c|=|e|=|f|`, `|d| <= |a|`:

  1. `(p, q) = divmod0(ab, e)`
     * `ab = p*e + q`
     * `|q| <= |a|`
     * `|p| <= |a| + 1`
     * `ab(0c)(0d) = p * e (0c)(0d) + q(0c)(0d)`
  1. `t = qcd - p * f(0d)`
     * `t = abcd - p * ef(0d)`
         = `ab(0c)(0d) + cd - p * ef(0d)`
         = `p * e (0c)(0d) + q(0c)(0d) + cd - p * e(0c)(0d) - p * f(0d)`
         = `qcd - p * f(0d)`
     * `|t| <= max (|qcd|, |p*f(0d)|) <= 2 * |a| + |d| + 1 <= 3 * |a| + 1`
     * The maximum can be reached if `qcd` is `0`, so `t` would be negative.
  1. if `t < 0`:
     * assume `-t = ABCD` with `|A| = |B| = |C| = |e| = |f|`. Then `|D| <= 1`.
     * `abcd = p * ef(0d) - (-t)`
     1. `(P, Q) = divmod0 (AB, e)`
        * `AB = P * e + Q`
        * `|Q| <= |A|`
        * `|P| <= |A| + 1`
        * `AB(0C)(0D) = P * e (0C)(0D) + Q(0C)(0D)`
     1. `T = QCD - P * f(0D)`
        * As above, `T = ABCD - P * ef(0D) = QCD - P * f(0D)`
        * As above, `|T| <= 2*|A| + |D| + 1 <= 2*|a| + 2`
        * Maximum can be reached when `T` is negative
     1. if `T < 0`:
        1. `(r,s) = divmodStandard(-T, ef)`
           * complexity is about `O(2*|ef|) = O(4*|a|)`
           * `-T = r * ef + s`
           * `ABCD = P*ef(0D) - r*ef - s`
           * `-t = P*ef(0D) - r*ef - s`
           * `abcd = p * ef(0d) + r * ef + s - P * ef(0D)`
                  = `(p(0d) + r - P(0D)) * ef + s`
        1. `return (p(0d) + r - P(0D), s)`
     1. else: T is positive, but it's almost the same
  1. else: t is positive, but it’s almost the same

###### Complexity analysis

Let `dmCost n` denote the cost of dividing `x` of size `2*n` to `y` of size `n`.

```hs
dmCost n = dmCost (n/2) + mul (n/2) + add (3*n/2+1) +
           dmcost (n/2) + mul (n/2) + add(n+2) +
           4*add(n) + 2*add(n)
         = 2 * dmCost (n/2) + 2*mul (n/2) + 17 * add(n/2) + const
         // let const = 3 * addConst1 - 8 * addConst0 + divideConquerConst
         = 2*mul(n/2) + 17 * add(n/2) + const +
           4*mul(n/4) + 17 * 2 * add(n/4) + 2*const +
           ................ +
           2^k*mul(n/2^k) + 17 * 2^(k-1) * add(n/2^k) + 2^(k-1) * const
         = sum(k=1,log_2 n, 2^k*(mulConst2*n^constKara/(2^constKara)^k + mulConst1 * n / 2^k + mulConst0)) + 17/2*sum(k=1, log_2 n, 2^k*(posAddConst1 * n / 2^k + posAddConst0)) + const * (n - 1)
         = mulConst2 * n^constKara * sum(k=1,log_2 n, 2^k * /(2^constKara)^k) +
           mulConst1 * n * sum(k=1,log_2 n, 2^k / 2^k) +
           mulConst0 * sum(k=1,log_2 n, 2^k) +

           17/2 * posAddConst1 * n * sum(k=1, log_2 n, 2^k / 2^k) +
           17/2 * posAddConst0 * sum(k=1, log_2 n, 2^k)) +

           const * n - const
         // Now, sum(k=1,log_2 n, 2^(k * (1 - constKara)))
         // is 2^(1 - constKara) * (1-2^(1 - constKara)^log_2 n) / (1 - 2^(1 - constKara))
         // i.e. 2^(1 - constKara) * (1 - n^(1 - constkara)) / (1 - 2^(1 - constKara))
         = mulConst2 * n^constKara * 2^(1 - constKara) *
           (1 - n^(1 - constkara))  / (1 - 2^(1 - constKara)) +
           2 * mulConst1 * n * (log_2 n - 1) +
           mulConst0 * (2 * n - 2)

           17/2 * posAddConst1 * n * 2 * (log_2 n - 1)
           17/2 * posAddConst0 * 2 * (n - 1)

           const * n - const
         = mulConst2 * n^constKara * 2^(1 - constKara) / (1 - 2^(1 - constKara)) -
           mulConst2 * n * 2^(1 - constKara) / (1 - 2^(1 - constKara)) +
           2 * mulConst1 * n * log_2 n -
           2 * mulConst1 * n +
           2 * mulConst0 * n -
           2 * mulConst0 +
           17 * posAddConst1 * n * log_2 n -
           17 * posAddConst1 * n
           17 * posAddConst0 * n -
           17 * posAddConst0 +

           const * n - const
        // let dmConst3 = mulConst2 * 2^(1-constKara) / (1 - 2^(1-constKara))
        // let dmConst2 = 2*mulConst1  +  17 * posAddConst1
        // let dmConst1 = 17 * posAddConst0 + 2 * mulConst0 + const - dmConst2 - 2*mulConst1 - 17 * posAddConst1
        // let dmConst0 = - 2 * mulCost0 - posAddConst0 - const
        // Of course, let us notice that 2^(1-constKara) =
        //      1 / (2^(constKara - 1)) =
        //      1 / 2 ^ (log2 3 - 1) =
        //      2 / 2 ^ log2 3 = 2/3
        // so dmConst3 = mulConst2 * 2/3 / (1/3) = 2 * mulConst2
         = dmConst3 * n^constKara + dmConst2 * n * log n + dmConst1 * n + dmConst0
```

Therefore:
```
dmCost n = dmConst3 * n ^ constKara + dmConst2 * n * log n + dmConst1 * n + dmConst0
  where
    dmConst3 = mulConst2 * 2^(1-constKara) / (1 - 2^(1-constKara))
    dmConst2 = 2*mulConst1  +  17 * posAddConst1
    dmConst1 = 17 * posAddConst0 + mulConst0 + const - dmConst2 - 2*mulConst1 - 17 * posAddConst1
    dmConst0 = - mulCost0 - posAddConst0 - const
    const = 3 * addConst1 - 8 * addConst0 + divideConquerConst
```

##### `x divmod y` when size of `x` is larger than twice the size of `y`

Suppose size of `x` is larger than twice the size of `y`.
Then divide `x` in blocks of the same size as `y`,
apply the algorithm above on those blocks,
and add and shift the results, with minor adjustments.

1. Suppose `x` is splitted in blocks of size `|y|`, starting from the right
   * leftmost block may have a smaller size
1. initialize empty stack `stack`
1. Let `q` be the leftmost block
1. for each block `b` of `x'`, starting from the left, skipping the first:
   1. `(p,q) = divmod0(qb, y)`
      * Note: `|p| <= |qb| - |y| + 1 = |q| + 1 <= |y| + 1`
   1. push `p` into `stack`
1. pop `p` from `stack`
1. let `i = 1`
1. while `stack` not empty:
   1. let `rs = p` such that `|s| = i * |y|`
      * Note: `|r| <= 2`
   1. pop `t` from `stack`
   1. `t += r`
   1. `p = ts`
   1. `i += 1`
1. return `(p,q)`

###### Complexity analysis

Both loops have maximum `|x| / |y|` iterations.

```hs
divModCost lx ly
  | max12 - min12 < tresh = divModStandardCost max12 min12
  | otherwise
  = max12 / min12 (dmCost min12 + addCost min12 + ct1) + divModConst0
                 = dmConst3 * max12 * min12^(constKara-1) +
                   dmConst2 * max12 * log min12 +
                   divModConst2 * max12 +
                   divModConst1 * max12 / min12 +
                   divModConst0
  where
    max12 = max lx ly
    min12 = min lx ly
    divModConst2 = dmConst1 + addConst1
    divModConst1 = dmConst0 + addConst0 + ct
```



* Multiplication modulo cost.
  When doing multiple multiplications modulo `m` of size `n` for really large `n`,
  one can compute only once the "inverse" `base^(2*n) / m`, with a cost of `divModCost (2*n) n` as above, followed by
  repeated operations of cost `mulModCost0 n`
  (Barrett reduction [https://en.wikipedia.org/wiki/Barrett_reduction]), where:
  ```hs
  mulModCost0 n = mul n + mul (n + 1) + 4 * add n
  ```


* *constKara = log 3 / log 2* - the exponent of the complexity for the Karatsuba
  algorithm

* `x ^ constKara` can be approximated by quadratic polynomials, successively.
  That is, we want a polynomial a * x ^ 2 + b * x + c
  To choose the approximation points we use the fact that
  `(2^k)^(log 3 / log 2) = 3^k`, so we choose them as successive powers of 2.

* Say we want to approximate `x^log_2 3` with a family of quadratic functions, say of the form `a2*x^2+a1*x+a0`,
* then, for `x = 2^k`, it means we want to approximate `3^k` with `a2*4^k(+...)`, whence `a2 ~= 1/(4/3)^k`.
* looking for powers of 2 (to make `a2*x^2` a shift) which are smaller, but close to `(4/3)^k`, we see that `(4/3)^5 ~= 4.21` and` (4/3)^10 ~=17.75`
* we then can take candidates `x^2 for x <=32`; `x^2/4 + a1* x + a0 for 32 <= x <=1024`, and  `x^2/16 + b1 * x + b0 for x >= 1024 `
* now, if we want the approximation to be differentiable, its derivative, `2* x for x <=32; x/2 + a1 for 32 <= x <=1024, x/8 + b1 for x >= 1024`,  must be continuous, so
* `a1 = 2 * 32 - 32/2 = 48`, and `b1 = 1024/2 + a1 - 1024 / 8 = 432`
* next, the approximation must also be continuous, so
* `a0 = 32^2 - 32^2/4 - 48*32 = -768`, and `b0 = 1024^2/4+ 48*1024 -768 - 1024^2/16 - 432*1024 = - 197376`


* Division / modulo cost function *divCost*
  ```hs
  divCost l1 l2 = constDiv * wordCost * (l1 - l2) * l2
  ```

### TODOS

* Check that GMP can check for 0 in constant time or update costs accordingly
* Check that GMP can give number of limbs in constant time or update costs accordingly
* Check that all background costs are accounted for (e.g. updating a register's)
  metadata after an assignment.
* Check that memory deltas are used properly everywhere (e.g. MLOAD).
* Bill each use of #newAccount as using account storage space.
* Account for #finalizeTx costs somehow.

Comments on ADGdiv < SCHED > +Int DMOD/MULMOD/EXPMOD
--------------------------------
It seems like addmod and mulmod exist mostly to avoid taking up extra space for an intermediate result, and shouldn't be expected to reduce computation costs by much. mulmod of numbers around the size of the modulus should have about the same asymptotic cost (as a function of size of the modulus) and a mul and a mod, just with independent constants so it can be a bit cheaper if appropriate (maybe better memory locality than a plain mul, or some other constant factor savings).

Modular exponentiation has a pretty simple form with a bit of setup costs and then doing mostly a bunch of squaring and multiplication modulo, with the number of those operations just linear in the length of the exponent

exponentiation requires enough work for nontrivial exponents that it's worth precalculating constants to make the mulmods cost about as little as a plain multiplication

Most applications in cryptography don't actually need mulmod, addmod, or expmod to operate on numbers larger than the modulus (rather than assuming inputs are pre-reduced), so we probably don't need to come up with expecially clever asymptotic costs for when the inputs are much larger than the modulus, just asymptotically charge as much as one or two separate mod operations preparing the inputs
But, we can capture the cost of reducing inputs with a formula that goes continuously to zero when the inputs are not larger than the modulus without losing safety, because the mulmod itself has a constant component to the cost.


### TODOS: Instructions to consider if they should be added

* REGISTERS
* FUNCTION

### TODOS: Make sure we don't need these

* CALLDATALOAD
* CALLDATASIZE
* CALLDATACOPY
* LOCALRETURN
* LOCALCALLI
* CALLDEST
* EXTCALLDEST
* RETURNDATASIZE
* RETURNDATACOPY
* CODECOPY
* EXTCODECOPY


#  Appendix:  Cost details

forIterationManagement = wordIncrementCost + limbComparisonCost

approxKara -- why both this and mulCost?
-- bitCost - time for a read-test-write thing on a limb, e.g.
  * x = 1 if y = 0, x = 0 otherwise.
-- copyWordCost - time to set a word?? (iszero)
-- lenCost - time to compute the length of a register??
registerMaintenanceCost
  * allocating a new buffer for the register +
  * updating the length +
  * setting/copying the sign
  * dellocating the buffer (this cost is paid at allocation time)
registerMaintenanceCost1
  * The 1-limb case of registerMaintenanceCost. Contains the value setting cost
    in case the value is 0 since length = 0. TODO: Does it contain all consts?
setWordCost - time for a read-test-write thing on a limb
mulCost - cost of doing multiplication that writes the result in a given place
divModCost - cost of doing division or modulo that writes the result in a given place

wordAddCost - add or sub two limbs
wordAddSetCost - wordAddCost + setWordCost
limbComparisonCost - compare two limbs and branch
limbComparisonCost0 - compare limb with 0 and branch
wordCopyCost - cost to copy a limb
wordIncrementCost - increment a limb
wordTestCost - time for a read-test-branch thing on a limb
wordTestSetCost - time for a read-test-write thing on a limb, replaces bitCost

wordCost - time for a read-op-write thing on a limb, e.g.
  * x = not y
  * Should rename

constBaseBoolBinOp
constExp
constSHA3, constSHA3Word
constSignOp
localStateCost - local state interrrogation complexity


------------------
min
registerSize(wREG) - the size of a register in limbs. Always returns at least 1!
