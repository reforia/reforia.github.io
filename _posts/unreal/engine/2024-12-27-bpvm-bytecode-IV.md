---
layout: post
title: "From Blueprint to Bytecode IV - Road to the Root"
description:
    "There's only one last challenge left before we can finally see the bytecode, and that is to compile the functions. In this post, we will go through this very step."
date: 2024-12-27 21:45 +0800
categories: [Unreal, Engine]
published: true
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
For each of the functions, we call `CreateLocalsAndRegisterNets()` on them. Which calls `RegisterNets()` As mentioned in the [first post], this basically tries to link input and output pin to a `FBPTerminal`, so that when the function is compilee later, the input and output values can be passed from or to a concrete place.

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
One tiny but very important step in the above code is the `CreateExecutionSchedule()`, it performs a topological sort on the graph of nodes passed in (which is expected to form a `DAG`), then schedule them. If there are cycles or unconnected nodes present in the graph, an error will be output for each node that failed to be scheduled. The value is then stored in `Context.LinearExecutionList` for later use.

The concept of `DAG` (Directed Acyclic Graph) is very common in computer science, it's a graph that has no cycles, which means you can't go from a node back to itself by following the edges. This is very important in the blueprint graph, as it ensures that the logic is executed in a linear order, and there are no circular dependencies.

For more information on `DAG`, you can check out the [DAG Wiki].

## Anatomy of CompileFunctions()
### Distinguish Skeleton Only Compile and Full Compile
Let's start with the simpler one, if this is not a full compile, then we just go through each function and call `FinishCompilingFunction()` on them. This is to set flags on the functions even for a skeleton class.

>`bIsFullCompile` might be a bit misleading here, basically, if this is false, then we are compiling a skeleton class
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

### Full Compile Process
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

### Post Compile Function
We will dive into `CompileFunction()` in the next section. So here let's skip it for now, assuming the compilation is done, `PostcompileFunction()` is called to finalize the function. This marks the final phase of compiling a function graph; It patches up cross-references, etc..., and performs final validation.

```cpp
/**
 * Final phase of compiling a function graph; called after all functions have had CompileFunction called
 *   - Patches up cross-references, etc..., and performs final validation
 */
void FKismetCompilerContext::PostcompileFunction(FKismetFunctionContext& Context)
{
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_PostcompileFunction);

    // The function links gotos, sorts statments, and merges adjacent ones. 
    Context.ResolveStatements();

    //@TODO: Code generation (should probably call backend here, not later)

    // Seal the function, it's done!
    FinishCompilingFunction(Context);
}
```
>The term "Seal" here means that we are setting the final metadata and flags on the function, passing this point, the function is considered done compiling.
{: .prompt-info }

A couple of important steps gets executed in the `ResolveStatements()` function:
- `FinalSortLinearExecList`
- `ResolveGoToFixups`
- `MergeAdjacentStates`

```cpp
void FKismetFunctionContext::ResolveStatements()
{
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_ResolveCompiledStatements);
    FinalSortLinearExecList();

    static const FBoolConfigValueHelper OptimizeExecutionFlowStack(TEXT("Kismet"), TEXT("bOptimizeExecutionFlowStack"), GEngineIni);
    if (OptimizeExecutionFlowStack)
    {
        bUseFlowStack = AllGeneratedStatements.ContainsByPredicate(&FKismetFunctionContext::DoesStatementRequiresFlowStack);
    }

    ResolveGotoFixups();

    static const FBoolConfigValueHelper OptimizeAdjacentStates(TEXT("Kismet"), TEXT("bOptimizeAdjacentStates"), GEngineIni);
    if (OptimizeAdjacentStates)
    {
        MergeAdjacentStates();
    }
}
```

### FinalSortLinearExecList
Sort the linear execution list for the last time to ensure the correctness of execution order, it's a complex function but here's briefly how it works:
- Get rid of any null nodes as a cleanup
- Copy all the nodes from `LinearExecutionList` to `UnsortedExecutionSet`
- Iterate through the `UnsortedExecutionSet`, starting from the `EntryPoint` from the `FKismetFunctionContext` and then crawl through the whole chain, place `UnconditionalGoto` connected chains together, and also take care of `Branches`
- Finally, copy the sorted nodes back to `LinearExecutionList`

### ResolveGoToFixups
Resolve any goto fixups in the function, it basically just trying to figure out which kind of `Goto` we need to use here.

The actual implementation for this `Goto` involves replacing any `KCST_Goto` with the correct `KCST_GotoReturn` or `KCST_EndOfThread`, `KCST_GotoIfNot` gets replaced with corresponding `KCST_GotoReturnIfNot` or `KCST_EndOfThreadIfNot`. As mentioned before, the significance here is the usage of Flow Stack Execution. If Flow Stack Execution is not required, then `GotoReturn` is used instead of `EndOfThread`, vice versa. `EndOfThread` pops the Flow Stack, while `GotoReturn` does not.

The `IfNot` suffix represents whether this is a `ConditionalGoto` or `UnconditionalGoto`. For an `UnconditionalGoto` we simply jump to the corresponding address, and for a `ConditionalGoto` we will check the condition first, if it's not met, then we jump to the corresponding address.

The only question left is, who has the final say of whether we need to use Flow Stack Execution or not? The answer is `FKismetFunctionContext::DoesStatementRequiresFlowStack()`, if the current statement is `KCST_EndOfThreadIfNot`, `KCST_EndOfThread`, or `KCST_PushState`, then we need to use Flow Stack Execution. Which means the `FNodeHandlingFunctor` can have the freedom to decide whether to use Flow Stack Execution or not.

```cpp
bool FKismetFunctionContext::DoesStatementRequiresFlowStack(const FBlueprintCompiledStatement* Statement)
{
    return Statement && (
        (Statement->Type == KCST_EndOfThreadIfNot) ||
        (Statement->Type == KCST_EndOfThread) ||
        (Statement->Type == KCST_PushState));
}
```

