---
layout: post
title: "BPVM Snack Pack #8 - Clean and Sanitize: The Memory Recycling Trick"
description: "Blueprint classes don't get deleted and recreated during compilation. They get cleaned and reused like a whiteboard. Here's the clever trick that makes hot reload possible."
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

## The Recompilation Problem

You hit the compile button on your Blueprint. The class needs to be rebuilt with new properties, functions, and logic.

**The naive approach:**
```cpp
// Delete old class
delete OldBlueprintClass;

// Create new class
UClass* NewClass = new UBlueprintGeneratedClass();

// Now fix EVERY pointer in the engine...
UpdateMillionsOfPointers(OldClass, NewClass);  // Nightmare!
```

This would be a **disaster**. Every actor, every reference, every pointer would break!

## The Whiteboard Solution

Unreal's clever trick: **Don't delete the class. Clean it and reuse it!**

```cpp
void CleanAndSanitizeClass(UBlueprintGeneratedClass* ClassToClean)
{
    // Same memory address, same pointers
    // Just erase the content and write new stuff!
}
```

Think of it like a whiteboard:
- You don't throw away the whiteboard when you need to write something new
- You just erase it and write again
- The whiteboard (memory address) stays in the same place!

## The Transient Trash Class

But wait - you can't just delete properties and functions. Other systems might be using them!

Enter the **TRASHCLASS**:

```cpp
// Create a temporary trash can
FName TrashName = "TRASHCLASS_MyBlueprint";
UClass* TransientClass = NewObject<UBlueprintGeneratedClass>(
    GetTransientPackage(),  // Special temporary package
    TrashName,
    RF_Transient  // Will be garbage collected
);

// Move old stuff to trash
MovePropertiesToTrash(ClassToClean, TransientClass);
MoveFunctionsToTrash(ClassToClean, TransientClass);
```

It's like having a **"Recycle Bin"** for class members!

## What Gets Moved to Trash?

Everything that will be regenerated:

```cpp
// Get all subobjects
TArray<UObject*> ClassSubObjects;
GetObjectsWithOuter(ClassToClean, ClassSubObjects);

for (UObject* SubObj : ClassSubObjects) {
    if (ShouldBeSaved(SubObj)) {
        continue;  // Keep special objects
    }

    // Move to trash
    SubObj->Rename(nullptr, TransientClass);
}
```

The trash will contain:
- Old properties (variables)
- Old functions
- Old components
- Old metadata
- Basically everything except the CDO!

## The CDO Preservation

The Class Default Object gets **special treatment**:

```cpp
// Save the old CDO (it has user's default values!)
UObject* OldCDO = ClassToClean->GetDefaultObject();

// Rename it to preserve it
FName OldCDOName = "BPGC_ARCH_OldCDO";
OldCDO->Rename(*OldCDOName, TransientClass);

// Later, after recompilation...
// Copy defaults from old CDO to new CDO
FBlueprintEditorUtils::PropagateDefaultValueChange(OldCDO, NewCDO);
```

Your default values survive because the CDO is **preserved and copied**!

## The Clean Slate

After moving everything to trash:

```cpp
// Clear all arrays
ClassToClean->NetFields.Empty();
ClassToClean->ClassReps.Empty();
ClassToClean->FuncMap.Empty();

// Reset all pointers
ClassToClean->Children = nullptr;
ClassToClean->PropertiesSize = 0;
ClassToClean->MinAlignment = 0;

// Clear all flags
ClassToClean->ClassFlags &= ~BadFlags;

// The class is now a blank slate!
```

It's like doing a **factory reset** but keeping the serial number!

## Why This Matters

**1. Pointers Stay Valid**
```cpp
AActor* MyActor = GetActor();
// Recompile happens...
MyActor->GetClass();  // STILL VALID! Same memory address!
```

**2. Hot Reload Works**
```cpp
// In-game, Blueprint gets recompiled
CleanAndSanitizeClass(BlueprintClass);
RegenerateClass(BlueprintClass);
// Game doesn't crash! All references still work!
```

**3. Circular Dependencies Resolved**
```cpp
// BP_A references BP_B
// BP_B references BP_A
// Both can recompile because addresses don't change!
```

## The Garbage Collection Magic

What happens to the trash?

```cpp
// TransientClass is marked RF_Transient
// Next garbage collection...
if (Object->HasAnyFlags(RF_Transient)) {
    delete Object;  // Trash gets collected!
}
```

The trash class **automatically disappears** during the next GC cycle!

## Visual Analogy

Imagine renovating a house:

**Bad Way (New Address):**
1. Demolish house
2. Build new house at new location
3. Update everyone's address books
4. Forward all mail
5. Update GPS systems

**Unreal's Way (Same Address):**
1. Move furniture to storage (trash)
2. Gut the interior (clean)
3. Rebuild interior (sanitize)
4. Move in new furniture
5. Address never changed!

## Quick Takeaway

- Blueprint classes are **reused, not recreated** during compilation
- Old members move to a **TRASHCLASS** in the transient package
- The **CDO is preserved** to keep default values
- Memory addresses stay the same (no pointer fixup needed!)
- The trash gets **automatically garbage collected**
- This enables **hot reload** without crashes!

## The Recycling Champion

Next time you recompile a Blueprint while the game is running and it doesn't crash, thank the Clean and Sanitize system. It's the unsung hero that makes Unreal's hot reload feel like magic!

## Want More Details?

For the complete Clean and Sanitize breakdown:
- [From Blueprint to Bytecode III - Clean and Sanitize](/posts/bpvm-bytecode-III/#clean-and-sanitize-class)

Next up: How your Blueprint variables become real properties!

---

**🍿 BPVM Snack Pack Series**
- [← #7: Node Handlers Explained](/posts/bpvm-snack-07-node-handlers/)
- **#8: Clean and Sanitize Magic** ← You are here
- [#9: Variables Become Properties](/posts/bpvm-snack-09-variables-properties/) →