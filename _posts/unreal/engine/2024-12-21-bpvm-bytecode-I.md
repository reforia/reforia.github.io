---
layout: post
title: "But what is Blueprint? From Blueprint to Bytecode - I"
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
Unreal Engine has been known for its powerful visual scripting system - Blueprint (Previously Kismet), there're plenty of tutorials and guides on how to use it, but not much on how it works. When we drag and drop nodes in the visual graph, click the compile button, and call it a day, it gave us a nice little hint: "Good to go", but what's really happening behind the scene? How does the Blueprint Virtual Machine (BPVM) interpret and execute the graph? This series of posts will try to answer these questions. So prepare your helmet, and let's dive in.

![Compile, Save and Good to go](bytecode_hitcompile.png){: width="500" }

## Previous Researches
Epic published a [document] that briefly covered how the Blueprint compilation process works, but it only scratches the surface and doesn't go into details. Luckily, the community has done some great researches as well, for BPVM, we have [Blueprint VM], for BP Compilation Process, we have [Blueprint I], [Blueprint II] and [Blueprint III]. 

> These blogs above are written in Chinese, for english readers, a translation tools like ChatGPT could be helpful.
{: .prompt-tip}

Despite these are really high quality posts that absolutely worth a read, we will still try to go through the key terminologies for them in a more complete way. so we can have a common ground to face the next challenge.

## Blueprint System
When people refer to a 'well-written Blueprint'. they're typically talking about the visual scripting graph created within the Blueprint Editor. Internally, this graph is managed by a `UEdGraph` object. The Graph (Event Graph for instance) is not the blueprint editor, but a part of it. The blueprint editor is a collection of `UEdGraphs` and panels, tools, etc.

In short, creating a Blueprint Asset in the Content Browser involves selecting a parent class and defining a new subclass through the Blueprint system. The Blueprint Editor allows us to add functions and logic within `UEdGraph` instances, as well as set up various properties. When we click the compile button in the editor, it orchestrates the compilation process: the content within the `UEdGraph` is processed and encapsulated into a reused UBlueprintGeneratedClass. This generated class contains bytecode that the engine ultimately executes during runtime, ensuring that our defined behaviors and logic are effectively integrated into the game.

![Blueprint System Overview](bytecode_blueprintflow.png)
_Blueprint System Overview_

![Blueprint Structure](bytecode_blueprintstructure.png)
_Blueprint Structure (Source: [1])_ 

### UBlueprint
When we click in the Content Browser to create a new Blueprint based on a custom class type, such as `ACustomClass`, we're creating a `Blueprint Asset`, more specifically, a UBlueprint object. This asset end with `.uasset` that we saw on our disk is a serialized representation that defines a *VIRTUAL* subclass of `ACustomClass` (more on that later) and exists solely within the editor environment.

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

we can see that upon calling `FKismetEditorUtilities::CreateBlueprint()` it immediately creates a UBlueprint instance, and set the `NewBP->ParentClass` to `ParentClass` (ACustomClass in this case). That's why some of the other documents were saying the created blueprint is a subclass of `ACustomClass`. This statement is technically incorrect, because it's actually just a UBlueprint object, with a `ParentClass` pointer pointing to `ACustomClass`.

### UBlueprintGeneratedClass
As mentioned before, when executing the Blueprint's logic, we're not directly running the UBlueprint object created (Since it only exist in editor). Instead, we're executing compiled bytecode stored in a compiled version of that `UBlueprint` object, known as `UBlueprintGeneratedClass`.

>Technically, the Blueprint Editor initiates the generation of `UBlueprintGeneratedClass`, but that's just a placeholder. The actual compilation work is handled by `FKismetCompilerContext`, which compiles the visual scripting nodes into executable code (bytecode) and write back to `UBlueprintGeneratedClass`.
{: .prompt-info}

Just like `UBlueprint` is *NOT* a subclass of `ACustomClass`. `UBlueprintGeneratedClass` is *NOT* a subclass of `ACustomClass`, meaning there's no such thing as:

```cpp
class UBlueprintGeneratedClass : public ACustomClass
{
    // ...
};
```

Instead, the UBlueprintGeneratedClass is already declared in `BlueprintGeneratedClass.h` as: 

```cpp
class UBlueprintGeneratedClass : public UClass, public IBlueprintPropertyGuidProvider
{
    // ...
};
```

Slightly different to `UBlueprint` object. (Since the asset we are seeing in Content Browser is actually an instance of `UBlueprint`, which is a `UObject` and being serialized as `.uasset`), the `UBlueprintGeneratedClass` is just a class rather than an instance. So the parenting relationship is leveraging the idea of `SuperClass` (`SetSuperStruct()` when setting it, and `GetSuperClass()` when getting it), to act as if the `UBlueprintGeneratedClass` is a subclass of another `UClass`. Here's the codes right after the UBlueprint instance is created:

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
An `UEdGraph` is the representation of a graph, which is a collection of nodes and connections. In the context of Blueprint, `UEdGraph` is used to represent the data orchestrated in the visual scripting graph, such as the Event Graph, Function Graph, and Macro Graph. The `UEdGraph` is responsible for managing the nodes and connections within the graph, as well as providing the necessary interfaces for the Blueprint Editor to interact with the graph.

`UEdGraph` has numerous subclasses, such as `UAIGraph`, `UAnimationGraph`, `UAnimationStateMachineGraph`, `UMaterialGraph`, etc. Basically, when we open an asset and see a place for us to drag and drop nodes, the underlying type is most likely an `UEdGraph`.

We intentionally mentioned this is just a representation of a graph, not a view of it. Because it's not the actual graph widget that we are seeing in the editor. The visual representation is a Slate UI, `SGraphEditor`. It also contains the actual frontend interactions on the widget.

![UEdGraph](bytecode_uedgraph.png)
_UEdGraph (Source: [1])_

### UEdGraphNode
`UEdGraphNode` is a fundamental class that represents a node in an Unreal Engine graph. It is part of the graph's data structure and holds the logic and properties of individual nodes within the graph, whether it's for Event Graphs, Function Graphs, or other types of graphs.

`UEdGraphNode` contains the logic and data necessary to execute or represent an operation in the graph. For example, a node could represent a function call, a variable assignment, or an action like “Print String.”

There are various subclasses of `UEdGraphNode` as well, such as `UAnimStatesNode`, `UNiagaraNode`, etc. Each of these classes introduces functionality specific to the type of graph being used. Note that the Blueprint Graph nodes are not called UBlueprintNode, but `UK2Node`.

![UEdGraphNode](bytecode_uk2nodes.png){: width="500" }
_Various UK2Nodes_

Similar to UEdGraph, `UEdGraphNode` has visual representation of `SGraphNode`.

![UEdGraphNode](bytecode_uedgraphnode.png)
_UEdGraphNode (Source: [1])_

### UEdGraphPin
`UEdGraphNode` maintain connections to other nodes via `UEdGraphPin` objects, which allow the flow of execution or data between them.

A pin in `UEdGraphPin` is a communication point between nodes. It can either be an input pin (where data flows into the node) or an output pin (where data flows out of the node).