>The Goto we are talking about here is not a node that the designer can write in Blueprint, this concept is more close to assembly code where the code is jumping to another address.
{: .prompt-info}

### MergeAdjacentStates
Merge adjacent states in the function. This is done by iterating over the statements and merging any adjacent `KCST_State` statements into a single `KCST_State` statement. There's a bit more than that, specifically, this function is concerning a special case of `KCST_Goto`, and a special case of `KCST_GotoReturn`

Imagine we have a function A , it calls function B, which calls function C at the end, when we compile it, the end of function B would have an unconditional `KCST_Goto` pointing at the address of C, but if C is right after B in the compiled code, this goto is completely unnecessary and can be removed, that's the first part of the optimization.

A second case is, if we are already at the end of a function, and the last `KCST` is an unconditional `KCST_GotoReturn`, and if no other code cares about this return address, then this state is also removed as redundant because the function would just naturally exit and moving forward even without it.

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
Follow up, we called the `Backend_VM` to generate the bytecode based from function's `FBlueprintCompiledStatement`, `GenerateCodeFromClass()` does the heavy lifting, more on this later.

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

What?! At a glance this might be a bit confusing, but it's actually a clever way to serialize the expressions. The `#include` ensured the content are being embedded here inplace. Which means the actual implementation is done in this `UObject/ScriptSerialization.h` file. This is a very neat way to keep the code clean and organized, as well as reusability.

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

## The Anatomy of CompileFunction()
Obviously, the magic happens in `CompileFunction()`, which converts each function into several `FBlueprintCompiledStatement`. In the next batch (After all functions has been compiled) a BPVM Backend converts them to bytecode in another batch.

In a big picture, the `CompileFunction()` is responsible for generating statements for each node in the linear execution order, then pull out pure chains and inline their generated code into the nodes that need it. Finally, it propagates thread-safe flags.

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

A caveat here is: a pure node can depend on another pure node, in this case `Context.CopyAndPrependStatements(Node, NodeToInline);` will be called to inline the antecedent pure nodes' code.

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

As introduced in the [first post] and in prior section "Generate Bytecode from `FBlueprintCompiledStatement`
". The code in question is:

```cpp
Backend_VM.GenerateCodeFromClass(NewClass, FunctionList, bGenerateStubsOnly);
```

>`FKismetCppBackend` has been moved to it's own module and for debugging purpose only, we will just focus on the `FKismetCompilerVMBackend` here.
{: .prompt-info}

The implementation is not that complicated, it's just loop through each function and call `ConstructFunction()` on them. Then remove duplicates from `CalledFunctions` in the `UBlueprintGeneratedClass`.

```cpp
//////////////////////////////////////////////////////////////////////////
// FKismetCompilerVMBackend

void FKismetCompilerVMBackend::GenerateCodeFromClass(UClass* SourceClass, TIndirectArray<FKismetFunctionContext>& Functions, bool bGenerateStubsOnly)
{
    // Generate script bytecode
    for (int32 i = 0; i < Functions.Num(); ++i)
    {
        FKismetFunctionContext& Function = Functions[i];
        if (Function.IsValid())
        {
            const bool bIsUbergraph = (i == 0);
            ConstructFunction(Function, bIsUbergraph, bGenerateStubsOnly);
        }
    }

    // Remove duplicates from CalledFunctions:
    UBlueprintGeneratedClass* ClassBeingBuilt = CastChecked<UBlueprintGeneratedClass>(SourceClass);
    TSet<UFunction*> Unique(ClassBeingBuilt->CalledFunctions);
    ClassBeingBuilt->CalledFunctions = Unique.Array();
}
```

### Construct Function
For each of the function, `ConstructFunction()` is called, by the comment of the function signature in codebase, it says `builds both the header declaration and body implementation of a function` But this might be a bit ambiguous, as it is actually generating the bytecode for the whole function. The process can be broken down into several steps:
- Push the return address to the Flow Stack if necessary
- Generate code for each statement in the linear execution list
- Handle the function return value
- Fix up jump addresses
- Close out the script
- Save off the offsets within the ubergraph if the function to compile is an `Ubergraph`

```cpp
void FKismetCompilerVMBackend::ConstructFunction(FKismetFunctionContext& FunctionContext, bool bIsUbergraph, bool bGenerateStubOnly)
{
    UFunction* Function = FunctionContext.Function;
    UBlueprintGeneratedClass* Class = FunctionContext.NewClass;

    FString FunctionName;
    Function->GetName(FunctionName);

    TArray<uint8>& ScriptArray = Function->Script;

    // Return statement, to push on FlowStack or to use with _GotoReturn
    FBlueprintCompiledStatement ReturnStatement;
    ReturnStatement.Type = KCST_Return;

    FScriptBuilderBase ScriptWriter(ScriptArray, Class, Schema, UbergraphStatementLabelMap, bIsUbergraph, ReturnStatement);

    if (!bGenerateStubOnly)
    {
        ReturnStatement.bIsJumpTarget = true;
        if (FunctionContext.bUseFlowStack)
        {
            ScriptWriter.PushReturnAddress(ReturnStatement);
        }
    
        // Emit code in the order specified by the linear execution list (the first node is always the entry point for the function)
        for (int32 NodeIndex = 0; NodeIndex < FunctionContext.LinearExecutionList.Num(); ++NodeIndex)
        {
            UEdGraphNode* StatementNode = FunctionContext.LinearExecutionList[NodeIndex];
            TArray<FBlueprintCompiledStatement*>* StatementList = FunctionContext.StatementsPerNode.Find(StatementNode);

            if (StatementList != nullptr)
            {
                for (int32 StatementIndex = 0; StatementIndex < StatementList->Num(); ++StatementIndex)
                {
                    FBlueprintCompiledStatement* Statement = (*StatementList)[StatementIndex];

                    ScriptWriter.GenerateCodeForStatement(CompilerContext, FunctionContext, *Statement, StatementNode);

                    // Abort code generation on error (no need to process additional statements).
                    // ... Other Code
                }
            }

            // Reduce to a stub if any errors were raised. This ensures the VM won't attempt to evaluate an incomplete expression.
            // ... Other Code
        }
    }

    // Handle the function return value
    ScriptWriter.GenerateCodeForStatement(CompilerContext, FunctionContext, ReturnStatement, nullptr);    

    // Fix up jump addresses
    ScriptWriter.PerformFixups();

    // Close out the script
    ScriptWriter.CloseScript();

    // Save off the offsets within the ubergraph, needed to patch up the stubs later on
    if (bIsUbergraph)
    {
        ScriptWriter.CopyStatementMapToUbergraphMap();
    }

    // Make sure we didn't overflow the maximum bytecode size
#if SCRIPT_LIMIT_BYTECODE_TO_64KB
    // ... Other Code
#else
    static_assert(sizeof(CodeSkipSizeType) == 4, "Update this code as size changed.");
#endif
}
```

