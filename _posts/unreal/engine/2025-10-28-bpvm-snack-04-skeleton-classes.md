---
layout: post
title: "BPVM Snack Pack #4 - Skeleton Classes: The Hidden Hero"
description: "How does Blueprint A reference Blueprint B when B isn't compiled yet? The skeleton class - Blueprint's version of forward declarations."
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: en
---

{% include ue_version_disclaimer.html version="5.4.0" %}

> **BPVM Snack Pack** - Bite-sized Blueprint knowledge! Part of the [Blueprint to Bytecode series](/posts/bpvm-bytecode-I/).
{: .prompt-tip }

## The Circular Dependency Problem

Here's a common scenario in multiplayer games:

```
Blueprint_PlayerController references Blueprint_GameMode
Blueprint_GameMode references Blueprint_PlayerState
Blueprint_PlayerState references Blueprint_PlayerController
```

Classic circular dependency. How do you compile these without deadlock?

## The C++ Way (Doesn't Work Here)

In C++, you'd use forward declarations:

```cpp
class AMyGameMode;  // Forward declaration

class AMyPlayerController : public APlayerController
{
    AMyGameMode* GameMode;  // Use the forward declaration
};
```

But Blueprints compile at runtime (or on-demand in editor). You can't just "forward declare" a Blueprint!

## The Solution: Skeleton Classes

Unreal solves this with a two-pass approach. During **Stage VIII (Recompile Skeleton)**, it creates a "skeleton" version of each Blueprint class:

```cpp
// Skeleton class: Just the structure, no implementation
class BP_PlayerController_SKEL : public APlayerController
{
    // Has all the properties
    UPROPERTY()
    ABP_GameMode* GameMode;

    // Has all the function signatures
    void DoSomething();

    // But NO bytecode yet!
};
```

Think of it like a **header file** (`.h`) in C++, but generated at compile-time for Blueprints.

## How It Solves Circular Dependencies

**Phase 1 - Create Skeletons:**
```cpp
// For each Blueprint, create skeleton FIRST
BP_PlayerController_SKEL  // Just the shape
BP_GameMode_SKEL          // Just the shape
BP_PlayerState_SKEL       // Just the shape
```

**Phase 2 - Full Compile:**
```cpp
// Now everyone can reference the skeletons!
BP_PlayerController references BP_GameMode_SKEL ✅
BP_GameMode references BP_PlayerState_SKEL ✅
BP_PlayerState references BP_PlayerController_SKEL ✅
```

No circular dependency! Everyone has something to reference.

## What's in a Skeleton?

A skeleton class contains:

✅ **Variable declarations** (with types)
```cpp
UPROPERTY()
float Health;  // Type is known

UPROPERTY()
ABP_Enemy* Enemy;  // Type is known
```

✅ **Function signatures** (parameters and return types)
```cpp
UFUNCTION()
void TakeDamage(float Amount);  // Signature is known

UFUNCTION()
float GetHealth();  // Return type is known
```

❌ **NO bytecode** (the actual function implementation)
```cpp
// Function exists but body is empty:
void TakeDamage(float Amount)
{
    // Nothing here yet!
}
```

## The Two-Pass Compilation

This is why Blueprint compilation happens in two major phases:

**Pass 1 - Skeleton Only (Fast):**
- Create class structure
- Add all properties
- Add all function signatures
- **NO bytecode generation**

**Pass 2 - Full Compile (Slower):**
- Generate bytecode for all functions
- Fill in the implementation details
- Update all instances

## When Do You See Skeletons?

You rarely see skeleton classes directly, but they're working behind the scenes:

**Scenario 1 - Opening a Blueprint:**
```cpp
OpenBlueprint(BP_MyActor);
// Quick skeleton compile happens
// → Can now see variables/functions in editor
// Full compile happens when you click "Compile"
```

**Scenario 2 - Circular References:**
```cpp
BP_A references BP_B
BP_B references BP_A
// Both get skeleton classes first
// Then both get fully compiled
// → No deadlock!
```

**Scenario 3 - Loading Game:**
```cpp
LoadLevel(MyLevel);
// Skeletons for all Blueprints load first
// Then full compiles happen in dependency order
```

## The SKEL Naming Convention

If you ever see this in logs or crashes:

```
BP_MyActor_C_SKEL
```

That `_SKEL` suffix means you're looking at a skeleton class. The `_C` is the generated class suffix.

## Quick Takeaway

- **Skeleton Class** = Class header (properties + function signatures, no implementation)
- Created in **Stage VIII** of compilation
- Solves **circular dependencies** by providing "something to reference"
- Think of it as a **smart forward declaration**
- Gets replaced by full class after bytecode generation

## Why This Matters

Understanding skeletons helps you:
- Debug "missing function" errors (skeleton compiled, full compile failed)
- Understand why compilation happens in passes
- Know why circular dependencies *usually* work (but can still cause issues if not careful)

## Want More Details?

For the complete explanation with code examples:
- [From Blueprint to Bytecode I - Skeleton Class](/posts/bpvm-bytecode-I/#skeleton-class)

Next snack: We'll peek inside the "Clean and Sanitize" process!

---

**🍿 BPVM Snack Pack Series**
- [← #3: Compilation Kick-Off](/posts/bpvm-snack-03-compilation-kickoff/)
- **#4: Skeleton Classes Explained** ← You are here
- [#5: Clean and Sanitize Magic](/posts/bpvm-snack-05-clean-sanitize/) →
