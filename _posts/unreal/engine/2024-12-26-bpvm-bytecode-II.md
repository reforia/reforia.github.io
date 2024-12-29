---
layout: post
title: "From Blueprint to Bytecode II - Compile and Good to Go"
description:
  "Despite the exhausted challenges faced in the chamber of terminologies, the adventurers managed to reach their bonfire. However, another monster is waiting in the darkness - Compilation"
date: 2024-12-26 01:04 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Load Checkpoint
In the previous post, we explored the Blueprint System in depth, covering its various terminologies and concepts. Now, it’s time to connect the dots and take a closer look at the blueprint compilation process.

## Compilation Process - From Document
According to the official [document], the blueprint compilation process can be broken down into the following steps:

![Blueprint Compilation Process](bytecode_compilationflow.png){: width="400"}

### Digesting the Process
While this may seem like the entire compilation process triggered when you hit the "`Compile`" button, the content in the image is just a small part of it.

Let’s break it down in reverse order to understand the purpose behind it all:
- Final Goal: 
  - The ultimate aim is to generate a class that contains functions, logic, and properties, all of which can be executed at runtime. This class needs to be structured efficiently, with unnecessary graph representations removed (since those are primarily for human readability).
- Conversion: 
  - This means that the graphs and functions need to be converted into an optimized format, namely Bytecode.
- Data Preparation: 
  - To achieve this conversion, we need to prepare the data for the compilation process.
- Data Population: 
  - The process essentially populates data into a `UBlueprintGeneratedClass`. This class serves as a container, where we can store the data. Instead of creating a new class each time, we reuse the existing one, but before doing so, we need to ensure the data is clean and doesn’t interfere with new data (hence, the "Clean and Sanitize Class" step).

Now we can better understand why the process unfolds in this particular way. And lastly, because our modifications may alter the class layout, so we need to "Re-instance" it to reflect the change, we also need to ensure that existing instances in the world are aware of it. So they are also being "Reinstanced".

>The steps mentioned above outline the compilation process for a single blueprint. However, the full process is much more complex, involving nearly 15 different steps. In this series, we'll cover each of these steps from start to finish. 
{: .prompt-info}

## Compile Button - The Trigger
The "`Compile`" button itself is part of the `FBlueprintEditorToolbar::AddCompileToolbar()` function, which is called during the initialization of a `BlueprintEditorMode`. This mode is specifically an instance of `FBlueprintEditorApplicationMode`, which is used by the BlueprintEditor.

![Editor Modes](bytecode_othereditormodes.png){: width="400"}
_Various Editor Modes_

From the codebase, we can also see several custom EditorModes that override or extend the default behavior, including the available tools. The `AddCompileToolbar()` function is essentially a pre-defined template that can be reused across different EditorModes.

```cpp
void FBlueprintEditorToolbar::AddCompileToolbar(UToolMenu* InMenu)
{
    // ... Other Code
    FNewToolMenuSectionDelegate::CreateLambda([](FToolMenuSection& InSection)
    {
        const UBlueprintEditorToolMenuContext* Context = InSection.FindContext<UBlueprintEditorToolMenuContext>();
        if (Context && Context->BlueprintEditor.IsValid() && Context->GetBlueprintObj())
        {
            TSharedPtr<class FBlueprintEditorToolbar> BlueprintEditorToolbar = Context->BlueprintEditor.Pin()->GetToolbarBuilder();
            if (BlueprintEditorToolbar.IsValid())
            {
                const FFullBlueprintEditorCommands& Commands = FFullBlueprintEditorCommands::Get();

                FToolMenuEntry& CompileButton = InSection.AddEntry(FToolMenuEntry::InitToolBarButton(
                    Commands.Compile,
                    TAttribute<FText>(),
                    TAttribute<FText>(BlueprintEditorToolbar.ToSharedRef(), &FBlueprintEditorToolbar::GetStatusTooltip),
                    TAttribute<FSlateIcon>(BlueprintEditorToolbar.ToSharedRef(), &FBlueprintEditorToolbar::GetStatusImage),
                    "CompileBlueprint"));
                CompileButton.StyleNameOverride = "CalloutToolbar";

                FToolMenuEntry& CompileOptions = InSection.AddEntry(FToolMenuEntry::InitComboButton(
                    "CompileComboButton",
                    FUIAction(),
                    FNewToolMenuDelegate::CreateStatic(&BlueprintEditorToolbarImpl::GenerateCompileOptionsMenu),
                    LOCTEXT("BlupeintCompileOptions_ToolbarTooltip", "Options to customize how Blueprints compile")
                ));
                // ... Other Code
            }
        }
    });
}
```

Pretty neat, it adds 2 entries, `CompileButton` and `CompileOptions`, `CompileOption` contains whether we should always save, only on compile success or never.

![Compile Toolbar](bytecode_compileoption.png){: width="400"}

## From Compile to FlushCompilationQueueImpl 
When the `CompileButton` is created, it triggers the `InitToolBarButton` function and passes in `Commands.Compile` as a parameter. This `Commands.Compile` is part of `FFullBlueprintEditorCommands`.

