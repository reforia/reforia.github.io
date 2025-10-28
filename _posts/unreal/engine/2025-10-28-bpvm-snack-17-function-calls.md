---
layout: post
title: "BPVM Snack Pack #17 - Function Calls in Bytecode: The Calling Convention"
description: "Function calls in Blueprint bytecode are complex! Parameters need copying, return values need handling, and the stack needs managing. Here's how it all works."
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

## The Function Call Problem

You call `PrintString("Hello")`. Simple, right?

Under the hood, the VM needs to:
1. **Find** the function
2. **Copy** parameters to function's stack
3. **Call** the function
4. **Copy** return value back
5. **Clean up** the stack

It's way more complex than it looks!

## The Bytecode Anatomy

Here's what a function call becomes:

```
$44: EX_CallFunction (FFrame::Step)
    $8: Function pointer → PrintString
    // Parameters start
    $1F: String "Hello"              // Parameter 1
    $B: EX_Nothing                   // End of params
    // Now execute function
```

Let's break it down!

## Step 1: Function Identification

```cpp
$44: EX_CallFunction
    $8: Function PrintString
```

The VM needs to:
```cpp
UFunction* Function = ReadPointerFromScript();
// Now we know WHAT to call
```

## Step 2: Parameter Space Allocation

```cpp
// Allocate temporary parameter buffer
uint8* ParamBuffer = (uint8*)FMemory_Alloca(Function->ParmsSize);

// Initialize to zero
FMemory::Memzero(ParamBuffer, Function->ParmsSize);
```

The VM creates a **temporary stack frame** for parameters!

## Step 3: Parameter Copying

For each parameter:

```cpp
// Blueprint
PrintString("Hello", true, FLinearColor::Red)

// Bytecode
$44: EX_CallFunction
    $8: PrintString
    $1F: String "Hello"          // Copy string
    $27: Bool true               // Copy bool
    $3A: Struct FLinearColor     // Copy struct
    $B: EX_Nothing
```

Each parameter is **copied** into the parameter buffer!

## Step 4: The Actual Call

```cpp
// ProcessInternal is the VM's function executor
Function->ProcessInternal(Stack, ParamBuffer);

// Inside ProcessInternal:
if (Function->IsNative()) {
    // Call C++ function
    Function->Invoke(Context, ParamBuffer);
} else {
    // Execute Blueprint bytecode
    ProcessScriptFunction(Context, Function);
}
```

Native functions jump to C++, Blueprint functions execute more bytecode!

## Step 5: Return Value Handling

```cpp
// Blueprint
Result = Add(5, 10)

// Bytecode
$44: EX_CallFunction
    $8: Add
    $1C: Int 5           // Param 1
    $1C: Int 10          // Param 2
    $B: EX_Nothing
// Return value copied to Result variable
$F: Let                  // Assignment
    $0: Local Result     // Target
```

Return values are **copied back** to your variable!

## The Hidden Cost: Copying

Every parameter and return value is **copied**:

```cpp
// C++ (fast - no copy)
PrintString(MyString);  // Pass by const reference

// Blueprint (slower - must copy)
ParamBuffer.MyString = CopyString(MyString);
PrintString(ParamBuffer.MyString);
Result = CopyString(ParamBuffer.ReturnValue);
```

This is why Blueprint is slower than C++!

## Struct Parameters Are Expensive

```cpp
// Passing a large struct
CallFunction(FHitResult)

// VM must:
CopyStruct(FHitResult, 200+ bytes)  // Expensive!
CallFunction()
CopyStruct(ReturnValue, 200+ bytes) // Expensive!
```

Large structs = lots of copying!

## Reference Parameters

Some functions use references to avoid copying:

```cpp
// C++ signature
void ModifyActor(AActor*& OutActor);

// Bytecode
$44: EX_CallFunction
    $8: ModifyActor
    $0: Reference to Local OutActor  // No copy! Just pointer!
    $B: EX_Nothing
```

References are **pointers**, not copies (much faster)!

## The Parameter Stack

The VM maintains a **parameter stack**:

```cpp
// Nested calls
A( B( C(5) ) )

// Stack grows:
Push 5         // For C
Call C()
Push result    // For B
Call B()
Push result    // For A
Call A()
Pop result     // Final result
```

Deep call chains = deeper stack!

## Out Parameters

Functions with multiple outputs:

```cpp
// Blueprint
GetPlayerController() → Controller, Index

// Bytecode
$44: EX_CallFunction
    $8: GetPlayerController
    // Out parameters are addresses!
    $0: Address of Controller    // Where to write result 1
    $1: Address of Index          // Where to write result 2
    $B: EX_Nothing
```

Out parameters receive **addresses**, not values!

## Delegate Calls Are Special

```cpp
// Delegate call
MyDelegate.Broadcast(Param)

// Bytecode
$46: EX_CallMulticastDelegate  // Different opcode!
    $0: Delegate MyDelegate
    $1F: Param value
    $B: EX_Nothing
```

Delegates use **special opcodes** because they call multiple functions!

## Quick Takeaway

- Function calls become **EX_CallFunction** bytecode
- **All parameters are copied** to temporary buffer
- **Return values are copied** back
- Large structs are **expensive** (lots of copying!)
- References avoid copying (use pointers instead)
- Out parameters receive **addresses**
- Native functions jump to C++, Blueprint functions execute more bytecode
- Deep call chains create **deep stacks**

## The Hidden Overhead

Every time you call a Blueprint function, the VM:
1. Allocates parameter space
2. Copies all inputs
3. Executes function
4. Copies return value
5. Cleans up stack

This overhead is why Blueprint is slower than C++ - not because the logic is slow, but because **parameter passing** has overhead!

## Want More Details?

For complete function call breakdown with examples:
- [From Blueprint to Bytecode V - Function Call Analysis](/posts/bpvm-bytecode-V/)

Next: Why Blueprint is inherently slower than C++!

---

**🍿 BPVM Snack Pack Series**
- [← #16: Reading Bytecode](/posts/bpvm-snack-16-reading-bytecode/)
- **#17: Function Calls in Bytecode** ← You are here
- [#18: Why Blueprint is Slower](/posts/bpvm-snack-18-blueprint-slower/) →