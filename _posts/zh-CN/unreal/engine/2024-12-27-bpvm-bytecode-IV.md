---
layout: post
title: "从蓝图到字节码 IV - 迈向核心"
description:
    "在最终看到字节码之前，只剩下最后一个挑战了——那就是编译函数。本文将带您逐步完成这一关键步骤。"
date: 2024-12-27 21:45 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## 函数编译启航
`FKismetCompilerContext::CompileFunctions()`的第一步是检查内部标志，然后决定是否生成局部变量、将值传递到`CDO`（类默认对象），以及刷新外部蓝图依赖节点。接着用蓝图、架构和编译器上下文初始化`FKismetCompilerVMBackend`。如果值没有传递到`CDO`，则跳过验证环节。开场相当简单明了。

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

## 生成局部变量
针对每个函数，我们会调用`CreateLocalsAndRegisterNets()`, 并调用`RegisterNets()` - 正如[first post]提到的，这本质上试图将输入和输出引脚链接到`FBPTerminal`，以便后续编译函数时，输入和输出值可以从具体位置传递或接收。

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

## 创建执行计划
上述代码中有一个微小但至关重要的步骤——`CreateExecutionSchedule()`。它对传入的节点图（预期构成一个`DAG`，即有向无环图）执行拓扑排序，然后进行调度。如果图中存在循环或未连接的节点，将为每个调度失败的节点输出错误信息。排序结果会存储在`Context.LinearExecutionList`中供后续使用。

`DAG`（有向无环图）的概念在计算机科学中非常常见，它是一种没有循环的图，意味着无法通过边从一个节点回到自身。这在蓝图图中尤为重要，因为它确保了逻辑按线性顺序执行，且不存在循环依赖。

想了解更多关于`DAG`的信息，可以参考[DAG Wiki]。

## 深入CompileFunctions()
### 区分仅骨架编译和完整编译
先从简单的开始：如果不是完整编译，我们只需遍历每个函数并调用`FinishCompilingFunction()`。这是为了即使在骨架类中也为函数设置标志。

>`bIsFullCompile` 在这里可能有点误导性，简单来说，如果它为false，则表示我们正在编译一个骨架类。
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

### 完整编译流程
现在来看看`bIsFullCompile`路径。很简单，我们遍历每个函数并调用`CompileFunction()`。实际的编译工作就在这里完成。然后，我们调用`PostcompileFunction()`来最终确定函数。最后，检查是否有任何`FMulticastDelegateProperty`未设置`SignatureFunction`，如果有则记录警告。

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

### 后编译函数
我们将在下一节深入探讨`CompileFunction()`。现在假设编译已完成，`PostcompileFunction()`被调用来完成函数的最终处理。这标志着函数图编译的最后阶段：修补交叉引用等，并执行最终验证。

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

> 这里的"Seal"意味着我们正在设置函数的最终元数据和标志。过了这一点，函数就被视为编译完成。
{: .prompt-info }

`ResolveStatements()`函数中执行了几个重要步骤：
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
最后一次对线性执行列表进行排序以确保执行顺序的正确性。这是一个复杂的函数，但简要工作流程如下：
- 清理空节点
- 将所有节点从`LinearExecutionList`复制到`UnsortedExecutionSet`
- 从`FKismetFunctionContext`的`EntryPoint`开始遍历`UnsortedExecutionSet`，爬取整个链，将`UnconditionalGoto`连接的链放在一起，并处理`Branches`
- 最后，将排序后的节点复制回`LinearExecutionList`

### ResolveGoToFixups
解析函数中的任何`Goto`修复，基本上是确定我们需要使用哪种`Goto`。

实际的`Goto`实现涉及将`KCST_Goto`替换为正确的`KCST_GotoReturn`或`KCST_EndOfThread`，`KCST_GotoIfNot`替换为相应的`KCST_GotoReturnIfNot`或`KCST_EndOfThreadIfNot`。如前所述，这里的关键在于流堆栈执行（`Flow Stack Execution`）的使用。如果不需要流堆栈执行，则使用`GotoReturn`而不是`EndOfThread`，反之亦然。`EndOfThread`会弹出流堆栈，而`GotoReturn`不会。