This command is registered early in the Blueprint Editor initialization process, as shown here:

```cpp
void FBlueprintEditor::InitBlueprintEditor(
    const EToolkitMode::Type Mode,
    const TSharedPtr< IToolkitHost >& InitToolkitHost,
    const TArray<UBlueprint*>& InBlueprints,
    bool bShouldOpenInDefaultsMode)
{
  // ... Other Code
    CreateDefaultCommands();
  // ... Other Code
}

void FBlueprintEditor::CreateDefaultCommands()
{
  // ... Other Code
    ToolkitCommands->MapAction(
        FFullBlueprintEditorCommands::Get().Compile,
        FExecuteAction::CreateSP(this, &FBlueprintEditor::Compile),
        FCanExecuteAction::CreateSP(this, &FBlueprintEditor::IsCompilingEnabled));
  // ... Other Code
}
```

Essentially it just act as an event handler, in this case, `Compile` gets mapped to `FBlueprintEditor::Compile()`, and internally it calls `FKismetEditorUtilities::CompileBlueprint()` to do the actual compilation.

```cpp
void FBlueprintEditor::Compile()
{
    DECLARE_SCOPE_HIERARCHICAL_COUNTER_FUNC()

    UBlueprint* BlueprintObj = GetBlueprintObj();
    if (BlueprintObj)
    {
    // ... Other Code
        FKismetEditorUtilities::CompileBlueprint(BlueprintObj, CompileOptions, &LogResults);
    // ... Other Code
    }
}
```

`FKismetEditorUtilities::CompileBlueprint()` is a wrapper function that calls `FBlueprintCompilationManager::CompileSynchronously()`, which is another wrapper function that calls `BPCMImpl->CompileSynchronouslyImpl()`

```cpp
void FKismetEditorUtilities::CompileBlueprint(UBlueprint* BlueprintObj, EBlueprintCompileOptions CompileFlags, FCompilerResultsLog* pResults)
{
    DECLARE_SCOPE_HIERARCHICAL_COUNTER_FUNC()

    FBlueprintCompilationManager::CompileSynchronously(FBPCompileRequest(BlueprintObj, CompileFlags, pResults));
}

void FBlueprintCompilationManager::CompileSynchronously(const FBPCompileRequest& Request)
{
    if(BPCMImpl)
    {
        BPCMImpl->CompileSynchronouslyImpl(Request);
    }
}
```

Let's chop it to a simpler form:
First, it tries to get the compile options from a series of flags:
- `bIsRegeneratingOnLoad`
- `bRegenerateSkeletonOnly`
- `bSkipGarbageCollection`
- `bBatchCompile`
- `bSkipReinstancing`
- `bSkipSaving`
- `bFindAndReplaceCDOReferences`

Then if all necessary checks passed, the `Request` is added to the `QueuedRequests` array, then it calls `FlushCompilationQueueImpl()` to do the actual compilation. Followed by `FlushReinstancingQueueImpl()`, At this point, once we broadcast the event for clients, the compilation is completely done.

```cpp
void FBlueprintCompilationManagerImpl::CompileSynchronouslyImpl(const FBPCompileRequestInternal& Request)
{
    // ... Other Code to do checks

    QueuedRequests.Add(Request);

    // ... Other Code

    FlushCompilationQueueImpl(bSuppressBroadcastCompiled, &CompiledBlueprints, &SkeletonCompiledBlueprints, nullptr, bFindAndReplaceCDOReferences ? &OldToNewTemplates : nullptr);
    FlushReinstancingQueueImpl(bFindAndReplaceCDOReferences, bFindAndReplaceCDOReferences ? &OldToNewTemplates : nullptr);
    
    // For level scripting, we need to update the bound events after the Blueprint has been recompiled
    if (FBlueprintEditorUtils::IsLevelScriptBlueprint(Request.UserData.BPToCompile) && !bRegenerateSkeletonOnly){...}

    // Make sure clients know they're being reinstanced as part of blueprint compilation. After this point. compilation is completely done:
    if ( GEditor && !bRegenerateSkeletonOnly){...}
    
    // If we're not regenerating the skeleton, we need to do a GC to clean up any old objects that are no longer referenced
    if(!bSkipGarbageCollection){...}

    // Broadcast the changed event for all compiled Skeleton Compiled Blueprints
    if (!bRegenerateSkeletonOnly){...}
    // ... Other Code

    // Broadcast the compiled event
    if (!bBatchCompile && !bRegenerateSkeletonOnly){...}

    // Save all the compiled blueprints
    if (CompiledBlueprintsToSave.Num() > 0 && !bRegenerateSkeletonOnly){...}

    // We've done our GC, so release old CDO references
    OldCDOs.Empty();
}
```

>You guessed it right, the `FlushCompilationQueueImpl()` is the main function that does the heavy lifting, it's written with a whopping 1200+ lines of codes, given the complexity of the scope, we are just gonna... well, we are not gonna give up until we see the bottom of it!
{: .prompt-info}

## FlushCompilationQueueImpl - The Heavy Lifter
As mentioned before, this function comes from `FBlueprintCompilationManager` We are lucky that the function is very well documented in the codebase, a paragraph can be found in the class header:

