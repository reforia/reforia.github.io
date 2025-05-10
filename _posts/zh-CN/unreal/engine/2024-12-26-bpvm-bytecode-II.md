---
layout: post
title: "从蓝图到字节码 II - 编译完毕，准备出发"
description:
  "尽管在术语迷宫中历尽艰险，冒险者们终于抵达了篝火营地。但黑暗中还潜伏着另一头猛兽——编译过程"
date: 2024-12-26 01:04 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## 读取存档点
上回我们深入探索了蓝图系统的各种术语和概念，现在该把这些线索串联起来，仔细看看蓝图编译的完整流程啦！

## 编译流程 - 官方手册版
根据官方 [document]说明，蓝图编译过程可分为以下步骤：

![Blueprint Compilation Process](bytecode_compilationflow.png){: width="500"}

### 流程解析
虽然看起来点击"编译"按钮就会触发完整流程，但其实图示只是冰山一角哦！

让我们用"倒推法"来理解编译过程：
- 终极目标：
  - 生成包含函数、逻辑和属性的可执行类，把人类可读的节点图转化为运行时高效的字节码，最后让所有现有实例更新换代。
- 转化阶段： 
  - 需要将图形化函数转换为虚拟机(VM)能高效执行的底层字节码。
- 数据准备： 
  - 为转化阶段铺路，需要整理好图表数据、变量引用和函数定义。
- 数据填充： 
  - 以上步骤的发生地是`UBlueprintGeneratedClass`。引擎不会每次都新建类，而是复用现有类——不过在填入新数据前，得先做个大扫除，避免残留数据干扰新编译。

实例更新就像更新模板：蓝图改动后，所有根据它生成的对象都要同步升级，确保游戏世界里的现有对象与新蓝图保持一致。

> 本文只是概览，完整编译流程其实包含近15个步骤！本系列会逐一详解，带你彻底掌握虚幻引擎的蓝图编译机制。 
{: .prompt-info}

## 编译按钮 - 进入雾门
"编译"按钮本身是`FBlueprintEditorToolbar::AddCompileToolbar()`函数的一部分，这个函数在`BlueprintEditorMode`初始化时被调用。该模式实际上是`FBlueprintEditorApplicationMode`的实例，专属于蓝图编辑器。

![Editor Modes](bytecode_othereditormodes.png){: width="500"}
_Various Editor Modes_

从代码库可以看到，除了默认模式外，还有许多定制化的`EditorMode`（它们扩展或覆盖了默认功能及工具）。而`AddCompileToolbar()`正是`FBlueprintEditorToolbar`类中的工具函数，专门负责在蓝图编辑器初始化时把编译按钮添加到工具栏。
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

Cool！它新增了两个条目：`CompileButton` 和 `CompileOptions`。其中 `CompileOption` 包含三种选项：总是保存、仅在编译成功时保存，或者从不保存。

![Compile Toolbar](bytecode_compileoption.png){: width="500"}

## 从 Compile 到 FlushCompilationQueueImpl 
当 `CompileButton` 被创建时，会触发 `InitToolBarButton` 函数，并将 `Commands.Compile` 作为参数传入。这个 `Commands.Compile` 属于 `FFullBlueprintEditorCommands` 的一部分。

这个命令在蓝图编辑器初始化阶段就被注册了，就像这样：

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

本质上它就是个事件处理器——点击 `Compile` 按钮会映射到 `FBlueprintEditor::Compile()`，而内部实际调用的是 `FKismetEditorUtilities::CompileBlueprint()` 来完成编译工作。

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

`FKismetEditorUtilities::CompileBlueprint()` 是个包装函数，它会调用 `FBlueprintCompilationManager::CompileSynchronously()`，而后者又调用了 `BPCMImpl->CompileSynchronouslyImpl()`。

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

让我们简化一下流程：
首先，它尝试从一系列标志位中获取编译选项：
- `bIsRegeneratingOnLoad`
- `bRegenerateSkeletonOnly`
- `bSkipGarbageCollection`
- `bBatchCompile`
- `bSkipReinstancing`
- `bSkipSaving`
- `bFindAndReplaceCDOReferences`

