---
layout: post
title: "From Blueprint to Bytecode I - But what is Blueprint? "
description:
  Curiosity calls adventurers to embark towards an ancient castle - Blueprint. We've heard a lot about how to wield it's magical power over the decades. But little did we know what's actually beneath it. So buckle up, because we are going deep.
date: 2024-12-21 18:27 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Preface
Unreal Engine is renowned for its powerful visual scripting system—Blueprint (formerly `Kismet`). There are countless tutorials and guides available on how to use Blueprint, but fewer resources explain how it actually works behind the scenes. When we drag and drop nodes in the visual graph, hit the compile button, and see the “Good to go” message, it’s easy to think everything’s just ready to run. But what's really happening under the hood? How does the Blueprint Virtual Machine (`BPVM`) interpret and execute the graph? This series of posts will dig into these questions. So, buckle up and let’s dive in.

![Compile, Save and Good to go](bytecode_hitcompile.png){: width="500" }

## Previous Researches
Epic has published a [document] that offers a brief overview of how the Blueprint compilation process works, but it only scratches the surface and doesn’t dive into the details. Fortunately, the community has contributed some great research as well. For BPVM, there’s the [Blueprint VM], and for Blueprint Compilation, there are [Blueprint I], [Blueprint II], and [Blueprint III].

> The blogs linked above are written in Chinese. For English readers, a translation tool like ChatGPT could be helpful. {: .prompt-tip}

While these posts are high-quality and definitely worth reading, we’ll still walk through the key concepts and terminology in a more comprehensive way to establish a common understanding as we tackle the next challenges.

## Blueprint System
When people talk about a "well-written Blueprint," they’re typically referring to the visual scripting graph created within the Blueprint Editor. Internally, this graph is managed by a `UEdGraph` object. However, it’s important to note that the graph (such as the Event Graph) is not the Blueprint Editor itself, but rather a part of it. The Blueprint Editor is a combination of multiple `UEdGraph`s, panels, tools, and more.

To put it simply, creating a Blueprint Asset in the Content Browser starts with selecting a parent class and defining a new subclass through the Blueprint system. The Blueprint Editor lets us add functions and logic within `UEdGraph` instances and set up various properties. When we click the compile button in the editor, it triggers the compilation process, processing the content in the `UEdGraph` and encapsulating it into a reusable `UBlueprintGeneratedClass`. This class contains bytecode that the engine executes during runtime, ensuring that the behaviors and logic we’ve defined are integrated into the game.

![Blueprint System Overview](bytecode_blueprintflow.png)
_Blueprint System Overview_

![Blueprint Structure](bytecode_blueprintstructure.png)
_Blueprint Structure (Source: [1])_ 

### UBlueprint
When we create a new Blueprint based on a custom class type (e.g., `ACustomClass`) from the Content Browser, we’re actually creating a Blueprint Asset—more specifically, a `UBlueprint` object. This object exists solely within the editor environment. The resulting asset will have a `.uasset` file extension on disk, which is the serialized form of the `UBlueprint` object.

Let's take a look at the code:

```cpp
/** Create a new Blueprint and initialize it to a valid state. */
UBlueprint* FKismetEditorUtilities::CreateBlueprint(UClass* ParentClass, UObject* Outer, const FName NewBPName, EBlueprintType BlueprintType, TSubclassOf<UBlueprint> BlueprintClassType, TSubclassOf<UBlueprintGeneratedClass> BlueprintGeneratedClassType, FName CallingContext)
{
    // ... Other code

    // Create new UBlueprint object
    UBlueprint* NewBP = NewObject<UBlueprint>(Outer, *BlueprintClassType, NewBPName, RF_Public | RF_Standalone | RF_Transactional | RF_LoadCompleted);
    // ... Other code
    NewBP->ParentClass = ParentClass;
    // ... Other code

    return NewBP;
}
```

When we call `FKismetEditorUtilities::CreateBlueprint()`, it immediately creates a `UBlueprint` instance and sets `NewBP->ParentClass` to the specified `ParentClass` (in this case, `ACustomClass`). This is why some documents describe the created Blueprint as a subclass of `ACustomClass`. However, this statement is technically incorrect. What actually happens is that a `UBlueprint` object is created, and it holds a pointer to `ParentClass` (i.e., `ACustomClass`), but it’s not a subclass of it.