#### Initialization
The function first retrieves the `UFunction` and the `UBlueprintGeneratedClass` from the `FunctionContext` as well as gets the function's name and stores it in `FunctionName`. It also hold a reference to the function script property.

```cpp
UFunction* Function = FunctionContext.Function;
UBlueprintGeneratedClass* Class = FunctionContext.NewClass;

FString FunctionName;
Function->GetName(FunctionName);

TArray<uint8>& ScriptArray = Function->Script;
```

#### Prepare Return Statement
A return statement is created with type set to `KCST_Return`, and created a `ScriptWriter` for further processing, the `ScriptWriter`.

```cpp
FBlueprintCompiledStatement ReturnStatement;
ReturnStatement.Type = KCST_Return;

FScriptBuilderBase ScriptWriter(ScriptArray, Class, Schema, UbergraphStatementLabelMap, bIsUbergraph, ReturnStatement);
```

#### Generate Code for Each Statement
if `bGenerateStubOnly` is true, then this process is simply skipped. Otherwise we will keep processing each function statements

#### Push Return Address
Marks the `ReturnStatement` as a jump target, meaning other parts of the bytecode can jump to this point. If the function uses a flow stack (a stack-based execution flow), it pushes the return address onto the stack using `ScriptWriter`.

```cpp
ReturnStatement.bIsJumpTarget = true;
if (FunctionContext.bUseFlowStack)
{
    ScriptWriter.PushReturnAddress(ReturnStatement);
}
```

#### GenerateCodeForStatement()
Iterates through each statement in the function's linear execution list, and for each statement, it generates code for the statement using `ScriptWriter.GenerateCodeForStatement()`. If an error is raised during code generation, the function aborts code generation and reduces the function to a stub. We will expand this function later.

```cpp
// Emit code in the order specified by the linear execution list (the first node is always the entry point for the function)
for (int32 NodeIndex = 0; NodeIndex < FunctionContext.LinearExecutionList.Num(); ++NodeIndex)
{
    UEdGraphNode* StatementNode = FunctionContext.LinearExecutionList[NodeIndex];
    TArray<FBlueprintCompiledStatement*>* StatementList = FunctionContext.StatementsPerNode.Find(StatementNode);

    if (StatementList != nullptr)
    {
        for (int32 StatementIndex = 0; StatementIndex < StatementList->Num(); ++StatementIndex)
        {
            FBlueprintCompiledStatement* Statement = (*StatementList)[StatementIndex];

            ScriptWriter.GenerateCodeForStatement(CompilerContext, FunctionContext, *Statement, StatementNode);

            // Abort code generation on error (no need to process additional statements).
            if (FunctionContext.MessageLog.NumErrors > 0)
            {
                break;
            }
        }
    }

    // Reduce to a stub if any errors were raised. This ensures the VM won't attempt to evaluate an incomplete expression.
    if (FunctionContext.MessageLog.NumErrors > 0)
    {
        ScriptArray.Empty();
        ReturnStatement.bIsJumpTarget = false;
        break;
    }
}
```

#### Handle the Function Return Value
Generates code for the function return value using `ScriptWriter.GenerateCodeForStatement()`.

```cpp
// Handle the function return value
ScriptWriter.GenerateCodeForStatement(CompilerContext, FunctionContext, ReturnStatement, nullptr);
```

#### Fix Up Jump Addresses
The primary role of `PerformFixups` is to resolve all placeholder jump addresses within the generated bytecode. During bytecode generation, jump instructions (like branches, loops, or function calls) may reference targets that are not yet known. These placeholders need to be "fixed up" with the correct bytecode offsets once all target addresses are determined. This function is fix up the jump address for the function. For more infomation on the `CommitSkip()` act on each `FBlueprintCompiledStatement`, check section "Fix Up End Goto Index" below.

```cpp
// Fix up all jump targets
void PerformFixups()
{
    for (TMap<CodeSkipSizeType, FCodeSkipInfo>::TIterator It(JumpTargetFixupMap); It; ++It)
    {
        CodeSkipSizeType OffsetToFix = It.Key();
        FCodeSkipInfo& CodeSkipInfo = It.Value();

        CodeSkipSizeType TargetStatementOffset = StatementLabelMap.FindChecked(CodeSkipInfo.TargetLabel);

        Writer.CommitSkip(OffsetToFix, TargetStatementOffset);

        if (CodeSkipInfo.Type == FCodeSkipInfo::InstrumentedDelegateFixup)
        {
            // Register delegate entrypoint offsets
            ClassBeingBuilt->GetDebugData().RegisterEntryPoint(TargetStatementOffset, CodeSkipInfo.DelegateName);
        }
    }

    JumpTargetFixupMap.Empty();
}
```

#### Close Out the Script
Just push in an `EX_EndOfScript` to mark the end of the script. `EX_EndOfScript` is a bytecode token, we will talk about them later.

```cpp
void CloseScript()
{
    Writer << EX_EndOfScript;
}
```

### Save the Label Map Offsets in Ubergraph
If we are compiling a Ubergraph, we need to copy the statement map to the Ubergraph map, this is because the ubergraph is just a giant graph with a bunch of function stubs, when we return back from a statement, we need to know where to jump back to. So this essentially act as an offset of the each **jumpable** statement in the ubergraph.