Each pin can be connected to other pins, and the system enforces type compatibility between them (e.g., connecting an integer pin to a float pin is allowed because an implicit cast is possible, but otherwise it's illegal).

Same old, pins have a visual representation in the Blueprint Editor, allowing users to connect them using drag-and-drop. This visual interaction is managed by the `SGraphPin` class.

### UEdGraphSchema
`UEdGraphSchema` defines the rules and conventions for a specific type of graph. It acts as a blueprint (literally) for how nodes and pins interact with each other, providing a way to describe valid node connections, node actions, and ensure that the graph behaves as expected.

For different types of graphs (Blueprint, Animation, AI, etc.), there are corresponding `UEdGraphSchema` subclasses. For example:

![UEdGraphSchema](bytecode_otherschemas.png){: width="500" }
_Other Schemas_

It can also define custom rules for creating and placing nodes within the graph. For instance, it may define which nodes are available to a user when they right-click to add a new node. It also defines the rules around linking pins between nodes. For example, which types of pins can connect to each other or how connections should be made.

![UEdGraphSchema](bytecode_uedgraphschema.png)
_UEdGraphSchema (Source: [1])_

### FKismetCompilerContext
`FKismetCompilerContext` is the core class responsible for compiling a Blueprint graph into executable bytecode that the Blueprint Virtual Machine (VM) can interpret. This class acts as the main driver for the compilation process, handling tasks such as node translation, validation, and generating the resulting intermediate representation.

The `FKismetCompilerContext` first translates the visual scripting graphs (represented as UEdGraph, UEdGraphNode, etc.) into an intermediate format composed of `FBlueprintCompiledStatement` objects, which will then be compiled into bytecode for the VM (Blueprint Virtual Machine). It manages the flow of the compilation process, ensuring that all nodes in the graph are properly translated and connected.

![FKismetCompilerContext](bytecode_fkismetcompilercontext.png)
_FKismetCompilerContext (Source: [1])_

### FKismetFunctionContext
`FKismetFunctionContext` represents the compilation context for a single function or graph within a Blueprint. It serves as a container for all the data needed to compile a specific function, such as variable definitions, control flow, and statements.

The `FKismetFunctionContext` tracks the local state of a function during compilation, including variables, temporaries, and flow control structures. It ensures that all nodes within the function are translated into valid intermediate representations (`FBlueprintCompiledStatement`).

### FBlueprintCompiledStatement
`FBlueprintCompiledStatement` is an intermediate representation of a single executable operation in a Blueprint graph. In other words, a function can have multiple `FBlueprintCompiledStatement` objects.

Each `FBlueprintCompiledStatement` corresponds to a specific operation in the graph, Statements are generated during the compilation process and are later converted into VM bytecode. Here's a full list of `FBlueprintCompiledStatement` types from `BlueprintCompiledStatement.h`:

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
`FBPTerminal` represents a variable or expression used within a `FBlueprintCompiledStatement`. It acts as a handle for data or objects in the Blueprint graph.

![FBPTerminal](bytecode_fbpterminal.png){: width="400"}
_"Hello World" Literal FBPTerminal_

### FNodeHandlingFunctor
`FNodeHandlingFunctor` is an abstraction used to handle the translation of specific node types during the compilation process. Each `UEdGraphNode` type has an associated `FNodeHandlingFunctor` that knows how to convert that node into the intermediate representation (`FBlueprintCompiledStatement`).

![FNodeHandlingFunctor](bytecode_fnodehandlingfunctor.png)
_FNodeHandlingFunctor (Source: [1])_

Each `UK2Node` subclass has an associated `FNodeHandlingFunctor` subclass that defines how that node should be compiled. An example:

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

As can be seen above, we have `FKCHandle_Select` for `UK2Node_Select`, it implements `RegisterNets()` and `Compile()`

![FKCHandler_Select](bytecode_selectnode.png){: width="400"}
_Select Node_

#### RegisterNets()
`RegisterNets()` is responsible for registering the input and output pins of the node, creating the necessary `FBPTerminal` objects to represent them. For example, if we connected anything to the options pin and the index pin, they will be picked up at this moment. It's called in `PrecompileFunction()` and `CreateLocalsAndRegisterNets()`.

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

`CreateLocalsAndRegisterNets()` can be called in `PrecompileFunction()` or `CompileFunction()`, the reason we say "Or" is because normally `PrecompileFunction()` will call it, but if `EInternalCompilerFlags::PostponeLocalsGenerationUntilPhaseTwo` is passed as parameter, then PrecompileFunction() will just omit this step, and `CompileFunction()` will call it later as that's "Phase Two".

>`EInternalCompilerFlags::PostponeLocalsGenerationUntilPhaseTwo` will be passed to CompileFunction() in `FBlueprintCompilationManagerImpl::FlushCompilationQueueImpl()`, `BlueprintCompilationManager` is a huge topic so we will not cover it here.
{: .prompt-info}

#### Compile()
`Compile()` is responsible for generating the intermediate representation (`FBlueprintCompiledStatement`) for the node, based on the input and output pins. Let's take a look:

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

Basically, there're 6 steps in `Compile()`, it first declares the `FBPTerminals`, then tries to get the value for these terms, creates a `FBlueprintCompiledStatement` for the `SelectNode` and set its type to `KCST_SwitchValue`, then it gets all the option pins, goes through each option and adds their value to the `SelectStatement`, finally adds the `DefaultTerm` to the `SelectStatement`.

`Literal Term` 
- For each option, a `FBPTerminal` of type Literal is created. This represents the literal value associated with that option (i.e., the index value that matches the option). If the option pin is associated with an enum, it uses the enum name, otherwise, it defaults to an index-based name.

`Value Term`
- For each option pin, the corresponding value term is retrieved from the context. If it’s not found, an error is logged. The value is then added to the RHS.

Now its pretty clear that for the `SelectNode`, the `Compile()` function just creates a `FBlueprintCompiledStatement` , and set its type to `KCST_SwitchValue`, then it feeds all the data into the `SelectStatement` object.

### FBlueprintCompileReinstancer
`FBlueprintCompileReinstancer` is a utility class in Unreal Engine that assists with reinstancing objects when a Blueprint class is recompiled. Reinstancing is necessary because existing instances of a Blueprint class in the game world need to be updated to match the newly compiled version of the class.

During Blueprint compilation, changes to the class structure (e.g., new variables, altered logic) mean that existing instances of the Blueprint may no longer align with the new class definition.
The `FBlueprintCompileReinstancer` ensures that these instances are correctly updated or replaced, avoiding crashes or inconsistencies.

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
A Skeleton Class is an intermediate representation of a Blueprint class used during the compilation process. It serves as a lightweight placeholder that contains only basic information about the class structure (e.g., variables and functions) without full implementation details.

>Think of SKEL class as a smarter forward declaration or a header file. It's created before any bytecode is compiled, and only provides metadata about the class structure. The nuance is there's no linkage process after compilation, unlike a header file.
{: .prompt-info}

This exists so Blueprints can reference each other in a cyclic manner during compilation. For example, if two Blueprints reference each other, their Skeleton Classes can be created first, resolving dependency issues.
Acts as a minimal version of the class that can be used in the editor before full compilation is completed.

When one Blueprint calls a function on another Blueprint class that hasn't been fully compiled yet, the Skeleton Class is used to represent the target class temporarily.

### CDO
The Class Default Object is a special instance of a class that serves as the archetype for all instances of that class. It is created automatically by the Unreal Engine for every class (including Blueprint classes).

The purpose is to store the default property values and settings for the class. When a new instance of the class is created, it is initialized using the values stored in the CDO. so it acts as the canonical representation of a class's default state and configuration.

When you edit default properties in a Blueprint's editor, you are modifying the CDO of the class. When you create an instance of the Blueprint, it inherits its properties from the CDO. When we edited a property of an instance, a small icon shows up and let us to revert our modification, what would it be reverted to? The CDO.

## Conclusion
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

A secure chamber found and a bonfire lit, we've taken our first step into the dark castle of Blueprint. However, something seems to be in the shadows.


[1]: https://www.cnblogs.com/ghl_carmack/p/5998693.html

[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[Blueprint VM]: https://www.cnblogs.com/ghl_carmack/p/6060383.html
[Blueprint I]: https://www.cnblogs.com/ghl_carmack/p/5995007.html
[Blueprint II]: https://www.cnblogs.com/ghl_carmack/p/5998693.html
[Blueprint III]: https://www.cnblogs.com/ghl_carmack/p/6014655.html