### UBlueprintGeneratedClass
As mentioned earlier, when executing a Blueprint’s logic, we’re not running the `UBlueprint` object directly (since it only exists in the editor). Instead, we’re executing the compiled bytecode stored in a compiled version of the `UBlueprint` object, which is known as `UBlueprintGeneratedClass`.

>Technically, the Blueprint Editor triggers the generation of the `UBlueprintGeneratedClass`, but that’s merely a placeholder. The actual compilation process is handled by `FKismetCompilerContext`, which compiles the visual scripting nodes into executable code (bytecode) and writes this back into the `UBlueprintGeneratedClass`.
{: .prompt-info}

Just as `UBlueprint` is *NOT* a subclass of `ACustomClass`, `UBlueprintGeneratedClass` is also *NOT* a subclass of `ACustomClass`. This means there’s no such thing as:

```cpp
class UBlueprintGeneratedClass : public ACustomClass
{
    // ...
};
```

Instead, the `UBlueprintGeneratedClass` is already declared in `BlueprintGeneratedClass.h` as: 

```cpp
class UBlueprintGeneratedClass : public UClass, public IBlueprintPropertyGuidProvider
{
    // ...
};
```

The `UBlueprintGeneratedClass` differs slightly from the `UBlueprint` object. While the asset we see in the Content Browser is actually an instance of `UBlueprint` (which is a `UObject` and serialized as a `.uasset`), the `UBlueprintGeneratedClass` is just a class, not an instance. The relationship between `UBlueprintGeneratedClass` and its parent class is managed using the `SuperClass` mechanism. When setting the parent class, Unreal Engine uses `SetSuperStruct()`, and when retrieving it, `GetSuperClass()` is used. This allows the `UBlueprintGeneratedClass` to appear as though it is a subclass of another `UClass`.

Here’s the code right after the `UBlueprint` instance is created:

```cpp
/** Create a new Blueprint and initialize it to a valid state. */
UBlueprint* FKismetEditorUtilities::CreateBlueprint(UClass* ParentClass, UObject* Outer, const FName NewBPName, EBlueprintType BlueprintType, TSubclassOf<UBlueprint> BlueprintClassType, TSubclassOf<UBlueprintGeneratedClass> BlueprintGeneratedClassType, FName CallingContext)
{
    // ... Other code

    // Create SimpleConstructionScript and UserConstructionScript
    if (FBlueprintEditorUtils::SupportsConstructionScript(NewBP))
    { 
        // ... Other code
        UBlueprintGeneratedClass* NewClass = NewObject<UBlueprintGeneratedClass>(
            NewBP->GetOutermost(), *BlueprintGeneratedClassType, NewGenClassName, RF_Public | RF_Transactional);
        NewBP->GeneratedClass = NewClass;
        NewClass->ClassGeneratedBy = NewBP;
        NewClass->SetSuperStruct(ParentClass);
        // <<< Temporary workaround
    }

    // ... Other code

    return NewBP;
}
```

### UEdGraph
An `UEdGraph` represents a graph, which is essentially a collection of nodes and connections. In the context of Blueprint, `UEdGraph` is used to represent the data within the visual scripting graph, such as the Event Graph, Function Graph, and Macro Graph. The `UEdGraph` manages the nodes and connections within the graph and provides the necessary interfaces for the Blueprint Editor to interact with it.

`UEdGraph` has several subclasses, including `UAIGraph`, `UAnimationGraph`, `UAnimationStateMachineGraph`, `UMaterialGraph`, and more. Essentially, when you open an asset and see a space where you can drag and drop nodes, the underlying type is usually an `UEdGraph`.

It’s important to note that `UEdGraph` is just the representation of the graph, not its visual display. The actual visual representation of the graph we see in the editor is handled by a Slate UI widget called `SGraphEditor`. This widget is responsible for rendering the graph and providing the frontend interactions.

![UEdGraph](bytecode_uedgraph.png)
_UEdGraph (Source: [1])_

