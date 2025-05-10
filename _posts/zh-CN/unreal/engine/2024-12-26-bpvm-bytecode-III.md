---
layout: post
title: "从蓝图到字节码 III - 解构类"
description: "虚空向冒险者们展示了一系列阶段，彼此环环相扣。有些阶段格外耀眼——比如类编译阶段。"
date: 2024-12-26 14:50 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## 故事继续
上篇文章我们探索了完整的蓝图编译流程——从点击`Compile`按钮到所有实例的`Reinstancing`。当时简要介绍了蓝图编译的实际阶段，现在让我们深入细节。

## 类编译启动
在`Stage XII: COMPILE CLASS LAYOUT`阶段，编译过程始于对`CompileClassLayout()`的调用。不过，在进入Epic官方[document] 描述的第一步（即清理和净化类）之前，还需要处理几个预编译步骤：

首先，会创建一个`UEdGraphSchema`作为编译过程的一部分。这个模式（我们在 [first post]中介绍过）定义了蓝图图中节点和引脚交互的规则与约定。

```cpp
void FKismetCompilerContext::CompileClassLayout(EInternalCompilerFlags InternalFlags)
{
    PreCompile();

    // ... Other Code, Initialization, clean up handles, null checks, etc.

    if (Schema == NULL)
    {
        BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_CreateSchema);
        Schema = CreateSchema();
        PostCreateSchema();
    }

    // ... Other Code
}
```

接着，编译器会检查父类是否有效。必要时会创建一个可用的`UBlueprintGeneratedClass`。如果不存在这样的类，就会新建实例。随后更新`Blueprint->GeneratedClass`指针以引用新创建的类。

```cpp
// Make sure the parent class exists and can be used
check(Blueprint->ParentClass && Blueprint->ParentClass->GetPropertiesSize());

UClass* TargetUClass = Blueprint->GeneratedClass;

// ... Other Code, backward compatibility support.

TargetClass = Cast<UBlueprintGeneratedClass>(TargetUClass);

if( !TargetClass )
{
    FName NewSkelClassName, NewGenClassName;
    Blueprint->GetBlueprintClassNames(NewGenClassName, NewSkelClassName);
    SpawnNewClass( NewGenClassName.ToString() );
    check(NewClass);

    TargetClass = NewClass;

    // Fix up the reference in the blueprint to the new class
    Blueprint->GeneratedClass = TargetClass;
}
```

新的`UBlueprintGeneratedClass`是通过调用`FKismetCompilerContext::SpawnNewClass()`创建的

```cpp
void FKismetCompilerContext::SpawnNewClass(const FString& NewClassName)
{
    // First, attempt to find the class, in case it hasn't been serialized in yet
    NewClass = FindObject<UBlueprintGeneratedClass>(Blueprint->GetOutermost(), *NewClassName);
    if (NewClass == NULL)
    {
        // If the class hasn't been found, then spawn a new one
        NewClass = NewObject<UBlueprintGeneratedClass>(Blueprint->GetOutermost(), FName(*NewClassName), RF_Public | RF_Transactional);
    }
    else
    {
        // Already existed, but wasn't linked in the Blueprint yet due to load ordering issues
        NewClass->ClassGeneratedBy = Blueprint;
        FBlueprintCompileReinstancer::Create(NewClass);
    }
}
```

接下来进行一系列验证：

```cpp
// Early validation
if (CompileOptions.CompileType == EKismetCompileType::Full){...}

// Ensure that member variable names are valid and that there are no collisions with a parent class
// This validation requires CDO object.
ValidateVariableNames();

if (GetAllowNativeComponentClassOverrides())
{
    ValidateComponentClassOverrides();
}
```

最后，我们缓存旧的`CDO`和链接器，并清理蓝图中所有无效的时间轴数组。

```cpp
OldCDO = NULL;
OldGenLinkerIdx = INDEX_NONE;
OldLinker = Blueprint->GetLinker();

if (OldLinker)
{
    // Cache linker addresses so we can fixup linker for old CDO
    for (int32 i = 0; i < OldLinker->ExportMap.Num(); i++)
    {
        FObjectExport& ThisExport = OldLinker->ExportMap[i];
        if (ThisExport.ObjectFlags & RF_ClassDefaultObject)
        {
            OldGenLinkerIdx = i;
            break;
        }
    }
}

for (int32 TimelineIndex = 0; TimelineIndex < Blueprint->Timelines.Num(); )
{
    if (NULL == Blueprint->Timelines[TimelineIndex])
    {
        Blueprint->Timelines.RemoveAt(TimelineIndex);
        continue;
    }
    ++TimelineIndex;
}
```

完成上述步骤后，紧接着就会执行`CleanAndSanitizeClass()`

## 清理与净化类
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
类采用原地编译方式，这意味着同一个`UBlueprintGeneratedClass`会被反复清理和重用，从而避免修复类指针的问题。`CleanAndSanitizeClass()`将属性和函数从类中移出，放入临时包中的垃圾类，然后清除类上的所有数据。
</div>

从代码来看，前半部分相当简单：我们尝试从`ClassToClean`中提取父类等重要信息，并希望安全地移除旧的CDO。

> 常见做法是将现有对象重命名到`TransientPackage`下以便安全删除。该对象会在下次GC周期时被处理。
{: .prompt-tip }

