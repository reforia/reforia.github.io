---
layout: post
title: "Tear a Class Apart. From Blueprint to Bytecode - III"
description:
  "Series of stages were presented to the adventurers from the void, each leads to the next. A few of them were more shiny than the others - Class Compilation"
date: 2024-12-26 14:50 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Story Continues
In the last post, we explored the entire Blueprint compilation process, from hitting the `Compile` button to `Reinstancing` all instances. We briefly covered the actual stages of Blueprint compilation, so now let’s dive deeper into the details.

## Class Compilation Kick off
At `Stage XII: COMPILE CLASS LAYOUT`, the compilation process begins with a call to `CompileClassLayout()`. However, before we get to the first step described by Epic in the official [document] (which is Clean and Sanitize Class), there are a few pre-compilation steps that need to be addressed:

First, a `UEdGraphSchema` is created as part of the compilation process. This schema, which we covered in the [first post], defines the rules and conventions that govern how nodes and pins interact in a Blueprint graph.

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

Next, the compiler checks if the parent class is valid. If necessary, it creates a usable `UBlueprintGeneratedClass`. If no such class exists, a new instance is created. The `Blueprint->GeneratedClass` pointer is then updated to reference the newly created class.

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

The creation of a new `UBlueprintGeneratedClass` is done by calling `FKismetCompilerContext::SpawnNewClass()`

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

Next, a bunch of validation is performed:

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

Finally, we cache the old `CDO` and linker, and clean up the blueprint's timeline array if any timeline is invalid.

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

After did all the above steps, the very next line is `CleanAndSanitizeClass()`

## Clean and Sanitize Class
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Classes are compiled in place, which means the same `UBlueprintGeneratedClass` is cleaned and reused over and over, so that pointers to the class do not have to be fixed up. `CleanAndSanitizeClass()` moves properties and functions off the class and into a trash class in the transient package, and then clears any data on the class.
</div>

From the code, the first half is quite simple: We try to extract important info like parent class from the `ClassToClean`, and we want to safely get rid of the old CDO.

>It's a common practice to just rename an existing object that takes `TransientPackage` as outer for a safe deletion, the object will be taken care of during next GC cycle.
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

Next, we want to get rid of all subobjects of a class, because they will be regenerated anyway, the code comment is fantastic, it explains the reason behind each step in detail.

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

## Set Class Metadata, then Validate
Next, the flags for the `NewClass` are adjusted to match those of the parent class. Specifically, the `CLASS_Interface` flag is set if the Blueprint is an interface Blueprint, and the `CLASS_Const` flag is set if `bGenerateConstClass` is true.

Afterward, the class type is validated, and any delegate proxy functions, along with their associated captured actor variables, are registered.

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

## Construct Class Layout
At this stage, the primary goal is to determine what the new Blueprint-edited class actually looks like. This process is similar to how the Unreal Header Tool (`UHT`) parses `.h` files and compiles them into a `.generated.h` file. We want to ensure that the class's metadata or skeleton is set up correctly. This involves creating the class variables, instances, and function lists.

### Create Class Variables From Blueprint
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The compiler iterates over the Blueprint's `NewVariables` array, as well as some other places (construction scripts, etc.) to find all of the `UProperties` needed by the class and then creates `UProperties` on the UClass's scope in the function `CreateClassVariablesFromBlueprint()`.
</div>

The `RegisterClassDelegateProxiesFromBlueprint()` function scans both the function graphs and the Event Graph for any delegate proxies. These proxies are then registered with the compiler context. If a "captured" variable is required, a new property is added to the current class. In this context, a captured variable refers to any target actor that the delegate will be called on.

`CreateClassVariableFromBlueprint()` creates a class variable for each entry in the Blueprint `NewVars` array.

```cpp
    // If applicable, register any delegate proxy functions and their captured actor variables
    RegisterClassDelegateProxiesFromBlueprint();
    
    // Run thru the class defined variables first, get them registered
    CreateClassVariablesFromBlueprint();
```

There’s a bit more involved here. We also need to add the timeline instances and simple construction script components to the class. This is accomplished by iterating over the timelines and simple construction script nodes, creating a class property for each one.

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

### Add Interface From Blueprint
Next, if the Blueprint implements any interfaces, they need to be added as well. This is done by iterating over the `ImplementedInterfaces` array and adding each interface to the class.

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

### Create Functions List
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The compiler creates the function list for the class by processing the event graphs, processing the regular function graphs, and calls `PrecompileFunction()` for each context.
</div>

