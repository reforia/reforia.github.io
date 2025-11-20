---
layout: post
title: "BPVM Snack Pack #12 - Statements 101: The Language Before Bytecode"
description: "Before your nodes become bytecode, they become statements. Think of them as the intermediate language between visual nodes and machine code."
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

## The Translation Pipeline

Your Blueprint nodes go through **three forms**:

```
Visual Nodes → Statements → Bytecode
(What you see) → (Intermediate) → (What runs)
```

Statements are the **middle ground** - more structured than nodes, simpler than bytecode!

## Meet FBlueprintCompiledStatement

Every operation becomes a statement:

```cpp
struct FBlueprintCompiledStatement
{
    EKismetCompiledStatementType Type;  // What kind of operation?
    FBPTerminal* LHS;                    // Left side (usually output)
    TArray<FBPTerminal*> RHS;            // Right side (inputs)
    UFunction* TargetFunction;           // For function calls
    UEdGraphNode* SourceNode;            // Where it came from
};
```

Think of it as a **recipe card** for one operation!

## The Statement Types

There are **30+ statement types**. Here are the essentials:

```cpp
enum EKismetCompiledStatementType
{
    KCST_Nop = 0,                // Do nothing
    KCST_CallFunction = 1,       // Call a function
    KCST_Assignment = 2,         // Set a variable
    KCST_CompileError = 3,       // Compilation failed
    KCST_UnconditionalGoto = 4,  // Jump to label
    KCST_Return = 7,             // Return from function
    KCST_SwitchValue = 29,       // Select/switch statement
    // ... many more
};
```

Each type tells the backend **exactly** what to generate!

## Real Example: Print String

Your "Print String" node becomes:

```cpp
// The node
UK2Node_CallFunction "PrintString"

// Becomes this statement
FBlueprintCompiledStatement {
    Type: KCST_CallFunction
    TargetFunction: "PrintString"
    RHS: [Terminal_StringValue]  // "Hello World"
}

// Eventually becomes bytecode
0x44 EX_CallFunc
0x08 PrintString
"Hello World"
0x53 EX_Return
```

## Assignment Statements

Setting a variable:

```cpp
// Blueprint: Health = 100

Statement {
    Type: KCST_Assignment
    LHS: Terminal_Health  // Target variable
    RHS: [Terminal_100]   // Value to assign
}
```

LHS = "Left Hand Side" (where to put it)
RHS = "Right Hand Side" (what to put there)

## Control Flow Statements

Branches and jumps:

```cpp
// Branch node
Statement {
    Type: KCST_GotoIfNot
    LHS: Terminal_Condition  // What to check
    TargetLabel: Label_False // Where to jump if false
}

// Unconditional jump
Statement {
    Type: KCST_UnconditionalGoto
    TargetLabel: Label_End
}
```

These become the **skeleton** of your logic flow!

## The Terminal System

Statements use `FBPTerminal` for data:

```cpp
FBPTerminal* Terminal = new FBPTerminal();
Terminal->Type = "int32";
Terminal->Name = "MyVariable";
Terminal->Source = OutputPin;  // Where it connects
```

Terminals are **placeholders** for values - like variables in assembly!

## Why Statements?

**Why not go straight to bytecode?**

1. **Optimization Opportunity**
```cpp
// Before optimization
Statement1: A = B + 1
Statement2: C = A
Statement3: D = C

// After optimization
Statement1: D = B + 1  // Merged!
```

2. **Platform Independence**
```cpp
// Same statements can generate:
- Bytecode (for VM)
- C++ code (for nativization)
- Debug output (for tools)
```

3. **Easier Validation**
```cpp
// Check for errors at statement level
if (Statement.LHS == nullptr) {
    Error("Assignment has no target!");
}
```

## The Compilation Flow

```cpp
void CompileNode(UK2Node* Node)
{
    // Step 1: Node handler creates statements
    FNodeHandlingFunctor* Handler = GetHandler(Node);
    Handler->Compile(Context, Node);

    // Step 2: Statements go into context
    Context.AllGeneratedStatements.Add(NewStatement);

    // Step 3: Backend converts to bytecode (later)
    Backend.GenerateBytecode(Context.AllGeneratedStatements);
}
```

## Statement Optimization

Before becoming bytecode, statements get **optimized**:

```cpp
// Adjacent gotos
Goto Label1
Label1:  // Removed!

// Dead code
Return
CallFunction  // Never reached - removed!

// Redundant assignments
A = B
A = C  // First one removed!
```

## Debug Sites

Special statements for debugging:

```cpp
Statement {
    Type: KCST_DebugSite
    SourceNode: MyNode  // Breakpoint here!
}
```

These become **breakpoint locations** in the debugger!

## Quick Takeaway

- Statements are the **intermediate language** between nodes and bytecode
- Each statement has a **type** (what to do) and **terminals** (data)
- **LHS** = output/target, **RHS** = inputs/sources
- Statements enable **optimization** before bytecode generation
- They're **platform-independent** (can generate different outputs)
- Think of them as **assembly language** for Blueprint!

## The Assembly Line

Your nodes go through this pipeline:
1. Visual node (what you see)
2. Statement (structured operation)
3. Bytecode (what runs)

Statements are where the **real compilation** happens!

## Want More Details?

For complete statement breakdown:
- [From Blueprint to Bytecode I - FBlueprintCompiledStatement](/posts/bpvm-bytecode-I/#fblueprintcompiledstatement)
- [From Blueprint to Bytecode IV - Statement Processing](/posts/bpvm-bytecode-IV/)

Next: How the DAG Scheduler orders your nodes!

---

**🍿 BPVM Snack Pack Series**
- [← #11: Linking and Binding](/posts/bpvm-snack-11-linking-binding/)
- **#12: Statements 101** ← You are here
- [#13: The DAG Scheduler](/posts/bpvm-snack-13-dag-scheduler/) →