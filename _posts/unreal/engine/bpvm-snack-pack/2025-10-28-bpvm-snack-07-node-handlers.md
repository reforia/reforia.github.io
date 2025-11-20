---
layout: post
title: "BPVM Snack Pack #7 - Node Handlers: The Translation Squad"
description: "Every node in your Blueprint needs a translator. Meet the Node Handlers - the unsung heroes that turn your visual nodes into executable code."
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

## The Translation Problem

You drag a "Select" node into your Blueprint. You connect some pins. You hit compile.

But wait - how does that visual node become actual executable code?

![Select node in Blueprint editor](bytecode_selectnode.png){: width="500" }

## Enter the Node Handlers

Every node type has a **dedicated translator** called a Node Handler:

```cpp
// For every UK2Node type...
UK2Node_Select  →  FKCHandler_Select
UK2Node_CallFunction  →  FKCHandler_CallFunction
UK2Node_VariableGet  →  FKCHandler_VariableGet
// ... hundreds more!
```

Think of them as **specialized translators** at the UN:
- Each handler speaks one "node language"
- They all translate to the same "bytecode language"
- Without them, your nodes are just pretty pictures!

## The Handler Pattern

Every handler follows the same pattern:

```cpp
class FKCHandler_Select : public FNodeHandlingFunctor
{
public:
    // Step 1: "What data do I need?"
    virtual void RegisterNets(FKismetFunctionContext& Context, UEdGraphNode* Node);

    // Step 2: "How do I translate this?"
    virtual void Compile(FKismetFunctionContext& Context, UEdGraphNode* Node);
};
```

Two jobs, crystal clear separation of concerns!

## RegisterNets: The Setup Phase

Before compiling, handlers need to **register their data needs**:

```cpp
void FKCHandler_Select::RegisterNets(Context, Node)
{
    // "I need storage for these pins!"

    // Register the index pin
    FBPTerminal* IndexTerm = Context.CreateLocalTerminal();
    Context.NetMap.Add(IndexPin, IndexTerm);

    // Register each option pin
    for (UEdGraphPin* Pin : OptionPins) {
        FBPTerminal* Term = Context.CreateLocalTerminal();
        Context.NetMap.Add(Pin, Term);
    }

    // Register output
    FBPTerminal* OutputTerm = Context.CreateLocalTerminal();
    Context.NetMap.Add(OutputPin, OutputTerm);
}
```

It's like declaring variables before using them - **reserve the memory first**!

## Compile: The Translation Phase

Now the actual translation happens:

```cpp
void FKCHandler_Select::Compile(Context, Node)
{
    // Create the bytecode statement
    FBlueprintCompiledStatement* Statement = new FBlueprintCompiledStatement();
    Statement->Type = KCST_SwitchValue;  // "This is a switch operation"

    // Get our registered terminals
    FBPTerminal* IndexTerm = Context.NetMap.FindRef(IndexPin);
    FBPTerminal* OutputTerm = Context.NetMap.FindRef(OutputPin);

    // Build the switch logic
    Statement->LHS = OutputTerm;  // Where to store result
    Statement->RHS.Add(IndexTerm);  // What to switch on

    // Add each case
    for (int32 i = 0; i < Options.Num(); i++) {
        Statement->RHS.Add(OptionTerms[i]);
    }
}
```

## Real Example: The Select Node

Let's see how a Select node gets translated:

**What You See:**
```
Index: 2
Option 0: "Hello"
Option 1: "World"
Option 2: "!"      <-- Selected!
Output: "!"
```

**What RegisterNets Does:**
```cpp
// Reserve memory slots
Terminal_0 = Index (integer)
Terminal_1 = Option0 (string)
Terminal_2 = Option1 (string)
Terminal_3 = Option2 (string)
Terminal_4 = Output (string)
```

**What Compile Creates:**
```cpp
Statement: KCST_SwitchValue
LHS: Terminal_4 (output)
RHS: [
    Terminal_0,  // Index
    Terminal_1,  // Case 0
    Terminal_2,  // Case 1
    Terminal_3   // Case 2
]
```

## The Handler Registry

The compiler maintains a **giant map** of handlers:

```cpp
// During compiler initialization
NodeHandlers.Add(UK2Node_Select::StaticClass(), new FKCHandler_Select());
NodeHandlers.Add(UK2Node_CallFunction::StaticClass(), new FKCHandler_CallFunction());
NodeHandlers.Add(UK2Node_VariableGet::StaticClass(), new FKCHandler_VariableGet());
// ... hundreds more
```

When compiling your graph:
```cpp
for (UEdGraphNode* Node : Graph->Nodes) {
    // Find the right translator
    FNodeHandlingFunctor* Handler = NodeHandlers.FindRef(Node->GetClass());

    if (Handler) {
        Handler->RegisterNets(Context, Node);  // Setup
        Handler->Compile(Context, Node);        // Translate
    }
}
```

## Why Two Phases?

**Why not just compile directly?**

The compiler needs to know about ALL variables before generating code:

```cpp
// Bad: Compile as we go
CompileNode(A);  // Creates var X
CompileNode(B);  // Needs var X... does it exist?

// Good: Two phases
RegisterNets(A);  // Declare var X
RegisterNets(B);  // Declare var Y
Compile(A);       // Use var X (guaranteed to exist)
Compile(B);       // Use var X and Y (both exist!)
```

## Special Handler Powers

Some handlers have **special abilities**:

```cpp
class FKCHandler_CallFunction : public FNodeHandlingFunctor
{
    // Special power: Can optimize certain calls!
    virtual void Transform(FKismetFunctionContext& Context, UEdGraphNode* Node) {
        // Convert Print(String) to fastpath if possible
    }

    // Special power: Runs early for signatures!
    virtual bool RequiresRegisterNetsBeforeScheduling() {
        return true;  // Function entry/exit nodes need this
    }
};
```

## The Statement Output

Handlers produce **intermediate statements** (not bytecode yet!):

```cpp
// Handler produces this:
Statement {
    Type: KCST_CallFunction
    Function: "PrintString"
    Parameters: ["Hello World"]
}

// Backend converts to bytecode later:
0x44 (EX_CallFunc)
0x08 (Function ID)
"Hello World"
0x53 (EX_Return)
```

It's a **two-stage rocket** - handlers get you to orbit, backend gets you to the moon!

## Quick Takeaway

- Every node type has a **Node Handler** (its personal translator)
- **RegisterNets**: "I need these variables" (setup phase)
- **Compile**: "Here's how to execute me" (translation phase)
- Handlers produce **statements**, not bytecode (that comes later)
- Two phases ensure all variables exist before use
- It's the **Strategy Pattern** in action - one handler per node type!

## Your Nodes Come Alive

Next time you drag a node into your Blueprint, remember:
- That node has a dedicated handler waiting to translate it
- RegisterNets runs first to set up the workspace
- Compile runs second to generate the logic
- Without handlers, your nodes would just be pretty pictures!

## Want More Details?

For the complete handler deep-dive:
- [From Blueprint to Bytecode I - Node Handlers](/posts/bpvm-bytecode-I/#fnodehandlingfunctor)
- [From Blueprint to Bytecode IV - Statement Generation](/posts/bpvm-bytecode-IV/)

Next snack: The magic of Clean and Sanitize!

---

**🍿 BPVM Snack Pack Series**
- [← #6: The CDO Mystery](/posts/bpvm-snack-06-cdo-mystery/)
- **#7: Node Handlers Explained** ← You are here
- [#8: Clean and Sanitize Magic](/posts/bpvm-snack-08-clean-sanitize/) →