`IfNot`后缀表示这是`ConditionalGoto`还是`UnconditionalGoto`。对于`UnconditionalGoto`，我们直接跳转到对应地址；对于`ConditionalGoto`，我们会先检查条件，如果不满足则跳转。

唯一剩下的问题是：谁来决定是否需要使用流堆栈执行？答案是`FKismetFunctionContext::DoesStatementRequiresFlowStack()`。如果当前语句是`KCST_EndOfThreadIfNot`、`KCST_EndOfThread`或`KCST_PushStat`e，则需要使用流堆栈执行。这意味着`FNodeHandlingFunctor`可以自由决定是否使用流堆栈执行。

```cpp
bool FKismetFunctionContext::DoesStatementRequiresFlowStack(const FBlueprintCompiledStatement* Statement)
{
    return Statement && (
        (Statement->Type == KCST_EndOfThreadIfNot) ||
        (Statement->Type == KCST_EndOfThread) ||
        (Statement->Type == KCST_PushState));
}
```

> 这里讨论的Goto并不是设计者可以在蓝图中编写的节点，这个概念更接近汇编代码中的跳转指令。
{: .prompt-info}

### MergeAdjacentStates
合并函数中的相邻状态。通过遍历语句并将相邻的`KCST_State`语句合并为一个`KCST_State`语句来实现。不仅如此，这个函数还处理`KCST_Goto`和`KCST_GotoReturn`的特殊情况。

想象有一个函数A调用函数B，而函数B在末尾调用函数C。编译时，函数B的末尾会有一个无条件的`KCST_Goto`指向C的地址。但如果C在编译后的代码中紧接在B之后，这个Goto就完全多余，可以移除——这是优化的第一部分。

第二种情况是：如果已经处于函数末尾，且最后的`KCST`是无条件的`KCST_GotoReturn`，并且没有其他代码关心这个返回地址，那么这个状态也会被视为冗余而被移除，因为即使没有它，函数也会自然退出并继续执行。

### 广播事件并保存中间产物
完成后，我们广播事件，然后根据需要设置中间产物的标志。

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

### 完成类编译
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
为了完成类的编译，编译器会最终确定类标志，并从父类传播标志和元数据，最后执行一些最终检查以确保编译过程中一切正常。
</div>

此时，我们将完成类编译的最后几个步骤：设置最终标志并密封类，构建CDO，如果有图则构建委托绑定映射。如果不是在加载时重新生成，我们将从旧的CDO复制属性。我们还会更新后构造逻辑中使用的自定义属性列表，以包括蓝图CDO与本机CDO不同的本机类属性。

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

### 从FBlueprintCompiledStatement生成字节码
接下来，我们调用`Backend_VM`根据函数的`FBlueprintCompiledStatement`生成字节码。`GenerateCodeFromClass()`承担了繁重的工作，更多细节将在后面讨论。

```cpp
// Always run the VM backend, it's needed for more than just debug printing
{
    const bool bGenerateStubsOnly = !bIsFullCompile || (0 != MessageLog.NumErrors);
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_CodeGenerationTime);
    Backend_VM.GenerateCodeFromClass(NewClass, FunctionList, bGenerateStubsOnly);
}
```

### 序列化表达式
之后，我们将所有表达式序列化到一个存档中。

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

这里使用了一个有趣的技巧：如果进入`SerializeExpr()`函数，会发现它看起来像这样：

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

什么？！乍一看可能有点困惑，但这实际上是一种巧妙的序列化表达式的方法。`#include`确保内容被嵌入到这里。这意味着实际实现在`UObject/ScriptSerialization.h`文件中。这是一种保持代码整洁有序且可重用的巧妙方式。

