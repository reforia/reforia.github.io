---
layout: post
title: "BPVM Snack Pack #2 - The Graph System Decoded"
description: "The node graph you see is actually two systems: the data (UEdGraph) and the rendering (Slate). Here's why that separation matters."
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: en
---

{% include ue_version_disclaimer.html version="5.4.0" %}

> **BPVM Snack Pack** is a companion series to the deep-dive [Blueprint to Bytecode series](/posts/bpvm-bytecode-I/). Each snack is a quick 3-5 minute read. Grab your coffee!
{: .prompt-tip }

## Model-View Separation (The Unreal Way)

When you open a Blueprint and see this node graph:

![UEdGraph](bytecode_uedgraph.png)

You're looking at classic MVC architecture in action:

1. **The Model** (`UEdGraph` - The data structure)
2. **The View** (`SGraphEditor` - The Slate rendering)

## The Data Layer: UEdGraph

The graph data is stored in a `UEdGraph` object. Think of it as a **JSON structure** that describes:
- What nodes exist
- What they're connected to
- What values they have

```cpp
class UEdGraph
{
    TArray<UEdGraphNode*> Nodes;     // All your nodes
    // That's basically it for the core!
};
```

No rendering code. No UI. Just pure data.

## The Visual Layer: SGraphEditor

When you see the pretty graph on screen, that's a Slate widget called `SGraphEditor`. It:
- Reads the `UEdGraph` data
- Draws the boxes and lines
- Handles your mouse clicks
- Updates the `UEdGraph` when you change things

**Important:** The graph can exist without any visuals! When you package your game, the `UEdGraph` is compiled to bytecode and the visual layer is stripped out. Your shipped game only contains the executable code, not the pretty node editor.

## Nodes: Data Meets Logic

Each node is a `UEdGraphNode` object (or more specifically, `UK2Node` for Blueprint):

![UK2 Nodes](bytecode_uk2nodes.png){: width="500"}

```cpp
class UEdGraphNode
{
    TArray<UEdGraphPin*> Pins;       // Input/output connections
    FString NodeComment;             // That yellow note you can add
    // Node-specific data here
};
```

And yes, it also has a visual representation: `SGraphNode` (another Slate widget).

## Pins: The Connection Points

Pins are where the magic happens:

```cpp
class UEdGraphPin
{
    FName PinName;                   // "Target", "Return Value", etc.
    EPinDirection Direction;         // Input or Output?
    TArray<UEdGraphPin*> LinkedTo;   // What's connected to me?
    FString DefaultValue;            // Value if nothing connected
};
```

When you drag a wire between nodes, you're creating a `LinkedTo` relationship between two pins.

## The Rulebook: Schema

You can't connect an `Integer` pin to a `String` pin. That's the `UEdGraphSchema` enforcing type safety:

```cpp
class UEdGraphSchema
{
    // Defines rules:
    // - What nodes are allowed?
    // - What connections are valid?
    // - What shows up in the right-click menu?
};
```

Different graph types have different schemas:
- **Blueprint** uses `UEdGraphSchema_K2`
- **Animation Blueprint** uses `UAnimationGraphSchema`
- **Behavior Tree** uses `UBehaviorTreeGraphSchema`

Each enforces its own rules!

## Why This Separation Matters

**Data is cheap to store and compile:**
```cpp
// Easy to save, load, and process
UEdGraph* Graph = LoadGraphFromAsset();
CompileToByteCode(Graph);
```

**Visuals are expensive:**
```cpp
// Only create when editor is open
SGraphEditor* VisualGraph = CreateWidget();
VisualGraph->SetGraphToVisualize(Graph);
```

At runtime, your game never loads the visual layer. It only cares about the compiled bytecode!

## Quick Takeaway

- **UEdGraph** = Your node data (serialized in .uasset)
- **UEdGraphNode** = Individual node data (Print String, Branch, etc.)
- **UEdGraphPin** = Connection points with type information
- **SGraphEditor / SGraphNode** = The pretty visuals (editor-only)
- **UEdGraphSchema** = The rulebook (what's allowed?)

## Want More Details?

For the complete breakdown of all these systems:
- [From Blueprint to Bytecode I - Graph System Deep Dive](/posts/bpvm-bytecode-I/#uedgraph)

Next snack: How those nodes turn into executable code!

---

**🍿 BPVM Snack Pack Series**
- [← #1: What is a Blueprint, Really?](/posts/bpvm-snack-01-what-is-blueprint/)
- **#2: The Graph System Decoded** ← You are here
- [#3: Compilation Kick-Off](/posts/bpvm-snack-03-compilation-kickoff/) →