```cpp
/*
    BLUEPRINT COMPILATION MANAGER IMPLEMENTATION NOTES

    INPUTS: UBlueprint, UEdGraph, UEdGraphNode, UEdGraphPin, references to UClass, UProperties
    INTERMEDIATES: Cloned Graph, Nodes, Pins
    OUPUTS: UClass, UProperties

    The blueprint compilation manager addresses shortcomings of compilation 
    behavior (performance, correctness) that occur when compiling blueprints 
    that are inter-dependent. If you are using blueprints and there are no dependencies
    between blueprint compilation outputs and inputs, then this code is completely
    unnecessary and you can directly interface with FKismetCompilerContext and its
    derivatives.

    In order to handle compilation correctly the manager splits compilation into
    the following stages (implemented below in FlushCompilationQueueImpl):

    STAGE I: GATHER
    STAGE II: FILTER
    STAGE III: SORT
    STAGE IV: SET TEMPORARY BLUEPRINT FLAGS
    STAGE V: VALIDATE
    STAGE VI: PURGE (LOAD ONLY)
    STAGE VII: DISCARD SKELETON CDO
    STAGE VIII: RECOMPILE SKELETON
    STAGE IX: RECONSTRUCT NODES, REPLACE DEPRECATED NODES (LOAD ONLY)
    STAGE X: CREATE REINSTANCER (DISCARD 'OLD' CLASS)
    STAGE XI: CREATE UPDATED CLASS HIERARCHY
    STAGE XII: COMPILE CLASS LAYOUT
    STAGE XIII: COMPILE CLASS FUNCTIONS
    STAGE XIV: REINSTANCE
    STAGE XV: POST CDO COMPILED 
    STAGE XVI: CLEAR TEMPORARY FLAGS

    The code that implements these stages are labeled below. At some later point a final
    reinstancing operation will occur, unless the client is using CompileSynchronously, 
    in which case the expensive object graph find and replace will occur immediately
*/
```

### Stage 0: The Before and After
The scope is managed by the `TRACE_CPUPROFILER_EVENT_SCOPE` macro, which is used to profile CPU events. This is an great tool for measuring the performance of code, especially in large codebases. After performing some checks, a `FScopedSlowTask` is created. This task is responsible for showing a progress bar to the user during the compilation process, preventing them from thinking the application has frozen.

Once the process is complete, it logs the time spent on compiling and reinstancing, then resets the timer. Sweet.

```cpp
void FBlueprintCompilationManagerImpl::FlushCompilationQueueImpl(bool bSuppressBroadcastCompiled, TArray<UBlueprint*>* BlueprintsCompiled, TArray<UBlueprint*>* BlueprintsCompiledOrSkeletonCompiled, FUObjectSerializeContext* InLoadContext, TMap<UClass*, TMap<UObject*, UObject*>>* OldToNewTemplates /* = nullptr*/)
{
    TRACE_CPUPROFILER_EVENT_SCOPE(FlushCompilationQueueImpl);

#if WITH_EDITOR
    FScopeLock ScopeLock(&Lock);
#endif

    TGuardValue<bool> GuardTemplateNameFlag(GCompilingBlueprint, true);
    ensure(bGeneratedClassLayoutReady);

    if( QueuedRequests.Num() == 0 )
    {
        return;
    }

    FScopedSlowTask SlowTask(17.f /* Number of steps */, LOCTEXT("FlushCompilationQueue", "Compiling blueprints..."));
    SlowTask.MakeDialogDelayed(1.0f);

    // ... Actual Compilation Work Code

    UE_LOG(LogBlueprint, Display, TEXT("Time Compiling: %f, Time Reinstancing: %f"),  GTimeCompiling, GTimeReinstancing);
    //GTimeCompiling = 0.0;
    //GTimeReinstancing = 0.0;
    VerifyNoQueuedRequests(CurrentlyCompilingBPs);
}
```

### Stage I: GATHER
This stage is responsible for gathering all the blueprints that need to be compiled, and then add any children

```cpp
// STAGE I: Add any related blueprints that were not compiled, then add any children so that they will be relinked:
TArray<UBlueprint*> BlueprintsToRecompile;

// First add any dependents of macro libraries that are being compiled:
for(const FBPCompileRequestInternal& CompileJob : QueuedRequests)
{...}

// ... Other Code

// then make sure any normal blueprints have their bytecode dependents recompiled, this is in case a function signature changes:
for(const FBPCompileRequestInternal& CompileJob : QueuedRequests)
{
    if ((CompileJob.UserData.CompileOptions & EBlueprintCompileOptions::RegenerateSkeletonOnly) != EBlueprintCompileOptions::None)
    {
        continue;
    }

    // Add any dependent blueprints for a bytecode compile, this is needed because we 
    // have no way to keep bytecode safe when a function is renamed or parameters are
    // added or removed. Below (Stage VIII) we skip further compilation for blueprints 
    // that are being bytecode compiled, but their dependencies have not changed:
    TArray<UBlueprint*> DependentBlueprints;
    FBlueprintEditorUtils::GetDependentBlueprints(CompileJob.UserData.BPToCompile, DependentBlueprints);
    for(UBlueprint* DependentBlueprint : DependentBlueprints)
    {
        if(!IsQueuedForCompilation(DependentBlueprint))
        {
            DependentBlueprint->bQueuedForCompilation = true;
            // Because we're adding this as a bytecode only blueprint compile we don't need to 
            // recursively recompile dependencies. The assumption is that a bytecode only compile
            // will not change the class layout. @todo: add an ensure to detect class layout changes
            CurrentlyCompilingBPs.Emplace(
                FCompilerData(
                    DependentBlueprint, 
                    ECompilationManagerJobType::Normal, 
                    nullptr, 
                    EBlueprintCompileOptions::None,
                    true
                )
            );
            BlueprintsToRecompile.Add(DependentBlueprint);
        }
    }
}
```