### UEdGraphNode
`UEdGraphNode` is a fundamental class that represents a node in an Unreal Engine graph. It is part of the graph's data structure and holds the logic and properties of individual nodes within the graph, whether it’s for Event Graphs, Function Graphs, or other types of graphs.

Each `UEdGraphNode` contains the necessary logic and data to execute or represent an operation in the graph. For example, a node might represent a function call, a variable assignment, or an action like “Print String.”

There are various subclasses of `UEdGraphNode`, such as `UAnimStatesNode`, `UNiagaraNode`, and more. These subclasses introduce functionality specific to the type of graph in use. It’s worth noting that Blueprint Graph nodes aren’t called `UBlueprintNode`; they’re referred to as `UK2Node`.

![UEdGraphNode](bytecode_uk2nodes.png){: width="500" }
_Various UK2Nodes_

Just like `UEdGraph`, `UEdGraphNode` also has a visual representation, which is handled by `SGraphNode`.

![UEdGraphNode](bytecode_uedgraphnode.png)
_UEdGraphNode (Source: [1])_

### UEdGraphPin
`UEdGraphNode` maintains connections to other nodes through `UEdGraphPin` objects, which enable the flow of execution or data between nodes.

A `UEdGraphPin` serves as a communication point between nodes. It can be either an input pin (where data flows into the node) or an output pin (where data flows out of the node).

Each pin can be connected to other pins, and the system enforces type compatibility between them. For example, connecting an integer pin to a float pin is allowed because an implicit cast can be performed, but connecting incompatible types is illegal.

Just like nodes, pins have a visual representation in the Blueprint Editor. Users can connect them using drag-and-drop interactions, which are managed by the `SGraphPin` class.

### UEdGraphSchema
`UEdGraphSchema` defines the rules and conventions for a specific type of graph. It essentially acts as a blueprint (literally) for how nodes and pins interact, providing a way to describe valid node connections, node actions, and ensuring the graph behaves as expected.

Each type of graph (Blueprint, Animation, AI, etc.) has its own corresponding `UEdGraphSchema` subclass. For example:

![UEdGraphSchema](bytecode_otherschemas.png){: width="500" }
_Other Schemas_

The `UEdGraphSchema` can also define custom rules for creating and placing nodes within the graph. For instance, it determines which nodes are available when a user right-clicks to add a new node. Additionally, it defines the rules for linking pins between nodes, such as which types of pins can connect to each other or how connections should be made.

![UEdGraphSchema](bytecode_uedgraphschema.png)
_UEdGraphSchema (Source: [1])_

### FKismetCompilerContext
`FKismetCompilerContext` is the core class responsible for compiling a Blueprint graph into executable bytecode that the Blueprint Virtual Machine (VM) can interpret. This class is the main driver of the compilation process, handling tasks like node translation, validation, and generating the intermediate representation.

The `FKismetCompilerContext` first translates the visual scripting graphs (represented as `UEdGraph`, `UEdGraphNode`, and others) into an intermediate format consisting of `FBlueprintCompiledStatement` objects. These statements will eventually be compiled into bytecode that the VM can execute. It manages the flow of the compilation process, ensuring that all nodes in the graph are correctly translated and connected.

![FKismetCompilerContext](bytecode_fkismetcompilercontext.png)
_FKismetCompilerContext (Source: [1])_

### FKismetFunctionContext
`FKismetFunctionContext` represents the compilation context for a single function or graph within a Blueprint. It acts as a container for all the data needed to compile a specific function, such as variable definitions, control flow, and individual statements.

The `FKismetFunctionContext` tracks the local state of a function during compilation, including variables, temporaries, and flow control structures. It ensures that all nodes within the function are translated into valid intermediate representations (`FBlueprintCompiledStatement`).

### FBlueprintCompiledStatement
`FBlueprintCompiledStatement` is an intermediate representation of a single executable operation within a Blueprint graph. In other words, a function can have multiple `FBlueprintCompiledStatement` objects.

Each `FBlueprintCompiledStatement` represents a specific operation in the graph. These statements are generated during the compilation process and are later converted into VM bytecode. Below is a full list of `FBlueprintCompiledStatement` types from `BlueprintCompiledStatement.h`:

