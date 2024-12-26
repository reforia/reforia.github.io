---
layout: post
title: "Root of Class Compilation. From Blueprint to Bytecode - III"
description:
  "Series of stages were presented to the adventurers from the void, each leads to the next. A few of them were more shiny than the others - Class Compilation"
date: 2024-12-25 23:04 +0800
categories: [Unreal, Engine]
published: false
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Story Continues
In the last post, we walked through the whole skeleton of compilation process, from hitting the `Compile` button all the way to the `Reinstancing` for all instances. We briefly went through the actual stages of a blueprint compilation, so now let's explore from there.

## Clean and Sanitize Class
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Classes are compiled in place, which means the same `UBlueprintGeneratedClass` is cleaned and reused over and over, so that pointers to the class do not have to be fixed up. `CleanAndSanitizeClass()` moves properties and functions off the class and into a trash class in the transient package, and then clears any data on the class.
</div>

## Create Class Variables From Blueprint
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The compiler iterates over the Blueprint's `NewVariables` array, as well as some other places (construction scripts, etc.) to find all of the `UProperties` needed by the class and then creates `UProperties` on the UClass's scope in the function `CreateClassVariablesFromBlueprint()`.
</div>

## Create Functions List
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The compiler creates the function list for the class by processing the event graphs, processing the regular function graphs, and pre-compiling the functions, i.e. calling `PrecompileFunction()` for each context.
</div>

##### Create and Process Ubergraph
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Processing of the event graphs is performed by the `CreateAndProcessUberGraph()` function. This copies all event graphs into one big graph, after which nodes are given a chance to expand. Then, a function stub is created for each Event node in the graph, and an `FKismetFunctionContext` is created for each event graph.
</div>

##### Process One Function Graph
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Processing of the regular function graphs is done by the `ProcessOneFunctionGraph()` function, which duplicates each graph to a temporary graph where nodes are given a chance to expand. A `FKismetFunctionContext` is created for each function graph as well.
</div>

##### Precompile Function
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

## Finish Compile Class
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
To finish compiling the class, compiler finalizes the class flags and propagates flags and metadata from the parent class before finally performing a few final checks to make sure everything went alright in the compile.
</div>

## Backend Emits Generated Code
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
The backends convert the collection of statements from each function context into code. There are two backends in use:

- FKismetCompilerVMBackend - Converts FKCS to UnrealScript VM bytecode which are then serialized into the function's script array.
- FKismetCppBackend - Emits C++-like code for debugging purposes only.
</div>

## Copy Class Default Object Properties
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Using a special function, CopyPropertiesForUnrelatedObjects(), the compiler copies the values from the old CDO of the class into the new CDO. Properties are copied via tagged serialization, so as long as the names are consistent, they should properly be transferred. Components of the CDO are re-instanced and fixed up appropriately at this stage. The GeneratedClass CDO is authoritative.
</div>

## Re-instance
<div class="box-info" markdown="1">
<div class="title"> Epic's Definition </div>
Since the class may have changed size and properties may have been added or removed, the compiler needs to re-instance all objects with the class that were just compiled. This process uses a TObjectIterator to find all instances of the class, spawn a new one, and then uses the CopyPropertiesForUnrelatedObjects() function to copy from the old instance to the new one.

For details, see the FBlueprintCompileReinstancer class.
</div>

## Even Deeper Dive





[1]: https://www.cnblogs.com/ghl_carmack/p/5998693.html




[document]: https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-compiler-overview?application_version=4.27
[Blueprint VM]: https://www.cnblogs.com/ghl_carmack/p/6060383.html
[Blueprint I]: https://www.cnblogs.com/ghl_carmack/p/5995007.html
[Blueprint II]: https://www.cnblogs.com/ghl_carmack/p/5998693.html
[Blueprint III]: https://www.cnblogs.com/ghl_carmack/p/6014655.html