### Stage II: FILTER
The purpose of this stage is to filter out data only and interface blueprints, and prevent 'pending kill' blueprints from being recompiled. Dependency gathering is currently done for the following reasons:
- Update a caller's called functions when they are recreated
- Update a child type's cached information about its superclass
- Update a child type's class layout when a parent type layout changes
- Update a reader/writers references to member variables when member variables are recreated

Pending kill objects do not need these updates and `StaticDuplicateObject` cannot duplicate them - so they cannot be updated as normal, anyway.

Ultimately pending kill `UBlueprintGeneratedClass` instances rely on the `GetDerivedClasses/ReparentChild`
calls in `FBlueprintCompileReinstancer()` to maintain accurate class layouts so that we don't leak or scribble memory.

>Above comments are directly from the codebase.
{: .prompt-info}

### Stage III: SORT
This stage is responsible for sorting the blueprints to be compiled by hierarchy depth, and then by reinstancer order. The hierarchy depth sort is done by checking if the blueprint is an interface, and then by calling `FBlueprintCompileReinstancer::ReinstancerOrderingFunction` to sort by reinstancer order.

```cpp
auto HierarchyDepthSortFn = [](const FCompilerData& CompilerDataA, const FCompilerData& CompilerDataB)
{
    UBlueprint& A = *(CompilerDataA.BP);
    UBlueprint& B = *(CompilerDataB.BP);

    bool bAIsInterface = FBlueprintEditorUtils::IsInterfaceBlueprint(&A);
    bool bBIsInterface = FBlueprintEditorUtils::IsInterfaceBlueprint(&B);

    if(bAIsInterface && !bBIsInterface)
    {
        return true;
    }
    else if(bBIsInterface && !bAIsInterface)
    {
        return false;
    }

    return FBlueprintCompileReinstancer::ReinstancerOrderingFunction(A.GeneratedClass, B.GeneratedClass);
};
CurrentlyCompilingBPs.Sort( HierarchyDepthSortFn );
```

### Stage IV: SET TEMPORARY BLUEPRINT FLAGS
For each blueprint that is being compiled, set the `bBeingCompiled` flag to true, and set the `CurrentMessageLog` to the `ActiveResultsLog`. If the blueprint has not been regenerated and has a linker, set the `bIsRegeneratingOnLoad` flag to true. If the blueprint should reset its error state, clear all compiler messages from the blueprint's graphs.

```cpp
// STAGE IV: Set UBlueprint flags (bBeingCompiled, bIsRegeneratingOnLoad)
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    if (!CompilerData.ShouldSetTemporaryBlueprintFlags())
    {
        continue;
    }

    UBlueprint* BP = CompilerData.BP;
    BP->bBeingCompiled = true;
    BP->CurrentMessageLog = CompilerData.ActiveResultsLog;
    BP->bIsRegeneratingOnLoad = !BP->bHasBeenRegenerated && BP->GetLinker();

    if(CompilerData.ShouldResetErrorState())
    {
        TArray<UEdGraph*> AllGraphs;
        BP->GetAllGraphs(AllGraphs);
        for (UEdGraph* Graph : AllGraphs )
        {
            for (UEdGraphNode* GraphNode : Graph->Nodes)
            {
                if (GraphNode)
                {
                    GraphNode->ClearCompilerMessage();
                }
            }
        }
    }
}
```

### Stage V - Phase 1: VALIDATE
This is a pretty good checkpoint to validate the variable names and class property defaults for each blueprint that is being compiled, before the actual per blueprint compilation process begins.

```cpp
// STAGE V: Validate
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    if(!CompilerData.ShouldValidate())
    {
        continue;
    }

    CompilerData.Compiler->ValidateVariableNames();
    CompilerData.Compiler->ValidateClassPropertyDefaults();
}
```

`ValidateVariableNames()` checks if there are any variable name conflicts (Done by `FKismetNameValidator()`), if so it will rename the variable to a unique name. Also, If the parent class is a native class, it will check if the variable name is already taken by a native class, and if it is and the variable type is the same, it will remove the blueprint variable and use the native variable wherever it is referenced.

The whole idea of `ValidateClassPropertyDefaults()` is to check if the default value of a class property is of the correct type. If the variable type has been changed since the last check, and a newer CDO has not been generated yet, it will check the default type of the property and log an error if the default type is invalid.