```cpp
void FKismetCompilerContext::CleanAndSanitizeClass(UBlueprintGeneratedClass* ClassToClean, UObject*& InOldCDO)
{
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_CleanAndSanitizeClass);

    const bool bRecompilingOnLoad = Blueprint->bIsRegeneratingOnLoad;
    FString TransientClassString = FString::Printf(TEXT("TRASHCLASS_%s"), *Blueprint->GetName());
    FName TransientClassName = MakeUniqueObjectName(GetTransientPackage(), UBlueprintGeneratedClass::StaticClass(), FName(*TransientClassString));
    UClass* TransientClass = NewObject<UBlueprintGeneratedClass>(GetTransientPackage(), TransientClassName, RF_Public | RF_Transient);
    
    UClass* ParentClass = Blueprint->ParentClass;

    if(CompileOptions.CompileType == EKismetCompileType::SkeletonOnly)
    {
        if(UBlueprint* BlueprintParent = Cast<UBlueprint>(Blueprint->ParentClass->ClassGeneratedBy))
        {
            ParentClass = BlueprintParent->SkeletonGeneratedClass;
        }
    }

    if( ParentClass == NULL )
    {
        ParentClass = UObject::StaticClass();
    }
    TransientClass->CppClassStaticFunctions = ParentClass->CppClassStaticFunctions;
    TransientClass->ClassGeneratedBy = Blueprint;
    TransientClass->ClassFlags |= CLASS_CompiledFromBlueprint|CLASS_NewerVersionExists;

    SetNewClass( ClassToClean );
    InOldCDO = ClassToClean->ClassDefaultObject; // we don't need to create the CDO at this point
    
    const ERenameFlags RenFlags = REN_DontCreateRedirectors |  ((bRecompilingOnLoad) ? REN_ForceNoResetLoaders : 0) | REN_NonTransactional | REN_DoNotDirty;

    if( InOldCDO )
    {
        FString TransientCDOString = FString::Printf(TEXT("TRASH_%s"), *InOldCDO->GetName());
        FName TransientCDOName = MakeUniqueObjectName(GetTransientPackage(), TransientClass, FName(*TransientCDOString));
        InOldCDO->Rename(*TransientCDOName.ToString(), GetTransientPackage(), RenFlags);
        FLinkerLoad::InvalidateExport(InOldCDO);
    }
    // ... Other Code
}
```

这里的关键一步是调用 `SetNewClass(ClassToClean);`。此时，`FKismetCompilerContext` 已经知晓即将被编译的 `UBlueprintGeneratedClass` 对象。这确保在后续编译过程中，数据会被正确写入 `UBlueprintGeneratedClass` 而非 `UBlueprint` 对象。

接下来，我们需要清除类的所有子对象——因为它们都会被重新生成。代码注释非常棒，详细解释了每个步骤背后的逻辑。

```cpp
// Purge all subobjects (properties, functions, params) of the class, as they will be regenerated
TArray<UObject*> ClassSubObjects;
GetObjectsWithOuter(ClassToClean, ClassSubObjects, false);

{
    // Save subobjects, that won't be regenerated.
    FSubobjectCollection SubObjectsToSave;
    SaveSubObjectsFromCleanAndSanitizeClass(SubObjectsToSave, ClassToClean);

    ClassSubObjects.RemoveAllSwap(SubObjectsToSave);
}

UClass* InheritableComponentHandlerClass = UInheritableComponentHandler::StaticClass();

for( UObject* CurrSubObj : ClassSubObjects )
{
    // ICH and ICH templates do not need to be destroyed in this way.. doing so will invalidate
    // transaction buffer references to these UObjects. The UBlueprint may not have a reference to
    // the ICH at the moment, and therefore might not have added it to SubObjectsToSave (and
    // removed the ICH from ClassSubObjects):
    if(Cast<UInheritableComponentHandler>(CurrSubObj) || CurrSubObj->IsInA(InheritableComponentHandlerClass) || CurrSubObj->HasAnyFlags(RF_InheritableComponentTemplate))
    {
        continue;
    }

    // Class properties are freed independently of GC, but functions we consign to the trash container object will persist until
    // the next GC pass, so we must purge serializable data first so we don't leak objects or crash due to invalidated references.
    if(UFunction* Function = Cast<UFunction>(CurrSubObj))
    {
        // Compiled function script (bytecode) may contain raw pointers to properties owned by this (or another) BP class. These
        // fields will be immediately freed after the compilation phase (see UClass::DestroyPropertiesPendingDestruction()), thus
        // invalidating any references to them in the "old" function object's serialized bytecode. Furthermore, reinstancing won't
        // update this function's bytecode, as that operation is only applied to a Blueprint class's dependencies, and does not
        // include "trash" class objects that we're creating here (see FBlueprintCompileReinstancer::UpdateBytecodeReferences()).
        // As we typically run a GC pass after BP compilation, this normally isn't an issue, because the "trash" class object that
        // owns this function object will get cleaned up at that point, preventing the "old" function object from being serialized
        // (e.g. as part of reinstancing an external dependency), and ensuring that we don't encounter one of these "dangling"
        // FField pointers. However, in certain cases (e.g. batched compiles) we may not run a GC pass in-between each operation,
        // so to cover that case, we ensure that existing bytecode is fully purged before moving a function to the "trash" class.
        Function->Script.Empty();

        // This array will get repopulated as part of constructing the new function object when compiling the class; we don't
        // want to preserve the old copy, because then the old function object could potentially be identified as a referencer
        // of a stale struct or a class asset during reference replacement if the previous dependency is subsequently recompiled.
        Function->ScriptAndPropertyObjectReferences.Empty();

        // We also need to destroy all child properties, as some may contain references to existing objects that can later be
        // invalidated as a result of compilation or GC, and also because we have cleared the references array above that's used
        // in ARO for reachability analysis during a GC pass. That means any references to objects owned by this class (e.g.
        // delegate signatures) are no longer seen as referenced by the function nor the class (due to the PurgeClass() below).
        // Additionally, references to any recompiled class objects or regenerated properties and functions won't be replaced
        // during the reinstancing phase, since "trash" class objects are meant for GC and will not be considered as a dependency.
        Function->DestroyChildPropertiesAndResetPropertyLinks();

        // Re-link to ensure that we also reset any cached data that's based on the (now empty) property list.
        Function->StaticLink(/*bRelinkExistingProperties =*/ true);
    }

    FName NewSubobjectName = MakeUniqueObjectName(TransientClass, CurrSubObj->GetClass(), CurrSubObj->GetFName());
    CurrSubObj->Rename(*NewSubobjectName.ToString(), TransientClass, RenFlags | REN_ForceNoResetLoaders);
    FLinkerLoad::InvalidateExport(CurrSubObj);
}

// Purge the class to get it back to a "base" state

// Set properties we need to regenerate the class with

if (bLayoutChanging)
{
    ClassToClean->bLayoutChanging = true;
}
```

