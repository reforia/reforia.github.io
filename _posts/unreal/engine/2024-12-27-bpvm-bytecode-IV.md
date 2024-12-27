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

## Before and After Function Compilation
Next part involves the actual per function compilation. Let's start with the simpler one, if this is not a full compile, then we just go through each function and call `FinishCompilingFunction()` on them. This is to set flags on the functions even for a skeleton class.

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

Now let's take a look at the `bIsFullCompile` path

## Full Compile
Simple enough, we just go through each function and call `CompileFunction()` on them. This is where the actual compilation happens.

```cpp
// Generate code for each function (done in a second pass to allow functions to reference each other)
for (int32 i = 0; i < FunctionList.Num(); ++i)
{
    if (FunctionList[i].IsValid())
    {
        CompileFunction(FunctionList[i]);
    }
}
```


### Backend Emits Generated Code
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The backends convert the collection of statements from each function context into code. There are two backends in use:

- FKismetCompilerVMBackend - Converts FKCS to UnrealScript VM bytecode which are then serialized into the function's script array.
- FKismetCppBackend - Emits C++-like code for debugging purposes only.
</div>

### Finish Compile Class
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
To finish compiling the class, compiler finalizes the class flags and propagates flags and metadata from the parent class before finally performing a few final checks to make sure everything went alright in the compile.
</div>

## Dive Even Deeper
At this point, we should already have a clear concept of how the blueprint works: When we write logic in the blueprint graph, we are essentially orchestrate connections or flow or logics, these information were wrapped by their abstract representations - `UEdGraphNode`, in order to reconstruct this flow for execution, we need to disassemble the whole `UBlueprint` into some byte sized commands. Aside from properties, for each function and the `Ubergraph` we expand their corresponding lists of `UEdGraphNode`, then for each `UEdGraphNode` we feed in `FBPTerminal` via `UEdGraphNodePin` by calling `RegisterNets()`, they then gets compiled into `FBlueprintCompiledStatement` by their own `FNodeHandlingFunctor`. Finally, `FBlueprintCompiledStatement` gets parsed into bytecode by `FKismetCompilerVMBackend`.

It makes sense but it's still a bit abstract, a real world example would be nice for comprehension. In the next post, we will walk through a simple blueprint and find out line by line how its bytecode works.



[first post]: https://jaydengames.com/posts/bpvm-bytecode-I/