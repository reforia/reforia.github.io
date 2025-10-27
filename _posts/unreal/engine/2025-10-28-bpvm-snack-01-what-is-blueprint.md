---
layout: post
title: "BPVM Snack Pack #1 - What is a Blueprint, Really?"
description: "That Blueprint you just created? It's not actually the class. It's more like a recipe. Here's the real structure behind it."
date: 2025-10-28 10:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: en
---

{% include ue_version_disclaimer.html version="5.4.0" %}

> **BPVM Snack Pack** is a companion series to the deep-dive [Blueprint to Bytecode series](/posts/bpvm-bytecode-I/). Each snack is a quick 3-5 minute read that breaks down one concept. Perfect for coffee breaks!
{: .prompt-tip }

## The Asset vs The Class

When you right-click in the Content Browser and create a "Blueprint Class" based on `AMyAwesomeActor`, the UI tells you you're creating a **subclass** of `AMyAwesomeActor`.

But here's what's actually happening: you're creating a `UBlueprint` asset that will *generate* a class at compile time.

## What You Actually Created

You created a `UBlueprint` object. It's not the class you selected - it's a *recipe* for making the class you want.

The relationship:
- `UBlueprint` = The source asset (editor-time data, exists in Content Browser)
- `UBlueprintGeneratedClass` = The compiled class (runtime executable, what spawns instances)
- Your `.uasset` file = The serialized Blueprint on disk

![Blueprint Structure](bytecode_blueprintstructure.png)
_What's really happening under the hood_

## The Real Relationship

Here's what actually happens when you create `BP_MyAwesomeActor` from `AMyAwesomeActor`:

```cpp
// What you think happens
class UBlueprintGeneratedClass : public AMyAwesomeActor  // ❌ NOPE!

// What actually happens in BlueprintGeneratedClass.h
class UBlueprintGeneratedClass : public UClass  // ✅ Inherits from UClass!
{
    // No C++ inheritance from AMyAwesomeActor!
};

// The parent relationship is managed by pointers:
UBlueprint* Blueprint;
Blueprint->ParentClass = AMyAwesomeActor::StaticClass();  // Points to parent
Blueprint->GeneratedClass = GeneratedClass;               // Points to generated

GeneratedClass->SetSuperStruct(AMyAwesomeActor::StaticClass());  // Parent relationship!
```

**Key insight:** Neither `UBlueprint` nor `UBlueprintGeneratedClass` actually inherit from `AMyAwesomeActor` in C++. They use Unreal's reflection system (`SuperStruct`) to *simulate* inheritance!

## Why This Matters

**In the editor:**
- You work with `UBlueprint` (the recipe)
- You edit graphs, variables, components
- Everything exists only in the editor

**At runtime:**
- The engine uses `UBlueprintGeneratedClass` (the compiled cake)
- This class **appears** to inherit using `SetSuperStruct()` / `GetSuperClass()`
- It's **NOT** true C++ inheritance (`class Generated : public Parent`)!
- It's a pointer-based parent relationship managed by the reflection system
- Your instances spawn from this generated class

## The Hot-Reload Trick

When you hit "Compile", the Blueprint Editor:
1. Takes your `UBlueprint` recipe
2. Compiles it into bytecode
3. Stuffs that bytecode into `UBlueprintGeneratedClass`
4. **Reuses the same class object** every time you recompile!

It doesn't create a new class - it cleans out the old one and refills it. This is the same pattern as hot-reloading game content: keep the memory address stable, swap the data underneath. That's why your references don't break when you recompile.

(Well, in theory. Live Coding helps a lot but isn't perfect. Legacy hot reload tends to leave `HOTRELOAD` tags scattered around, and you'll probably need to restart the editor if you change anything structural. Save often.)

## Quick Takeaway

- **UBlueprint** = Editor-only recipe (what you see in Content Browser)
- **UBlueprintGeneratedClass** = Runtime class (what actually runs your game)
- They're connected but **completely different** objects

## Want More Details?

This is just a taste! For the full deep-dive, check out:
- [From Blueprint to Bytecode I - But what is Blueprint?](/posts/bpvm-bytecode-I/#ublueprint)

Next snack: We'll explore what those colorful nodes and wires *really* are under the hood!

---

**🍿 BPVM Snack Pack Series**
- **#1: What is a Blueprint, Really?** ← You are here
- [#2: The Graph System Decoded](/posts/bpvm-snack-02-graph-system/) →