```cpp
void CopyStatementMapToUbergraphMap()
{
    UbergraphStatementLabelMap = StatementLabelMap;
}
```

>We said "jumpable" because only those statements that are marked as `bIsJumpTarget` will be added to the `StatementLabelMap`, who fits into this criteria? In section "Push Return Address" we know that all return statements are having `bIsJumpTarget` marked true
{: .prompt-info}

## GenerateCodeForStatement() Deep Dive
We are only one step away from our final goal, the bytecode. Once we figured out the in and out of `GenerateCodeForStatement()`, we will have a clear understanding of how the bytecode is generated. Prepare for the final showdown!

```cpp
void GenerateCodeForStatement(FKismetCompilerContext& CompilerContext, FKismetFunctionContext& FunctionContext, FBlueprintCompiledStatement& Statement, UEdGraphNode* SourceNode)
{
    TGuardValue<FKismetCompilerContext*> CompilerContextGuard(CurrentCompilerContext, &CompilerContext);
    TGuardValue<FKismetFunctionContext*> FunctionContextGuard(CurrentFunctionContext, &FunctionContext);

    // Record the start of this statement in the bytecode if it's needed as a target label
    if (Statement.bIsJumpTarget)
    {
        StatementLabelMap.Add(&Statement, Writer.ScriptBuffer.Num());
    }

    // Generate bytecode for the statement
    switch (Statement.Type)
    {
    case KCST_Nop:
        Writer << EX_Nothing;
        break;
    case KCST_CallFunction:
        EmitFunctionCall(CompilerContext, FunctionContext, Statement, SourceNode);
        break;
    case KCST_CallDelegate:
        EmitCallDelegate(Statement);
        break;
    case KCST_Assignment:
        EmitAssignmentStatment(Statement);
        break;
    case KCST_AssignmentOnPersistentFrame:
        EmitAssignmentOnPersistentFrameStatment(Statement);
        break;
    case KCST_CastObjToInterface:
        EmitCastObjToInterfaceStatement(Statement);
        break;
    case KCST_CrossInterfaceCast:
        EmitCastBetweenInterfacesStatement(Statement);
        break;
    case KCST_CastInterfaceToObj:
        EmitCastInterfaceToObjStatement(Statement);
        break;
    case KCST_DynamicCast:
        EmitDynamicCastStatement(Statement);
        break;
    case KCST_MetaCast:
        EmitMetaCastStatement(Statement);
        break;
    case KCST_ObjectToBool:
        EmitObjectToBoolStatement(Statement);
        break;
    case KCST_AddMulticastDelegate:
        EmitAddMulticastDelegateStatement(Statement);
        break;
    case KCST_RemoveMulticastDelegate:
        EmitRemoveMulticastDelegateStatement(Statement);
        break;
    case KCST_BindDelegate:
        EmitBindDelegateStatement(Statement);
        break;
    case KCST_ClearMulticastDelegate:
        EmitClearMulticastDelegateStatement(Statement);
        break;
    case KCST_CreateArray:
        EmitCreateArrayStatement(Statement);
        break;
    case KCST_ComputedGoto:
    case KCST_UnconditionalGoto:
    case KCST_GotoIfNot:
    case KCST_EndOfThreadIfNot:
    case KCST_GotoReturn:
    case KCST_GotoReturnIfNot:
        EmitGoto(Statement);
        break;
    case KCST_PushState:
        EmitPushExecState(Statement);
        break;
    case KCST_EndOfThread:
        EmitPopExecState(Statement);
        break;
    case KCST_Comment:
        // VM ignores comments
        break;
    case KCST_Return:
        EmitReturn(FunctionContext);
        break;
    case KCST_SwitchValue:
        EmitSwitchValue(Statement);
        break;
    case KCST_DebugSite:
    case KCST_WireTraceSite:
    case KCST_InstrumentedEvent:
    case KCST_InstrumentedEventStop:
    case KCST_InstrumentedWireEntry:
    case KCST_InstrumentedWireExit:
    case KCST_InstrumentedStatePush:
    case KCST_InstrumentedStateReset:
    case KCST_InstrumentedStateSuspend:
    case KCST_InstrumentedStatePop:
    case KCST_InstrumentedStateRestore:
    case KCST_InstrumentedPureNodeEntry:
    case KCST_InstrumentedTunnelEndOfThread:
        EmitInstrumentation(CompilerContext, FunctionContext, Statement, SourceNode);
        break;
    case KCST_ArrayGetByRef:
        EmitArrayGetByRef(Statement);
        break;
    case KCST_CreateSet:
        EmitCreateSetStatement(Statement);
        break;
    case KCST_CreateMap:
        EmitCreateMapStatement(Statement);
        break;
    case KCST_DoubleToFloatCast:
    case KCST_FloatToDoubleCast:
        EmitCastStatement(Statement);
        break;
    default:
        UE_LOG(LogK2Compiler, Warning, TEXT("VM backend encountered unsupported statement type %d"), (int32)Statement.Type);
    }
}
```

Yes, after all the hassle and head scratching days, it's just that simple: a giant switch case, covered all the possible `FBlueprintCompiledStatement` types, and then call the corresponding function to emit the bytecode. Remember in the official document this step is called "Backend Emits Generated Code"? This is exactly why - all the bytecode is generated from a "EmitXXX" function, each mapped to one or more `FBlueprintCompiledStatement`. Here's a full list of them:
- EmitFunctionCall
- EmitCallDelegate
- EmitAssignmentStatment
- EmitAssignmentOnPersistentFrameStatment
- EmitCastObjToInterfaceStatement
- EmitCastBetweenInterfacesStatement
- EmitCastInterfaceToObjStatement
- EmitDynamicCastStatement
- EmitMetaCastStatement
- EmitObjectToBoolStatement
- EmitAddMulticastDelegateStatement
- EmitRemoveMulticastDelegateStatement
- EmitBindDelegateStatement
- EmitClearMulticastDelegateStatement
- EmitCreateArrayStatement
- EmitGoto
- EmitPushExecState
- EmitPopExecState
- EmitReturn
- EmitSwitchValue
- EmitInstrumentation
- EmitArrayGetByRef
- EmitCreateSetStatement
- EmitCreateMapStatement
- EmitCastStatement