## 设置类元数据并验证
首先调整 `NewClass` 的标志位以匹配父类。具体来说：如果当前蓝图是接口蓝图，则设置 `CLASS_Interface` 标志；如果 `bGenerateConstClass` 为真，则设置 `CLASS_Const` 标志。

随后进行类类型验证，并注册所有委托代理函数及其关联的捕获用`Actor`变量。

```cpp
NewClass->ClassGeneratedBy = Blueprint;

// Set class metadata as needed
UClass* ParentClass = NewClass->GetSuperClass();
NewClass->ClassFlags |= (ParentClass->ClassFlags & CLASS_Inherit);
NewClass->ClassCastFlags |= ParentClass->ClassCastFlags;

if (FBlueprintEditorUtils::IsInterfaceBlueprint(Blueprint))
{
    TargetClass->ClassFlags |= CLASS_Interface;
}

if(Blueprint->bGenerateConstClass)
{
    NewClass->ClassFlags |= CLASS_Const;
}

if (CompileOptions.CompileType == EKismetCompileType::Full)
{
    UInheritableComponentHandler* InheritableComponentHandler = Blueprint->GetInheritableComponentHandler(false);
    if (InheritableComponentHandler)
    {
        InheritableComponentHandler->ValidateTemplates();
    }
}

IKismetCompilerInterface& KismetCompilerModule = FModuleManager::LoadModuleChecked<IKismetCompilerInterface>("KismetCompiler");
KismetCompilerModule.ValidateBPAndClassType(Blueprint, MessageLog);
```

## 构建类结构
这个阶段的主要目标是确定经过蓝图编辑的新类最终形态。该过程类似于虚幻头文件工具（`UHT`）解析 `.h` 文件并编译为 `.generated.h` 文件的流程。我们需要确保正确设置类的元数据骨架，包括创建类变量、实例和函数列表。

### 从蓝图创建类变量
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
编译器会遍历蓝图的 `NewVariables` 数组以及其他位置（如构造脚本等），找到类所需的所有 `UProperties`，然后在 `CreateClassVariablesFromBlueprint()` 函数中为 `UClass` 作用域创建这些属性。
</div>

`RegisterClassDelegateProxiesFromBlueprint()` 函数会扫描函数图和事件图中的委托代理，并将其注册到编译器上下文。如果需要"捕获"变量（即委托将要调用的目标Actor），就会在当前类中添加新属性。

`CreateClassVariableFromBlueprint()` 会为蓝图 `NewVariables` 数组中的每个条目创建类变量。

```cpp
    // If applicable, register any delegate proxy functions and their captured actor variables
    RegisterClassDelegateProxiesFromBlueprint();
    
    // Run thru the class defined variables first, get them registered
    CreateClassVariablesFromBlueprint();
```

实际上，`CreateClassVariablesFromBlueprint()` 会对 `UBlueprint` 的 `NewVariables` 数组中的每个元素调用 `CreateVariable()`。从代码库可知，蓝图编辑器中创建的新变量并非真正的 `UProperty` 类型，而是包含构成 `UProperty` 对象所需信息的 `FBPVariableDescription` 结构体。`CreateVariable()` 会进一步调用 `FKismetCompilerUtilities::CreatePropertyOnScope()` 在类作用域上创建 `UProperty` 对象（注意第一个参数正是我们正在处理的 `UBlueprintGeneratedClass` 对象 `NewClass`）。

```cpp
/** Creates a class variable */
FProperty* FKismetCompilerContext::CreateVariable(const FName VarName, const FEdGraphPinType& VarType)
{
    // ... Other Code
    FProperty* NewProperty = FKismetCompilerUtilities::CreatePropertyOnScope(NewClass, VarName, VarType, NewClass, CPF_None, Schema, MessageLog);
    // ... Other Code
    return NewProperty;
}

/** Creates a property named PropertyName of type PropertyType in the Scope or returns NULL if the type is unknown, but does *not* link that property in */
FProperty* FKismetCompilerUtilities::CreatePropertyOnScope(UStruct* Scope, const FName& PropertyName, const FEdGraphPinType& Type, UClass* SelfClass, EPropertyFlags PropertyFlags, const UEdGraphSchema_K2* Schema, FCompilerResultsLog& MessageLog, UEdGraphPin* SourcePin);
```

此外还需要处理时间轴实例和简单构造脚本组件：通过遍历时间轴和简单构造脚本节点，为每个元素创建类属性。

