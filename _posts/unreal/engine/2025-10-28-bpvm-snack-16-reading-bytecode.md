---
layout: post
title: "BPVM Snack Pack #16 - Reading Bytecode: The Matrix Revealed"
description: "Ever wondered what your compiled Blueprint actually looks like? Here's how to read the bytecode output and understand what your nodes became."
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: en
---

{% include ue_version_disclaimer.html version="5.6.0" %}

> **BPVM Snack Pack** - Quick Blueprint knowledge drops! Part of the [Blueprint to Bytecode series](/posts/bpvm-bytecode-I/).
{: .prompt-tip }

## Enable Bytecode Output

First, you need to see the bytecode! Add this to your config:

```ini
[Kismet]
CompileDisplaysBinaryBackend=True
```

Now when you compile, the output log shows **the actual bytecode**!

## The Bytecode Format

Your Blueprint becomes text like this:

```
LogK2Compiler: [function ExecuteUbergraph_BPA_MyActor]:
Label_0x0:
    $4E: Computed Jump, offset specified by expression:
        $0: Local variable of type int32 named EntryPoint
Label_0x10:
    $44: EX_CallFunction (FFrame::Step)
        $8: Function PrintString
        $B: EX_Nothing
    $4: Return expression
        $B: EX_Nothing
Label_0x20:
    $53: EX_EndOfScript
```

It looks like **Assembly language** for Blueprint!

## Understanding the Symbols

**$XX:** EExprToken (instruction or data)
```cpp
$44 = EX_CallFunction  // Call a function
$0  = EX_LocalVariable // Local variable
$4  = EX_Return        // Return from function
$53 = EX_EndOfScript   // End of bytecode
```

These are the **VM opcodes**!

## Labels Are Jump Targets

```
Label_0x0:   // Offset 0 bytes
Label_0x10:  // Offset 16 bytes
Label_0x20:  // Offset 32 bytes
```

Labels mark **where jumps go**. The number is the byte offset from function start!

## Reading a Function Call

```
$44: EX_CallFunction (FFrame::Step)
    $8: Function PrintString
    "Hello World"
    $B: EX_Nothing
```

Translation:
1. **$44** = "I'm calling a function"
2. **$8** = "Here's the function pointer"
3. **"Hello World"** = "Here's the parameter"
4. **$B** = "End of parameters"

## The Ubergraph Mystery

```
[function ExecuteUbergraph_BPA_MyActor]:
Label_0x0:
    $4E: Computed Jump, offset specified by expression:
        $0: Local variable of type int32 named EntryPoint
```

Remember the Ubergraph? It starts with a **jump table**:
- EntryPoint 0 = BeginPlay
- EntryPoint 1 = Tick
- EntryPoint 2 = Your custom event

The VM **jumps to the right entry** based on which event fired!

## Reading Variables

```
$0: Local variable of type float named Health
$1A: Self
$11: Object variable Property /Script/Engine.Actor:RootComponent
```

Variables show:
- **Type** (float, int, object)
- **Name** (Health, RootComponent)
- **Scope** (Local, Self, Property)

## Common EExprToken Values

Here's a cheat sheet ($ prefix indicates hex values as shown in disassembly):

```cpp
$00 = EX_LocalVariable       // Local var (hex: 0x00)
$0B = EX_Nothing             // Null/empty (hex: 0x0B)
$04 = EX_Return              // Return (hex: 0x04)
$06 = EX_Jump                // Unconditional jump (hex: 0x06)
$07 = EX_JumpIfNot           // Conditional jump (hex: 0x07)
$1A = EX_Self                // The 'this' pointer (hex: 0x1A)
$1C = EX_IntConst            // Integer literal (hex: 0x1C)
$1F = EX_StringConst         // String literal (hex: 0x1F)
$27 = EX_ObjectConst         // Object reference (hex: 0x27)
$44 = EX_CallFunction        // Function call (hex: 0x44)
$4E = EX_ComputedJump        // Jump table (hex: 0x4E)
$53 = EX_EndOfScript         // End marker (hex: 0x53)
```

## A Complete Example

**Your Blueprint:**
```
BeginPlay → Print("Hello")
```

**The Bytecode:**
```
[function ExecuteUbergraph_BP_MyActor]:
Label_0x0:
    $4E: Computed Jump            // Entry jump table
        $0: EntryPoint

Label_0x10:                       // BeginPlay entry
    $44: EX_CallFunction          // Call function
        $8: PrintString           // Function to call
        $1F: String "Hello"       // Parameter
        $B: EX_Nothing            // End params
    $4: Return                    // Return
        $B: EX_Nothing

Label_0x30:
    $53: EX_EndOfScript           // All done
```

## The Stack Machine

The VM is a **stack machine**:

```cpp
// Your code: A = B + 5

// Bytecode:
Push B        // Put B on stack
Push 5        // Put 5 on stack
Add           // Pop two, add, push result
Pop A         // Pop result into A
```

Most operations work on a **virtual stack**!

## Why Offsets Matter

```
Label_0x10: CallFunction
Label_0x20: Return
Label_0x22: EX_EndOfScript
```

The VM uses **byte offsets** for jumps:
```cpp
// Jump 16 bytes forward
JumpIfFalse 0x10  // Goes to Label_0x10
```

It's all **pointer arithmetic** under the hood!

## Reading Complex Logic

**Branch node:**
```
$7: EX_JumpIfNot              // If condition is false
    $0: Local bool Condition   // Check this variable
    Label_0x30                 // Jump here

// True path
CallFunction(DoSomething)

Label_0x30:                    // False path
CallFunction(DoSomethingElse)
```

Branches become **conditional jumps**!

## Quick Takeaway

- Enable bytecode output in **DefaultEngine.ini**
- **$XX** = EExprToken (instruction/data)
- **Label_0xXX** = Jump target at byte offset XX
- **Ubergraph** starts with a computed jump table
- VM is a **stack machine** (push/pop operations)
- Function calls show **function + parameters + end marker**
- Branches become **conditional jumps**

## Seeing The Matrix

Once you enable bytecode output, you can see exactly what your Blueprint becomes. It's like seeing The Matrix - those pretty nodes are just a facade for the raw bytecode underneath!

## Want More Details?

For complete bytecode deep-dive with real examples:
- [From Blueprint to Bytecode V - Bytecode Analysis](/posts/bpvm-bytecode-V/)

Next: How function calls work in bytecode!

---

**🍿 BPVM Snack Pack Series**
- [← #15: Optimizations Explained](/posts/bpvm-snack-15-optimizations/)
- **#16: Reading Bytecode** ← You are here
- [#17: Function Calls in Bytecode](/posts/bpvm-snack-17-function-calls/) →