### Stage V - Phase 2: Give the blueprint the possibility for edits
Used for performing custom patching during stage IX of the compilation during load.

```cpp
// STAGE V (phase 2): Give the blueprint the possibility for edits
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    UBlueprint* BP = CompilerData.BP;
    if (BP->bIsRegeneratingOnLoad)
    {
        FKismetCompilerContext& CompilerContext = *(CompilerData.Compiler);
        CompilerContext.PreCompileUpdateBlueprintOnLoad(BP);
    }
}
```

### Stage VI: PURGE (LOAD ONLY)
At this stage, the compiler does the following behavior:
- Purges null graphs
  - Get rid of null graphs from:
  - `UbergraphPages`
  - `FunctionGraphs`
  - `DelegateSignatureGraphs`
  - `MacroGraphs`
- Conforms native components
  - Updates the blueprint's `OwnedComponents`, such that they reflect changes made natively since the blueprint was last saved (a change in `AttachParents`, etc.) It's also a fix used to handle reparenting
- Changes the owner of templates for older blueprints
  - This is a backward compatibility fix for blueprints that were saved before the `VER_UE4_EDITORONLY_BLUEPRINTS` version

```cpp
// STAGE VI: Purge null graphs, misc. data fixup
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    UBlueprint* BP = CompilerData.BP;
    if(BP->bIsRegeneratingOnLoad)
    {
        FBlueprintEditorUtils::PurgeNullGraphs(BP);
        BP->ConformNativeComponents();
        if (FLinkerLoad* Linker = BP->GetLinker())
        {
            if (Linker->UEVer() < VER_UE4_EDITORONLY_BLUEPRINTS)
            {
                BP->ChangeOwnerOfTemplates();
            }
        }
    }
}
```

### Stage VII: DISCARD SKELETON CDO
Two functions are mainly used in this stage:

`MoveDependentSkelToReinst`:
- Moves CDOs aside to immutable versions of classes(`REINST`) so that the CDO's can safely be GC'd. These `REINST` classes will be re-parented to a native parent that we know will not be churning through this function again later, so we avoid O(N^2) processing of REINST classes. Maps each given `SKEL` class to its appropriate `REINST` version of itself

`MoveSkelCDOAside`:
- Recursive function to move CDOs aside to immutable versions of classes
so that CDOs can be safely GC'd. Recursion is necessary to find REINST_ classes
that are still parented to a valid SKEL (e. g. from MarkBlueprintAsStructurallyModified)
and therefore need to be REINST_'d again before the SKEL is mutated... Normally
these old REINST_ classes are GC'd but, there is no guarantee of that:

>These comments are directly from the codebase.
{: .prompt-info}

```cpp
// STAGE VII: safely throw away old skeleton CDOs:
using namespace UE::Kismet::BlueprintCompilationManager;

TMap<UClass*, UClass*> NewSkeletonToOldSkeleton;
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    UBlueprint* BP = CompilerData.BP;
    UClass* OldSkeletonClass = BP->SkeletonGeneratedClass;
    if(OldSkeletonClass)
    {
        if (Private::ConsoleVariables::bEnableSkelReinstUpdate)
        {
            TRACE_CPUPROFILER_EVENT_SCOPE(MoveDependentSkelToReinst);

            FBlueprintCompileReinstancer::MoveDependentSkelToReinst(OldSkeletonClass, NewSkeletonToOldSkeleton);
        }
        else
        {
            // Old code path
            MoveSkelCDOAside(OldSkeletonClass, NewSkeletonToOldSkeleton);
        }
    }
}
```

### Stage VIII: RECOMPILE SKELETON
Detect any variable-based properties that are not in the old generated class, save them for after reinstancing. This can occur when a new variable is introduced in an ancestor class, and we'll need to use its default as our generated class's initial value.

>These comments are directly from the codebase.
{: .prompt-info}

### Stage IX: RECONSTRUCT NODES, REPLACE DEPRECATED NODES (LOAD ONLY)
Go through all the nodes and call their corresponding `ReconstructNode()` function. Each node can now have the chance to establish their connections or do whatever they need to do during reconstruction. Similarly, the `ReplaceDeprecatedNodes()` is called so that `EditorSchema` class can have the chance to replace deprecated nodes with their newer counterparts.

```cpp
// STAGE IX: Reconstruct nodes and replace deprecated nodes, then broadcast 'precompile
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    // ... Other Code
    // Some nodes are set up to do things during reconstruction only when this flag is NOT set.
    if(BP->bIsRegeneratingOnLoad)
    {
        FBlueprintEditorUtils::ReconstructAllNodes(BP);
        FBlueprintEditorUtils::ReplaceDeprecatedNodes(BP);
    }
    // ... Other Code
    
    // Broadcast pre-compile
    {
        if(GEditor && GIsEditor)
        {
            GEditor->BroadcastBlueprintPreCompile(BP);
        }
    }

    // ... Other Code

    // we are regenerated, tag ourself as such so that
    // old logic to 'fix' circular dependencies doesn't
    // cause redundant regeneration (e.g. bForceRegenNodes
    // in ExpandTunnelsAndMacros):
    BP->bHasBeenRegenerated = true;
}
```