```cpp
//////////////////////////////////////////////////////////////////////////
// FBlueprintCompiledStatement

enum EKismetCompiledStatementType
{
    KCST_Nop = 0,
    // [wiring =] TargetObject->FunctionToCall(wiring)
    KCST_CallFunction = 1,
    // TargetObject->TargetProperty = [wiring]
    KCST_Assignment = 2,
    // One of the other types with a compilation error during statement generation
    KCST_CompileError = 3,
    // goto TargetLabel
    KCST_UnconditionalGoto = 4,
    // FlowStack.Push(TargetLabel)
    KCST_PushState = 5,
    // [if (!TargetObject->TargetProperty)] goto TargetLabel
    KCST_GotoIfNot = 6,
    // return TargetObject->TargetProperty
    KCST_Return = 7,
    // if (FlowStack.Num()) { NextState = FlowStack.Pop; } else { return; }
    KCST_EndOfThread = 8,
    // Comment
    KCST_Comment = 9,
    // NextState = LHS;
    KCST_ComputedGoto = 10,
    // [if (!TargetObject->TargetProperty)] { same as KCST_EndOfThread; }
    KCST_EndOfThreadIfNot = 11,
    // NOP with recorded address
    KCST_DebugSite = 12,
    // TargetInterface(TargetObject)
    KCST_CastObjToInterface = 13,
    // Cast<TargetClass>(TargetObject)
    KCST_DynamicCast = 14,
    // (TargetObject != None)
    KCST_ObjectToBool = 15,
    // TargetDelegate->Add(EventDelegate)
    KCST_AddMulticastDelegate = 16,
    // TargetDelegate->Clear()
    KCST_ClearMulticastDelegate = 17,
    // NOP with recorded address (never a step target)
    KCST_WireTraceSite = 18,
    // Creates simple delegate
    KCST_BindDelegate = 19,
    // TargetDelegate->Remove(EventDelegate)
    KCST_RemoveMulticastDelegate = 20,
    // TargetDelegate->Broadcast(...)
    KCST_CallDelegate = 21,
    // Creates and sets an array literal term
    KCST_CreateArray = 22,
    // TargetInterface(Interface)
    KCST_CrossInterfaceCast = 23,
    // Cast<TargetClass>(TargetObject)
    KCST_MetaCast = 24,
    KCST_AssignmentOnPersistentFrame = 25,
    // Cast<TargetClass>(TargetInterface)
    KCST_CastInterfaceToObj = 26,
    // goto ReturnLabel
    KCST_GotoReturn = 27,
    // [if (!TargetObject->TargetProperty)] goto TargetLabel
    KCST_GotoReturnIfNot = 28,
    KCST_SwitchValue = 29,
    
    KCST_DoubleToFloatCast = 30,
    KCST_FloatToDoubleCast = 31,

    //~ Kismet instrumentation extensions:

    // Instrumented event
    KCST_InstrumentedEvent,
    // Instrumented event stop
    KCST_InstrumentedEventStop,
    // Instrumented pure node entry
    KCST_InstrumentedPureNodeEntry,
    // Instrumented wiretrace entry
    KCST_InstrumentedWireEntry,
    // Instrumented wiretrace exit
    KCST_InstrumentedWireExit,
    // Instrumented state push
    KCST_InstrumentedStatePush,
    // Instrumented state restore
    KCST_InstrumentedStateRestore,
    // Instrumented state reset
    KCST_InstrumentedStateReset,
    // Instrumented state suspend
    KCST_InstrumentedStateSuspend,
    // Instrumented state pop
    KCST_InstrumentedStatePop,
    // Instrumented tunnel exit
    KCST_InstrumentedTunnelEndOfThread,

    KCST_ArrayGetByRef,
    KCST_CreateSet,
    KCST_CreateMap,
};
```

### FBPTerminal
`FBPTerminal` represents a variable or expression used within a `FBlueprintCompiledStatement`. It serves as a handle for data or objects in the Blueprint graph.

![FBPTerminal](bytecode_fbpterminal.png){: width="400"}
_"Hello World" Literal FBPTerminal_

### FNodeHandlingFunctor
`FNodeHandlingFunctor` is an abstraction used to handle the translation of specific node types during the compilation process. Each `UEdGraphNode` type has an associated `FNodeHandlingFunctor` that understands how to convert that node into an intermediate representation (`FBlueprintCompiledStatement`).