Just by looking at the comment in codebase, we know that `CreateFunctionList()` does the following:
- Performs initial validation that the graph is at least well formed enough to be processed further
- Merge separate pages of the ubergraph together into one ubergraph
- Creates a copy of the graph to allow further transformations to occur

```cpp
// Construct a context for each function, doing validation and building the function interface
CreateFunctionList();

// Function list creation should process captured variables. Something went wrong if we missed any.
if (!ConvertibleDelegates.IsEmpty())
{
    // ... Other Code, handling unexpected case
}
```

Decompose `CreateFunctionList()`, we can see the anatomy looks like this:
- Allow blueprint extensions for the blueprint to generate function graphs
- Process the ubergraph if one should be present by calling `CreateAndProcessUbergraph()`
- Process all 4 types of function graphs by calling `ProcessOneFunctionGraph()`
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
Note that before calling `CreateAndProcessUbergraph()`, we checked if the blueprint support event graph by `FBlueprintEditorUtils::DoesSupportEventGraphs()`, in code, only Blueprint type of `BPTYPE_Normal` and `BPTYPE_LevelScript` falls into this category. For Data Only BP, Macro Lib, Function Lib, and Interface BP, they don't have event graph, hence no Ubergraph is created.

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

#### Create and Process Ubergraph
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Processing of the event graphs is performed by the `CreateAndProcessUberGraph()` function. This copies all event graphs page into one big graph, after which nodes are given a chance to expand. Then, a function stub is created for each Event node in the graph, and an `FKismetFunctionContext` is created for each event graph.
</div>

The concept behind this step is simple: Designers might have created multiple event graph pages for better readability, but for the compiler, this is essentially meaningless. So, the natural approach is to merge them into one large graph, known as the `Ubergraph`. While we say "merge," in reality, a new graph is created, and all the nodes from the individual graphs are copied into this new graph.

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

Then we iterate over the interfaces that haven't been implemented by the user, create a dummy event entry point for them so that the interface can be called.

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

Next, we move the old event graphs to the transient package, effectively remove them.

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

A dummy entry point is added to the `Ubergraph`, setting up the function signature and allocating default pins. This serves as the actual entry point for execution.

Next, we call `ExpansionStep()` to expand all the nodes in the `Ubergraph`. This involves traversing the graph from the root, removing any isolated nodes that aren't connected to anything executable. For the remaining nodes, we "expand" them—this includes removing unnecessary wrappers and performing special operations for specific nodes like `UK2Node_Knot`. Additionally, we handle the `UEdGraphPin` objects for each `UEdGraphNode`, optimizing the addition or removal of pins where necessary. In short, this step gives each node a chance to evolve from a designer-friendly state into a more compiler-friendly one.


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

Several validation are being performed afterwards, including replacing convertible delegates, verifying valid override event, and cursory validation.

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

If everything proceeds smoothly up to this point, the next step is to create function stubs for all the functions by calling `CreateFunctionStubForEvent()`.

A function stub acts as a placeholder entry point before the actual function is compiled. It essentially creates a `UK2Node_FunctionEntry` to wrap the function. This process involves linking and resolving input/output pins metadata, setting up flags, and creating a `FKismetFunctionContext` for each function. Once the function stub is created, it is added to the `FunctionList`. This allows other functions to call the stub even though the function hasn't been compiled yet. Later, when the actual function is compiled, the function stub will be replaced by the fully compiled function.

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

#### Process One Function Graph
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Processing of the regular function graphs is done by the `ProcessOneFunctionGraph()` function, which duplicates each graph to a temporary graph where nodes are given a chance to expand. A `FKismetFunctionContext` is created for each function graph as well.
</div>

At this point, we have already processed the `Ubergraph`, and now we move on to process the individual function graphs.