### 生成调试字节码
此时，我们已经生成了所有字节码，但人类无法直接阅读它们。除非`bDisplayBytecode`设置为`true`，这时我们会反汇编字节码并打印出来。

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

### 标记依赖项为脏
这一步很简单：如果编译了函数，我们应该将依赖的蓝图标记为脏，以便必要时重新编译它们。

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

### 收尾工作
最后，我们做一些收尾工作：最终确定类标志，从父类传播标志和元数据，并存储`CDO`和签名的`crc32`校验和。最后，我们调用`PostCompile()`广播事件并完成编译。

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

## 深入CompileFunction()
显然，魔法发生在`CompileFunction()`中，它将每个函数转换为多个`FBlueprintCompiledStatement`。在下一批处理中（所有函数编译完成后），`BPVM`后端将它们批量转换为字节码。

从大局来看，`CompileFunction()`负责为线性执行顺序中的每个节点生成语句，然后提取纯链并将其生成的代码内联到需要它的节点中。最后，它传播线程安全标志。

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

### 为每个节点生成语句
这看起来像火箭科学，但其实并非如此。我们已经有了`LinearExecutionList`，它是一个按正确顺序排列的`UEdGraphNode`列表。我们只需遍历它们并为每个节点生成语句。我们还添加了调试注释和操作码插入点以方便调试。70%的代码只是为了添加调试用的`FBlueprintCompiledStatement`，如`KCST_Comment`。实际工作只是一行代码：`Handler->Compile(Context, Node);`。如[first post]所述，这允许`FNodeHandlingFunctor`编译节点并填充`FBlueprintCompiledStatement`。

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
这一步处理纯节点。它遍历整个列表，将它们分为两组：一组是Pure Nodes，它们被推送到其他节点的需求列表中；另一组是非Pure Nodes，它们实际Inline Pure Nodes的代码。说人话就是，Non Pure Nodes会将Pure Nodes的代码内联到它们的代码中。

这里有一个注意事项：一个纯节点可能依赖另一个纯节点。在这种情况下，将调用`Context.CopyAndPrependStatements(Node, NodeToInline);`来内联前置纯节点的代码。

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
最后，我们为函数设置元数据。在第一轮中，我们在这里传播线程安全标志。在第二轮中，`SetCalculatedMetaDataAndFlags`也会调用它来捕获骨架类的生成。

`MD_ThreadSafe`是一个特定的元数据键，指示函数是否是线程安全的。线程安全意味着可以安全地从多个线程同时调用函数而不会导致数据损坏或意外行为。

```cpp
// Propagate thread-safe flags in this first pass. Also gets called from SetCalculatedMetaDataAndFlags in the second
// pass to catch skeleton class generation
if (Context.EntryPoint->MetaData.bThreadSafe)
{
    Context.Function->SetMetaData(FBlueprintMetadata::MD_ThreadSafe, TEXT("true"));
}
```

## 后端生成代码输出
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
后端模块将每个函数上下文中的语句集合转换为代码。当前使用的有两个后端：

- `FKismetCompilerVMBackend` - 将`FKCS`转换为`UnrealScript`虚拟机字节码，随后序列化到函数的脚本数组中
- `FKismetCppBackend` - Emits C++-like code for debugging purposes only.
</div>

正如[first post]和前一节"从`FBlueprintCompiledStatement`生成字节码"所述，相关代码如下：

```cpp
Backend_VM.GenerateCodeFromClass(NewClass, FunctionList, bGenerateStubsOnly);
```

>`FKismetCppBackend` 已被移至独立模块且仅用于调试，本文我们只关注`FKismetCompilerVMBackend` here.
{: .prompt-info}

实现逻辑并不复杂：遍历每个函数并调用`ConstructFunction()`，最后清理`UBlueprintGeneratedClass`中`CalledFunctions`的重复项。

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