如果所有必要检查都通过，就会将 `Request` 加入 `QueuedRequests` 数组，接着调用 `FlushCompilationQueueImpl()` 执行实际编译工作。之后还会调用 `FlushReinstancingQueueImpl()`。等到向客户端广播事件时，整个编译流程就彻底完成啦。

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

> 你猜对了！`FlushCompilationQueueImpl()` 才是干苦力的主函数，足足有 1200+ 行代码！考虑到这个函数的复杂度，我们当然就应该跳......好吧，不看到底我们是不会放弃的！
{: .prompt-info}

## FlushCompilationQueueImpl - 天选牛马
之前提到过，这个函数来自`FBlueprintCompilationManager`。幸运的是代码库中对这个函数的注释非常完善，如下所示

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

### Stage 0: 过去与未来
作用域由`TRACE_CPUPROFILER_EVENT_SCOPE`宏管理，这个宏用于分析CPU事件。在大型代码库中测量代码性能时它简直是个神器。经过若干检查后，会创建一个`FScopedSlowTask`。这个任务负责在编译过程中向用户显示进度条，防止他们以为程序卡死了。

当流程完成后，它会记录编译和重新实例化所花费的时间，然后重置计时器。完美。

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

### Stage I: 采集大会
这个阶段会收集所有需要编译的`Blueprint`，包括它们的依赖项（比如子`Blueprint`），以确保正确的编译顺序。

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

### Stage II: 过滤大师
本阶段的目的是过滤掉纯数据类和接口类`Blueprint`，并阻止'待销毁'的`Blueprint`被重新编译。目前收集依赖项主要出于以下原因：
- 当被调用函数被重建时，更新调用者的被调用函数
- 当父类布局变更时，更新子类的内存布局
- 当成员变量被重建时，更新Getter/Setter对成员变量的引用

待销毁对象不需要这些更新，而且`StaticDuplicateObject`也无法复制它们——反正它们本来就不能按常规方式更新。

待销毁的`UBlueprintGeneratedClass`实例依靠`FBlueprintCompileReinstancer()`中的`GetDerivedClasses`和`ReparentChild`调用来维持正确的类布局，防止内存损坏。

> 以上注释直接来自代码库
{: .prompt-info}

### Stage III: 排序狂魔
本阶段负责先按继承层级深度，再按重新实例化顺序对`Blueprint`进行排序。层级深度排序会先检查是否是接口类，然后调用`FBlueprintCompileReinstancer::ReinstancerOrderingFunction`来按重新实例化顺序排序。

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

### Stage IV: 临时flag
为每个正在编译的`Blueprint`设置`bBeingCompiled`标志为`true`，并将`CurrentMessageLog`设为`ActiveResultsLog`。如果`Blueprint`尚未重新生成且具有`Linker`，则将`bIsRegeneratingOnLoad`标志设为`true`。如果需要重置错误状态，则清除该`Blueprint`所有图表中的编译器消息。

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

### Stage V - Phase 1: 验证
在真正的单Blueprint编译流程开始前，这是个绝佳的检查点来验证每个Blueprint的变量名和类属性默认值。

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

`ValidateVariableNames()` 会检查变量名是否存在冲突（通过 `FKismetNameValidator()` 实现），若存在冲突则将变量重命名为唯一名称。此外，若父类是原生类（`native class`），它会检查变量名是否已被原生类占用——如果变量名被占用且类型相同，则会移除蓝图变量，并在所有引用处改用原生变量。

`ValidateClassPropertyDefaults()` 的核心功能是验证类属性的默认值类型是否正确。若变量类型自上次检查后发生变更，且尚未生成新的`CDO`，该方法会检查属性的默认类型，并在类型无效时记录错误。

### Stage V - Phase 2: 为蓝图提供编辑可能性
用于在加载时的编译阶段IX中执行自定义额外处理。

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