The first thing we do is ignore data-only Blueprints (those that don't have any executable function graphs) since there's no function logic to process in those cases.

For Blueprints that do contain function graphs, we proceed by cloning the source function graph into a temporary graph. This ensures that the original function graph remains intact and unmodified during the compilation process. Essentially, this cloning step makes the original graph a source of reference while we work with the temporary version, just like we did with the `Ubergraph`.

By working on a cloned graph, we avoid accidentally modifying the graph during the compilation phase and maintain a safe and isolated environment for editing and processing the nodes in the graph.

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

Similarly, a function may called other child `UEdGraph` like macros for reusable logics, etc. So we need to expand them here as well. The next step moves the contents of all of the children graphs of `ParentGraph` (recursively) into the `MergeTarget` graph. This does not clone, it's destructive to the `ParentGraph`, but since we are already putting the original function graph into a target graph, it's safe to do so.

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
One thing worth noting is `ReplaceConvertibleDelegates()`, according to the codebase, it:
- Modifies the graph to use a proxy delegate function if it uses a convertible delegate signature. This involves several steps:
  - Creates a new function graph that uses the exact function signature of the delegate.
  - Adds and links the original delegate function call, which implicitly casts the input parameters.
  - If applicable, adds a node to the original graph that sets the variable of the target actor (ie: the captured variable)

A `ConvertibleDelegate` is just a delegate whose signature is convertible to, or implicitly castable to another one. In reality, this only applies for function signatures that differ by float/ double parameters.

They gets added to `ConvertibleDelegates` array in `RegisterConvertibleDelegates()` upon `FKismetCompilerContext::CompileClassLayout()`. Then they will be replaced by a new function graph as it's proxy delegate function, and the original delegate function just points to the new proxy.
</div>

Finally, we create a `FKismetFunctionContext` for each function graph, and add them to the `FunctionList`.

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

#### Precompile Function
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Pre-compiling of the functions is handled by the `PrecompileFunction()` of each context. This function performs the following actions:
  - Schedules execution and calculates data dependencies.
  - Prunes any nodes that are unscheduled or not a data dependency.
  - Runs the node handler's `RegisterNets()` on each remaining node.
  - This creates the `FKismetTerms` for values within the function.
  - Creates the `UFunction` and associated properties."
</div>

Right after we created the function list, the following steps happen:
- Validate the processed `ConvertibleDelegates` array
- Precompile Delegate Signatures first, because they are needed by other functions
- Precompile the rest of the functions

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

From comments in the codebase, we know that this is the first phase of compiling a function graph (Previously we just find them and add them to a list), which includes:
- Prunes the graph to only included the connected portion that contains the function entry point
- Schedules execution of each node based on data dependencies
- Creates a `UFunction` object containing parameters and local variables (but no script code yet)

Although this is another huge function, the above description closely resonates with the codebase. What happens here is we created a proper function skeleton (`UFunction`) for each function, including their metadata, we also created and linked their local input output pins. A function stub for delegates are created as well for other functions to depend on.

Now it concludes the `Construct Class Layout` phase, we have created the class variables, added interfaces, created and pre-processed the function list. It's time to bind and link them.

## Bind and Link Class
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Now that the compiler is aware of all of the `UProperties` and `UFunctions` for the class, it can bind and link the class, which involves filling out the property chain, the property size, function map, etc. At this point, it essentially has a class header - minus the final flags and metadata - as well as a `Class Default Object (CDO)`.
</div>

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

### UClass::Bind()
The whole purpose of `Bind()` is to recursively find 3 things:
- Class Constructor
- Class VTable Helper Constructor
- Cpp Class Static Functions

### UClass::StaticLink()
`StaticLink()` is a wrapper that calls `UStruct::Link()` which creates the field/ property links and gets structure ready for use at runtime, including:
- Binding properties (such as `FProperty` objects) to the associated class.
- Relinking existing properties if necessary (`bRelinkExistingProperties`).
- Handling editor-only data and properties that might require special attention during the linking phase.
- Managing object references, such as cleaning up properties that point to UObject or other objects that need to be properly initialized.
- Recursively linking superclasses' properties and structures.

If the archive `Ar` is loading, the function will preload the properties of the superclass (InheritanceSuper) and any child properties. This ensures that all necessary data is available for linking before actual size calculations or alignment checks.

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

Then we iterates over the properties of the struct (`ChildProperties`).
For each `FProperty`, we calls its `Link()`, which handles the serialization and binding of the property.

The function also tracks the `PropertiesSize` and `MinAlignment` to ensure the struct’s total size and memory alignment are correctly calculated.

`Relinking` may trigger if a property has been modified, causing the loop to iterate again (LoopNum++), ensuring that properties are correctly linked and the struct size/alignment are updated.

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

Next we handle native structs that require special operations. It checks if the struct is a child of `UScriptStruct`, and if so, it prepares and uses `CppStructOps` to retrieve the alignment and size of the struct. These operations are used for native structs (usually in C++) to manage things like alignment, size, and custom memory handling.

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

Finally, we just do some cleanup and conclude the `StaticLink()` function.

## Take a Long Rest
Look how much we have covered! Virtually the "Header" of a class is ready, we just need to go through the actual implementation, and parse them into bytecode. This will be covered in the next post. As this post is already exhaustive enough. Take a long rest, and drink some potions!

[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[first post]: https://jaydengames.com/posts/bpvm-bytecode-I/