### 构建函数
对每个函数调用`ConstructFunction()`时，根据代码库中的函数签名注释，其作用是"构建函数的头部声明和主体实现"。但这个描述可能有些模糊，实际它是在为整个函数生成字节码。该过程可分为以下步骤：
- 必要时将返回地址压入流栈(Flow Stack)
- 为线性执行列表中的每个语句生成代码
- 处理函数返回值
- 修正跳转地址
- 结束脚本
- 若当前编译函数是Ubergraph，则保存该函数在`Ubergraph`中的地址偏移量

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

#### 初始化阶段
函数首先从`FunctionContext`获取`UFunction`和`UBlueprintGeneratedClass`，同时存储函数名到`FunctionName`变量，并持有函数脚本属性的引用。

```cpp
UFunction* Function = FunctionContext.Function;
UBlueprintGeneratedClass* Class = FunctionContext.NewClass;

FString FunctionName;
Function->GetName(FunctionName);

TArray<uint8>& ScriptArray = Function->Script;
```

#### 准备返回语句
创建类型为`KCST_Return`的返回语句，并初始化`ScriptWriter`用于后续处理。

```cpp
FBlueprintCompiledStatement ReturnStatement;
ReturnStatement.Type = KCST_Return;

FScriptBuilderBase ScriptWriter(ScriptArray, Class, Schema, UbergraphStatementLabelMap, bIsUbergraph, ReturnStatement);
```

#### 为每个语句生成代码
若`bGenerateStubOnly`为真则跳过此过程，否则逐个处理函数语句。

#### 压入返回地址
将`ReturnStatement`标记为跳转目标（其他字节码可跳转至此）。若函数使用流栈(基于栈的执行流)，则通过`ScriptWriter`将返回地址压栈。

```cpp
ReturnStatement.bIsJumpTarget = true;
if (FunctionContext.bUseFlowStack)
{
    ScriptWriter.PushReturnAddress(ReturnStatement);
}
```

#### GenerateCodeForStatement()
遍历函数线性执行列表中的每个语句，通过ScriptWriter.GenerateCodeForStatement()生成对应代码。若代码生成过程中出现错误，则中止生成并将函数先作为一个函数桩(stub)。后文将展开解析此函数。

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

#### 处理函数返回值
使用`ScriptWriter.GenerateCodeForStatement()`生成函数返回值的代码。

```cpp
// Handle the function return value
ScriptWriter.GenerateCodeForStatement(CompilerContext, FunctionContext, ReturnStatement, nullptr);
```

#### 修正跳转地址
`PerformFixups`的核心作用是解析字节码中所有占位跳转地址。在字节码生成阶段，跳转指令（如分支、循环或函数调用）可能引用尚未确定的目标地址。当所有目标地址确定后，这些占位符需要被修正为正确的字节码偏移量。更多关于`CommitSkip()`对`FBlueprintCompiledStatement`的作用，请参阅后文"修正结束跳转索引"章节。

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

#### 结束脚本

压入`EX_EndOfScript`标记脚本结束。`EX_EndOfScript`是字节码指令，后文将详细讨论。

```cpp
void CloseScript()
{
    Writer << EX_EndOfScript;
}
```

### 在Ubergraph中保存标签映射偏移量
当编译`Ubergraph`时，需要将语句映射复制到`Ubergraph`映射中。因为`Ubergraph`本质上是一个包含多个函数桩的大型图，当从某条语句返回时，需要知道跳转目标。这实际上相当于`Ubergraph`中每个可跳转语句的偏移量。

```cpp
void CopyStatementMapToUbergraphMap()
{
    UbergraphStatementLabelMap = StatementLabelMap;
}
```

> 所谓"可跳转"是指只有标记了`bIsJumpTarget`的语句才会被加入`StatementLabelMap`。在"压入返回地址"章节我们了解到，所有返回语句的`bIsJumpTarget`都被标记为真
{: .prompt-info}

## 深入GenerateCodeForStatement()
距离最终目标——字节码生成仅一步之遥。理解`GenerateCodeForStatement()`的运作机制后，我们将彻底掌握字节码的生成原理。准备迎接终极Boss吧！

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

