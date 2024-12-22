---
layout: post
title: Unreal Deep Dive - Compile and Good to go, from Blueprint to Bytecode
description: 
  Unreal Blueprint system has made the development and iteration become incredibly convenient, in fact, too convenient - that we didn't even realize the magic behind the scene. This blog is trying to unveil the mist. of Blueprint, even just a little bit.
date: 2024-12-21 18:27 +0800
categories: [Unreal, Engine]
published: false
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Preface
Unreal Engine has been known for its powerful visual scripting system - Blueprint (Previously Kismet), there're plenty of tutorials and guides on how to use it, but not much on how it works. When we drag and drop nodes in the visual graph, click the compile button, and call it a day, it gave us a nice little hint: "Good to go", but what's really happening behind the scene? How does the Blueprint Virtual Machine (BPVM) interpret and execute the graph? This blog is trying to unveil the mist. of Blueprint.

![Compile, Save and Good to go](bytecode_hitcompile.png)

## Previous Researches
Epic published a [document] that briefly covered how the Blueprint compilation process works, but it only scratches the surface and doesn't go into details. Luckily, the community has done some great researches as well, for BPVM, we have [Blueprint VM], for BP Compilation Process, we have [Blueprint I], [Blueprint II] and [Blueprint III]. 

> These blogs above are written in Chinese, for english readers, a translation tools like GPT could be helpful.
{: .prompt-tip}

Despite these are really high quality posts that absolutely worth a read, we will briefly summarize the key points from them so we can have a common ground to start with. For experienced readers, feel free to skip next part.

## Blueprint System Overview
To eliminate ambiguity as much as possible, let's clarify some terms first: 

When people refer to a 'well-written Blueprint,' they're typically talking about the visual scripting graph created within the Blueprint Editor. Internally, this graph is managed by a `UEdGraph` object. The Graph (Event Graph for instance) is not the blueprint editor, but a part of it. The blueprint editor is a collection of `UEdGraphs` and panels, tools, etc.

In short, creating a Blueprint Asset in the Content Browser involves selecting a parent class and defining a new subclass through the Blueprint system. The Blueprint Editor allows us to add functions and logic within `UEdGraph` instances, as well as set up various properties. When we click the compile button in the editor, it orchestrates the compilation process: the content within the `UEdGraph` is processed and encapsulated into a reused UBlueprintGeneratedClass. This generated class is what the engine executes during runtime, ensuring that our defined behaviors and logic are effectively integrated into the game.

![Blueprint System Overview](bytecode_blueprintflow.png)
_Blueprint System Overview_

### UBlueprint
When we click in the Content Browser to create a new Blueprint based on a custom class type, such as `ACustomClass`, we're creating a `Blueprint Asset`, more specifically, a UBlueprint object. This asset is a serialized representation that defines a subclass of `ACustomClass` and exists solely within the editor environment.

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
It's also important to note that when executing the Blueprint's logic in a cooked package, we're not directly running the UBlueprint object created (Since it only exist in editor). Instead, we're executing a compiled version of that UBlueprint object, known as `UBlueprintGeneratedClass`.

`UBlueprintGeneratedClass` is a runtime class generated from the Blueprint by the Blueprint Editor*. It consolidates and optimizes the logic defined in the visual graph, making it the actual class instance executed during the game's runtime.

>*Technically, the Blueprint Editor initiates the generation of `UBlueprintGeneratedClass`, while the actual compilation work is handled by `FKismetCompileContext`, which processes and optimizes the visual scripting nodes into executable code.
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

Slightly Different to `UBlueprint` object. (Since the asset we are seeing in Content Browser is actually an instance of `UBlueprint`, which is a `UObject` and being serialized as `.uasset`), the `UBlueprintGeneratedClass` is just a class rather than an instance. So the parenting relationship is leveraging the idea of `SuperClass` (`SetSuperStruct()` when setting it, and `GetSuperClass()` when getting it), to act as if the `UBlueprintGeneratedClass` is a subclass of another `UClass`. Here's the codes right after the UBlueprint instance is created:

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

### UEdGraphNode

### UEdGraphPin

### UEdGraphSchema

### FKismetCompilerContext

### FKismetFunctionContext

### FBlueprintCompiledStatement

### FBPTerminal

### FNodeHandlingFunctor

### FBlueprintCompileReinstancer

### FKismetCompilerOptions

### Skeleton Class vs CDO

## Blueprint Compilation Process

### Clean and Sanitize Class

### Create Class Variables From Blueprint

### Create Functions List

### Create and Process Ubergraph

### Process One Function Graph

### Precompile Function

### Bind and Link Class

### Compile Function

### Postcompile Function

### Complete Compilation

### Generate Bytecode/Cpp

### Serialize Bytecode/Cpp

### Copy Properties from Old CDO

### Reinstancing

## BPVM

## BPVM Architecture

## Blueprint Bytecode Example

### Prerequisite

### Create a Blueprint Asset

### Add a custom function

### Call the function in event graph

### Compile and Save

## Bytecode Analysis

### Ubergraph

### CustomPrintString

## Conclusion










[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[Blueprint VM]: https://www.cnblogs.com/ghl_carmack/p/6060383.html
[Blueprint I]: https://www.cnblogs.com/ghl_carmack/p/5995007.html
[Blueprint II]: https://www.cnblogs.com/ghl_carmack/p/5998693.html
[Blueprint III]: https://www.cnblogs.com/ghl_carmack/p/6014655.html
