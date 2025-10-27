# BPVM Snack Pack Series Roadmap

## Overview
The **BPVM Snack Pack** is a companion series to the deep-dive "From Blueprint to Bytecode" posts. Each snack is designed to be:
- **3-5 minutes** to read
- **1-2 concepts** per post
- **More examples**, less code
- **Fun and conversational** tone
- **Reuses images** from the original series

## Series Structure

### ✅ Created (4 posts)

#### **Snack #1: What is a Blueprint, Really?**
- UBlueprint vs UBlueprintGeneratedClass
- The recipe vs the cake analogy
- Why Blueprints aren't subclasses
- Links to: BPVM I

#### **Snack #2: The Graph System Decoded**
- UEdGraph (data) vs SGraphEditor (visuals)
- UEdGraphNode and UEdGraphPin
- Schema rules explained
- Links to: BPVM I

#### **Snack #3: Compilation Kick-Off**
- The compile button journey
- 16 stages overview
- Batch compilation explained
- Links to: BPVM II

#### **Snack #4: Skeleton Classes: The Hidden Hero**
- Solving circular dependencies
- Skeleton vs full class
- Two-pass compilation
- Links to: BPVM I & II

---

### 📝 Planned (13+ more posts)

#### **Blueprint Fundamentals (BPVM I companions)**

**Snack #5: The CDO Mystery**
- What is a Class Default Object?
- Why every class has one
- How instances inherit from CDO
- Links to: BPVM I

**Snack #6: Node Handlers Explained**
- FNodeHandlingFunctor pattern
- RegisterNets() and Compile()
- Example: Select node breakdown
- Links to: BPVM I

#### **Compilation Pipeline (BPVM II companions)**

**Snack #7: Dependency Hell Solved**
- Stages I-III (Gather, Filter, Sort)
- Handling Blueprint dependencies
- Why order matters
- Links to: BPVM II

**Snack #8: The Reinstancer's Job**
- What is reinstancing?
- Updating existing instances
- Avoiding crashes during recompile
- Links to: BPVM II

#### **Class Layout (BPVM III companions)**

**Snack #9: Clean and Sanitize Magic**
- Why classes reuse memory
- The TransientClass trick
- Avoiding pointer fixups
- Links to: BPVM III

**Snack #10: Variables Become Properties**
- FBPVariableDescription → FProperty
- CreatePropertyOnScope magic
- Timeline and component properties
- Links to: BPVM III

**Snack #11: The Function Factory**
- CreateAndProcessUbergraph
- Ubergraph vs regular functions
- Function graph processing
- Links to: BPVM III

**Snack #12: Linking and Binding**
- UClass::Bind() explained
- StaticLink() and property chains
- Size calculation and alignment
- Links to: BPVM III

#### **Function Compilation (BPVM IV companions)**

**Snack #13: Statements 101**
- FBlueprintCompiledStatement types
- KCST_* enum explained
- Statement generation
- Links to: BPVM IV

**Snack #14: The DAG Scheduler**
- Topological sort explained
- Linear execution lists
- Detecting cycles
- Links to: BPVM IV

**Snack #15: Backend Magic**
- FKismetCompilerVMBackend
- ConstructFunction workflow
- FScriptBuilderBase
- Links to: BPVM IV

**Snack #16: Optimizations Explained**
- MergeAdjacentStates
- Removing redundant jumps
- Flow stack vs direct returns
- Links to: BPVM IV

#### **Bytecode Deep Dive (BPVM V companions)**

**Snack #17: Reading Bytecode**
- EExprToken basics
- Label offsets
- Disassembly output format
- Links to: BPVM V

**Snack #18: Function Calls in Bytecode**
- Parameter passing
- EX_CallFunction breakdown
- Return value handling
- Links to: BPVM V

**Snack #19: Why Blueprint is Slower**
- Copying overhead
- Stack management
- Comparison with C++
- Links to: BPVM V

**Snack #20: Custom Blueprints**
- Extending FKismetCompilerContext
- Custom node types
- Real-world applications
- Links to: BPVM V

---

## Navigation Structure

### Forward/Backward Links
Each snack includes:
```markdown
**🍿 BPVM Snack Pack Series**
- [← #N: Previous Snack](/posts/bpvm-snack-N/)
- **#N+1: Current Snack** ← You are here
- [#N+2: Next Snack](/posts/bpvm-snack-N+2/) →
```

### Link to Deep Dive
Each snack includes:
```markdown
> **Want More Details?**
> For the complete breakdown:
> - [From Blueprint to Bytecode X - Topic](/posts/bpvm-bytecode-X/#section)
```

### Link from Deep Dive
Original posts include:
```markdown
## 🍿 BPVM Snack Pack - Bite-Sized Companions

Want to digest these concepts in smaller pieces? Check out these quick reads:
- [Snack #X: Topic](/posts/bpvm-snack-X/)
- [Snack #Y: Topic](/posts/bpvm-snack-Y/)
```

---

## Writing Guidelines

### Tone
- **Conversational** and approachable
- Use **analogies** (recipe/cake, header files, etc.)
- **Emojis** for visual breaks (🍿 🤯 ✅ ❌)
- **"You" language** (talk to the reader directly)

### Structure
```markdown
## The Hook (Problem/Question)
Brief scenario or surprising fact

## The Explanation
1-2 core concepts with examples

## Quick Takeaway
Bullet-point summary

## Want More Details?
Link to deep-dive post

## Navigation
Series navigation links
```

### Code Examples
- **Minimal** code (only essentials)
- **Heavy commenting** in code blocks
- Prefer **pseudo-code** over full implementation
- Show **before/after** comparisons

### Images
- **Reuse** from original posts
- Add **captions** explaining the image
- Use `{: width="500"}` for reasonable sizing

### Length Target
- **800-1200 words** per snack
- **3-5 minute** read time
- **1-2 concepts** maximum per post

---

## File Naming Convention

```
YYYY-MM-DD-bpvm-snack-NN-slug.md

Examples:
2025-01-01-bpvm-snack-01-what-is-blueprint.md
2025-01-02-bpvm-snack-02-graph-system.md
```

## Tags

All posts include:
```yaml
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
```

The `BPVM-Snack-Pack` tag creates an automatic collection page!

---

## Publishing Schedule (Suggested)

**Phase 1** (✅ Complete):
- Snacks #1-4 (Fundamentals)

**Phase 2** (Immediate):
- Snacks #5-8 (Compilation basics)

**Phase 3** (Week 2):
- Snacks #9-12 (Class layout)

**Phase 4** (Week 3):
- Snacks #13-16 (Function compilation)

**Phase 5** (Week 4):
- Snacks #17-20 (Bytecode)

**Total:** 20 snacks × 3-5 min = ~1.5 hours of reading

---

## Success Metrics

Target audience feedback:
- ✅ "I finally understand how Blueprint works!"
- ✅ "This was way easier to follow than the full post"
- ✅ "The analogies really helped"
- ✅ "I can share this with junior devs"

---

## Future Extensions

Potential spin-offs:
- **UHT Snack Pack** - Breaking down Unreal Header Tool
- **GAS Snack Pack** - Gameplay Ability System explained
- **Animation Snack Pack** - Animation Blueprint internals

---

Last Updated: 2025-10-27
