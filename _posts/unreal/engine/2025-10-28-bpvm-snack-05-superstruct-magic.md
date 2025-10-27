---
layout: post
title: "BPVM Snack Pack #5 - SuperStruct: Pointer-Based Inheritance"
description: "Blueprint classes don't use C++ inheritance. They use a pointer-based system through SuperStruct. Here's why that design matters."
date: 2025-10-28 10:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: en
---

{% include ue_version_disclaimer.html version="5.4.0" %}

> **BPVM Snack Pack** - Quick Blueprint knowledge drops! Part of the [Blueprint to Bytecode series](/posts/bpvm-bytecode-I/).
{: .prompt-tip }

## C++ Inheritance vs Blueprint Inheritance

When you create a Blueprint from `AMyActor`, the editor says you're creating a **subclass** of `AMyActor`.

That's true from an API perspective - it *behaves* like a subclass. But the implementation is completely different from C++ inheritance.

## What True C++ Inheritance Looks Like

```cpp
// Real C++ inheritance
class AMyChildActor : public AMyActor  // ✅ True inheritance
{
    // Compiler creates vtable
    // Memory layout includes parent's data
    // Linker resolves function addresses
};
```

With true inheritance:
- The **compiler** bakes the relationship into the binary at compile time
- The **vtable** is statically linked
- The **memory layout** includes all parent members
- Everything is **resolved statically** (fast, but inflexible)

## What Blueprint "Inheritance" Actually Is

```cpp
// Blueprint's approach
class UBlueprintGeneratedClass : public UClass  // NOT AMyActor!
{
    // This is a UClass, not your actor!
};

// Somewhere during compilation:
GeneratedClass->SetSuperStruct(AMyActor::StaticClass());
```

Here's the key insight:

1. `UBlueprintGeneratedClass` inherits from `UClass` (not your actor!)
2. It stores a **pointer** to the parent via `SetSuperStruct()`
3. When you call `GetSuperClass()`, it follows that pointer

This is **composition + delegation**, not traditional inheritance.

## The Pointer Chain

Here's the actual relationship:

```cpp
UBlueprintGeneratedClass* GeneratedClass;
// |
// | SetSuperStruct()
// v
UClass* ParentClass = AMyActor::StaticClass();
// |
// | GetSuperClass()
// v
UClass* GrandParent = AActor::StaticClass();
// |
// v
UObject::StaticClass();
```

It's a **linked list of pointers**, not C++ inheritance!

## Why This Matters

**Problem 1: Property Lookup**

When you access a variable on a Blueprint instance:
```cpp
// BP_MyActor has variable "Health"
float MyHealth = MyActor->Health;
```

Under the hood:
1. Look for `Health` in `GeneratedClass` properties
2. Not found? Follow `SuperStruct` pointer to parent
3. Repeat until found or reach `UObject`

This is **runtime reflection**, not compile-time!

**Problem 2: Function Calls**

When you call a function:
```cpp
MyActor->Foo();
```

The engine:
1. Checks if `GeneratedClass` overrides `Foo`
2. If not, follows `SuperStruct` chain
3. Finds the function in parent class
4. Executes (could be bytecode OR native C++)

Again, **runtime lookup**!

## The Benefits

Why use pointers instead of real inheritance?

**1. Hot Reloading**
```cpp
// Recompile Blueprint while game is running
GeneratedClass->CleanAndSanitize();  // Clear old data
Compile(Blueprint);                   // Fill with new data
Reinstancer->UpdateInstances();       // Update existing objects

// Still using the SAME GeneratedClass object!
// No memory address changes (sort of...)
// No pointer fixups needed
```

**2. Dynamic Class Creation**
```cpp
// Create Blueprint classes at runtime!
UBlueprint* NewBP = CreateBlueprint(...);
Compile(NewBP);
// Now you have a new "class"
```

**3. Circular Dependencies**
```cpp
BP_A->SetSuperStruct(BP_B);  // A "inherits" from B
BP_B->SetSuperStruct(BP_A);  // ERROR: Would create cycle!

// But the pointer system can detect this
// And create skeleton classes as intermediaries
```

## The Trade-Off

**C++ Inheritance (Fast):**
```cpp
class Child : public Parent {  };
// Compile time: vtable, memory layout
// Runtime: Direct memory access, no lookup
```

**Blueprint SuperStruct (Flexible):**
```cpp
Generated->SetSuperStruct(Parent);
// Compile time: Nothing baked in
// Runtime: Pointer chasing, reflection lookup
```

Blueprint trades performance for flexibility - classic game dev trade-off.

## How to Think About It

**Bad mental model:**
```cpp
BP_MyActor : public AMyActor  // ❌ Not what's happening
```

**Good mental model:**
```cpp
class BP_MyActor {
    UClass* Parent = AMyActor::StaticClass();  // ✅ Pointer relationship
    TArray<FProperty*> MyProperties;
    TArray<UFunction*> MyFunctions;
    TArray<uint8> Bytecode;
};
```

## Quick Takeaway

- Blueprint classes **DON'T** use C++ inheritance
- They use `SetSuperStruct()` / `GetSuperClass()` (pointer chain)
- This enables **hot reloading** and **runtime class creation**
- Trade-off: More flexible, but slower than C++ inheritance
- The reflection system makes it **look like** inheritance to developers

## The Abstraction Works

From your Blueprint code, it behaves exactly like inheritance:
```cpp
// In your Blueprint, this just works
Parent::MyFunction();  // Calls parent version
Super::Tick();         // Calls parent tick
```

But under the hood, it's all pointer chasing and reflection lookups. The abstraction is so good that most developers never need to know the difference.

## Want More Details?

For the complete explanation with code:
- [From Blueprint to Bytecode I - UBlueprintGeneratedClass](/posts/bpvm-bytecode-I/#ublueprintgeneratedclass)

Next snack: The mysterious Class Default Object (CDO)!

---

**🍿 BPVM Snack Pack Series**
- [← #4: Skeleton Classes](/posts/bpvm-snack-04-skeleton-classes/)
- **#5: The SuperStruct Magic Trick** ← You are here
- [#6: The CDO Mystery](/posts/bpvm-snack-06-cdo-mystery/) →