```cpp
void FKismetCompilerContext::CreateClassVariablesFromBlueprint()
{
    // ... Other Code
    for (int32 i = 0; i < Blueprint->NewVariables.Num(); ++i)
    {
        FBPVariableDescription& Variable = Blueprint->NewVariables[Blueprint->NewVariables.Num() - (i + 1)];

        FProperty* NewProperty = CreateVariable(Variable.VarName, Variable.VarType);
        if (NewProperty != NULL)
        {
            // ... Other Code, process the NewProperty to set metadata, flags, etc.
            if (bRebuildPropertyMap)
            {
                // Update new class property guid map
                NewClass->PropertyGuids.Add(Variable.VarName, Variable.VarGuid);
            }
        }
    }

    // Ensure that timeline names are valid and that there are no collisions with a parent class
    ValidateTimelineNames();

    // ... Other Code, Create a class property for each timeline instance contained in the blueprint

    // Create a class property for any simple-construction-script created components that should be exposed
    if (Blueprint->SimpleConstructionScript)
    {
        // Ensure that nodes have valid templates (This will remove nodes that have had the classes the inherited from removed
        Blueprint->SimpleConstructionScript->ValidateNodeTemplates(MessageLog);

        // Ensure that variable names are valid and that there are no collisions with a parent class
        Blueprint->SimpleConstructionScript->ValidateNodeVariableNames(MessageLog);

        for (USCS_Node* Node : Blueprint->SimpleConstructionScript->GetAllNodes())
        {
            if (Node)
            {
                FName VarName = Node->GetVariableName();
                if ((VarName != NAME_None) && (Node->ComponentClass != nullptr))
                {
                    FEdGraphPinType Type(UEdGraphSchema_K2::PC_Object, NAME_None, Node->ComponentClass, EPinContainerType::None, false, FEdGraphTerminalType());
                    if (FProperty* NewProperty = CreateVariable(VarName, Type))
                    {
                        const FText CategoryName = Node->CategoryName.IsEmpty() ? FText::FromString(Blueprint->GetName()) : Node->CategoryName ;
                    
                        NewProperty->SetMetaData(TEXT("Category"), *CategoryName.ToString());
                        NewProperty->SetPropertyFlags(CPF_BlueprintVisible | CPF_NonTransactional );
                    }
                }
            }
        }
    }
}
```

### 添加蓝图实现的接口
如果蓝图实现了任何接口，则需要遍历 `ImplementedInterfaces` 数组并将这些接口添加到类中。

```cpp
// Add any interfaces that the blueprint implements to the class
// (has to happen before we validate pin links in CreateFunctionList(), so that we can verify self/interface pins)
AddInterfacesFromBlueprint(NewClass);
```

```cpp
void FKismetCompilerContext::AddInterfacesFromBlueprint(UClass* Class)
{
    // Make sure we actually have some interfaces to implement
    if( Blueprint->ImplementedInterfaces.Num() == 0 )
    {
        return;
    }

    // Iterate over all implemented interfaces, and add them to the class
    for(int32 i = 0; i < Blueprint->ImplementedInterfaces.Num(); i++)
    {
        UClass* Interface = Blueprint->ImplementedInterfaces[i].Interface;
        if( Interface )
        {
            // Make sure it's a valid interface
            check(Interface->HasAnyClassFlags(CLASS_Interface));

            //propogate the inheritable ClassFlags
            Class->ClassFlags |= (Interface->ClassFlags) & CLASS_ScriptInherit;

            new (Class->Interfaces) FImplementedInterface(Interface, 0, true);
        }
    }
}
```

<div class="box-info" markdown="1">
<div class="title"> Good To Know </div>
`FImplementedInterface(Interface, 0, true);` 这种语法称为`placement new`。它会在指定内存位置构造对象——这里就是在 `Class->Interfaces` 处构造 `FImplementedInterface` 对象。
</div>

### 创建函数列表
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
编译器通过处理事件图、常规函数图以及对每个上下文调用 `PrecompileFunction()` 来创建类的函数列表。
</div>

从代码注释可知 `CreateFunctionList()` 的工作流程：
- 执行初始验证确保图表结构有效
- 将ubergraph的不同页面合并为单一图表
- 创建图表副本以便后续转换

```cpp
// Construct a context for each function, doing validation and building the function interface
CreateFunctionList();

// Function list creation should process captured variables. Something went wrong if we missed any.
if (!ConvertibleDelegates.IsEmpty())
{
    // ... Other Code, handling unexpected case
}
```

分解 `CreateFunctionList()` 可以看到其结构如下：
- 允许蓝图扩展生成函数图
- 通过 `CreateAndProcessUbergraph()` 处理`ubergraph`（如果存在）
- 通过 `ProcessOneFunctionGraph()` 处理四种函数图：
  - Function Graph
  - Generated Function Graphs
  - Delegate Signature Graphs
  - Implemented Interfaces

```cpp
void FKismetCompilerContext::CreateFunctionList()
{
    TRACE_CPUPROFILER_EVENT_SCOPE(CreateFunctionList);
    {
        // ... Other Code
        // Allow blueprint extensions for the blueprint to generate function graphs
        for (const TObjectPtr<UBlueprintExtension>& Extension : Blueprint->GetExtensions())
        {
            Extension->GenerateFunctionGraphs(this);
        }
    }
    // ... Other Code
    // Process the ubergraph if one should be present
    if (FBlueprintEditorUtils::DoesSupportEventGraphs(Blueprint))
    {
        CreateAndProcessUbergraph();
    }

    if (Blueprint->BlueprintType != BPTYPE_MacroLibrary)
    {
        // Ensure that function graph names are valid and that there are no collisions with a parent class
        //ValidateFunctionGraphNames();

        // Run thru the individual function graphs
        for (int32 i = 0; i < Blueprint->FunctionGraphs.Num(); ++i)
        {
            ProcessOneFunctionGraph(Blueprint->FunctionGraphs[i]);
        }

        for (UEdGraph* FunctionGraph : GeneratedFunctionGraphs)
        {
            ProcessOneFunctionGraph(FunctionGraph);
        }

        for (int32 i = 0; i < Blueprint->DelegateSignatureGraphs.Num(); ++i)
        {
            // change function names to unique

            ProcessOneFunctionGraph(Blueprint->DelegateSignatureGraphs[i]);
        }

        // Run through all the implemented interface member functions
        for (int32 i = 0; i < Blueprint->ImplementedInterfaces.Num(); ++i)
        {
            for(int32 j = 0; j < Blueprint->ImplementedInterfaces[i].Graphs.Num(); ++j)
            {
                UEdGraph* SourceGraph = Blueprint->ImplementedInterfaces[i].Graphs[j];
                ProcessOneFunctionGraph(SourceGraph);
            }
        }
    }
}
```