### Stage VI: 清理（仅限加载时）
此阶段编译器执行以下操作：
- 清理空图表
  - 从以下位置移除空图表：
  - `UbergraphPages`
  - `FunctionGraphs`
  - `DelegateSignatureGraphs`
  - `MacroGraphs`
- 适配原生组件
  - 更新蓝图的 `OwnedComponents`，使其反映自上次保存后原生代码的变更（如 `AttachParents` 的改动等）。该操作也用于处理重定父级（`reparenting`）问题
- 变更旧版蓝图模板的所有者
  - 这是针对 `VER_UE4_EDITORONLY_BLUEPRINTS` 版本之前保存的蓝图的向后兼容性修复

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

### Stage VII: 清理 SKELETON CDO
这个阶段主要使用两个函数：

`MoveDependentSkelToReinst`:
- 将CDO移动到不可变版本的类(`REINST`)中，以便CDO可以安全地被GC。 这些`REINST`类将被重新父类到我们知道不会再次在此函数中循环的本机父类，因此我们避免了O(N^2)处理REINST类。 将每个给定的`SKEL`类映射到其适当的`REINST`版本
`MoveSkelCDOAside`:
- 递归函数，用于将CDO移到类的不可变版本中以便安全GC回收。递归是必要的，用于发现那些仍然挂载在有效`SKEL`上的`REINST_`类（比如来自`MarkBlueprintAsStructurallyModified`的情况），因此在`SKEL`被修改前需要再次`REINST_`化...通常这些旧的`REINST_`类会被GC回收，但并不绝对保证:

> 这些注释直接来自代码库
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

### Stage VIII: 重新编译 SKELETON
检测旧版生成类中不存在的变量属性，将其暂存以便在重新实例化后处理。这种情况通常发生在父类中引入了新变量时，我们需要将其默认值作为生成类的初始值。

> 这些注释直接来自代码库
{: .prompt-info}

### Stage IX: 重建节点，替换废弃节点（仅加载阶段）
遍历所有节点并调用其对应的 `ReconstructNode()` 函数。此时每个节点都有机会建立连接或执行重建期间所需的操作。同时，系统会调用 `ReplaceDeprecatedNodes()`，以便 `EditorSchema` 类能够将废弃节点替换为更新版本。

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

### Stage X: 创建重新实例化器（丢弃"旧"类）
对队列中的每个蓝图进行重新实例化。注意：这意味着未被编译的层级结构中的类将被挂载到该类的 `REINST` 版本上，因此涉及这些类型的类型检查（如 `IsA` 等）可能会出现不一致！

> 这些注释直接来自代码库
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

### Stage XI: 创建更新后的类层级结构
此阶段主要完成两项工作：首先更新 `GeneratedClass` 的类层级结构，然后接管 `GeneratedClass` 的 `SparseClassData` 所有权。

这里的 `SCD`（稀疏类数据）是一项新特性，它通过仅存储必要数据来减少 `GeneratedClass` 的内存占用，同时保持所有`actor`实例共享同一份数据，从而降低发行版本的内存使用量。详见官方 [SCD Document].

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

> 由于内容过多，我们将先简要介绍阶段十二至阶段十四，具体细节留待下篇文章展开。
{: .prompt-info}

### Stage XII: 编译类布局
终于来到本文开头提到的阶段。乍看之下并不复杂，但若还记得上篇文章内容，就会明白这个 `FKismetCompilerContext::CompileClassLayout()`绝不简单——当前代码块只是隐藏了其复杂性。

在编译蓝图的所有步骤中（见文首流程图），以下步骤都在 `CompileClassLayout()` 中完成：:
- 清理类
- 根据蓝图创建类变量
- 创建函数列表
  - 创建并处理`Ubergraph`
  - 处理单个函数图
  - 预编译函数

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

最后执行 Bind 和 StaticLink 操作

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