![FNodeHandlingFunctor](bytecode_fnodehandlingfunctor.png)
_FNodeHandlingFunctor (Source: [1])_

Each `UK2Node` subclass has a corresponding `FNodeHandlingFunctor` subclass, which defines how that specific node should be compiled. For example:

```cpp
//////////////////////////////////////////////////////////////////////////
// FKCHandler_Select

class FKCHandler_Select : public FNodeHandlingFunctor
{
protected:
    TMap<UEdGraphNode*, FBPTerminal*> DefaultTermMap;

public:
    FKCHandler_Select(FKismetCompilerContext& InCompilerContext)
        : FNodeHandlingFunctor(InCompilerContext);

    virtual void RegisterNets(FKismetFunctionContext& Context, UEdGraphNode* Node) override;

    virtual void Compile(FKismetFunctionContext& Context, UEdGraphNode* Node) override;
};
```

As shown above, `FKCHandle_Select` is associated with `UK2Node_Select`. It implements two key functions: `RegisterNets()` and `Compile()`.

![FKCHandler_Select](bytecode_selectnode.png){: width="400"}
_Select Node_

#### RegisterNets()
`RegisterNets()` is responsible for registering the input and output pins of the node. It creates the necessary `FBPTerminal` objects to represent these pins. For example, if anything is connected to the options pin or the index pin, they are registered during this step. This function is called in both `PrecompileFunction()` and `CreateLocalsAndRegisterNets()`.

```cpp
/**
 * First phase of compiling a function graph
 *   - Prunes the 'graph' to only included the connected portion that contains the function entry point 
 *   - Schedules execution of each node based on data dependencies
 *   - Creates a UFunction object containing parameters and local variables (but no script code yet)
 */
void FKismetCompilerContext::PrecompileFunction(FKismetFunctionContext& Context, EInternalCompilerFlags InternalFlags)
{
    // ... Other Code

    if (EntryPoints.Num())
    {
        Context.EntryPoint = EntryPoints[0];

        // Register nets from function entry/exit nodes first, even for skeleton compiles (as they form the signature)
        // We're violating the FNodeHandlingFunctor abstraction here because we want to make sure that the signature
        // matches even if all result nodes were pruned:
        bool bReturnNodeFound = false;
        for (UEdGraphNode* Node : Context.SourceGraph->Nodes)
        {
            // ... Other Code

            if (FNodeHandlingFunctor* Handler = NodeHandlers.FindRef(Node->GetClass()))
            {
                if (Handler->RequiresRegisterNetsBeforeScheduling())
                {
                    Handler->RegisterNets(Context, Node);
                }
            }
        }
        // ... Other Code
    }
}

void FKismetCompilerContext::CreateLocalsAndRegisterNets(FKismetFunctionContext& Context, FField**& FunctionPropertyStorageLocation)
{
    // ... Other Code
    if (bIsFullCompile)
    {
        // ... Other Code

        // Register nets for any nodes still in the schedule (as long as they didn't get registered in the initial all-nodes pass)
        for (UEdGraphNode* Node : Context.LinearExecutionList)
        {
            if (FNodeHandlingFunctor* Handler = NodeHandlers.FindRef(Node->GetClass()))
            {
                if (!Handler->RequiresRegisterNetsBeforeScheduling())
                {
                    Handler->RegisterNets(Context, Node);
                }
            }
            // ... Other Code
        }
    }
    // ... Other Code
}
```

`CreateLocalsAndRegisterNets()` can be called in either `PrecompileFunction()` or `CompileFunction()`. The reason we say "or" is that, normally, `PrecompileFunction()` will call it, but if `EInternalCompilerFlags::PostponeLocalsGenerationUntilPhaseTwo` is passed as a parameter, `PrecompileFunction()` will skip this step. In that case, `CompileFunction()` will call it later during "Phase Two."

>`EInternalCompilerFlags::PostponeLocalsGenerationUntilPhaseTwo` is passed to `CompileFunction()` in `FBlueprintCompilationManagerImpl::FlushCompilationQueueImpl()`. `BlueprintCompilationManager` is a large topic in itself, so we won't dive into it here.
{: .prompt-info}