<div class="box-tip" markdown="1">
<div class="title"> Good to know </div>
注意在调用 `CreateAndProcessUbergraph()` 之前，我们会用 `FBlueprintEditorUtils::DoesSupportEventGraphs()` 检查蓝图是否支持事件图。代码中只有 `BPTYPE_Normal` 和 `BPTYPE_LevelScript` 类型的蓝图符合条件。数据型蓝图、宏库、函数库和接口蓝图没有事件图，因此不会创建Ubergraph。
</div>

```cpp
/** Enumerates types of blueprints. */
UENUM()
enum EBlueprintType : int
{
    /** Normal blueprint. */
    BPTYPE_Normal                UMETA(DisplayName="Blueprint Class"),
    /** Blueprint that is const during execution (no state graph and methods cannot modify member variables). */
    BPTYPE_Const                UMETA(DisplayName="Const Blueprint Class"),
    /** Blueprint that serves as a container for macros to be used in other blueprints. */
    BPTYPE_MacroLibrary            UMETA(DisplayName="Blueprint Macro Library"),
    /** Blueprint that serves as an interface to be implemented by other blueprints. */
    BPTYPE_Interface            UMETA(DisplayName="Blueprint Interface"),
    /** Blueprint that handles level scripting. */
    BPTYPE_LevelScript            UMETA(DisplayName="Level Blueprint"),
    /** Blueprint that serves as a container for functions to be used in other blueprints. */
    BPTYPE_FunctionLibrary        UMETA(DisplayName="Blueprint Function Library"),

    BPTYPE_MAX,
};
```
</div>

#### 创建与处理Ubergraph
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
事件图的处理由`CreateAndProcessUberGraph()`函数完成。该函数将所有事件图页面复制到一个大图中，随后为节点提供扩展机会。接着，为图中的每个Event节点创建函数桩，并为每个事件图生成`FKismetFunctionContext`。
</div>

这个步骤背后的理念很简单：设计师可能为了可读性创建了多个事件图页面，但对编译器而言这本质上没有区别。因此，自然的做法是将它们合并成一个大型图表，即`Ubergraph`。虽然我们称之为"合并"，实际上是创建新图表并将所有节点从独立图表复制到其中。

> 想过为什么`CreateAndProcessUberGraph()`在`CreateFunctionList()`中被调用吗？因为`Ubergraph`本质上就是个巨型函数图，它也是函数列表的一部分。后续适用于函数的步骤同样会作用于`Ubergraph`。
{: .prompt-tip }

```cpp
// Merges pages and creates function stubs, etc... from the ubergraph entry points
void FKismetCompilerContext::CreateAndProcessUbergraph()
{
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_ProcessUbergraph);

    ConsolidatedEventGraph = NewObject<UEdGraph>(Blueprint, GetUbergraphCallName());
    ConsolidatedEventGraph->Schema = UEdGraphSchema_K2::StaticClass();
    ConsolidatedEventGraph->SetFlags(RF_Transient);

    // Merge all of the top-level pages
    MergeUbergraphPagesIn(ConsolidatedEventGraph);
    // ... Other Code
}
```

接着我们遍历用户未实现的接口，为它们创建虚拟事件入口点，以便接口能被调用。

```cpp
// Loop over implemented interfaces, and add dummy event entry points for events that aren't explicitly handled by the user
TArray<UK2Node_Event*> EntryPoints;
ConsolidatedEventGraph->GetNodesOfClass(EntryPoints);

for (int32 i = 0; i < Blueprint->ImplementedInterfaces.Num(); i++)
{
    const FBPInterfaceDescription& InterfaceDesc = Blueprint->ImplementedInterfaces[i];
    for (TFieldIterator<UFunction> FunctionIt(InterfaceDesc.Interface, EFieldIteratorFlags::IncludeSuper); FunctionIt; ++FunctionIt)
    {
        const UFunction* Function = *FunctionIt;
        const FName FunctionName = Function->GetFName();

        const bool bCanImplementAsEvent = UEdGraphSchema_K2::FunctionCanBePlacedAsEvent(Function);
        bool bExistsAsGraph = false;

        // Any function that can be implemented as an event needs to check to see if there is already an interface function graph
        if (bCanImplementAsEvent)
        {
            for (UEdGraph* InterfaceGraph : InterfaceDesc.Graphs)
            {
                if (InterfaceGraph->GetFName() == Function->GetFName())
                {
                    bExistsAsGraph = true;
                }
            }
        }

        // If this is an event, check the merged ubergraph to make sure that it has an event handler, and if not, add one
        if (bCanImplementAsEvent && UEdGraphSchema_K2::CanKismetOverrideFunction(Function) && !bExistsAsGraph)
        {
            bool bFoundEntry = false;
            // Search the cached entry points to see if we have a match
            for (int32 EntryIndex = 0; EntryIndex < EntryPoints.Num(); ++EntryIndex)
            {
                const UK2Node_Event* EventNode = EntryPoints[EntryIndex];
                if( EventNode && (EventNode->EventReference.GetMemberName() == FunctionName) )
                {
                    bFoundEntry = true;
                    break;
                }
            }

            if (!bFoundEntry)
            {
                // Create an entry node stub, so that we have a entry point for interfaces to call to
                UK2Node_Event* EventNode = SpawnIntermediateNode<UK2Node_Event>(nullptr, ConsolidatedEventGraph);
                EventNode->EventReference.SetExternalMember(FunctionName, InterfaceDesc.Interface);
                EventNode->bOverrideFunction = true;
                EventNode->AllocateDefaultPins();
            }
        }
    }
}
```

随后，我们将旧事件图移至`Transient Package`中，实际上就是移除它们。