### Stage X: CREATE REINSTANCER (DISCARD 'OLD' CLASS)
Reinstance every blueprint that is queued, note that this means classes in the hierarchy that are *not* being compiled will be parented to REINST versions of the class, so type checks (IsA, etc) involving those types will be incoherent!

>These comments are directly from the codebase.
{: .prompt-info}

```cpp
// STAGE X: reinstance every blueprint that is queued, note that this means classes in the hierarchy that are *not* being 
// compiled will be parented to REINST versions of the class, so type checks (IsA, etc) involving those types
// will be incoherent!
{
    TRACE_CPUPROFILER_EVENT_SCOPE(ReinstanceQueued);
    for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
    {
        // we including skeleton only compilation jobs for reinstancing because we need UpdateCustomPropertyListForPostConstruction
        // to happen (at the right time) for those generated classes as well. This means we *don't* need to reinstance if 
        // the parent is a native type (unless we hot reload, but that should not need to be handled here):
        if(CompilerData.ShouldSkipReinstancerCreation())
        {
            continue;
        }

        // no need to reinstance skeleton or relink jobs that are not in a hierarchy that has had reinstancing initiated:
        bool bRequiresReinstance = CompilerData.ShouldInitiateReinstancing();
        if (!bRequiresReinstance)
        {
            UClass* Iter = CompilerData.BP->GeneratedClass;
            if (!Iter)
            {
                bRequiresReinstance = true;
            }
            while (Iter)
            {
                if (Iter->HasAnyClassFlags(CLASS_NewerVersionExists))
                {
                    bRequiresReinstance = true;
                    break;
                }

                Iter = Iter->GetSuperClass();
            }
        }

        if (!bRequiresReinstance)
        {
            continue;
        }

        UBlueprint* BP = CompilerData.BP;
        SCOPED_LOADTIMER_ASSET_TEXT(*BP->GetPathName());

        if(BP->GeneratedClass)
        {
            OldCDOs.Add(BP, BP->GeneratedClass->ClassDefaultObject);
        }

        EBlueprintCompileReinstancerFlags CompileReinstancerFlags =
            EBlueprintCompileReinstancerFlags::AutoInferSaveOnCompile
            | EBlueprintCompileReinstancerFlags::AvoidCDODuplication;

        if (CompilerData.UseDeltaSerializationDuringReinstancing())
        {
            CompileReinstancerFlags |= EBlueprintCompileReinstancerFlags::UseDeltaSerialization;
        }

        CompilerData.Reinstancer = TSharedPtr<FBlueprintCompileReinstancer>(
            new FBlueprintCompileReinstancer(
                BP->GeneratedClass,
                CompileReinstancerFlags
            )
        );

        if(CompilerData.Compiler.IsValid())
        {
            CompilerData.Compiler->OldClass = Cast<UBlueprintGeneratedClass>(CompilerData.Reinstancer->DuplicatedClass);
        }

        if(BP->GeneratedClass)
        {
            BP->GeneratedClass->bLayoutChanging = true;
            CompilerData.Reinstancer->SaveSparseClassData(BP->GeneratedClass);
        }
    }
}
```

### Stage XI: CREATE UPDATED CLASS HIERARCHY
Two things are happening here: first it updates the class hierarchy for the `GeneratedClass`, and then, it takes ownership of the `SparseClassData` for the `GeneratedClass`.

The `SCD` or `Sparse Class Data` here is a new feature, what it does is it tries to reduce the memory footprint of the `GeneratedClass` by storing only the necessary data, while remaining one shared data for all instances of an actor. As a result, the memory usage in shipping build is reduced. Here is a comprehensive official [SCD Document].

```cpp
// STAGE XI: Reinstancing done, lets fix up child->parent pointers and take ownership of SCD:
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    UBlueprint* BP = CompilerData.BP;
    if(BP->GeneratedClass && BP->GeneratedClass->GetSuperClass()->HasAnyClassFlags(CLASS_NewerVersionExists))
    {
        BP->GeneratedClass->SetSuperStruct(BP->GeneratedClass->GetSuperClass()->GetAuthoritativeClass());
    }
    if(BP->GeneratedClass && CompilerData.Reinstancer.IsValid())
    {
        CompilerData.Reinstancer->TakeOwnershipOfSparseClassData(BP->GeneratedClass);
    }
}
```

>we will briefly go through Stage XII to Stage XIV here, and explore them in detail in the next post, as there are too much stuff to cover.
{: .prompt-info}

### Stage XII: COMPILE CLASS LAYOUT
Finally, we are at the beginning of this post, at a glance it's not too complex, however if we still remembered what the last post was about, we know that this `FKismetCompilerContext::CompileClassLayout()` is nowhere near trivial, this chunk just hides the complexity.

Among all the steps for compiling a blueprint (The image at the beginning), the following steps are finished in `CompileClassLayout()`:
- Clean and Sanitize Class
- Create Class Variables From Blueprint
- Create Functions List
  - Create and Process Ubergraph
  - Process One Function Graph
  - Precompile Function