经过诸多波折与苦思冥想的日子后，答案竟如此简单：一个覆盖所有可能`FBlueprintCompiledStatement`类型的巨型`switch-case`结构，调用对应的`EmitXXX`函数输出字节码。官方文档将此步骤称为"后端生成代码"的原因正在于此——所有字节码都源自与一个或多个`FBlueprintCompiledStatement`映射的"`EmitXXX`"函数。完整列表如下：
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

关键要理解：这些函数如同汇编指令，在线性语句列表上以最底层操作进行编写。每个操作和值类型实际上都是可求值表达式类型`EExprToken`。例如`EX_Return`表示函数返回（此处代码将触发返回），`EX_IntConst`表示整型常量，`EX_FloatConst`表示浮点常量等。后文将详细讨论。

> `EX_Return`并非我们在函数末尾编写的"Return节点"，这个细微差别将在下篇文章探讨
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

## 深入EmitSwitchValue()
若要覆盖所有`EmitXXX`函数可能需要再写十篇文章（所以我们不打算这么做 :D），这里仅以较简单的`EmitSwitchValue()`为例——这也正是[first post]中通过`FNodeHandlingFunctor`和`FBlueprintCompiledStatement`时使用的案例。作为回顾，以下是当时生成的`FBlueprintCompiledStatement`简况：注意我们已将`IndexTerm`的值、所有选项的`LiteralTerm-ValueTerm`对以及`DefaultTerm`都存入`SelectStatement`的`RHS`（右值）数组。

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

由于语句类型是`KCST_SwitchValue`，将调用`EmitSwitchValue()`。以下是该语句编译为字节码的流程解析：

### 准备语句
首先定义`TermsBeforeCases`和`TermsPerCase`。`TermsBeforeCases`为1（对应`IndexTerm`），`TermsPerCase`为2（对应每个`case`的`LiteralTerm`和`ValueTerm`对）。

接着检查`RHS`数组的项数，至少需要4项：1项`IndexTerm`，至少1个`case`的2项，以及1项`DefaultTerm`。同时检查项数模值，结果应为偶数（因为每个`case`都有`LiteralTerm-ValueTerm`对）。计入`IndexTerm`和`DefaultTerm`后，总项数始终为偶数。

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

### 输出 Switch EExprToken
首先向流中压入`EX_SwitchValue`——这是`switch`语句的表达式标识。

```cpp
Writer << EX_SwitchValue;
```

### 计算case数量
计算很简单：从所有`RHS`元素中减去`IndexTerm`和`DefaultTerm`，再除以`TermsPerCase`（本例为2，即`LiteralTerm`和`ValueTerm`），结果即为`case`数量。

```cpp
// number of cases (without default)
uint16 NumCases = IntCastChecked<uint16, int32>((Statement.RHS.Num() - 2) / TermsPerCase);
Writer << NumCases;
```

### 输出 End Goto Index
这是个有趣的步骤：此行代码实际上向`ScriptBuffer`末尾压入了一个占位符。原理是我们需要在语句开头存储字节码的实际大小，但此时无法预知实际值，故先存入-1。待整个语句的字节码生成完毕后，再修补这个值。

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
<div class="title"> 重要 </div>
虽然`CodeSkipSizeType Placeholder = -1;`是32位值（`CodeSkipSizeType`是uint32的别名），但`ScriptBuffer`是`TArray<uint8>`，因此实际向流中压入了4个`0xFF`元素，而非单个-1值。

示例：
- 原始 `ScriptBuffer`: `[0x00, 0x01, 0x02, 0x03]`
- `CodeSkipSizeType currentOffset = EmitPlaceholderSkip();`
  - `CodeSkipSizeType Result = ScriptBuffer.Num(); // 结果 = 4`
  - `CodeSkipSizeType Placeholder = -1; // 占位符 = 0xFFFFFFFF`
  - `(*this) << Placeholder; // 向ScriptBuffer追加0xFF, 0xFF, 0xFF, 0xFF`
  - `return Result; // 返回4`
