---
layout: post
title: "BPVM Snack Pack #3 - Compilation Kick-Off"
description: "You hit 'Compile'. Behind that button is a 16-stage pipeline that handles dependencies, generates code, and updates live instances. Here's how it works."
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: en
---

{% include ue_version_disclaimer.html version="5.4.0" %}

> **BPVM Snack Pack** is a companion series to the deep-dive [Blueprint to Bytecode series](/posts/bpvm-bytecode-I/). Each snack is 3-5 minutes of pure knowledge!
{: .prompt-tip }

## The Compile Button

![Compile Button](bytecode_hitcompile.png){: width="500"}

You click it. It turns green. Ship it!

But between that click and the green checkmark, there's a **16-stage compilation pipeline** executing in precise order. Think of it like a game's rendering pipeline, but for code generation.

## Stage 0: The Button Click

When you click "Compile", you trigger a command from this function:

```cpp
FBlueprintEditorToolbar::AddCompileToolbar()
{
    // Creates the compile button
    FToolMenuEntry& CompileButton = InSection.AddEntry(
        FToolMenuEntry::InitToolBarButton(
            Commands.Compile,  // ← This is the command
            ...
        )
    );
}
```

This kicks off `FBlueprintEditor::Compile()`, which adds your Blueprint to a **compilation queue**.

## The Queue System

Unreal doesn't compile Blueprints one at a time - it uses `FBlueprintCompilationManager` to batch them:

```cpp
QueueForCompilation(YourBlueprint);
// ... queue up dependencies too ...
FlushCompilationQueueImpl();  // ← The real work starts here
```

**Why batch?** Same reason games batch draw calls: if Blueprint A depends on Blueprint B, and B depends on C, you need to resolve the dependency graph and process them in topological order.

## The 16 Stages (High-Level)

Here's what `FlushCompilationQueueImpl()` does:

![Compilation Flow](bytecode_compilationflow.png){: width="500"}

**Preparation (Stages I-VII):**
1. **GATHER** - Find all dependent Blueprints
2. **FILTER** - Remove duplicates and invalid ones
3. **SORT** - Order by dependency (C → B → A)
4. **SET FLAGS** - Mark as "currently compiling"
5. **VALIDATE** - Check for errors
6. **PURGE** - Clean up old data (load-time only)
7. **DISCARD SKELETON CDO** - Prepare for regeneration

**Compilation (Stages VIII-XIII):**
8. **RECOMPILE SKELETON** - Create class headers
9. **RECONSTRUCT NODES** - Update deprecated nodes
10. **CREATE REINSTANCER** - Prepare to update instances
11. **CREATE CLASS HIERARCHY** - Link parent/child classes
12. **COMPILE CLASS LAYOUT** - Generate properties and functions ⚡
13. **COMPILE CLASS FUNCTIONS** - Generate bytecode ⚡⚡

**Finalization (Stages XIV-XVI):**
14. **REINSTANCE** - Update all existing instances
15. **POST CDO COMPILED** - Finalize Class Default Object
16. **CLEAR FLAGS** - Mark as "done"

## The Two Critical Stages

Stages 12 and 13 are where code generation happens:

**Stage XII - COMPILE CLASS LAYOUT:**
- Creates `UProperties` for your variables
- Creates `UFunctions` for your functions
- Sets up the class structure (like generating a C++ header)

**Stage XIII - COMPILE CLASS FUNCTIONS:**
- Converts your nodes into intermediate statements
- Generates bytecode from those statements
- Links bytecode into the class (like compiling a .cpp file)

## Why So Many Stages?

Each stage handles a specific problem:

**Circular Dependencies?**
- Stage I-III (Gather/Sort) handles this

**Blueprint A references Blueprint B that's not compiled yet?**
- Stage VIII (Skeleton) creates a "header" first so B can reference A

**Existing instances in the level?**
- Stage XIV (Reinstance) updates them all

**Old data from previous compile?**
- Stage VII (Purge) cleans it up

## Quick Takeaway

When you hit "Compile":
1. Your Blueprint joins a **compilation queue**
2. The queue **sorts by dependencies**
3. **16 stages** execute in order
4. Stages 12-13 do the **actual compilation**
5. Result: Fresh bytecode ready to run!

## The Journey Ahead

In the next snacks, we'll zoom into:
- **Stage XII** - How variables and functions are created
- **Stage XIII** - How nodes become bytecode
- **Reinstancing** - How existing instances get updated

## Want More Details?

For the complete 16-stage breakdown with code:
- [From Blueprint to Bytecode II - FlushCompilationQueueImpl](/posts/bpvm-bytecode-II/#flushcompilationqueueimpl---the-heavy-lifter)

Next snack: The mysterious "Skeleton Class"!

---

**🍿 BPVM Snack Pack Series**
- [← #2: The Graph System Decoded](/posts/bpvm-snack-02-graph-system/)
- **#3: Compilation Kick-Off** ← You are here
- [#4: Skeleton Classes Explained](/posts/bpvm-snack-04-skeleton-classes/) →