```cpp
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    UBlueprint* BP = CompilerData.BP;
    if(CompilerData.ShouldCompileClassLayout())
    {
        // ... Other Code

        // default value propagation occurs in ReinstaneBatch, CDO will be created via CompileFunctions call:
        if(BP->ParentClass)
        {
            if(BP->GeneratedClass)
            {
                BP->GeneratedClass->ClassDefaultObject = nullptr;
            }

            // Reset the flag, so if the user tries to use PIE it will warn them if the BP did not compile
            BP->bDisplayCompilePIEWarning = true;

            // this will create FProperties for the UClass and generate the sparse class data
            // if the compiler in question wants to:
            FKismetCompilerContext& CompilerContext = *(CompilerData.Compiler);
            CompilerContext.CompileClassLayout(EInternalCompilerFlags::PostponeLocalsGenerationUntilPhaseTwo);

            // ... Other Code
        }
        // ... Other Code
    }
    // ... Other Code
}
```

Then, `Bind` and `StaticLink` is performend. As the step:
- Bind and Link

```cpp
// We immediately relink children so that iterative compilation logic has an easier time:
TArray<UClass*> ClassesToRelink;
GetDerivedClasses(BP->GeneratedClass, ClassesToRelink, false);
for (UClass* ChildClass : ClassesToRelink)
{
    ChildClass->Bind();
    ChildClass->StaticLink();
    ensure(ChildClass->ClassDefaultObject == nullptr);
}
```

### Stage XIII: COMPILE FUNCTIONS
A lot of checks and misc operations are being performed in this function, but the major part is the `CompileFunctions()` function call, this matches with the step in Epic's official document:
- Copy CDO Properties
- Backend Generate Bytecode
- Finish Compiling Class

```cpp
// STAGE XIII: Compile functions
// ... Other Code
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    // ... Other Code
    {
        // ... Other Code
        // default value propagation occurs below:
        if(BPGC)
        {
            // ... Other Code
            FKismetCompilerContext& CompilerContext = *(CompilerData.Compiler);
            CompilerContext.CompileFunctions(
                EInternalCompilerFlags::PostponeLocalsGenerationUntilPhaseTwo
                |EInternalCompilerFlags::PostponeDefaultObjectAssignmentUntilReinstancing
                |EInternalCompilerFlags::SkipRefreshExternalBlueprintDependencyNodes
            ); 
        }
        // ... Other Code
    }
    // ... Other Code
}
```

### Stage XIV: REINSTANCE (Class)
This stage is responsible for moving old classes to new classes, corresponding *Part* to the step in the official document:
- Copy Class Default Object Properties
- Reinstance

`ReinstanceBatch()` calls `CopyPropertiesForUnrelatedClasses()` to copy properties from the old class to the new class, as well as from old instance to new instance. This resonates with Epic's official document:

<div class="box-info" markdown="1">
<div class="title"> Copy Class Default Object Properties </div>
Using a special function, `CopyPropertiesForUnrelatedObjects()`, the compiler copies the values from the old CDO of the class into the new CDO. Properties are copied via tagged serialization, so as long as the names are consistent, they should properly be transferred. Components of the CDO are re-instanced and fixed up appropriately at this stage. The GeneratedClass CDO is authoritative.
</div>

<div class="box-info" markdown="1">
<div class="title"> Re-Instance </div>
Since the class may have changed size and properties may have been added or removed, the compiler needs to re-instance all objects with the class that were just compiled. This process uses a TObjectIterator to find all instances of the class, spawn a new one, and then uses the `CopyPropertiesForUnrelatedObjects()` function to copy from the old instance to the new one.
</div>

>Note that at this moment we are just reinstancing the class, not the instances of the class, this will be handled later
{: .prompt-info}

```cpp
// STAGE XIV: Now we can finish the first stage of the reinstancing operation, moving old classes to new classes:
{
    TRACE_CPUPROFILER_EVENT_SCOPE(MoveOldClassesToNewClasses);

    TArray<FReinstancingJob> Reinstancers;
    // Set up reinstancing jobs - we need a reference to the compiler in order to honor 
    // CopyTermDefaultsToDefaultObject
    for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
    {
        if(CompilerData.Reinstancer.IsValid() && CompilerData.Reinstancer->ClassToReinstance)
        {
            Reinstancers.Push(
                FReinstancingJob( CompilerData.Reinstancer, CompilerData.Compiler )
            );
        }
    }

    FScopedDurationTimer ReinstTimer(GTimeReinstancing);
    ReinstanceBatch(Reinstancers, MutableView(ClassesToReinstance), InLoadContext, OldToNewTemplates);

    // We purposefully do not remove the OldCDOs yet, need to keep them in memory past first GC
}
```

### Stage XV: POST CDO COMPILED
At this point, the blueprint is already compiled, only a few housekeeping tasks are left, such as calling the `PostCDOCompiled()` function, which act as a callback event for the blueprint to do any post-compilation tasks.