- 新 `ScriptBuffer`: `[0x00, 0x01, 0x02, 0x03, 0xFF, 0xFF, 0xFF, 0xFF]`
</div>

接下来将处理`RHS`数组中的实际值，但需要先理解两个重要概念：`EmitTerm()`和`EmitTermExpr()`。

### Emit Term
该函数接收`FBPTerminal`参数。若该`FBPTerminal`是`InlineGeneratedParameter`，则需要进一步展开——此时会递归调用`GenerateCodeForStatement()`，直到所有`InlineGeneratedParameter`都被解析。

若非`InlineGeneratedParameter`，则检查是否为`StructContextType`。若是，则输出`EX_StructMemberContext`指令，并递归调用`EmitTerm()`处理`FBPTerminal`的`Context`。最终所有路径都会导向最底层的字节码生成函数`EmitTermExpr()`。

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
面对如此多样的值类型，如何生成对应字节码？如果你预感到又是巨型`switch-case`...没错。

最终根据`term`类型，向流中压入对应的`EExprToken`及可能存在的`term`值。以下是`EmitTermExpr()`的代码片段：

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

### 输出 Index Term
接着处理`Statement.RHS[0]`处的`IndexTerm`，通过`EmitTerm()`辅助函数将其输出到流中。

```cpp
// index term
auto IndexTerm = Statement.RHS[0];
check(IndexTerm);
EmitTerm(IndexTerm);
FProperty* VirtualIndexProperty = IndexTerm->AssociatedVarProperty;
check(VirtualIndexProperty);
```

### 输出每个case
为每个`case`向流中压入其`LiteralTerm`和`ValueTerm`：

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

### 输出DefaultTerm
最后将`RHS`数组末尾的`DefaultTerm`压入流中——这始终是默认`case`。

```cpp
auto DefaultTerm = Statement.RHS[TermsBeforeCases + NumCases*TermsPerCase];
check(DefaultTerm);
FProperty* VirtualValueProperty = DefaultTerm->AssociatedVarProperty;
check(VirtualValueProperty);

EmitTerm(DefaultTerm);
```

### 修正 End Goto Index
最终修正结束跳转地址。此时我们已获知函数体大小，可以用实际字节码偏移量替换最初压入的占位符。

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

由于`NewValue`是`uint32`而`ScriptBuffer`是`TArray<uint8>`，需要将`NewValue`拆分为4个字节写入`ScriptBuffer`相应位置（因此`WriteOffset`分别+1、+2、+3）。

## 举杯庆祝！
大功告成！我们成功将`KCST_SwitchValue`语句编译为字节码！这段旅程堪称精彩！快开瓶啤酒庆祝吧！🍻

## 更深入的探索
至此，我们已清晰理解蓝图工作原理：当在蓝图图表中编写逻辑时，本质上是在编排参数、流程或逻辑——这些信息都被抽象表示为`UEdGraphNode`。为了在底层以可执行方式重建该流程，需要通过点击`Compile`按钮进行编译。该过程将整个`UBlueprint`的信息解构到`UBlueprintGeneratedClass`中。除属性外，对每个函数和`Ubergraph`，我们展开其对应的`UEdGraphNode`列表，然后通过`UEdGraphNodePin`调用`RegisterNets()`为每个`UEdGraphNode`输入`FBPTerminal`，这些信息随后被各自的`FNodeHandlingFunctor`编译为`FBlueprintCompiledStatement`。最终`FBlueprintCompiledStatement`通过`FKismetCompilerVMBackend`解析为字节码。经过最终验证和序列化，蓝图即可由虚拟机执行。

虽然原理清晰但仍觉抽象？下篇文章作为本系列终章，我们将通过一个简单蓝图示例逐行检视字节码，见证魔法的流动。

[first post]: https://jaydengames.com/posts/bpvm-bytecode-I/
[DAG Wiki]: https://en.wikipedia.org/wiki/Directed_acyclic_graph