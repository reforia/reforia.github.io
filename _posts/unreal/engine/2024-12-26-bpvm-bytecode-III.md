---
layout: post
title: "Root of Class Compilation. From Blueprint to Bytecode - III"
description:
  "Series of stages were presented to the adventurers from the void, each leads to the next. A few of them were more shiny than the others - Class Compilation"
date: 2024-12-26 14:50 +0800
categories: [Unreal, Engine]
published: false
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Story Continues
In the last post, we walked through the whole skeleton of compilation process, from hitting the `Compile` button all the way to the `Reinstancing` for all instances. We briefly went through the actual stages of a blueprint compilation, so now let's explore from there.

## Compilation Kick off
At Stage XII: COMPILE CLASS LAYOUT, the compiler kicks of the process by calling `CompileClassLayout()`. Before we reached the first step described by Epic in the official [document] (Clean and Sanitize Class), there're actually a few pre-compile steps missing:

First, a `UEdGraphSchema` is created for the compilation process, which was explained in the [first post].

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

Then, it checks if the parent class is valid, and try to facilitate a usable `UBlueprintGeneratedClass` to use, a new instance is created if there's none exist. The `Blueprint->GeneratedClass` pointer is then updated to the new class. 

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

Finally, we cache the old CDO and linker, and clean up the blueprint's timeline array if any timeline is invalid.

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

From the code, the first half is quite simple: We try to extract important info like parent class from the `ClassToClean`, and we want to safely get rid of the CDO. However, destroy an object directly is not safe, so it's a common practice in codebase to just rename an existing object, which takes in a new package as it's outer, as long as the outer package is transient, the object will be taken care of during next GC cycle.

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

Next, we want to get rid of all subobjects of a clas, because they will be regenerated anyway, the code comment is fantastic, it explains the reason behind each step in detail.

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
Next, we flip the flags for the `NewClass` to match the parent class, and set the `CLASS_Interface` flag if the blueprint is an interface blueprint. We also set the `CLASS_Const` flag if `bGenerateConstClass` is true.
Then, we validate the class type and register any delegate proxy functions and their captured actor variables.

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

## Create Class Variables From Blueprint
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The compiler iterates over the Blueprint's `NewVariables` array, as well as some other places (construction scripts, etc.) to find all of the `UProperties` needed by the class and then creates `UProperties` on the UClass's scope in the function `CreateClassVariablesFromBlueprint()`.
</div>

```cpp
    // If applicable, register any delegate proxy functions and their captured actor variables
    RegisterClassDelegateProxiesFromBlueprint();
    
    // Run thru the class defined variables first, get them registered
    CreateClassVariablesFromBlueprint();
```

The `RegisterClassDelegateProxiesFromBlueprint()` searches the function graphs and ubergraph pages for any delegate proxies, which are then registered with the compiler context. If a "captured" variable is needed, then a new property will be added to the current class. In this context, a captured variable is any target actor that the delegate will be called on.

`CreateClassVariableFromBlueprint()` creates a class variable for each entry in the Blueprint NewVars array, but there's more thant that:

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

## Add Interface From Blueprint

```cpp
    // Add any interfaces that the blueprint implements to the class
    // (has to happen before we validate pin links in CreateFunctionList(), so that we can verify self/interface pins)
    AddInterfacesFromBlueprint(NewClass);
```

## Create Functions List
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The compiler creates the function list for the class by processing the event graphs, processing the regular function graphs, and pre-compiling the functions, i.e. calling `PrecompileFunction()` for each context.
</div>

```cpp
    // Construct a context for each function, doing validation and building the function interface
    CreateFunctionList();

    // Function list creation should process captured variables. Something went wrong if we missed any.
    if (!ConvertibleDelegates.IsEmpty())
    {
        UE_LOG(LogK2Compiler, Warning, TEXT("%d convertible delegates were not processed during class layout compilation. Listing delegates in log below."), ConvertibleDelegates.Num());
        for (auto DelegateIt = ConvertibleDelegates.CreateConstIterator(); DelegateIt; ++DelegateIt)
        {
            UE_LOG(LogK2Compiler, Display, TEXT("  Node:%s Function:%s Variable:%s"), *GetPathNameSafe(DelegateIt.Key()), *DelegateIt.Value().ProxyFunctionName.ToString(), *DelegateIt.Value().CapturedVariableName.ToString());
        }
    }
```

### Create and Process Ubergraph
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Processing of the event graphs is performed by the `CreateAndProcessUberGraph()` function. This copies all event graphs into one big graph, after which nodes are given a chance to expand. Then, a function stub is created for each Event node in the graph, and an `FKismetFunctionContext` is created for each event graph.
</div>

### Process One Function Graph
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Processing of the regular function graphs is done by the `ProcessOneFunctionGraph()` function, which duplicates each graph to a temporary graph where nodes are given a chance to expand. A `FKismetFunctionContext` is created for each function graph as well.
</div>

### Precompile Function
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Pre-compiling of the functions is handled by the `PrecompileFunction()` of each context. This function performs the following actions:
  - Schedules execution and calculates data dependencies.
  - Prunes any nodes that are unscheduled or not a data dependency.
  - Runs the node handler's `RegisterNets()` on each remaining node.
  - This creates the `FKismetTerms` for values within the function.
  - Creates the `UFunction` and associated properties."
</div>

## Bind and Link Class
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Now that the compiler is aware of all of the `UProperties` and `UFunctions` for the class, it can bind and link the class, which involves filling out the property chain, the property size, function map, etc. At this point, it essentially has a class header - minus the final flags and metadata - as well as a `Class Default Object (CDO)`.
</div>

## Compile Functions
### Copy Class Default Object Properties
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Using a special function, CopyPropertiesForUnrelatedObjects(), the compiler copies the values from the old CDO of the class into the new CDO. Properties are copied via tagged serialization, so as long as the names are consistent, they should properly be transferred. Components of the CDO are re-instanced and fixed up appropriately at this stage. The GeneratedClass CDO is authoritative.
</div>

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

## Re-instance (Preparation)
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Since the class may have changed size and properties may have been added or removed, the compiler needs to re-instance all objects with the class that were just compiled. This process uses a TObjectIterator to find all instances of the class, spawn a new one, and then uses the CopyPropertiesForUnrelatedObjects() function to copy from the old instance to the new one.

For details, see the FBlueprintCompileReinstancer class.
</div>

## Dive Even Deeper
At this point, we should already have a clear concept of how the blueprint works: When we write logic in the blueprint graph, we are essentially orchestrate connections or flow or logics, these infommation were wrapped by their abstract reprensentations - `UEdGraphNode`, in order to recounstruct this flow for execution, we need to disassemle the whole `UBlueprint` into some byte sized commands. Aside from properties, for each function and the `Ubergraph` we expand their corresponding lists of `UEdGraphNode`, then for each `UEdGraphNode` we feed in `FBPTerminal` via `UEdGraphNodePin` by calling `RegisterNets()`, they then gets compiled into `FBlueprintCompiledStatement` by their own `FNodeHandlingFunctor`. Finally, `FBlueprintCompiledStatement` gets parsed into bytecodes by `FKismetCompilerVMBackend`.

It makes sense but it's still a bit abstract, a real world example would be nice for comprehension. In the next post, we will walk through a simple blueprint and find out line by line how its bytecode works.



[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[first post]: https://jaydengames.com/posts/bpvm-bytecode-I/