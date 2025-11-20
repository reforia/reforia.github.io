---
layout: post
title: "BPVM Snack Pack #18 - Why Blueprint is Slower: The Performance Truth"
description: "Blueprint is slower than C++, but not for the reasons you might think. It's not the VM - it's the copying! Here's the real performance story."
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

## The Performance Question

"Why is Blueprint slower than C++?"

Most answers you'll hear are **wrong**. Let's bust some myths!

## Myth #1: "Interpreted Code is Slow"

**Wrong!** Blueprint isn't interpreted - it's **compiled to bytecode**.

The VM executes this bytecode very efficiently. A simple loop in Blueprint is nearly as fast as C++!

## Myth #2: "Visual Scripting Has Overhead"

**Wrong!** The visual nodes disappear at compile time.

Running compiled Blueprint has **zero visual overhead**. Those nodes are just an editor representation!

## The Real Culprit: Copying

Here's the actual performance killer:

```cpp
// C++ (FAST)
void MyFunction(const FVector& Location) {
    // Direct memory access, no copying
    UseLocation(Location);
}

// Blueprint (SLOWER)
void MyFunction(FVector Location) {
    // Step 1: Copy FVector to parameter stack (12 bytes)
    memcpy(ParamBuffer, &Location, sizeof(FVector));

    // Step 2: Execute function

    // Step 3: Clean up stack
    // Total: ~100 nanoseconds of copying overhead!
}
```

Every function call **copies data**!

## The Copying Overhead

Let's measure it:

```cpp
// C++ function call
MyFunc(Vector, Actor, String);
// Time: ~10 nanoseconds

// Blueprint function call
MyFunc(Vector, Actor, String);
// Time: ~50-100 nanoseconds
// Extra time = copying parameters!
```

Blueprint is **5-10x slower** just from copying!

## Stack Management Cost

The VM maintains a runtime stack:

```cpp
// C++ (compiled stack management)
void Call() {
    int Local = 5;  // Stack pointer adjusted at compile time
}

// Blueprint (runtime stack management)
void Call() {
    // VM allocates stack space at runtime
    uint8* Stack = AllocateStack(FunctionStackSize);

    // VM manages locals
    int* Local = (int*)(Stack + LocalOffset);

    // VM cleans up
    FreeStack(Stack);
}
```

Runtime stack management adds **microseconds per call**!

## Type Checking Overhead

The VM does **runtime type checking**:

```cpp
// C++ (compile-time, zero cost)
AActor* MyActor = GetActor();  // Compiler validates type

// Blueprint (runtime cost)
AActor* MyActor = GetActor();
// VM checks: "Is this really an AActor*?"
if (!MyActor->IsA(AActor::StaticClass())) {
    Error();
}
```

Safety has a **small cost**!

## Reflection System Usage

Blueprint uses reflection for **everything**:

```cpp
// C++ (direct access)
float Health = Actor->Health;  // Direct memory read
// Time: 1 nanosecond

// Blueprint (reflection)
FProperty* Prop = FindProperty("Health");  // Lookup!
float Health = Prop->GetFloatValue(Actor);  // Indirect read!
// Time: 10-50 nanoseconds
```

Reflection is flexible but **slower**!

## The Real Performance Numbers

Let's benchmark common operations:

**Variable Access:**
- C++: 1-2 ns
- Blueprint: 5-10 ns
- **Overhead: 5-10x**

**Function Call:**
- C++: 5-10 ns
- Blueprint: 50-100 ns
- **Overhead: 10x**

**Math Operations:**
- C++: 1 ns
- Blueprint: 2-5 ns
- **Overhead: 2-5x**

## When Blueprint is Fast Enough

The overhead is **absolute time**, not percentage:

```cpp
// Expensive operation (1 millisecond)
RenderComplexMesh();

// Adding Blueprint overhead (100 nanoseconds)
// Total: 1.0001 milliseconds
// Difference: 0.01% (unnoticeable!)
```

If your function does **actual work**, Blueprint overhead disappears!

## When Blueprint Hurts

**Tight loops are painful:**

```cpp
// Blueprint (BAD!)
For i = 0 to 10000:
    Result = Result + Array[i]
// 10,000 function calls × 100ns = 1 millisecond lost!

// C++ (GOOD)
for (int i = 0; i < 10000; i++) {
    Result += Array[i];
}
// Direct memory access = microseconds, and modern compiler will optimize it directly to O(1) because we have a formula for the sum of an arithmetic series!
```

**Hot paths matter:** Functions called every frame "should" be C++! But it really depends on what's actually been done in those functions.

## The Optimization Strategy

**Keep in Blueprint:**
- High-level game logic
- Event handlers
- UI updates
- Infrequent operations

**Move to C++:**
- Tight loops
- Math-heavy algorithms
- Per-frame calculations
- Performance-critical paths

## Nativization (RIP)

Unreal had **Blueprint Nativization**:
- Converted Blueprint to C++
- Compiled as native code
- Removed all overhead!

It was **removed** because:
- Hard to maintain
- Binary bloat
- Debugging difficulties

Hot reload was more valuable than nativization!

## The Future: Verse

Epic's new language **Verse** aims to solve this:
- Compile-time optimizations
- Zero-copy function calls
- Native performance
- Visual scripting benefits

Blueprint won't go away, but Verse will handle performance-critical code!

## Quick Takeaway

- Blueprint slowness comes from **copying**, not interpretation
- Every function call copies **all parameters**
- Runtime **stack management** adds overhead
- **Reflection** is flexible but slower than direct access
- Typical overhead: **5-10x for simple operations**
- Overhead **doesn't matter** for expensive operations
- **Tight loops** and **hot paths** should be C++
- Keep Blueprint for **high-level logic**

## The Performance Trade-Off

Blueprint trades **raw speed** for:
- Visual editing
- Fast iteration
- Hot reload
- Designer-friendly
- Reflection capabilities

For most game logic, this trade-off is **absolutely worth it**. Only optimize to C++ when profiling shows it matters!

## Want More Details?

For complete performance analysis:
- [From Blueprint to Bytecode V - Performance Discussion](/posts/bpvm-bytecode-V/)

Next: Creating your own custom Blueprint nodes!

---

**🍿 BPVM Snack Pack Series**
- [← #17: Function Calls in Bytecode](/posts/bpvm-snack-17-function-calls/)
- **#18: Why Blueprint is Slower** ← You are here
- [#19: Custom Blueprints](/posts/bpvm-snack-19-custom-blueprints/) →