#### Compile()
The `Compile()` function is responsible for generating the intermediate representation (`FBlueprintCompiledStatement`) for the node, based on its input and output pins. Let's take a closer look:

```cpp
virtual void Compile(FKismetFunctionContext& Context, UEdGraphNode* Node) override
{
    // I. Declare FBPTerminals
    UK2Node_Select* SelectNode = CastChecked<UK2Node_Select>(Node);
    FBPTerminal* DefaultTerm = nullptr;
    FBPTerminal* ReturnTerm = nullptr;
    FBPTerminal* IndexTerm = nullptr;

    {
        // II. Try to get value for these terms
        // ... Other Code
    }

    // III. Create FBlueprintCompiledStatement for SelectNode
    FBlueprintCompiledStatement* SelectStatement = new FBlueprintCompiledStatement();
    SelectStatement->Type = EKismetCompiledStatementType::KCST_SwitchValue;

    // IV. Get the option pins
    TArray<UEdGraphPin*> OptionPins;
    SelectNode->GetOptionPins(OptionPins);

    // V. Go through each option and add their value to SelectStatement
    for (int32 OptionIdx = 0; OptionIdx < OptionPins.Num(); ++OptionIdx)
    {
        {
            FBPTerminal* LiteralTerm = Context.CreateLocalTerminal(ETerminalSpecification::TS_Literal);
            // ... Other Code
            SelectStatement->RHS.Add(LiteralTerm);
        }
        {
            UEdGraphPin* NetPin = OptionPins[OptionIdx] ? FEdGraphUtilities::GetNetFromPin(OptionPins[OptionIdx]) : nullptr;
            FBPTerminal** ValueTermPtr = NetPin ? Context.NetMap.Find(NetPin) : nullptr;
            FBPTerminal* ValueTerm = ValueTermPtr ? *ValueTermPtr : nullptr;

            // ... Other Code
            SelectStatement->RHS.Add(ValueTerm);
        }
    }

    // VI. Add DefaultTerm to SelectStatement
    SelectStatement->RHS.Add(DefaultTerm);
}
```

The `Compile()` function for the `SelectNode` essentially follows six steps:
- Declare `FBPTerminals`:
  -  It starts by declaring the necessary `FBPTerminal` objects.
- Get Values for Terms:
  - It retrieves the values for these terms.
- Create `FBlueprintCompiledStatement`:
  - A `FBlueprintCompiledStatement` is created for the SelectNode, and its type is set to `KCST_SwitchValue`.
- Retrieve Option Pins:
  - It then collects all the option pins.
- Process Each Option:
  - For each option, its value is added to the `SelectStatement`.
- Add Default Term:
  - Finally, the DefaultTerm is added to the `SelectStatement`.


`Literal Term` 
- For each option, a `FBPTerminal` of type Literal is created. This represents the literal value associated with that option (e.g., the index value that matches the option). If the option pin is associated with an enum, the terminal uses the enum name; otherwise, it defaults to an index-based name.

`Value Term`
- For each option pin, the corresponding value term is retrieved from the context. If it isn’t found, an error is logged. The value is then added to the RHS (right-hand side) of the operation.

At this point, it’s clear that the `Compile()` function for the `SelectNode` creates a `FBlueprintCompiledStatement`, sets its type to `KCST_SwitchValue`, and then feeds all the necessary data into the `SelectStatement` object.

### FBlueprintCompileReinstancer
`FBlueprintCompileReinstancer` is a utility class in Unreal Engine that helps with reinstancing objects when a Blueprint class is recompiled. Reinstancing is necessary because existing instances of a Blueprint class in the game world need to be updated to reflect the newly compiled version of the class.

When a Blueprint class is recompiled, changes to its structure (such as new variables or altered logic) can cause the existing instances in the game world to become out of sync with the new class definition. The `FBlueprintCompileReinstancer` ensures that these instances are properly updated or replaced, preventing crashes or inconsistencies.

### FKismetCompilerOptions
`FKismetCompilerOptions` is a configuration class that defines various options and settings used during the Blueprint compilation process. It allows customization of how Blueprints are compiled, influencing behaviors like debugging, optimization, and error handling.

