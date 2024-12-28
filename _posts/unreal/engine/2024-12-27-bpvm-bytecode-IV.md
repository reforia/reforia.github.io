---
layout: post
title: "Road to the Root. From Blueprint to Bytecode - IV"
description:
    "There's only one last challenge left before we can finally see the bytecode, and that is to compile the functions. In this post, we will go through this very step."
date: 2024-12-27 21:45 +0800
categories: [Unreal, Engine]
published: false
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Compile Functions Kick off
The first bit of the function `FKismetCompilerContext::CompileFunctions()` is to check the internal flags, and then decide whether to generate locals, propagate values to CDO, and refresh external blueprint dependency nodes. The `FKismetCompilerVMBackend` is then initialized with the blueprint, schema, and the compiler context. The validation is skipped if the values are not propagated to CDO. Pretty simple stuff to start with.

```cpp
void FKismetCompilerContext::CompileFunctions(EInternalCompilerFlags InternalFlags)
{
    // This is phase two, so we want to generated locals if PostponeLocalsGenerationUntilPhaseTwo is set:
    const bool bGenerateLocals = !!(InternalFlags & EInternalCompilerFlags::PostponeLocalsGenerationUntilPhaseTwo);
    // Don't propagate values to CDO if we're going to do that in reinstancing:
    const bool bPropagateValuesToCDO = !(InternalFlags & EInternalCompilerFlags::PostponeDefaultObjectAssignmentUntilReinstancing);
    // Don't RefreshExternalBlueprintDependencyNodes if the calling code has done so already:
    const bool bSkipRefreshExternalBlueprintDependencyNodes = !!(InternalFlags & EInternalCompilerFlags::SkipRefreshExternalBlueprintDependencyNodes);
    FKismetCompilerVMBackend Backend_VM(Blueprint, Schema, *this);

    // Validation requires CDO value propagation to occur first.
    bool bSkipGeneratedClassValidation = !bPropagateValuesToCDO;
    // ... Other Code
}
```

## Generate Locals
For each of the functions, we call `CreateLocalsAndRegisterNets()` on them. Which calls `RegisterNets()` As mentioned in the [first post], this basically tries to link input and output pin to a `FBPTerminal`, so that when the function is called, the input and output values can be passed in and out.

```cpp
if( bGenerateLocals )
{
    for (int32 i = 0; i < FunctionList.Num(); ++i)
    {
        if (FunctionList[i].IsValid())
        {
            FKismetFunctionContext& Context = FunctionList[i];
            CreateLocalsAndRegisterNets(Context, Context.LastFunctionPropertyStorageLocation);
        }
    }
}

// --------------------------------------------------------------------------------------------
void FKismetCompilerContext::CreateLocalsAndRegisterNets(FKismetFunctionContext& Context, FField**& FunctionPropertyStorageLocation)
{
    // Create any user defined variables, this must occur before registering nets so that the properties are in place
    CreateUserDefinedLocalVariablesForFunction(Context, FunctionPropertyStorageLocation);

    check(Context.IsValid());
    //@TODO: Prune pure functions that don't have any consumers
    if (bIsFullCompile)
    {
        // Find the execution path (and make sure it has no cycles)
        CreateExecutionSchedule(Context.SourceGraph->Nodes, Context.LinearExecutionList);

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
            else
            {
                MessageLog.Error(
                    *FText::Format(
                        LOCTEXT("UnexpectedNodeType_ErrorFmt", "Unexpected node type {0} encountered at @@"),
                        FText::FromString(Node->GetClass()->GetName())
                    ).ToString(),
                    Node
                );
            }
        }
    }

    using namespace UE::KismetCompiler;

    CastingUtils::RegisterImplicitCasts(Context);

    // Create net variable declarations
    CreateLocalVariablesForFunction(Context, FunctionPropertyStorageLocation);
}
```

## Create Execution Schedule
One tiny but very important step in the above code is the `CreateExecutionSchedule()`, it performs a topological sort on the graph of nodes passed in (which is expected to form a DAG), scheduling them. If there are cycles or unconnected nodes present in the graph, an error will be output for each node that failed to be scheduled. The value is then stored in `Context.LinearExecutionList` for later use.

The concept of DAG (Directed Acyclic Graph) is very important in computer science, it's a graph that has no cycles, which means you can't go from a node back to itself by following the edges. This is very important in the blueprint graph, as it ensures that the logic is executed in a linear order, and there are no circular dependencies.