### Stage XIII: 函数编译
此函数内部执行了大量检查与杂项操作，但其核心部分是 `CompileFunctions()` 函数调用，对应 Epic 官方文档中的步骤：
- 复制 CDO 属性
- 后端生成字节码
- 完成类编译

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

### Stage XIV: 类重实例化（REINSTANCE）
此阶段负责将旧类迁移至新类，对应官方文档中的以下部分步骤：
- 复制类默认对象属性
- 重实例化

`ReinstanceBatch()` 会调用 `CopyPropertiesForUnrelatedClasses()`，将属性从旧类复制到新类，同时从旧实例复制到新实例。这与 Epic 官方文档的描述一致：

<div class="box-info" markdown="1">
<div class="title"> 复制类默认对象属性 </div>
通过一个特殊函数 `CopyPropertiesForUnrelatedObjects()`，编译器将旧类的 CDO（Class Default Object）属性值复制到新的 CDO 中。属性通过标记序列化（tagged serialization）复制，因此只要名称一致，属性就能正确迁移。此阶段还会对 CDO 的组件进行适当的重新实例化和修复。GeneratedClass 的 CDO 具有权威性。 </div>

<div class="box-info" markdown="1"> <div class="title"> 重实例化 </div> 由于类的大小可能已改变，且属性可能被增删，编译器需要为刚刚编译的类重新实例化所有对象。此过程通过 `TObjectIterator` 查找该类的所有实例，生成新实例，并调用 `CopyPropertiesForUnrelatedObjects()` 函数将旧实例的属性复制到新实例中。
</div>

> 注意：此时我们仅对类进行重实例化，而非类的实例，实例的处理将在后续进行。
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

### Stage XV: CDO 编译后处理（POST CDO COMPILED）
至此，蓝图已编译完成，仅剩一些收尾工作，例如调用 `PostCDOCompiled()` 函数。该函数作为回调事件，供蓝图执行编译后的后续任务。

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

### Stage XVI: 清除临时标志
此阶段会清除编译流程开始时设置的临时标志。这样，从外部视角看，蓝图编译已彻底完成（其他类检查该类的 `RF` 标志时，将不再看到临时标志）。

### 后续处理
虽然函数描述未提及，但最后一步还包括清理字节码中的冗余数据、存储编译后的蓝图，并广播编译完成事件。随后记录必要信息，编译流程才真正结束。

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

## 实例的重实例化
快完成了。还记得我们概述 `FlushCompilationQueueImpl()` 时提到的代码片段吗？来回顾一下：

```cpp
void FBlueprintCompilationManagerImpl::CompileSynchronouslyImpl(const FBPCompileRequestInternal& Request)
{
    // ... Other Code
    FlushCompilationQueueImpl(bSuppressBroadcastCompiled, &CompiledBlueprints, &SkeletonCompiledBlueprints, nullptr, bFindAndReplaceCDOReferences ? &OldToNewTemplates : nullptr);
    FlushReinstancingQueueImpl(bFindAndReplaceCDOReferences, bFindAndReplaceCDOReferences ? &OldToNewTemplates : nullptr);
    // ... Other Code
}
```

我们注意到，在 `FlushCompilationQueueImpl()` 之后，紧接着调用了 `FlushReinstancingQueueImpl()`。但已知 `FlushCompilationQueueImpl()` 内部已调用过 `ReinstancingBatch()`，那么 `FlushReinstancingQueueImpl()` 的作用是什么？简而言之，`FlushCompilationQueueImpl()` 中的 `ReinstancingBatch()` 用于重实例化类，而 `FlushReinstancingQueueImpl()` 则用于替换该类的实例。

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

## 阶段总结
至此，我们已覆盖编译流程的所有阶段，但仅简要探讨了最重要的阶段 `XII` 至 `XIV`。下一篇文章将深入解析类的编译过程，并浅谈函数编译。敬请期待！

[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[88e52ed]: https://github.com/EpicGames/UnrealEngine/commit/88e52ed2a633d12292a6ce28b0f6f0cef380ce7f
[SCD Document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/sparse-class-data-in-unreal-engine