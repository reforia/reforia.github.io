---
layout: post
title: "BPVM Snack Pack #9 - Variables Become Properties: The Transformation"
description: "When you create a variable in Blueprint, it's not really a variable yet. It's just a description waiting to become a real property. Here's the metamorphosis."
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

## The Variable Illusion

In the Blueprint editor, you click "+Variable" and create `Health`:

![Blueprint variable creation in editor]

You think you just created a variable. **You didn't.**

You created a **description** of a variable. The real variable doesn't exist yet!

## Meet FBPVariableDescription

When you create a Blueprint variable, this is what actually gets stored:

```cpp
struct FBPVariableDescription
{
    FName VarName;           // "Health"
    FEdGraphPinType VarType; // Float
    FString Category;        // "Stats"
    uint64 PropertyFlags;    // EditAnywhere, BlueprintReadWrite, etc.

    // Metadata
    FString Tooltip;         // "Player's current health"
    FName RepNotifyFunc;     // "OnRep_Health"

    // NOT an actual property yet!
};
```

It's just **data about a variable**, not the variable itself!

## The Compilation Transformation

During compilation, these descriptions become **real properties**:

```cpp
void CreateClassVariablesFromBlueprint()
{
    // Loop through all variable descriptions
    for (FBPVariableDescription& Variable : Blueprint->NewVariables)
    {
        // Transform description into real property!
        FProperty* NewProperty = CreateVariable(Variable.VarName, Variable.VarType);

        // Now it's a REAL property on the class!
    }
}
```

## The Birth of a Property

Here's the magical moment:

```cpp
FProperty* CreateVariable(FName VarName, FEdGraphPinType& VarType)
{
    // Determine property type
    if (VarType.PinCategory == "Float") {
        // Create REAL float property
        FFloatProperty* NewProp = new FFloatProperty(
            NewClass,     // Owner class
            VarName,      // "Health"
            RF_Public     // Flags
        );

        // It's alive! Real memory will be allocated!
        return NewProp;
    }
}
```

## Why the Two-Step Process?

**Why not create real properties immediately?**

**1. Editor Performance**
```cpp
// Bad: Create real property every edit
Click +Variable → Allocate memory
Type name → Reallocate
Change type → Reallocate again
Set tooltip → Reallocate AGAIN

// Good: Just update description
Click +Variable → Create description
Type name → Update string
Change type → Update enum
Set tooltip → Update string
// Only create real property on compile!
```

**2. Hot Reload Safety**
```cpp
// During editing (safe)
VariableDescription.VarName = "NewName";  // Just data

// During compilation (careful!)
OldProperty->Destroy();
NewProperty = CreateProperty("NewName");  // Real memory operation
```

**3. Validation First**
```cpp
// Check all descriptions BEFORE creating properties
for (auto& Desc : Variables) {
    if (IsDuplicate(Desc)) return;  // Stop before damage!
    if (IsInvalid(Desc)) return;
}
// All good? Now create real properties
```

## The Property Creation Pipeline

**Step 1: Gather Descriptions**
```cpp
TArray<FBPVariableDescription> Descriptions;
Descriptions.Add("Health", Float);
Descriptions.Add("Armor", Int32);
Descriptions.Add("Name", String);
```

**Step 2: Sort by Size (Optimization!)**
```cpp
// Large properties first for better memory alignment
Descriptions.Sort([](auto& A, auto& B) {
    return GetSize(A) > GetSize(B);
});
```

**Step 3: Create Real Properties**
```cpp
for (auto& Desc : Descriptions) {
    FProperty* Prop = CreatePropertyOnScope(
        NewClass,           // Where it lives
        Desc.VarName,       // Its name
        Desc.VarType        // Its type
    );

    // Configure the property
    Prop->SetPropertyFlags(Desc.PropertyFlags);
    Prop->SetMetaData("Tooltip", Desc.Tooltip);
}
```

**Step 4: Link to Class**
```cpp
// Add to class's property chain
NewClass->AddCppProperty(NewProperty);

// Calculate memory offsets
NewProperty->Offset = CurrentOffset;
CurrentOffset += NewProperty->ElementSize;
```

## Special Property Types

Some variables need **extra transformation**:

**Timeline Variables:**
```cpp
// You create one timeline in editor
"MyTimeline"

// Compiler creates MULTIPLE properties:
FTimelineComponent* MyTimeline;        // Component
FOnTimelineFloat MyTimeline_UpdateFunc; // Delegate
FOnTimelineEvent MyTimeline_FinishFunc; // Delegate
```

**Component Variables:**
```cpp
// You add a component variable
"MyMeshComp" (StaticMeshComponent)

// Compiler does extra work:
CreateComponentProperty("MyMeshComp");
RegisterComponent("MyMeshComp");
SetupComponentDefaults("MyMeshComp");
```

## The Memory Layout

After all properties are created:

```cpp
class BP_MyActor {
    // Memory layout (ordered by size!)
    0x0000: UStaticMeshComponent* MyMesh;  // 8 bytes
    0x0008: FString Name;                   // 16 bytes (TArray)
    0x0018: float Health;                   // 4 bytes
    0x001C: int32 Armor;                    // 4 bytes
    0x0020: bool bIsAlive;                  // 1 byte
    0x0021: [padding]                       // 7 bytes
    // Total size: 0x0028 (40 bytes)
}
```

The compiler **optimizes the layout** for cache efficiency!

## Quick Takeaway

- Blueprint variables start as **FBPVariableDescription** (just metadata)
- During compilation, they become **FProperty** objects (real memory)
- This two-step process enables **safe editing** and **hot reload**
- Properties are **sorted by size** for optimal memory layout
- Special types (Timeline, Component) create **multiple properties**
- The transformation happens in `CreateClassVariablesFromBlueprint()`

## From Description to Reality

Next time you create a variable in Blueprint, remember:
- You're creating a description, not a variable
- The real property is born during compilation
- The two-step process keeps the editor fast and safe
- Your "simple" variable might create multiple properties!

## Want More Details?

For the complete property creation breakdown:
- [From Blueprint to Bytecode III - Variables and Components](/posts/bpvm-bytecode-III/#variables-and-components)

Next up: How functions get manufactured!

---

**🍿 BPVM Snack Pack Series**
- [← #8: Clean and Sanitize Magic](/posts/bpvm-snack-08-clean-sanitize/)
- **#9: Variables Become Properties** ← You are here
- [#10: The Function Factory](/posts/bpvm-snack-10-function-factory/) →