`FKismetCompilerOptions` is passed to the `FKismetCompilerContext` to control specific aspects of the compilation process, such as whether debug information is generated or whether strict validation is enforced.

The header file already gives us a very clear idea of what it does:

```cpp
/** Options used for a specific invication of the blueprint compiler */
struct FKismetCompilerOptions
{
public:
    /** The compile type to perform (full compile, skeleton pass only, etc) */
    EKismetCompileType::Type    CompileType;

    /** Whether or not to save intermediate build products (temporary graphs and expanded macros) for debugging */
    bool bSaveIntermediateProducts;

    /** Whether to regenerate the skeleton first, when compiling on load we don't need to regenerate the skeleton. */
    bool bRegenerateSkelton;

    /** Whether or not this compile is for a duplicated blueprint */
    bool bIsDuplicationInstigated;

    /** Whether or not to reinstance and stub if the blueprint fails to compile */
    bool bReinstanceAndStubOnFailure;

    /** Whether or not to skip class default object validation */
    bool bSkipDefaultObjectValidation;

    /** Whether or not to update Find-in-Blueprint search metadata */
    bool bSkipFiBSearchMetaUpdate;

    /** Whether or not to use Delta Serialization when copying unrelated objects */
    bool bUseDeltaSerializationDuringReinstancing;

    /** Whether or not to skip new variable defaults detection */
    bool bSkipNewVariableDefaultsDetection;
};
```

### Skeleton Class
A `Skeleton Class` is an intermediate representation of a Blueprint class used during the compilation process. It serves as a lightweight placeholder that contains only basic information about the class structure (such as variables and functions) but without full implementation details.

>Think of the `SKEL` class as a more intelligent forward declaration or a header file. It is created before any bytecode is compiled and only provides metadata about the class structure. The key difference is that there’s no linkage process after compilation, unlike a traditional header file. 
{: .prompt-info}

The `Skeleton Class` exists to allow Blueprints to reference each other in a cyclic manner during compilation. For example, if two Blueprints reference each other, their `Skeleton Classes` are created first, resolving dependency issues. It acts as a minimal version of the class that can be used in the editor before full compilation is completed.

When one Blueprint calls a function on another Blueprint class that hasn’t been fully compiled yet, the Skeleton Class is used to temporarily represent the target class.

### CDO
The Class Default Object (CDO) is a special instance of a class that serves as the archetype for all instances of that class. It is automatically created by Unreal Engine for every class, including Blueprint classes.

The purpose of the `CDO` is to store the default property values and settings for the class. When a new instance of the class is created, it is initialized using the values stored in the `CDO`. In essence, the `CDO` represents the canonical state and configuration of the class by default.

When you edit default properties in a Blueprint editor, you’re modifying the `CDO` of the class. Similarly, when you create an instance of a Blueprint, it inherits its properties from the `CDO`. If you edit a property of an instance and then choose to revert it, the modification is reset to the `CDO’s` values.

## Bonfire Lit, What's Next?
Phew, that's a lot of information to digest. We've covered the basic structure of the Blueprint system, including:
- `UBlueprint`
- `UBlueprintGeneratedClass`
- `UEdGraph`
- `UEdGraphNode`
- `UEdGraphPin`
- `UEdGraphSchema`
- `FKismetCompilerContext`
- `FKismetFunctionContext`
- `FBlueprintCompiledStatement`
- `FBPTerminal`
- `FNodeHandlingFunctor`
- `FBlueprintCompileReinstancer`
- `FKismetCompilerOptions`
- `Skeleton Class`
- `CDO`

A secure chamber found and a bonfire lit, we've taken our first step into the dark castle of Blueprint. However, something seems to be hidden in the shadows.


[1]: https://www.cnblogs.com/ghl_carmack/p/5998693.html

[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[Blueprint VM]: https://www.cnblogs.com/ghl_carmack/p/6060383.html
[Blueprint I]: https://www.cnblogs.com/ghl_carmack/p/5995007.html
[Blueprint II]: https://www.cnblogs.com/ghl_carmack/p/5998693.html
[Blueprint III]: https://www.cnblogs.com/ghl_carmack/p/6014655.html