For more information on DAG, you can check out the [DAG Wiki].

## Anatomy of CompileFunctions()
### Generate FBlueprintCompiledStatement for each Function
Let's start with the simpler one, if this is not a full compile, then we just go through each function and call `FinishCompilingFunction()` on them. This is to set flags on the functions even for a skeleton class.

>Note: `bIsFullCompile` might be a bit misleading here, basically, if this is false, then we are compiling a skeleton class
{: .prompt-info}

```cpp
if (bIsFullCompile && !MessageLog.NumErrors)
{
    // ... Other Code
}
else
{
    // Still need to set flags on the functions even for a skeleton class
    for (int32 i = 0; i < FunctionList.Num(); ++i)
    {
        FKismetFunctionContext& Function = FunctionList[i];
        if (Function.IsValid())
        {
            BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_PostcompileFunction);
            FinishCompilingFunction(Function);
        }
    }
}
```

Now let's take a look at the `bIsFullCompile` path, simple enough, we just go through each function and call `CompileFunction()` on them. This is where the actual compilation happens. Then, we call `PostcompileFunction()` on them to finalize the function. Finally, we check if there are any `FMulticastDelegateProperty` that doesn't have a `SignatureFunction` set, and log a warning if so.

```cpp
// Generate code for each function (done in a second pass to allow functions to reference each other)
for (int32 i = 0; i < FunctionList.Num(); ++i)
{
    if (FunctionList[i].IsValid())
    {
        CompileFunction(FunctionList[i]);
    }
}

// Finalize all functions (done last to allow cross-function patchups)
for (int32 i = 0; i < FunctionList.Num(); ++i)
{
    if (FunctionList[i].IsValid())
    {
        PostcompileFunction(FunctionList[i]);
    }
}

for (TFieldIterator<FMulticastDelegateProperty> PropertyIt(NewClass); PropertyIt; ++PropertyIt)
{
    if(const FMulticastDelegateProperty* MCDelegateProp = *PropertyIt)
    {
        if(NULL == MCDelegateProp->SignatureFunction)
        {
            MessageLog.Warning(*FString::Printf(TEXT("No SignatureFunction in MulticastDelegateProperty '%s'"), *MCDelegateProp->GetName()));
        }
    }
}
```

### Broadcast Event and Save Intermediate Products
Once that's done, we broadcast the event out, and then we just set the flags for the intermediate products if requested.

```cpp
FunctionListCompiledEvent.Broadcast(this);

// Save off intermediate build products if requested
if (bIsFullCompile && CompileOptions.bSaveIntermediateProducts && !Blueprint->bIsRegeneratingOnLoad)
{
    // Generate code for each function (done in a second pass to allow functions to reference each other)
    for (int32 i = 0; i < FunctionList.Num(); ++i)
    {
        FKismetFunctionContext& ContextFunction = FunctionList[i];
        if (FunctionList[i].SourceGraph != NULL)
        {
            // Record this graph as an intermediate product
            ContextFunction.SourceGraph->Schema = UEdGraphSchema_K2::StaticClass();
            Blueprint->IntermediateGeneratedGraphs.Add(ContextFunction.SourceGraph);
            ContextFunction.SourceGraph->SetFlags(RF_Transient);
        }
    }
}
```

### Finish Compile Class
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
To finish compiling the class, compiler finalizes the class flags and propagates flags and metadata from the parent class before finally performing a few final checks to make sure everything went alright in the compile.
</div>

At this moment, we will wrap up the final few steps for the class compilation. We will set the final flags and seal the class, build a CDO, and build delegate binding maps if we have a graph. If we are not regenerating on load, we will copy over the CDO properties from the old one. We will also update the custom property list used in post construction logic to include native class properties for which the Blueprint CDO differs from the native CDO.

