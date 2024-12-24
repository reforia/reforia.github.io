---
layout: post
title: "But what is Blueprint? from Blueprint to Bytecode - II"
description:
  "Despite the exhausted challenges faced in the chamber of terminologies, the adventurers managed to reach our bonfire eventually. However, another monster is waiting in the darkness - Compilation"
date: 2024-12-23 23:04 +0800
categories: [Unreal, Engine]
published: false
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Load Checkpoint
In the previous post, we did a deep dive into the Blueprint System, specifically the numerous terminologies and concepts. Now it's time to connect these dots and understand the process of blueprint compilation.

## Blueprint Compilation Process
According to the official [document], the compilation process can be briefly breakdown into the following steps:

![Blueprint Compilation Process](bytecode_compilationflow.png)

This looks like an overwhelming process, but the purpose behind it is pretty straight forward, in order to capture the idea here, we need to look at the process in a backward manner:
- Eventually We want to have a class that contains functions, logics, properties that can be executed at runtime. And this class should have a optimized structure, that ditched out unnecessary graph representations (Since that's for human readability)
- Which means, some sort of conversion should happen that takes in the graphs and functions, and transform them into the desired form (Bytecode)
- Which means, we need to prepare the data for the compilation process
- Since the process eventually just populates data and write to `UBlueprintGeneratedClass`, so the `UBlueprintGeneratedClass` looks just like a container, we can just dump data to the container, rather than always create a new one. But to ensure that old stuff doesn't mess with our new data, we better clean and sanitize it before we do anything (Hence the Clean and Sanitize Class)

By viewing it reversely, we can understand why the process looks like this. Last but not least, since our changes may have changed the class layout, existing instances in the world should be aware of that change, hence we Re-instance them.

Great, now we have a rough idea of what's going on, let's dive into the details of each step.

## Clean and Sanitize Class
Classes are compiled in place, which means the same `UBlueprintGeneratedClass` is cleaned and reused over and over, so that pointers to the class do not have to be fixed up. `CleanAndSanitizeClass()` moves properties and functions off the class and into a trash class in the transient package, and then clears any data on the class.

## Create Class Variables From Blueprint
The compiler iterates over the Blueprint's `NewVariables` array, as well as some other places (construction scripts, etc.) to find all of the `UProperties` needed by the class and then creates `UProperties` on the UClass's scope in the function `CreateClassVariablesFromBlueprint()`.

## Create Functions List
The compiler creates the function list for the class by processing the event graphs, processing the regular function graphs, and pre-compiling the functions, i.e. calling `PrecompileFunction()` for each context.

### Create and Process Ubergraph
Processing of the event graphs is performed by the `CreateAndProcessUberGraph()` function. This copies all event graphs into one big graph, after which nodes are given a chance to expand. Then, a function stub is created for each Event node in the graph, and an `FKismetFunctionContext` is created for each event graph.

### Process One Function Graph
Processing of the regular function graphs is done by the `ProcessOneFunctionGraph()` function, which duplicates each graph to a temporary graph where nodes are given a chance to expand. A `FKismetFunctionContext` is created for each function graph as well.

### Precompile Function
Pre-compiling of the functions is handled by the `PrecompileFunction()` of each context. This function performs the following actions:
  - Schedules execution and calculates data dependencies.
  - Prunes any nodes that are unscheduled or not a data dependency.
  - Runs the node handler's `RegisterNets()` on each remaining node.
  - This creates the `FKismetTerms` for values within the function.
  - Creates the `UFunction` and associated properties."

## Bind and Link Class
Now that the compiler is aware of all of the `UProperties` and `UFunctions` for the class, it can bind and link the class, which involves filling out the property chain, the property size, function map, etc. At this point, it essentially has a class header - minus the final flags and metadata - as well as a `Class Default Object (CDO)`.

## Compile Function
The next step consists of generating `FKismetCompiledStatement` objects for the remaining nodes which is accomplished through the node handler's `Compile()` function, using `AppendStatementForNode()`. This function can create `FKismetTerm` objects in the compile function as long as they are only used locally.

## Finish Compiling Class
To finish compiling the class, compiler finalizes the class flags and propagates flags and metadata from the parent class before finally performing a few final checks to make sure everything went alright in the compile.

### Generate Bytecode/Cpp
The backends convert the collection of statements from each function context into code. There are two backends in use:
  - `FKismetCompilerVMBackend`
Converts FKCS to UnrealScript VM bytecode which are then serialized into the function's script array.
  - `FKismetCppBackend` 
Emits C++-like code for debugging purposes only.

> Note: at Commit [88e52ed], `FKismetCppBackend` was removed from the engine to it's own module
{: .prompt-info}

### Copy Properties from Old CDO
Using a special function, `CopyPropertiesForUnrelatedObjects()`, the compiler copies the values from the old CDO of the class into the new CDO. Properties are copied via tagged serialization, so as long as the names are consistent, they should properly be transferred. Components of the CDO are re-instanced and fixed up appropriately at this stage. The GeneratedClass CDO is authoritative.

## Reinstancing
Since the class may have changed size and properties may have been added or removed, the compiler needs to re-instance all objects with the class that were just compiled. This process uses a `TObjectIterator` to find all instances of the class, spawn a new one, and then uses the `CopyPropertiesForUnrelatedObjects()` function to copy from the old instance to the new one.

For details, see the FBlueprintCompileReinstancer class.

## Great Enemy Fallen


[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[88e52ed]: https://github.com/EpicGames/UnrealEngine/commit/88e52ed2a633d12292a6ce28b0f6f0cef380ce7f
