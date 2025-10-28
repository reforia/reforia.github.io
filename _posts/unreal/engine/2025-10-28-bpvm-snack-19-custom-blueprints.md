---
layout: post
title: "BPVM Snack Pack #19 - Custom Blueprints: Extending the System"
description: "Now you understand how Blueprint compiles. Want to create your own custom Blueprint types with special compilation rules? Here's how the extension system works."
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

## Beyond Regular Blueprints

Animation Blueprints, Widget Blueprints, Gameplay Ability Blueprints - they all use **custom compilation**!

You can create your own too!

## The Extension Points

The Blueprint system has **hooks** everywhere:

```cpp
class UBlueprint {
    // Custom blueprint type
    TSubclassOf<UBlueprint> BlueprintClassType;

    // Custom compiler
    TSubclassOf<FKismetCompilerContext> CompilerType;

    // Custom nodes
    TArray<UEdGraphNode*> CustomNodes;

    // Extension hooks
    TArray<UBlueprintExtension*> Extensions;
};
```

You can customize **every stage**!

## Custom Blueprint Class

Create your own Blueprint type:

```cpp
// YourCustomBlueprint.h
UCLASS()
class UCustomBlueprint : public UBlueprint
{
    GENERATED_BODY()

    // Custom data
    UPROPERTY()
    TArray<FCustomData> SpecialData;

    // Override compilation
    virtual FKismetCompilerContext* CreateCompilerContext() override;
};
```

Now you have a **new asset type** in the editor!

## Custom Compiler Context

Control how your Blueprint compiles:

```cpp
class FCustomCompilerContext : public FKismetCompilerContext
{
public:
    FCustomCompilerContext(UCustomBlueprint* Blueprint)
        : FKismetCompilerContext(Blueprint)
    {}

    // Override compilation stages
    virtual void SpawnNewClass(const FString& NewClassName) override;
    virtual void CreateFunctionList() override;
    virtual void CompileClassLayout() override;

    // Add custom validation
    virtual void ValidateCustomData();

    // Add custom nodes
    virtual void RegisterCustomNodes();
};
```

Total control over **every compilation stage**!

## Custom Node Types

Create special nodes for your Blueprint:

```cpp
UCLASS()
class UK2Node_CustomOperation : public UK2Node
{
    GENERATED_BODY()

    // Custom node behavior
    virtual void ExpandNode(FKismetCompilerContext& Context) override;

    // Custom compilation
    virtual FNodeHandlingFunctor* CreateNodeHandler(FKismetCompilerContext& Context) override;
};

// Custom handler
class FKCHandler_CustomOperation : public FNodeHandlingFunctor
{
    virtual void RegisterNets(Context, Node) override {
        // Register custom terminals
    }

    virtual void Compile(Context, Node) override {
        // Generate custom statements
    }
};
```

Your nodes can do **anything**!

## Real Example: Animation Blueprint

Animation Blueprints extend the system:

```cpp
class UAnimBlueprint : public UBlueprint
{
    // Custom graph types
    UPROPERTY()
    UAnimationGraph* AnimGraph;

    UPROPERTY()
    UAnimationStateMachineGraph* StateMachineGraph;

    // Custom compiler
    virtual FKismetCompilerContext* CreateCompilerContext() override {
        return new FAnimBlueprintCompilerContext(this);
    }
};
```

The compiler adds **state machine compilation**!

## Animation Compiler Extensions

```cpp
class FAnimBlueprintCompilerContext : public FKismetCompilerContext
{
    virtual void CreateFunctionList() override {
        // Call base implementation
        FKismetCompilerContext::CreateFunctionList();

        // Add custom: Process state machines!
        ProcessStateMachines();
        ProcessAnimationNodes();
    }

    void ProcessStateMachines() {
        // Convert state machine graph to bytecode
        for (auto* StateMachine : AnimBP->StateMachines) {
            CompileStateMachine(StateMachine);
        }
    }
};
```

## Custom Validation

Add special checks:

```cpp
class FCustomCompilerContext : public FKismetCompilerContext
{
    virtual void ValidateLink() override {
        // Base validation
        FKismetCompilerContext::ValidateLink();

        // Custom validation
        if (!Blueprint->HasSpecialProperty()) {
            Error("Custom Blueprint requires SpecialProperty!");
        }

        if (FunctionCount > MAX_FUNCTIONS) {
            Warning("Too many functions for optimal performance");
        }
    }
};
```

## Blueprint Extensions

Add functionality without subclassing:

```cpp
UCLASS()
class UMyBlueprintExtension : public UBlueprintExtension
{
    GENERATED_BODY()

    // Called during compilation
    virtual void HandleBeginCompilation(FCompilerContext& Context) override {
        // Inject custom behavior
    }

    virtual void HandleEndCompilation(FCompilerContext& Context) override {
        // Post-process compiled class
    }
};

// Register extension
MyBlueprint->Extensions.Add(NewObject<UMyBlueprintExtension>());
```

Extensions are **modular**!

## Custom Generated Class

Control the generated class:

```cpp
UCLASS()
class UCustomBlueprintGeneratedClass : public UBlueprintGeneratedClass
{
    GENERATED_BODY()

    // Custom runtime data
    UPROPERTY()
    TArray<FRuntimeData> SpecialRuntimeData;

    // Custom initialization
    virtual void InitializeCustomData();
};
```

## Graph Schema Customization

Control what nodes are allowed:

```cpp
class UCustomGraphSchema : public UEdGraphSchema_K2
{
    // Override node creation
    virtual void GetGraphContextActions(FGraphContextMenuBuilder& Context) override {
        // Add custom nodes to context menu
        Context.AddAction(NewCustomNodeAction());
    }

    // Override connection rules
    virtual bool CanCreateConnection(const UEdGraphPin* A, const UEdGraphPin* B) override {
        // Custom connection validation
        return IsValidCustomConnection(A, B);
    }
};
```

## Real-World Use Cases

**State Machine Blueprints:**
- Custom graph types for states
- Special compilation for transitions
- Runtime state execution

**Gameplay Ability Blueprints:**
- Ability-specific nodes
- Prediction compilation
- Network replication handling

**Behavior Tree Blueprints:**
- Custom task nodes
- Special decorators
- AI-specific compilation

## Quick Takeaway

- Blueprint system is **fully extensible**
- Create custom **Blueprint subclasses**
- Override **compiler context** for custom compilation
- Add **custom node types** with handlers
- Use **Blueprint extensions** for modularity
- Control **schema** for allowed nodes
- Examples: Animation, Widget, Gameplay Ability Blueprints
- Total control over **compilation pipeline**!

## The Power of Extension

The Blueprint system isn't just for gameplay - it's a framework for **visual scripting systems**. Understanding the compilation pipeline lets you create powerful custom tools that look and feel like native Unreal features!

## Want More Details?

For complete custom Blueprint guide:
- [Unreal Documentation: Custom Blueprints](https://dev.epicgames.com/documentation/en-us/unreal-engine/custom-blueprints-in-unreal-engine)
- Animation Blueprint source code
- Widget Blueprint source code

Final snack: Where to go from here!

---

**🍿 BPVM Snack Pack Series**
- [← #18: Why Blueprint is Slower](/posts/bpvm-snack-18-blueprint-slower/)
- **#19: Custom Blueprints** ← You are here
- [#20: The Journey Ahead](/posts/bpvm-snack-20-journey-ahead/) →