```cpp
{ 
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_FinalizationWork);

    // Set any final flags and seal the class, build a CDO, etc...
    FinishCompilingClass(NewClass);

    // Build delegate binding maps if we have a graph
    if (ConsolidatedEventGraph)
    {
        // Build any dynamic binding information for this class
        BuildDynamicBindingObjects(NewClass);
    }

    UObject* NewCDO = NewClass->GetDefaultObject();

    // Copy over the CDO properties if we're not already regenerating on load.  In that case, the copy will be done after compile on load is complete
    if(bPropagateValuesToCDO)
    {
        FBlueprintEditorUtils::PropagateParentBlueprintDefaults(NewClass);

        if( !Blueprint->HasAnyFlags(RF_BeingRegenerated) )
        {
            // Propagate the old CDO's properties to the new
            if( OldCDO )
            {
                if (OldLinker && OldGenLinkerIdx != INDEX_NONE)
                {
                    // If we have a list of objects that are loading, patch our export table. This also fixes up load flags
                    FBlueprintEditorUtils::PatchNewCDOIntoLinker(Blueprint->GeneratedClass->GetDefaultObject(), OldLinker, OldGenLinkerIdx, nullptr);
                }

                UEditorEngine::FCopyPropertiesForUnrelatedObjectsParams CopyDetails;
                CopyDetails.bCopyDeprecatedProperties = Blueprint->bIsRegeneratingOnLoad;
                CopyDetails.bNotifyObjectReplacement = true; 
                UEditorEngine::CopyPropertiesForUnrelatedObjects(OldCDO, NewCDO, CopyDetails);
                FBlueprintEditorUtils::PatchCDOSubobjectsIntoExport(OldCDO, NewCDO);
            }
            else
            {
                // Don't perform generated class validation since we didn't do any value propagation.
                bSkipGeneratedClassValidation = true;
            }
        }

        PropagateValuesToCDO(NewCDO, OldCDO);

        // Perform any fixup or caching based on the new CDO.
        PostCDOCompiled(UObject::FPostCDOCompiledContext());
    }

    // Note: The old->new CDO copy is deferred when regenerating, so we skip this step in that case.
    if (!Blueprint->HasAnyFlags(RF_BeingRegenerated))
    {
        // Update the custom property list used in post construction logic to include native class properties for which the Blueprint CDO differs from the native CDO.
        TargetClass->UpdateCustomPropertyListForPostConstruction();
    }
}
```

### Generate Bytecode from FBlueprintCompiledStatement
Follow up, we called the `Backend_VM` to parse the bytecode based from function's `FBlueprintCompiledStatement`, `GenerateCodeFromClass()` does the heavy lifting, more on this later.

```cpp
// Always run the VM backend, it's needed for more than just debug printing
{
    const bool bGenerateStubsOnly = !bIsFullCompile || (0 != MessageLog.NumErrors);
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_CodeGenerationTime);
    Backend_VM.GenerateCodeFromClass(NewClass, FunctionList, bGenerateStubsOnly);
}
```

### Serialize Expressions
Afterwards, we serialize all expressions to an archive.

```cpp
// Fill ScriptAndPropertyObjectReferences arrays in functions
if (bIsFullCompile && (0 == MessageLog.NumErrors)) // Backend_VM can generate errors, so bGenerateStubsOnly cannot be reused
{
    for (FKismetFunctionContext& FunctionContext : FunctionList)
    {
        if (FunctionContext.IsValid())
        {
            UFunction* Function = FunctionContext.Function;
            auto FunctionScriptAndPropertyObjectReferencesView = MutableView(Function->ScriptAndPropertyObjectReferences);
            FArchiveScriptReferenceCollector ObjRefCollector(FunctionScriptAndPropertyObjectReferencesView, Function);
            for (int32 iCode = 0; iCode < Function->Script.Num();)
            {
                Function->SerializeExpr(iCode, ObjRefCollector);
            }
        }
    }
}
```

Here an interesting technique is used, if we step into the `SerializeExpr()` function, it looks like this:

```cpp
EExprToken UStruct::SerializeExpr( int32& iCode, FArchive& Ar )
{
#define SERIALIZEEXPR_INC
#define SERIALIZEEXPR_AUTO_UNDEF_XFER_MACROS
#include "UObject/ScriptSerialization.h"
    return Expr;
#undef SERIALIZEEXPR_INC
#undef SERIALIZEEXPR_AUTO_UNDEF_XFER_MACROS
}
```

What?! At a glance this might be a bit confusing, but it's actually a clever way to serialize the expressions. The `#include` ensured the content are being embeded here inplace. Which means the actual implementation is done in this `UObject/ScriptSerialization.h` file. This is a very neat way to keep the code clean and organized, as well as reusability.

### Generate Debug Bytecode
At this moment, we already have all the bytecode generated, but as a human we can't read them, unless `bDisplayBytecode` is set to true, then we will disassemble the bytecode and print them out.

