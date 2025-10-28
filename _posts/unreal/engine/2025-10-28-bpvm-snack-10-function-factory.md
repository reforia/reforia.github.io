---
layout: post
title: "BPVM Snack Pack #10 - The Function Factory: Where Graphs Become Functions"
description: "Your Event Graph isn't really a graph when it runs. It's transformed into a giant function called the Ubergraph. Here's how the function factory works its magic."
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

## The Multiple Graph Problem

You've created multiple Event Graph pages for organization:

- "Player Input" page
- "Combat Logic" page
- "UI Updates" page

Clean and organized, right? But here's the secret: **They all become ONE function**.

## Meet the Ubergraph

The compiler takes ALL your event graphs and merges them:

```cpp
void CreateAndProcessUbergraph()
{
    // Create one mega-graph
    ConsolidatedEventGraph = NewObject<UEdGraph>("Ubergraph");

    // Copy ALL event graph pages into it
    for (UEdGraph* EventGraph : Blueprint->EventGraphs) {
        MergeIntoUbergraph(EventGraph, ConsolidatedEventGraph);
    }

    // This is now ONE giant function!
}
```

Think of it like taking multiple recipe cards and combining them into one cookbook!

## Why Merge Everything?

**The VM doesn't understand "pages"** - it only executes functions:

```cpp
// What you see in editor:
EventGraph_Page1 → BeginPlay node
EventGraph_Page2 → Tick node
EventGraph_Page3 → OnDamaged node

// What the VM sees:
Ubergraph() {
    BeginPlay_Implementation();
    Tick_Implementation();
    OnDamaged_Implementation();
}
```

Pages are for **humans**. The machine wants **one function**.

## The Function Creation Pipeline

The factory processes **four types** of graphs:

```cpp
void CreateFunctionList()
{
    // 1. The Ubergraph (all event graphs merged)
    if (DoesSupportEventGraphs(Blueprint)) {
        CreateAndProcessUbergraph();
    }

    // 2. Regular function graphs
    for (UEdGraph* Graph : Blueprint->FunctionGraphs) {
        ProcessOneFunctionGraph(Graph);
    }

    // 3. Generated function graphs (from macros, etc.)
    for (UEdGraph* Graph : GeneratedFunctionGraphs) {
        ProcessOneFunctionGraph(Graph);
    }

    // 4. Interface functions
    for (auto& Interface : Blueprint->ImplementedInterfaces) {
        for (UEdGraph* Graph : Interface.Graphs) {
            ProcessOneFunctionGraph(Graph);
        }
    }
}
```

## Processing Each Function

Each graph goes through the **same factory process**:

```cpp
void ProcessOneFunctionGraph(UEdGraph* SourceGraph)
{
    // Step 1: Clone to temporary graph
    UEdGraph* TempGraph = DuplicateGraph(SourceGraph);

    // Step 2: Expand nodes (macros become real nodes)
    ExpandAllMacroNodes(TempGraph);

    // Step 3: Create function context
    FKismetFunctionContext* Context = CreateFunctionContext();
    Context->SourceGraph = TempGraph;

    // Step 4: Add to function list
    FunctionList.Add(Context);
}
```

## The Event Node Magic

Each event in your graph becomes a **function stub**:

```cpp
// You have a BeginPlay event node
UK2Node_Event* BeginPlayNode;

// Compiler creates a function stub
void ReceiveBeginPlay() {
    // Jump to the right spot in Ubergraph
    Ubergraph(ENTRY_BeginPlay);
}
```

Events are just **entry points** into the mega-function!

## Function Context: The Blueprint

Each function gets a `FKismetFunctionContext`:

```cpp
struct FKismetFunctionContext
{
    UEdGraph* SourceGraph;           // The visual graph
    TArray<FBPTerminal*> Parameters; // Input pins
    TArray<FBPTerminal*> Locals;     // Local variables
    TArray<UEdGraphNode*> LinearExecutionList;  // Node order
    TArray<FBlueprintCompiledStatement*> AllGeneratedStatements;  // The code!
};
```

This context is the **blueprint** (pun intended) for building the actual function!

## Macro Expansion

Macros get **inlined** during processing:

```cpp
// Before expansion
CallMacro("MyUtilityMacro")

// After expansion (nodes copied directly)
Node1 → Node2 → Node3 → Node4  // The macro's actual nodes
```

Macros **disappear** - their nodes are copied right into your function!

## The Ubergraph Name

Ever see this in crash logs?

```
ExecuteUbergraph_BP_MyActor
```

Now you know what it means - it's the **mega-function** containing all your events!

## Function Types Explained

**Regular Functions:**
```cpp
ProcessOneFunctionGraph(MyFunction)
→ Creates: MyFunction()
```

**Event Graph Events:**
```cpp
CreateAndProcessUbergraph()
→ Creates: ExecuteUbergraph_BP_MyActor()
→ With stubs: ReceiveBeginPlay(), ReceiveTick(), etc.
```

**Interface Functions:**
```cpp
ProcessOneFunctionGraph(InterfaceFunc)
→ Creates: InterfaceFunc_Implementation()
```

## The Hidden Optimization

Why merge everything into Ubergraph?

**Without Ubergraph (inefficient):**
```cpp
void BeginPlay() { /* bytecode */ }
void Tick() { /* bytecode */ }
void OnDamaged() { /* bytecode */ }
// Three separate function calls, three contexts
```

**With Ubergraph (optimized):**
```cpp
void ExecuteUbergraph(int EntryPoint) {
    switch(EntryPoint) {
        case 0: /* BeginPlay bytecode */
        case 1: /* Tick bytecode */
        case 2: /* OnDamaged bytecode */
    }
    // One function, shared context!
}
```

## Quick Takeaway

- All Event Graph pages become **ONE function** (the Ubergraph)
- Regular functions each get their **own function**
- Macros are **expanded inline** (they disappear)
- Each function gets a **FKismetFunctionContext** (its blueprint)
- Events are just **entry points** into the Ubergraph
- Interface functions get **_Implementation** suffix

## The Factory Never Sleeps

Every time you compile:
1. Event graphs merge into Ubergraph
2. Functions are processed individually
3. Macros expand and vanish
4. Contexts are created for each function
5. The factory produces executable functions!

## Want More Details?

For the complete function creation process:
- [From Blueprint to Bytecode III - Function Graphs](/posts/bpvm-bytecode-III/#function-graphs)

Next: How everything gets linked together!

---

**🍿 BPVM Snack Pack Series**
- [← #9: Variables Become Properties](/posts/bpvm-snack-09-variables-properties/)
- **#10: The Function Factory** ← You are here
- [#11: Linking and Binding](/posts/bpvm-snack-11-linking-binding/) →