```cpp
// We need to stop the old EventGraphs from having the Blueprint as an outer, it impacts renaming.
if(!Blueprint->HasAnyFlags(RF_NeedLoad|RF_NeedPostLoad))
{
    for(UEdGraph* OldEventGraph : Blueprint->EventGraphs)
    {
        if (OldEventGraph)
        {
            OldEventGraph->Rename(NULL, GetTransientPackage(), (Blueprint->bIsRegeneratingOnLoad) ? REN_ForceNoResetLoaders : 0);
        }
    }
}
Blueprint->EventGraphs.Empty();
```

在`Ubergraph`中添加虚拟入口点，设置函数签名并分配默认引脚。这将成为实际执行的入口点。

接下来调用`ExpansionStep()`来扩展`Ubergraph`中的所有节点。这包括从根节点遍历图表，移除所有未连接到可执行内容的孤立节点。对于剩余节点，我们对其进行"扩展"——包括移除不必要的包装器，以及对特定节点（如`UK2Node_Knot`）执行特殊操作。此外，我们处理每个`UEdGraphNode`的`UEdGraphPin`对象，根据需要优化引脚的增减。简言之，这一步将节点从设计师友好状态转换为编译器友好状态。

```cpp
if (ConsolidatedEventGraph->Nodes.Num())
{
    // Add a dummy entry point to the uber graph, to get the function signature correct
    {
        UK2Node_FunctionEntry* EntryNode = SpawnIntermediateNode<UK2Node_FunctionEntry>(NULL, ConsolidatedEventGraph);
        EntryNode->FunctionReference.SetExternalMember(UEdGraphSchema_K2::FN_ExecuteUbergraphBase, UObject::StaticClass());
        EntryNode->CustomGeneratedFunctionName = ConsolidatedEventGraph->GetFName();
        EntryNode->AllocateDefaultPins();
    }

    // Expand out nodes that need it
    ExpansionStep(ConsolidatedEventGraph, true);
    //... Other Code
}
```

随后进行多项验证，包括替换可转换委托、验证有效覆盖事件以及基础校验。
如果一切顺利，下一步就是通过调用`CreateFunctionStubForEvent()`为所有函数创建桩函数。

```cpp
ReplaceConvertibleDelegates(ConsolidatedEventGraph);

// If a function in the graph cannot be overridden/placed as event make sure that it is not.
VerifyValidOverrideEvent(ConsolidatedEventGraph);

// Do some cursory validation (pin types match, inputs to outputs, pins never point to their parent node, etc...)
{
    UbergraphContext = new FKismetFunctionContext(MessageLog, Schema, NewClass, Blueprint);
    FunctionList.Add(UbergraphContext);
    UbergraphContext->SourceGraph = ConsolidatedEventGraph;
    UbergraphContext->MarkAsEventGraph();
    UbergraphContext->MarkAsInternalOrCppUseOnly();
    UbergraphContext->SetExternalNetNameMap(&ClassScopeNetNameMap);

    // Validate all the nodes in the graph
    for (int32 ChildIndex = 0; ChildIndex < ConsolidatedEventGraph->Nodes.Num(); ++ChildIndex)
    {
        const UEdGraphNode* Node = ConsolidatedEventGraph->Nodes[ChildIndex];
        const int32 SavedErrorCount = MessageLog.NumErrors;
        UK2Node_Event* SrcEventNode = Cast<UK2Node_Event>(ConsolidatedEventGraph->Nodes[ChildIndex]);
        if (bIsFullCompile)
        {
            // We only validate a full compile, we want to always make a function stub so we can display the errors for it later
            ValidateNode(Node);
        }
        // ... Other Code
    }
}
```

函数桩是实际函数编译前的占位入口点，本质上创建`UK2Node_FunctionEntry`来包装函数。该过程涉及链接和解析输入/输出引脚元数据、设置标志位，并为每个函数创建`FKismetFunctionContext`。

桩函数创建后会被加入`FunctionList`，这样其他函数就能调用该桩函数（即使原函数尚未编译）。后续实际函数编译时，桩函数会被完整编译的函数替代。

```cpp
// If the node didn't generate any errors then generate function stubs for event entry nodes etc.
if (ConsolidatedEventGraph->Nodes.Num())
{
    //... Other Code

    if ((SavedErrorCount == MessageLog.NumErrors) && SrcEventNode)
    {
        CreateFunctionStubForEvent(SrcEventNode, Blueprint);
    }
}
```

#### 处理单个函数图
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
常规函数图由`ProcessOneFunctionGraph()`处理，该函数将每个图表复制到临时图中供节点扩展，同时为每个函数图创建`FKismetFunctionContext`。
</div>

此时我们已处理完`Ubergraph`，开始处理独立函数图。

首先忽略纯数据蓝图（不含任何可执行函数图的），因为这类蓝图没有函数逻辑需要处理。

对于包含函数图的蓝图，我们先将源函数图克隆到临时图中。这确保原始函数图在编译过程中保持完整未被修改。本质上，这个克隆步骤让原图成为参考源（类似处理`Ubergraph`的方式），我们只在临时版本上操作。

通过操作克隆图，我们避免在编译阶段意外修改原图，为图表节点的编辑处理提供了安全隔离环境。

```cpp
/**
 * Merges macros/subgraphs into the graph and validates it, creating a function list entry if it's reasonable.
 */
void FKismetCompilerContext::ProcessOneFunctionGraph(UEdGraph* SourceGraph, bool bInternalFunction)
{
    BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_ProcessFunctionGraph);

    if (SourceGraph->GetFName() == Schema->FN_UserConstructionScript && FBlueprintEditorUtils::IsDataOnlyBlueprint(Blueprint))
    {
        // This is a data only blueprint, we do not want to actually create our user construction script as it only consists of a call to the parent
        return;
    }

    // Clone the source graph so we can modify it as needed; merging in the child graphs
    UEdGraph* FunctionGraph = FEdGraphUtilities::CloneGraph(SourceGraph, Blueprint, &MessageLog, true);

    // ... Other Code
}
```