```cpp
if (bDisplayBytecode && bIsFullCompile && !IsRunningCommandlet())
{
    TGuardValue<ELogTimes::Type> DisableLogTimes(GPrintLogTimes, ELogTimes::None);

    FKismetBytecodeDisassembler Disasm(*GLog);

    // Disassemble script code
    for (int32 i = 0; i < FunctionList.Num(); ++i)
    {
        FKismetFunctionContext& Function = FunctionList[i];
        if (Function.IsValid())
        {
            UE_LOG(LogK2Compiler, Log, TEXT("\n\n[function %s]:\n"), *(Function.Function->GetName()));
            Disasm.DisassembleStructure(Function.Function);
        }
    }
}
```

### Mark Dependencies Dirty
This step is pretty simple, if we have compiled the functions, we should mark the dependent blueprints dirty, so that they will be recompiled if necessary.

```cpp
// For full compiles, find other blueprints that may need refreshing, and mark them dirty, in case they try to run
if( bIsFullCompile && !Blueprint->bIsRegeneratingOnLoad && !bSkipRefreshExternalBlueprintDependencyNodes )
{
    TArray<UBlueprint*> DependentBlueprints;
    FBlueprintEditorUtils::GetDependentBlueprints(Blueprint, DependentBlueprints);
    for (UBlueprint* CurrentBP : DependentBlueprints)
    {
        // Get the current dirty state of the package
        UPackage* const Package = CurrentBP->GetOutermost();
        const bool bStartedWithUnsavedChanges = Package != nullptr ? Package->IsDirty() : true;
        const EBlueprintStatus OriginalStatus = CurrentBP->Status;

        FBlueprintEditorUtils::RefreshExternalBlueprintDependencyNodes(CurrentBP, NewClass);
        
        // Dependent blueprints will be recompile anyway by reinstancer (if necessary).
        CurrentBP->Status = OriginalStatus;

        // Note: We do not send a change notification event to the dependent BP here because
        // we have not yet reinstanced any of the instances of the BP being compiled, which may
        // be referenced by instances of the dependent BP that may be reconstructed as a result.

        // Clear the package dirty state if it did not initially have any unsaved changes to begin with
        if(Package != nullptr && Package->IsDirty() && !bStartedWithUnsavedChanges)
        {
            Package->SetDirtyFlag(false);
        }
    }
}
```

### Housekeeping
Finally, we do some housekeeping, we finalize the class flags, propagate flags and metadata from the parent class, and store the crc32 checksums for the CDO and the signature. In the end, we call `PostCompile()` to broadcast the event and finish the compilation.

```cpp
// Clear out pseudo-local members that are only valid within a Compile call
UbergraphContext = NULL;
CallsIntoUbergraph.Empty();
TimelineToMemberVariableMap.Empty();


check(NewClass->PropertiesSize >= UObject::StaticClass()->PropertiesSize);
check(NewClass->ClassDefaultObject != NULL);

PostCompileDiagnostics();

// ... Other Code

if (bIsFullCompile)
{
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_ChecksumCDO);

    static const FBoolConfigValueHelper ChangeDefaultValueWithoutReinstancing(TEXT("Kismet"), TEXT("bChangeDefaultValueWithoutReinstancing"), GEngineIni);
    // CRC is usually calculated for all Properties. If the bChangeDefaultValueWithoutReinstancing optimization is enabled, then only specific properties are considered (in fact we should consider only . See UE-9883.
    // Some native properties (bCanEverTick) may be implicitly changed by KismetCompiler during compilation, so they always need to be compared.
    // Some properties with a custom Property Editor Widget may not propagate changes among instances. They may be also compared.

    class FSpecializedArchiveCrc32 : public FArchiveObjectCrc32
    {...};

    UObject* NewCDO = NewClass->GetDefaultObject(false);
    FSpecializedArchiveCrc32 CrcArchive(!ChangeDefaultValueWithoutReinstancing);
    Blueprint->CrcLastCompiledCDO = NewCDO ? CrcArchive.Crc32(NewCDO) : 0;
}

if (bIsFullCompile)
{
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_ChecksumSignature);

    class FSignatureArchiveCrc32 : public FArchiveObjectCrc32
    {...};

    FSignatureArchiveCrc32 SignatureArchiveCrc32;
    UBlueprint* ParentBP = UBlueprint::GetBlueprintFromClass(NewClass->GetSuperClass());
    const uint32 ParentSignatureCrc = ParentBP ? ParentBP->CrcLastCompiledSignature : 0;
    Blueprint->CrcLastCompiledSignature = SignatureArchiveCrc32.Crc32(NewClass, ParentSignatureCrc);
}

PostCompile();
```

