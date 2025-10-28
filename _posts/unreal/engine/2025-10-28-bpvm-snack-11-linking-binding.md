---
layout: post
title: "BPVM Snack Pack #11 - Linking and Binding: The Final Assembly"
description: "After creating properties and functions, they're just loose parts. Linking and Binding connects everything together into a working class. Here's the final assembly line."
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

## The Scattered Parts Problem

After compilation, you have:
- Properties created ✓
- Functions generated ✓
- Memory allocated ✓

But they're **not connected**. It's like having all car parts but no assembly!

## The Two-Step Assembly

Unreal uses two operations to connect everything:

```cpp
// Step 1: Find the C++ connections
NewClass->Bind();

// Step 2: Link all the properties
NewClass->StaticLink(true);
```

Think of it as:
1. **Bind**: Connect to the engine (find the steering wheel)
2. **StaticLink**: Connect internally (wire the dashboard)

## Bind(): Finding the C++ Functions

`Bind()` searches for **three critical things**:

```cpp
void UClass::Bind()
{
    // 1. Find the constructor
    ClassConstructor = FindConstructor();
    // "How do I create instances?"

    // 2. Find VTable helper
    ClassVTableHelperCtorCaller = FindVTableHelper();
    // "How do I set up virtual functions?"

    // 3. Find static functions
    ClassCppStaticFunctions = FindStaticFunctions();
    // "What C++ functions can I call?"

    // Recursively bind parent class
    if (GetSuperClass()) {
        GetSuperClass()->Bind();
    }
}
```

It's like finding the **instruction manual** for your class!

## Why Bind Matters

Without `Bind()`, Blueprint can't:

```cpp
// Can't create instances
AMyActor* Actor = NewObject<AMyActor>();  // No constructor!

// Can't call parent functions
Super::BeginPlay();  // No VTable!

// Can't call static functions
AMyActor::StaticFunction();  // Not found!
```

`Bind()` creates the **bridge** between Blueprint and C++!

## StaticLink(): The Property Chain

`StaticLink()` creates the **property linked list**:

```cpp
void UStruct::StaticLink(bool bRelinkExistingProperties)
{
    // Link all properties into a chain
    FProperty* Previous = nullptr;
    for (FProperty* Prop : Properties) {
        if (Previous) {
            Previous->Next = Prop;
        }
        Prop->Offset = CalculateOffset(Prop);
        Previous = Prop;
    }

    // Calculate total size
    PropertiesSize = 0;
    for (FProperty* Prop : PropertyLink) {
        PropertiesSize += Prop->ElementSize;
    }
}
```

Before: Properties exist but don't know about each other
After: Properties form a **linked list** with calculated offsets!

## Memory Layout Calculation

`StaticLink()` figures out **where everything lives**:

```cpp
// Before StaticLink
Property: Health (?)
Property: Armor (?)
Property: Name (?)

// After StaticLink
Property: Health → Offset: 0x0000 (4 bytes)
Property: Armor  → Offset: 0x0004 (4 bytes)
Property: Name   → Offset: 0x0008 (16 bytes)
Total Size: 0x0018 (24 bytes)
```

Now the engine knows **exactly** where each property is in memory!

## The Reference Chain

Properties can reference each other:

```cpp
// During StaticLink
FObjectProperty* MyActorRef;
MyActorRef->PropertyClass = AMyActor::StaticClass();
MyActorRef->LinkInternal();  // Connect to the class!
```

This creates the **web of references** between objects!

## Parent Class Recursion

Both operations work **recursively**:

```cpp
// Bind() goes up the chain
BP_MyActor::Bind()
  → AActor::Bind()
    → UObject::Bind()

// StaticLink() does too
BP_MyActor::StaticLink()
  → AActor::StaticLink()
    → UObject::StaticLink()
```

Every level of inheritance gets properly connected!

## The Alignment Magic

`StaticLink()` also handles **memory alignment**:

```cpp
// Optimize for CPU cache
if (Property->Size == 1) {
    Alignment = 1;  // Bytes can go anywhere
} else if (Property->Size <= 4) {
    Alignment = 4;  // Align to 4 bytes
} else {
    Alignment = 8;  // Align to 8 bytes
}
```

This makes your Blueprint **faster** at runtime!

## The Final Connection

After both operations:

```cpp
// Everything is connected!
Class {
    Constructor: ✓ (found by Bind)
    VTable: ✓ (found by Bind)
    Properties: ✓ (linked by StaticLink)
    Size: 0x0018 ✓ (calculated by StaticLink)
    Alignment: 8 ✓ (calculated by StaticLink)
}
```

Your class is now a **fully functional machine**!

## Real-World Example

```cpp
// You create a Blueprint with:
float Health = 100;
int32 Armor = 50;
AActor* Target;

// After Bind() and StaticLink():
BP_MyClass {
    Constructor → AMyActor::AMyActor()  // Found!
    Properties → [
        0x00: Health (float, 4 bytes)
        0x04: Armor (int32, 4 bytes)
        0x08: Target (AActor*, 8 bytes)
    ]
    Total Size: 16 bytes
    Property Chain: Health→Armor→Target→nullptr
}
```

## Quick Takeaway

- **Bind()** finds C++ functions (constructor, VTable, statics)
- **StaticLink()** connects properties and calculates memory layout
- Properties become a **linked list** with offsets
- Memory is **aligned** for performance
- Both work **recursively** through inheritance
- Together they transform loose parts into a **working class**!

## The Assembly Complete

When compilation finishes with Bind() and StaticLink(), your Blueprint class is no longer a collection of parts - it's a fully assembled, ready-to-run machine with every wire connected and every bolt tightened!

## Want More Details?

For the complete linking process:
- [From Blueprint to Bytecode III - Finish Compiling Class](/posts/bpvm-bytecode-III/#finish-compiling-class)

Next: Understanding the statements that become bytecode!

---

**🍿 BPVM Snack Pack Series**
- [← #10: The Function Factory](/posts/bpvm-snack-10-function-factory/)
- **#11: Linking and Binding** ← You are here
- [#12: Statements 101](/posts/bpvm-snack-12-statements/) →