同样地，函数可能调用其他子`UEdGraph`（如宏等可复用逻辑），因此也需要在此扩展它们。下一步将`ParentGraph`的所有子图内容（递归地）移入`MergeTarget`图。这不是克隆操作而是覆盖操作，会破坏`ParentGraph`结构，但由于我们已将原函数图放入目标图，所以操作是安全的。

```cpp
const int32 SavedErrorCount = MessageLog.NumErrors;
bool bIsInvalidFunctionGraph = false;
FEdGraphUtilities::MergeChildrenGraphsIn(FunctionGraph, FunctionGraph, /* bRequireSchemaMatch = */ true, /* bInIsCompiling = */ true, &MessageLog);
```

Then we expand and validate all the nodes in the graph, pretty similar to how we did with the `Ubergraph`.

```cpp
// If we failed to merge with any child graphs due to an error, we shouldn't continue processing the intermediate graph.
if (MessageLog.NumErrors > SavedErrorCount)
{
    bIsInvalidFunctionGraph = true;
}
else
{
    ExpansionStep(FunctionGraph, false);

    ReplaceConvertibleDelegates(FunctionGraph);

    // Cull the entire construction script graph if after node culling it's trivial, this reduces event spam on object construction:
    if (SourceGraph->GetFName() == Schema->FN_UserConstructionScript )
    {
        if(FKismetCompilerUtilities::IsIntermediateFunctionGraphTrivial(Schema->FN_UserConstructionScript, FunctionGraph))
        {
            return;
        }
    }

    // If a function in the graph cannot be overridden/placed as event make sure that it is not.
    VerifyValidOverrideFunction(FunctionGraph);

    // NOTE: The Blueprint compilation manager generates the skeleton class using a different
    // code path. We do NOT want ValidateGraphIsWellFormed() ran for skeleton-only compiles here
    // because it can result in errors (the function hasn't been added to the class yet, etc.)
    check(CompileOptions.CompileType != EKismetCompileType::SkeletonOnly);

    // First do some cursory validation (pin types match, inputs to outputs, pins never point to their parent node, etc...)
    // If this fails we will "stub" the function graph (if callable) or stop altogether to avoid crashes or infinite loops
    bIsInvalidFunctionGraph = !ValidateGraphIsWellFormed(FunctionGraph);
}

if (bIsInvalidFunctionGraph)
{
    if(bInternalFunction)
    {
        // Internal functions that are not well-formed can be culled, since they're not exposed or callable.
        return;
    }
    else
    {
        // Break all links to the entry point in the cloned graph to create a "stub" context that's still exposed
        // as a callable function. This way external dependencies can still rely on the public interface if they're
        // not themselves being fully recompiled as a dependency of this Blueprint class.
        TArray<UK2Node_FunctionEntry*> EntryNodes;
        FunctionGraph->GetNodesOfClass<UK2Node_FunctionEntry>(EntryNodes);
        for (UK2Node_FunctionEntry* EntryNode : EntryNodes)
        {
            if (EntryNode)
            {
                EntryNode->BreakAllNodeLinks();
            }
        }
    }
}
```

<div class="box-tip" markdown="1">
<div class="title"> Convertible Delegates </div>
值得注意的`ReplaceConvertibleDelegates()`，根据代码库： 
- 如果图表使用可转换委托签名，则修改图表改用代理委托函数： 
- 创建使用委托精确签名的新函数图 
- 添加并链接原委托函数调用（隐式转换输入参数） 
- 如适用，在原始图中添加设置目标actor变量（即捕获变量）的节点

`ConvertibleDelegate`指签名可隐式转换到另一委托的委托。实际仅适用于`float/double`参数不同的函数签名。

这些委托在`FKismetCompilerContext::CompileClassLayout()`中通过`RegisterConvertibleDelegates()`加入`ConvertibleDelegates`数组。随后它们会被新建的函数图代理委托替代，原委托函数则指向新代理。
</div>

最后为每个函数图创建`FKismetFunctionContext`并加入`FunctionList`。

```cpp
const UEdGraphSchema_K2* FunctionGraphSchema = CastChecked<const UEdGraphSchema_K2>(FunctionGraph->GetSchema());
FKismetFunctionContext& Context = *new FKismetFunctionContext(MessageLog, FunctionGraphSchema, NewClass, Blueprint);
FunctionList.Add(&Context);
Context.SourceGraph = FunctionGraph;

if (FBlueprintEditorUtils::IsDelegateSignatureGraph(SourceGraph)) //-V1051
{
    Context.SetDelegateSignatureName(SourceGraph->GetFName());
}

// If this is an interface blueprint, mark the function contexts as stubs
if (FBlueprintEditorUtils::IsInterfaceBlueprint(Blueprint))
{
    Context.MarkAsInterfaceStub();
}

bool bEnforceConstCorrectness = true;
if (FBlueprintEditorUtils::IsBlueprintConst(Blueprint) || Context.Schema->IsConstFunctionGraph(Context.SourceGraph, &bEnforceConstCorrectness))
{
    Context.MarkAsConstFunction(bEnforceConstCorrectness);
}

if (bInternalFunction)
{
    Context.MarkAsInternalOrCppUseOnly();
}
```

#### 函数预编译
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
函数预编译由各上下文的`PrecompileFunction()`处理，该函数： 
- 调度执行并计算数据依赖 
- 剪除未调度或无数据依赖的节点
- 对剩余节点运行节点处理器的`RegisterNets()`
- 为函数内值创建`FKismetTerms`
- 创建`UFunction`及相关属性
</div>