## Generate FBlueprintCompiledStatement for each Function
Obviously, the magic happens in `CompileFunction()`, which converts each function into several `FBlueprintCompiledStatement`. In the next batch (After all functions has been compiled) a BPVM Backend converts them to bytecode in another batch.

### The Anatomy of CompileFunction()
In a big picture, the `CompileFunction()` function is responsible for generating statements for each node in the linear execution order, then pull out pure chains and inline their generated code into the nodes that need it. Finally, it propagates thread-safe flags in the first pass, and also gets called from `SetCalculatedMetaDataAndFlags` in the second pass to catch skeleton class generation.

```cpp
void FKismetCompilerContext::CompileFunction(FKismetFunctionContext& Context)
{
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_CompileFunction);
        
    check(Context.IsValid());

    // Generate statements for each node in the linear execution order (which should roughly correspond to the final execution order)
    TMap<UEdGraphNode*, int32> SortKeyMap;
    int32 NumNodesAtStart = Context.LinearExecutionList.Num();
    for (int32 i = 0; i < Context.LinearExecutionList.Num(); ++i)
    {...}
    
    if (Context.ImplicitCastMap.Num() > 0)
    {...}

    // The LinearExecutionList should be immutable at this point
    check(Context.LinearExecutionList.Num() == NumNodesAtStart);

    // Now pull out pure chains and inline their generated code into the nodes that need it
    TMap< UEdGraphNode*, TSet<UEdGraphNode*> > PureNodesNeeded;
    
    for (int32 TestIndex = 0; TestIndex < Context.LinearExecutionList.Num(); )
    {...}

    // Propagate thread-safe flags in this first pass. Also gets called from SetCalculatedMetaDataAndFlags in the second
    // pass to catch skeleton class generation
    if (Context.EntryPoint->MetaData.bThreadSafe)
    {
        Context.Function->SetMetaData(FBlueprintMetadata::MD_ThreadSafe, TEXT("true"));
    }
}
```

### Generate Statements for Each Node
This looks like rocket science, but it really isn't, we already have the `LinearExecutionList` which is a list of `UEdGraphNode` in the correct order, we just need to go through them and generate statements for each node. We also add debug comments and opcode insertion points for debugging purposes. the 70% of the code just for adding debugging purposed `FBlueprintCompiledStatement` like `KCST_Comment`. The actual work is just one line of code, `Handler->Compile(Context, Node);`. As mentioned in the [first post], this allows the `FNodeHandlingFunctor` to compile the node and populate `FBlueprintCompiledStatement`.

```cpp
// Generate statements for each node in the linear execution order (which should roughly correspond to the final execution order)
TMap<UEdGraphNode*, int32> SortKeyMap;
int32 NumNodesAtStart = Context.LinearExecutionList.Num();
for (int32 i = 0; i < Context.LinearExecutionList.Num(); ++i)
{
    UEdGraphNode* Node = Context.LinearExecutionList[i];
    SortKeyMap.Add(Node, i);

    const FString NodeComment = Node->NodeComment.IsEmpty() ? Node->GetName() : Node->NodeComment;
    const bool bPureNode = IsNodePure(Node);
    // Debug comments
    if (KismetCompilerDebugOptions::EmitNodeComments)
    {
        FBlueprintCompiledStatement& Statement = Context.AppendStatementForNode(Node);
        Statement.Type = KCST_Comment;
        Statement.Comment = NodeComment;
    }

    // Debug opcode insertion point
    if (Context.IsDebuggingOrInstrumentationRequired())
    {...}

    // Let the node handlers try to compile it
    if (FNodeHandlingFunctor* Handler = NodeHandlers.FindRef(Node->GetClass()))
    {
        Handler->Compile(Context, Node);
    }
    else
    {
        MessageLog.Error(
            *FText::Format(
                LOCTEXT("UnexpectedNodeTypeWhenCompilingFunc_ErrorFmt", "Unexpected node type {0} encountered in execution chain at @@"),
                FText::FromString(Node->GetClass()->GetName())
            ).ToString(),
            Node
        );
    }
}
```