All we need to know is: these function just act like assembly code, on a linear list of statements, we write in each operations in the lowest level, each operations and value type are actually an evaluable expression type `EExprToken`, For example, a `EX_Return` is a return statement of a function, (the code will trigger a return here) And `EX_IntConst` is an integer constant, `EX_FloatConst` is a floating point constant, etc. We will talk about them later.

>`EX_Return` is **NOT** the "Return Node" that we wrote at the end of a function, we will talk about it's nuance in the next post.
{: .prompt-info}

```cpp
//
// Evaluatable expression item types.
//
enum EExprToken : uint8
{
    // Variable references.
    EX_LocalVariable        = 0x00,    // A local variable.
    EX_InstanceVariable        = 0x01,    // An object variable.
    EX_DefaultVariable        = 0x02, // Default variable for a class context.
    //                        = 0x03,
    EX_Return                = 0x04,    // Return from function.
    //                        = 0x05,
    EX_Jump                    = 0x06,    // Goto a local address in code.
    EX_JumpIfNot            = 0x07,    // Goto if not expression.
    //                        = 0x08,
    EX_Assert                = 0x09,    // Assertion.
    //                        = 0x0A,
    EX_Nothing                = 0x0B,    // No operation.
    EX_NothingInt32            = 0x0C, // No operation with an int32 argument (useful for debugging script disassembly)
    //                        = 0x0D,
    //                        = 0x0E,
    EX_Let                    = 0x0F,    // Assign an arbitrary size value to a variable.
    //                        = 0x10,
    EX_BitFieldConst        = 0x11, // assign to a single bit, defined by an FProperty
    EX_ClassContext            = 0x12,    // Class default object context.
    EX_MetaCast             = 0x13, // Metaclass cast.
    EX_LetBool                = 0x14, // Let boolean variable.
    EX_EndParmValue            = 0x15,    // end of default value for optional function parameter
    EX_EndFunctionParms        = 0x16,    // End of function call parameters.
    EX_Self                    = 0x17,    // Self object.
    EX_Skip                    = 0x18,    // Skippable expression.
    EX_Context                = 0x19,    // Call a function through an object context.
    EX_Context_FailSilent    = 0x1A, // Call a function through an object context (can fail silently if the context is NULL; only generated for functions that don't have output or return values).
    EX_VirtualFunction        = 0x1B,    // A function call with parameters.
    EX_FinalFunction        = 0x1C,    // A prebound function call with parameters.
    EX_IntConst                = 0x1D,    // Int constant.
    EX_FloatConst            = 0x1E,    // Floating point constant.
    EX_StringConst            = 0x1F,    // String constant.
    EX_ObjectConst            = 0x20,    // An object constant.
    EX_NameConst            = 0x21,    // A name constant.
    EX_RotationConst        = 0x22,    // A rotation constant.
    EX_VectorConst            = 0x23,    // A vector constant.
    EX_ByteConst            = 0x24,    // A byte constant.
    EX_IntZero                = 0x25,    // Zero.
    EX_IntOne                = 0x26,    // One.
    EX_True                    = 0x27,    // Bool True.
    EX_False                = 0x28,    // Bool False.
    EX_TextConst            = 0x29, // FText constant
    EX_NoObject                = 0x2A,    // NoObject.
    EX_TransformConst        = 0x2B, // A transform constant
    EX_IntConstByte            = 0x2C,    // Int constant that requires 1 byte.
    EX_NoInterface            = 0x2D, // A null interface (similar to EX_NoObject, but for interfaces)
    EX_DynamicCast            = 0x2E,    // Safe dynamic class casting.
    EX_StructConst            = 0x2F, // An arbitrary UStruct constant
    EX_EndStructConst        = 0x30, // End of UStruct constant
    EX_SetArray                = 0x31, // Set the value of arbitrary array
    EX_EndArray                = 0x32,
    EX_PropertyConst        = 0x33, // FProperty constant.
    EX_UnicodeStringConst   = 0x34, // Unicode string constant.
    EX_Int64Const            = 0x35,    // 64-bit integer constant.
    EX_UInt64Const            = 0x36,    // 64-bit unsigned integer constant.
    EX_DoubleConst            = 0x37, // Double constant.
    EX_Cast                    = 0x38,    // A casting operator which reads the type as the subsequent byte
    EX_SetSet                = 0x39,
    EX_EndSet                = 0x3A,
    EX_SetMap                = 0x3B,
    EX_EndMap                = 0x3C,
    EX_SetConst                = 0x3D,
    EX_EndSetConst            = 0x3E,
    EX_MapConst                = 0x3F,
    EX_EndMapConst            = 0x40,
    EX_Vector3fConst        = 0x41,    // A float vector constant.
    EX_StructMemberContext    = 0x42, // Context expression to address a property within a struct
    EX_LetMulticastDelegate    = 0x43, // Assignment to a multi-cast delegate
    EX_LetDelegate            = 0x44, // Assignment to a delegate
    EX_LocalVirtualFunction    = 0x45, // Special instructions to quickly call a virtual function that we know is going to run only locally
    EX_LocalFinalFunction    = 0x46, // Special instructions to quickly call a final function that we know is going to run only locally
    //                        = 0x47, // CST_ObjectToBool
    EX_LocalOutVariable        = 0x48, // local out (pass by reference) function parameter
    //                        = 0x49, // CST_InterfaceToBool
    EX_DeprecatedOp4A        = 0x4A,
    EX_InstanceDelegate        = 0x4B,    // const reference to a delegate or normal function object
    EX_PushExecutionFlow    = 0x4C, // push an address on to the execution flow stack for future execution when a EX_PopExecutionFlow is executed.   Execution continues on normally and doesn't change to the pushed address.
    EX_PopExecutionFlow        = 0x4D, // continue execution at the last address previously pushed onto the execution flow stack.
    EX_ComputedJump            = 0x4E,    // Goto a local address in code, specified by an integer value.
    EX_PopExecutionFlowIfNot = 0x4F, // continue execution at the last address previously pushed onto the execution flow stack, if the condition is not true.
    EX_Breakpoint            = 0x50, // Breakpoint.  Only observed in the editor, otherwise it behaves like EX_Nothing.
    EX_InterfaceContext        = 0x51,    // Call a function through a native interface variable
    EX_ObjToInterfaceCast   = 0x52,    // Converting an object reference to native interface variable
    EX_EndOfScript            = 0x53, // Last byte in script code
    EX_CrossInterfaceCast    = 0x54, // Converting an interface variable reference to native interface variable
    EX_InterfaceToObjCast   = 0x55, // Converting an interface variable reference to an object
    //                        = 0x56,
    //                        = 0x57,
    //                        = 0x58,
    //                        = 0x59,
    EX_WireTracepoint        = 0x5A, // Trace point.  Only observed in the editor, otherwise it behaves like EX_Nothing.
    EX_SkipOffsetConst        = 0x5B, // A CodeSizeSkipOffset constant
    EX_AddMulticastDelegate = 0x5C, // Adds a delegate to a multicast delegate's targets
    EX_ClearMulticastDelegate = 0x5D, // Clears all delegates in a multicast target
    EX_Tracepoint            = 0x5E, // Trace point.  Only observed in the editor, otherwise it behaves like EX_Nothing.
    EX_LetObj                = 0x5F,    // assign to any object ref pointer
    EX_LetWeakObjPtr        = 0x60, // assign to a weak object pointer
    EX_BindDelegate            = 0x61, // bind object and name to delegate
    EX_RemoveMulticastDelegate = 0x62, // Remove a delegate from a multicast delegate's targets
    EX_CallMulticastDelegate = 0x63, // Call multicast delegate
    EX_LetValueOnPersistentFrame = 0x64,
    EX_ArrayConst            = 0x65,
    EX_EndArrayConst        = 0x66,
    EX_SoftObjectConst        = 0x67,
    EX_CallMath                = 0x68, // static pure function from on local call space
    EX_SwitchValue            = 0x69,
    EX_InstrumentationEvent    = 0x6A, // Instrumentation event
    EX_ArrayGetByRef        = 0x6B,
    EX_ClassSparseDataVariable = 0x6C, // Sparse data variable
    EX_FieldPathConst        = 0x6D,
    //                        = 0x6E,
    //                        = 0x6F,
    EX_AutoRtfmTransact     = 0x70, // AutoRTFM: run following code in a transaction
    EX_AutoRtfmStopTransact = 0x71, // AutoRTFM: if in a transaction, abort or break, otherwise no operation
    EX_AutoRtfmAbortIfNot   = 0x72, // AutoRTFM: evaluate bool condition, abort transaction on false
    EX_Max                    = 0xFF,
};
```

