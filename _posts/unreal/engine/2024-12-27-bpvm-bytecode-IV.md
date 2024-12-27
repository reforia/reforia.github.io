---
layout: post
title: "Road to the Root. From Blueprint to Bytecode - IV"
description:
  "There's only last challenge left before we can finally see the bytecode, and that is to compile the functions. In this post, we will go through this very step."
date: 2024-12-27 21:45 +0800
categories: [Unreal, Engine]
published: false
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Compile Functions Kick off

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

## Dive Even Deeper
At this point, we should already have a clear concept of how the blueprint works: When we write logic in the blueprint graph, we are essentially orchestrate connections or flow or logics, these information were wrapped by their abstract representations - `UEdGraphNode`, in order to reconstruct this flow for execution, we need to disassemble the whole `UBlueprint` into some byte sized commands. Aside from properties, for each function and the `Ubergraph` we expand their corresponding lists of `UEdGraphNode`, then for each `UEdGraphNode` we feed in `FBPTerminal` via `UEdGraphNodePin` by calling `RegisterNets()`, they then gets compiled into `FBlueprintCompiledStatement` by their own `FNodeHandlingFunctor`. Finally, `FBlueprintCompiledStatement` gets parsed into bytecode by `FKismetCompilerVMBackend`.

It makes sense but it's still a bit abstract, a real world example would be nice for comprehension. In the next post, we will walk through a simple blueprint and find out line by line how its bytecode works.