### Inline Pure Nodes
This step is concerned with pure nodes, it walk through the whole list, and divide them into two groups, one is the pure nodes, they are being pushed to the requirement list for other nodes. And for non pure nodes, they are doing the actual inlining of the pure nodes' code.

```cpp
// Now pull out pure chains and inline their generated code into the nodes that need it
TMap< UEdGraphNode*, TSet<UEdGraphNode*> > PureNodesNeeded;

for (int32 TestIndex = 0; TestIndex < Context.LinearExecutionList.Num(); )
{
    UEdGraphNode* Node = Context.LinearExecutionList[TestIndex];

    // List of pure nodes this node depends on.
    bool bHasAntecedentPureNodes = PureNodesNeeded.Contains(Node);

    if (IsNodePure(Node))
    {
        // For profiling purposes, find the statement that marks the function's entry point.
        // ... Other Code

        // Push this node to the requirements list of any other nodes using it's outputs, if this node had any real impact
        if (bDidNodeGenerateCode || bHasAntecedentPureNodes)
        {...}

        // Remove it from the linear execution list; the dependent nodes will inline the code when necessary
        Context.LinearExecutionList.RemoveAt(TestIndex);
    }
    else
    {
        if (bHasAntecedentPureNodes)
        {
            // This node requires the output of one or more pure nodes, so that pure code needs to execute at this node

            // Sort the nodes by execution order index
            TSet<UEdGraphNode*>& AntecedentPureNodes = PureNodesNeeded.FindChecked(Node);
            TArray<UEdGraphNode*> SortedPureNodes;
            for (TSet<UEdGraphNode*>::TIterator It(AntecedentPureNodes); It; ++It)
            {
                OrderedInsertIntoArray(SortedPureNodes, SortKeyMap, *It);
            }

            // Inline their code
            for (int32 i = 0; i < SortedPureNodes.Num(); ++i)
            {
                UEdGraphNode* NodeToInline = SortedPureNodes[SortedPureNodes.Num() - 1 - i];

                Context.CopyAndPrependStatements(Node, NodeToInline);
            }
        }

        // Proceed to the next node
        ++TestIndex;
    }
}
```

### Set Meta Data
Finally, we set the meta data for the function, this is where we propagate thread-safe flags in the first pass. Also gets called from `SetCalculatedMetaDataAndFlags` in the second pass to catch skeleton class generation.

`MD_ThreadSafe` is a specific metadata key that indicates whether a function is thread-safe. Thread safety means that a function can be safely called from multiple threads simultaneously without causing data corruption or unexpected behavior.

```cpp
// Propagate thread-safe flags in this first pass. Also gets called from SetCalculatedMetaDataAndFlags in the second
// pass to catch skeleton class generation
if (Context.EntryPoint->MetaData.bThreadSafe)
{
    Context.Function->SetMetaData(FBlueprintMetadata::MD_ThreadSafe, TEXT("true"));
}
```

## Backend Emits Generated Code
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The backends convert the collection of statements from each function context into code. There are two backends in use:

- FKismetCompilerVMBackend - Converts FKCS to UnrealScript VM bytecode which are then serialized into the function's script array.
- FKismetCppBackend - Emits C++-like code for debugging purposes only.
</div>

## Dive Even Deeper
At this point, we should already have a clear concept of how the blueprint works: When we write logic in the blueprint graph, we are essentially orchestrate connections or flow or logics, these information were wrapped by their abstract representations - `UEdGraphNode`, in order to reconstruct this flow for execution, we need to disassemble the whole `UBlueprint` into some byte sized commands. Aside from properties, for each function and the `Ubergraph` we expand their corresponding lists of `UEdGraphNode`, then for each `UEdGraphNode` we feed in `FBPTerminal` via `UEdGraphNodePin` by calling `RegisterNets()`, they then gets compiled into `FBlueprintCompiledStatement` by their own `FNodeHandlingFunctor`. Finally, `FBlueprintCompiledStatement` gets parsed into bytecode by `FKismetCompilerVMBackend`.

It makes sense but it's still a bit abstract, a real world example would be nice for comprehension. In the next post, we will walk through a simple blueprint and find out line by line how its bytecode works.



[first post]: https://jaydengames.com/posts/bpvm-bytecode-I/
[DAG Wiki]: https://en.wikipedia.org/wiki/Directed_acyclic_graph