```cpp
// STAGE XV: POST CDO COMPILED
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    TRACE_CPUPROFILER_EVENT_SCOPE(PostCDOCompiled);

    if (CompilerData.Compiler.IsValid())
    {
        SCOPED_LOADTIMER_ASSET_TEXT(*CompilerData.BP->GetPathName());
        UObject::FPostCDOCompiledContext PostCDOCompiledContext;
        PostCDOCompiledContext.bIsRegeneratingOnLoad = CompilerData.BP->bIsRegeneratingOnLoad;
        PostCDOCompiledContext.bIsSkeletonOnly = CompilerData.IsSkeletonOnly();

        CompilerData.Compiler->PostCDOCompiled(PostCDOCompiledContext);
    }
}
```

### Stage XVI: CLEAR TEMPORARY FLAGS
Then, this stage is to clear the temporary flags that were set in the beginning of the compilation process. So that the blueprint compilation is ready from outer perspective (Other class checking the RF flags of this class won't find temporary flags anymore).

### Stage AFTERMATH
The function description didn't mention this, but the last bit is clear junk in bytecode, store the compiled blueprints, and broadcast the compiled event. After that, log the necessary information, and we've reached the actual end of the compilation process.

```cpp
// Make sure no junk in bytecode, this can happen only for blueprints that were in CurrentlyCompilingBPs because
// the reinstancer can detect all other references (see UpdateBytecodeReferences):
for (FCompilerData& CompilerData : CurrentlyCompilingBPs)
{
    if(CompilerData.ShouldCompileClassFunctions())
    {
        if(BlueprintsCompiled)
        {
            BlueprintsCompiled->Add(CompilerData.BP);
        }
        
        if(!bSuppressBroadcastCompiled)
        {
            // Some logic (e.g. UObject::ProcessInternal) uses this flag to suppress warnings:
            TGuardValue<bool> ReinstancingGuard(GIsReinstancing, true);
            CompilerData.BP->BroadcastCompiled();
        }

        continue;
    }

    UBlueprint* BP = CompilerData.BP;
    for( TFieldIterator<UFunction> FuncIter(BP->GeneratedClass, EFieldIteratorFlags::ExcludeSuper); FuncIter; ++FuncIter )
    {
        UFunction* CurrentFunction = *FuncIter;
        if( CurrentFunction->Script.Num() > 0 )
        {
            FFixupBytecodeReferences ValidateAr(CurrentFunction);
        }
    }
}
```

## Reinstancing Instances
Almost done. Remember when we were overviewing the `FlushCompilationQueueImpl()`, how does the code snippet look like? Here's a refresher:

```cpp
void FBlueprintCompilationManagerImpl::CompileSynchronouslyImpl(const FBPCompileRequestInternal& Request)
{
    // ... Other Code
    FlushCompilationQueueImpl(bSuppressBroadcastCompiled, &CompiledBlueprints, &SkeletonCompiledBlueprints, nullptr, bFindAndReplaceCDOReferences ? &OldToNewTemplates : nullptr);
    FlushReinstancingQueueImpl(bFindAndReplaceCDOReferences, bFindAndReplaceCDOReferences ? &OldToNewTemplates : nullptr);
    // ... Other Code
}
```

We noticed that right after `FlushCompilationQueueImpl()`, there's a call to `FlushReinstancingQueueImpl()`, but we also know that `ReinstancingBatch()` has already been called in `FlushCompilationQueueImpl()`, then what this `FlushReinstancingQueueImpl()` is all about? In a nutshell, `ReinstancingBatch()` called in `FlushCompilationQueueImpl()` is to reinstance the class, while `FlushReinstancingQueueImpl()` is to replace the instances of the class.

```cpp
void FBlueprintCompilationManagerImpl::FlushReinstancingQueueImpl(bool bFindAndReplaceCDOReferences, TMap<UClass*, TMap<UObject*, UObject*>>* OldToNewTemplates /* = nullptr*/)
{
    // ... Other Code
    if(ClassesToReinstance.Num() == 0)
    {
        return;
    }

    {
        // ... Other Code
        FReplaceInstancesOfClassParameters Options;
        Options.bArchetypesAreUpToDate = true;
        Options.bReplaceReferencesToOldCDOs = bFindAndReplaceCDOReferences;
        Options.OldToNewTemplates = OldToNewTemplates;
        FBlueprintCompileReinstancer::BatchReplaceInstancesOfClass(ClassesToReinstanceOwned, Options);
        // ... Other Code
    }
    // ... Other Code

    UE_LOG(LogBlueprint, Display, TEXT("Time Compiling: %f, Time Reinstancing: %f"),  GTimeCompiling, GTimeReinstancing);
}
```

## Checkpoint Reached
Up to this point, we have covered all the stages of the compilation process, yet we only briefly talked the most important Stage XII to Stage XIV. The next post will be dedicated to go through the class compilation process, with a sneak peak of function compilation. Until then, stay tuned!

[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[88e52ed]: https://github.com/EpicGames/UnrealEngine/commit/88e52ed2a633d12292a6ce28b0f6f0cef380ce7f
[SCD Document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/sparse-class-data-in-unreal-engine