## EmitSwitchValue() Deep Dive
It would took probably another 10 posts to cover all the `EmitXXX` functions (So we aren't planning to do that :D), we are just gonna take a look at a simpler one, `EmitSwitchValue()`, since this is also the example we used in the [first post] when going through `FNodeHandlingFunctor` and `FBlueprintCompiledStatement`. As a refresher, here's briefly the `FBlueprintCompiledStatement` we've generated back then, note that we've pushed the value of the `IndexTerm`, `LiteralTerm` - `ValueTerm` Pair for all the options, and the `DefaultTerm`, all to the `RHS` (Right Hand Side) array of the `SelectStatement`.

```cpp
FBlueprintCompiledStatement* SelectStatement = new FBlueprintCompiledStatement();
SelectStatement->Type = EKismetCompiledStatementType::KCST_SwitchValue;
Context.AllGeneratedStatements.Add(SelectStatement);
ReturnTerm->InlineGeneratedParameter = SelectStatement;
SelectStatement->RHS.Add(IndexTerm);

// ... Other Code
for (int32 OptionIdx = 0; OptionIdx < OptionPins.Num(); ++OptionIdx)
{
    // ... Other Code
    SelectStatement->RHS.Add(LiteralTerm);

    // ... Other Code
    SelectStatement->RHS.Add(ValueTerm);
}

SelectStatement->RHS.Add(DefaultTerm);
```

Since the statement type is `KCST_SwitchValue`, the `EmitSwitchValue()` will be called, and here's a walkthrough of how this statement gets compiled into bytecode:

### Prepare the Statement
First, we defined `TermsBeforeCases` and `TermsPerCase`, `TermsBeforeCases` is 1, because that's the `IndexTerm`, and `TermsPerCase` is 2, because that's the `LiteralTerm` and `ValueTerm` pair for each case.

Then we will check the number of terms in the `RHS` array, it should at least have 4 terms, because we need at least 1 term for the `IndexTerm`, and 2 terms for at least 1 case, and 1 term for the default case. We also checks the modulo of the number of terms, it should always be an even number, because each case should have a pair of `LiteralTerm` and `ValueTerm`. And the `IndexTerm` and `DefaultTerm` already counted as 2 terms, so the total terms should always be an even number.

```cpp
void EmitSwitchValue(FBlueprintCompiledStatement& Statement)
{
    const int32 TermsBeforeCases = 1;
    const int32 TermsPerCase = 2;

    if ((Statement.RHS.Num() < 4) || (1 == (Statement.RHS.Num() % 2)))
    {
        // Error
        ensure(false);
    }

    // ... Other Code
}
```

### Emit the Switch EExprToken
First token gets pushed to the stream is an `EX_SwitchValue`, this is the switch statement expression.

```cpp
Writer << EX_SwitchValue;
```

### Calculate the Number of Cases
The calculation is pretty simple, out of all the `RHS` elements, we subtract the `IndexTerm` and `DefaultTerm`, then divide by `TermsPerCase` (2 in this case, as `LiteralTerm` and `ValueTerm`), the result is the number of cases.

```cpp
// number of cases (without default)
uint16 NumCases = IntCastChecked<uint16, int32>((Statement.RHS.Num() - 2) / TermsPerCase);
Writer << NumCases;
```

### Emit End Goto Index
This is a interesting step, this line actually pushes a placeholder to the ScriptBuffer's end, the idea for that is we need to store the actual size of the bytecode of the statement at the beginning, but at this moment it's impossible to know the actual value, so we just store -1 at the end, and later when the whole bytecode for the statement is generated, we can then patch up this value.

```cpp
CodeSkipSizeType PatchUpNeededAtOffset = Writer.EmitPlaceholderSkip();

//--------------------------------------------------------------------------------------------
CodeSkipSizeType EmitPlaceholderSkip()
{
    CodeSkipSizeType Result = ScriptBuffer.Num();

    CodeSkipSizeType Placeholder = -1;
    (*this) << Placeholder;

    return Result;
}
```
<div class="box-info" markdown="1">
<div class="title"> Important </div>
This `CodeSkipSizeType Placeholder = -1;` has a value of 32bit (`CodeSkipSizeType` is an alias of uint32) however, the `ScriptBuffer` is a `TArray<uint8>`, so we are actually pushing 4 elements of `0xFF` to the stream, not just a single `-1` value.

E.g:
- Original `ScriptBuffer`: `[0x00, 0x01, 0x02, 0x03]`
- `CodeSkipSizeType currentOffset = EmitPlaceholderSkip();`
  - `CodeSkipSizeType Result = ScriptBuffer.Num(); // Result = 4`
  - `CodeSkipSizeType Placeholder = -1; // Placeholder = 0xFFFFFFFF`
  - `(*this) << Placeholder; // Appends 0xFF, 0xFF, 0xFF, 0xFF to ScriptBuffer`
  - `return Result; // Returns 4`
- New `ScriptBuffer`: `[0x00, 0x01, 0x02, 0x03, 0xFF, 0xFF, 0xFF, 0xFF]`
</div>

Next, we are going to process the actual values from the `RHS` array, but there're two important concepts to cover: `EmitTerm()` and `EmitTermExpr()`, 

### Emit Term
it took a `FBPTerminal`, however, it is possible that this `FBPTerminal` is a `InlineGeneratedParameter`, meaning we need to further expand it, hence another `GenerateCodeForStatement()` is called, this is a recursive process, and it will keep expanding until all the `InlineGeneratedParameter` are resolved.

If this is not an `InlineGeneratedParameter`, then we will check if it's a `StructContextType`, if it is, we will emit a `EX_StructMemberContext` token, and then call `EmitTerm()` again with the `Context` of the `FBPTerminal`. This is also a recursive process, eventually, all the path should lead to a `EmitTermExpr()` function, which is the lowest level of the bytecode generation.

```cpp
void EmitTerm(FBPTerminal* Term, const FProperty* CoerceProperty = NULL, FBPTerminal* RValueTerm = NULL)
{
    if (Term->InlineGeneratedParameter)
    {
        ensure(!Term->InlineGeneratedParameter->bIsJumpTarget);
        auto TermSourceAsNode = Cast<UEdGraphNode>(Term->Source);
        auto TermSourceAsPin = Term->SourcePin;
        UEdGraphNode* SourceNode = TermSourceAsNode ? TermSourceAsNode
            : (TermSourceAsPin ? TermSourceAsPin->GetOwningNodeUnchecked() : nullptr);
        if (ensure(CurrentCompilerContext && CurrentFunctionContext))
        {
            GenerateCodeForStatement(*CurrentCompilerContext, *CurrentFunctionContext, *Term->InlineGeneratedParameter, SourceNode);
        }
    }
    else if (Term->Context == NULL)
    {
        EmitTermExpr(Term, CoerceProperty);
    }
    else
    {
        if (Term->Context->IsStructContextType())
        {
            check(Term->AssociatedVarProperty);

            Writer << EX_StructMemberContext;
            Writer << Term->AssociatedVarProperty;

            // Now run the context expression
            EmitTerm(Term->Context, NULL);
        }
        else
        {
            // If this is the top of the chain this context, then save it off the r-value and pass it down the chain so we can safely handle runtime null contexts
            if( RValueTerm == NULL )
            {
                RValueTerm = Term;
            }

            FContextEmitter CallContextWriter(*this);
            FProperty* RValueProperty = RValueTerm->AssociatedVarProperty;
            CallContextWriter.TryStartContext(Term->Context, /*@TODO: bUnsafeToSkip*/ true, /*bIsInterfaceContext*/ false, RValueProperty);

            EmitTermExpr(Term, CoerceProperty);
        }
    }
}
```

### Emit Term Expr
But there are so many types of different value types, how do we generate the corresponding bytecode for them? Well if you are sensing another giant switch case... Yes.

Eventually, a corresponding `EExprToken` will be pushed to the stream based on the term type, followed by the term value, if any. Here's a snippet of the `EmitTermExpr()` function:

```cpp
void EmitTermExpr(FBPTerminal* Term, const FProperty* CoerceProperty = NULL, bool bAllowStaticArray = false, bool bCallerRequiresBit = false)
{
    if (Term->bIsLiteral)
    {
        // ... Other Code for validation
        if (FLiteralTypeHelper::IsString(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsText(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsFloat(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsDouble(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsInt(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsInt64(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsUInt64(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsByte(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsBoolean(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsName(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsStruct(&Term->Type, CoerceProperty))
        {...}
        else if (const FArrayProperty* ArrayPropr = CastField<FArrayProperty>(CoerceProperty))
        {...}
        else if (const FSetProperty* SetPropr = CastField<FSetProperty>(CoerceProperty))
        {...}
        else if (const FMapProperty* MapPropr = CastField<FMapProperty>(CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsDelegate(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsSoftObject(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsFieldPath(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsObject(&Term->Type, CoerceProperty) || FLiteralTypeHelper::IsClass(&Term->Type, CoerceProperty))
        {...}
        else if (FLiteralTypeHelper::IsInterface(&Term->Type, CoerceProperty))
        {...}
        else if (!CoerceProperty && Term->Type.PinCategory.IsNone() && (Term->Type.PinSubCategory == UEdGraphSchema_K2::PN_Self))
        {...}
        // else if (CoerceProperty->IsA(FMulticastDelegateProperty::StaticClass()))
        // Cannot assign a literal to a multicast delegate; it should be added instead of assigned
        else
        {...}
    }
    else
    {
        if (Term->IsDefaultVarTerm())
        {
            Writer << EX_DefaultVariable;
        }
        else if (Term->IsLocalVarTerm())
        {
            Writer << (Term->AssociatedVarProperty->HasAnyPropertyFlags(CPF_OutParm) ? EX_LocalOutVariable : EX_LocalVariable);
        }
        else if (Term->IsSparseClassDataVarTerm())
        {
            Writer << EX_ClassSparseDataVariable;
        }
        else
        {
            Writer << EX_InstanceVariable;
        }
        Writer << Term->AssociatedVarProperty;
    }
}
```

### Emit Index Term
Next part is to get the `IndexTerm` at the `Statement.RHS[0]` and emit it to the stream. This is done by calling `EmitTerm()` function, which is a helper function to emit the bytecode for a `FBPTerminal`.

```cpp
// index term
auto IndexTerm = Statement.RHS[0];
check(IndexTerm);
EmitTerm(IndexTerm);
FProperty* VirtualIndexProperty = IndexTerm->AssociatedVarProperty;
check(VirtualIndexProperty);
```

### Emit Each Case
For each case, we will push their `LiteralTerm` and `ValueTerm` to the stream:

```cpp
for (uint16 TermIndex = TermsBeforeCases; TermIndex < (NumCases * TermsPerCase); ++TermIndex)
{
    EmitTerm(Statement.RHS[TermIndex], VirtualIndexProperty); // it's a literal value
    ++TermIndex;
    CodeSkipSizeType PatchOffsetToNextCase = Writer.EmitPlaceholderSkip();
    EmitTerm(Statement.RHS[TermIndex], VirtualValueProperty);  // it could be literal for 'self'
    Writer.CommitSkip(PatchOffsetToNextCase, Writer.ScriptBuffer.Num());
}
```

### Emit Default Term
Afterwards, we will push the `DefaultTerm` to the stream, this is the last term in the `RHS` array, and it's always the default case.

```cpp
auto DefaultTerm = Statement.RHS[TermsBeforeCases + NumCases*TermsPerCase];
check(DefaultTerm);
FProperty* VirtualValueProperty = DefaultTerm->AssociatedVarProperty;
check(VirtualValueProperty);

EmitTerm(DefaultTerm);
```

### Fix Up End Goto Index
Finally, we will fix up the end go to addresses, since at this moment we already know the size of our function body, we can now replace the placeholder we pushed in the beginning with the actual bytecode offset.

```cpp
Writer.CommitSkip(PatchUpNeededAtOffset, Writer.ScriptBuffer.Num());

// --------------------------------------------------------------------------------------------
void CommitSkip(CodeSkipSizeType WriteOffset, CodeSkipSizeType NewValue)
{
    //@TODO: Any endian issues?
#if SCRIPT_LIMIT_BYTECODE_TO_64KB
    static_assert(sizeof(CodeSkipSizeType) == 2, "Update this code as size changed.");
    ScriptBuffer[WriteOffset] = NewValue & 0xFF;
    ScriptBuffer[WriteOffset+1] = (NewValue >> 8) & 0xFF;
#else
    static_assert(sizeof(CodeSkipSizeType) == 4, "Update this code as size changed.");
    ScriptBuffer[WriteOffset] = NewValue & 0xFF;
    ScriptBuffer[WriteOffset+1] = (NewValue >> 8) & 0xFF;
    ScriptBuffer[WriteOffset+2] = (NewValue >> 16) & 0xFF;
    ScriptBuffer[WriteOffset+3] = (NewValue >> 24) & 0xFF;
#endif
}
```

Since the `NewValue` is a `uint32`, but the `ScriptBuffer` is a `TArray<uint8>`, we need to split the `NewValue` into 4 bytes and write them to the `ScriptBuffer` accordingly. (Hence WriteOffset + 1, +2, +3)

## Grab a Beer!
And that's it! We've successfully compiled a `KCST_SwitchValue` statement into bytecode! What an incredible journey! Grab a beer and celebrate! 🍻

## Dive Even Deeper
At this point, we should already have a clear idea of how the blueprint works: When we write logic in the blueprint graph, we are essentially orchestrate parameters, flow or logics, each of these information were wrapped by their abstract representations - `UEdGraphNode`, in order to reconstruct this flow for execution in a lower level executable manner, we need to compile them by hitting the `Compile` button, this process disassembles the whole `UBlueprint`'s info into a `UBlueprintGeneratedClass`. Aside from properties, for each function and the `Ubergraph` we expand their corresponding lists of `UEdGraphNode`, then for each `UEdGraphNode` we feed in `FBPTerminal` via `UEdGraphNodePin` by calling `RegisterNets()`, they then gets compiled into `FBlueprintCompiledStatement` by their own `FNodeHandlingFunctor`. Finally, `FBlueprintCompiledStatement` gets parsed into bytecode by `FKismetCompilerVMBackend`. Final validation and serialization would happen, and our blueprint is ready to be executed by the VM.

It makes sense but it might still feel a bit abstract, a real world example would be nice. In the next and last post in this series, we will walk through a simple blueprint example and inspect the bytecodes line by line and see how the magic flows.

[first post]: https://jaydengames.com/posts/bpvm-bytecode-I/
[DAG Wiki]: https://en.wikipedia.org/wiki/Directed_acyclic_graph