创建函数列表后立即执行：
- 验证处理后的`ConvertibleDelegates`数组
- 首先预编译委托签名（其他函数需要它们）
- 预编译其余函数

```cpp
// Function list creation should process captured variables. Something went wrong if we missed any.
if (!ConvertibleDelegates.IsEmpty())
{
    UE_LOG(LogK2Compiler, Warning, TEXT("%d convertible delegates were not processed during class layout compilation. Listing delegates in log below."), ConvertibleDelegates.Num());
    for (auto DelegateIt = ConvertibleDelegates.CreateConstIterator(); DelegateIt; ++DelegateIt)
    {
        UE_LOG(LogK2Compiler, Display, TEXT("  Node:%s Function:%s Variable:%s"), *GetPathNameSafe(DelegateIt.Key()), *DelegateIt.Value().ProxyFunctionName.ToString(), *DelegateIt.Value().CapturedVariableName.ToString());
    }
}

// Precompile the functions
// Handle delegates signatures first, because they are needed by other functions
for (int32 i = 0; i < FunctionList.Num(); ++i)
{
    if(FunctionList[i].IsDelegateSignature())
    {
        PrecompileFunction(FunctionList[i], InternalFlags);
    }
}

for (int32 i = 0; i < FunctionList.Num(); ++i)
{
    if(!FunctionList[i].IsDelegateSignature())
    {
        PrecompileFunction(FunctionList[i], InternalFlags);
    }
}
```

从代码注释可知，这是编译函数图的第一阶段（此前仅查找并加入列表），包括：
- 修剪图表仅保留含函数入口点的连接部分
- 根据数据依赖调度节点执行
- 创建含参数和局部变量（尚无脚本代码）的`UFunction`对象

虽然这也是个庞大函数，但上述描述与代码高度吻合。这里我们为每个函数创建完整骨架（`UFunction`）及其元数据，同时创建并链接本地输入/输出引脚。还会创建委托的函数桩供其他函数依赖。

至此`Construct Class Layout`阶段结束。我们已创建类变量、添加接口、创建并预处理函数列表。接下来是绑定和链接它们。

## 绑定与链接类
<div class="box-info" markdown="1">
<div class="title"> Epic的定义 </div>
编译器现已知悉类的所有`UProperties`和`UFunctions`，可进行绑定和链接，包括填充属性链、属性大小、函数映射等。此时类头文件（除最终标志和元数据外）及`Class Default Object (CDO)`已就绪。
</div>

```cpp
{ BP_SCOPED_COMPILER_EVENT_STAT(EKismetCompilerStats_BindAndLinkClass);

    // Relink the class
    NewClass->Bind();
    NewClass->StaticLink(true);
}
```

### UClass::Bind()
`Bind()`的核心目的是递归查找三项：
- 类构造函数
- 类虚表辅助构造函数
- Cpp类静态函数

### UClass::StaticLink()
`StaticLink()`是调用`UStruct::Link()`的包装器，该函数创建字段/属性链接并使结构在运行时可用，包括：
- 将属性（如`FProperty`）绑定到关联类
- 必要时重新链接现有属性（`bRelinkExistingProperties`）
- 处理仅编辑器数据及需特殊关注的属性
- 管理对象引用（如清理指向`UObject`的属性）
- 递归链接超类的属性和结构

若归档`Ar`正在加载，函数会预加载超类（`InheritanceSuper`）和子属性，确保链接前所有必要数据可用。

```cpp
if (Ar.IsLoading())
{
    if (InheritanceSuper)
    {
        Ar.Preload(InheritanceSuper);
    }

    PreloadChildren(Ar);
}
```

接着遍历结构体属性（`ChildProperties`），对每个`FProperty`调用其`Link()`处理属性的序列化与绑定。

函数还跟踪`PropertiesSize`和`MinAlignment`以确保正确计算结构体总大小和内存对齐。

若属性被修改可能触发重新链接，使得循环次数增加（`LoopNum++`），确保属性正确链接且结构体大小/对齐更新。

```cpp
int32 LoopNum = 1;
for (int32 LoopIter = 0; LoopIter < LoopNum; LoopIter++)
{
    PropertiesSize = 0;
    MinAlignment = 1;

    if (InheritanceSuper)
    {
        PropertiesSize = InheritanceSuper->GetPropertiesSize();
        MinAlignment = InheritanceSuper->GetMinAlignment();
    }

    for (FField* Field = ChildProperties; Field; Field = Field->Next)
    {
        if (Field->GetOwner<UObject>() != this)
        {
            break;
        }

        if (FProperty* Property = CastField<FProperty>(Field))
        {
            // Linking logic for properties
            PropertiesSize = Property->Link(Ar);
            MinAlignment = FMath::Max(MinAlignment, Property->GetMinAlignment());
        }
    }
}
```

随后处理需要特殊操作的原生结构体。检查结构体是否为·子类，若是则使用·获取结构体的对齐和大小。这些操作用于管理原生结构体（通常为`C++`）的内存对齐、大小和自定义内存处理。

```cpp
if (GetClass()->IsChildOf(UScriptStruct::StaticClass()))
{
    // Handling for native struct operations
    UScriptStruct& ScriptStruct = dynamic_cast<UScriptStruct&>(*this);
    ScriptStruct.PrepareCppStructOps();

    if (UScriptStruct::ICppStructOps* CppStructOps = ScriptStruct.GetCppStructOps())
    {
        MinAlignment = CppStructOps->GetAlignment();
        PropertiesSize = CppStructOps->GetSize();
    }
}
```

最后进行清理并结束`StaticLink()`。

## 进行一个长休动作
看看我们完成了多少！实际上类的"头文件"已准备就绪，接下来只需解析实现为字节码。这部分将留待下篇讲解——本篇内容已经足够详尽。好好休息，喝点生命药剂吧！

[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[first post]: https://jaydengames.com/posts/bpvm-bytecode-I/