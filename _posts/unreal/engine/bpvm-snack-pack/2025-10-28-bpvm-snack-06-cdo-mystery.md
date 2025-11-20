---
layout: post
title: "BPVM Snack Pack #6 - The CDO Mystery: Your Class's Secret Template"
description: "Every Blueprint class has a hidden template object that nobody talks about. Meet the CDO - the mysterious instance that defines what 'default' really means."
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

## The Mystery Object

You've created a Blueprint class. You haven't spawned any instances yet. But surprise - **an instance already exists**.

It's called the Class Default Object (CDO), and it's been quietly living in memory since your class was loaded.

## What Is a CDO?

Think of the CDO as the **master mold** for your class:

```cpp
// When you create BP_MyActor...
UClass* MyClass = BP_MyActor::StaticClass();

// This already exists!
AActor* CDO = MyClass->GetDefaultObject();  // The secret instance
```

The CDO is:
- A **real instance** of your class (it's an actual object in memory!)
- Created **automatically** when the class loads
- Never spawned in the world (it exists in limbo)
- The **template** for all future instances

## Why Does Every Class Need One?

**Problem:** When you spawn an actor, where do its default values come from?

**Bad Solution:** Store defaults as metadata somewhere
```cpp
// Imaginary bad design
class ClassMetadata {
    float DefaultHealth = 100;
    FString DefaultName = "Player";
    // Hundreds of properties...
};
```

**Unreal's Solution:** Just create one "perfect" instance and copy from it!
```cpp
// The CDO IS the defaults
AActor* CDO = GetDefault<AActor>();
CDO->Health = 100;  // Set once
CDO->Name = "Player";

// Spawning copies from CDO
AActor* NewActor = SpawnActor();  // Copies all properties from CDO
```

## The Magic Moment

When you edit "Default" values in the Blueprint editor:

![Blueprint Editor showing default values](bytecode_hitcompile.png){: width="500" }

You're not editing metadata. **You're editing the CDO directly!**

```cpp
// In Blueprint Editor, when you set Health = 100
CDO->Health = 100;  // You're literally setting a property on the CDO

// Later, when spawning
NewInstance->Health = CDO->Health;  // Copy from CDO
```

## CDO in Action

Here's the lifecycle:

**1. Class Creation**
```cpp
// Blueprint gets compiled
UBlueprintGeneratedClass* NewClass = CompileBlueprint();

// CDO is created immediately
UObject* CDO = NewClass->GetDefaultObject();
```

**2. Setting Defaults**
```cpp
// You edit in Blueprint editor
CDO->MaxHealth = 150;
CDO->TeamColor = FColor::Red;
CDO->WeaponClass = AK47::StaticClass();
```

**3. Instance Creation**
```cpp
// Player spawns your actor
AActor* Instance = World->SpawnActor<AActor>(BP_MyActor);

// Under the hood:
// 1. Allocate memory
// 2. Copy all properties from CDO
// 3. Run constructor
```

## The Revert Button Mystery

Ever wondered how the "Revert to Default" button works?

![Property with revert button in editor]

It's just comparing to the CDO:
```cpp
bool IsModified = (Instance->Health != CDO->Health);
// If true, show yellow revert button

void RevertToDefault() {
    Instance->Health = CDO->Health;  // Just copy from CDO!
}
```

## CDO vs Constructor Defaults

**C++ Constructor:**
```cpp
AMyActor::AMyActor() {
    Health = 100;  // Runs EVERY spawn
}
```

**CDO System:**
```cpp
// Set once on CDO
CDO->Health = 100;

// Spawning just copies memory (faster!)
memcpy(NewInstance, CDO, sizeof(AActor));
```

The CDO approach is **much faster** for spawning many instances!

## The Hidden CDO Lifecycle

**During Compilation:**
```cpp
void CompileBlueprint() {
    // Old CDO still has player's configured defaults
    UObject* OldCDO = OldClass->GetDefaultObject();

    // Clean the class
    CleanAndSanitizeClass(OldClass);

    // Recompile everything
    CompileClass(NewClass);

    // Copy defaults from old CDO to new CDO!
    CopyPropertiesFrom(OldCDO, NewCDO);
}
```

This is why your default values survive recompilation!

## CDO Gotchas

**1. CDO Exists in Editor AND Runtime**
```cpp
// In editor
CDO->SomeProperty = 10;  // Editing defaults

// In packaged game
CDO->SomeProperty;  // Still 10! (read-only now)
```

**2. Never Modify CDO at Runtime**
```cpp
// DON'T DO THIS in gameplay code!
CDO->Health = 200;  // You just changed defaults for ALL future spawns!
```

**3. CDO and Hot Reload**
```cpp
// During hot reload
OldCDO->SaveDefaults();
RecompileClass();
NewCDO->RestoreDefaults();  // Your settings survived!
```

## Quick Takeaway

- Every class has a **CDO** (Class Default Object) - a hidden template instance
- When you edit defaults in Blueprint, you're **editing the CDO**
- Spawning actors **copies properties from the CDO** (fast!)
- The CDO survives recompilation (that's why defaults persist)
- **Never modify the CDO at runtime** (it affects all future spawns)

## The CDO Is Everywhere

Next time you:
- Set a default value in Blueprint
- Hit the revert button
- Spawn an actor
- Recompile a Blueprint

Remember: You're interacting with the CDO, the secret template object that makes Unreal's class system work!

## Want More Details?

For the complete explanation with code:
- [From Blueprint to Bytecode I - CDO Deep Dive](/posts/bpvm-bytecode-I/#cdo)
- [From Blueprint to Bytecode III - CDO in Compilation](/posts/bpvm-bytecode-III/#clean-and-sanitize-class)

Next up: How node handlers turn your graph into code!

---

**🍿 BPVM Snack Pack Series**
- [← #5: SuperStruct Magic](/posts/bpvm-snack-05-superstruct-magic/)
- **#6: The CDO Mystery** ← You are here
- [#7: Node Handlers Explained](/posts/bpvm-snack-07-node-handlers/) →