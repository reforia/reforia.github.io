---
layout: post
title: "Black Myth: Sobol Sequence - Random Enemy Spawning"
description: "A deep dive into quasi-random number generation, achieving low discrepancy distributed random enemy spawning in games"
date: 2025-11-21 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Mathematics, Algorithms, Game Development]
lang: en
math: true
---

> In Unreal, there's a `FSobol` class in `Sobol.h` that implements such quasi-random sequences for us to use directly, so we don't have to write the matrix ourselves. It also supports gray number order evaluation.
{: .prompt-tip }

## The Problem That Started It All
I came across this code in an enemy spawner from a talented developer: [Skylake-Official Github] Where the code reads:

```cpp
//Generate the i-th Sobol number in dimension d
float AAFPEnemySpawnerActor::Sobol(uint32 d, uint32 i) {
	const uint32 Matrix[8 * 32] = {
        2147483648, 1073741824, 536870912, 268435456, 134217728, 67108864, 33554432, 16777216, 8388608, 4194304, 2097152, 1048576, 524288, 262144, 131072, 65536, 32768, 16384, 8192, 4096, 2048, 1024, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1,
        2147483648, 3221225472, 2684354560, 4026531840, 2281701376, 3422552064, 2852126720, 4278190080, 2155872256, 3233808384, 2694840320, 4042260480, 2290614272, 3435921408, 2863267840, 4294901760, 2147516416, 3221274624, 2684395520, 4026593280, 2281736192, 3422604288, 2852170240, 4278255360, 2155905152, 3233857728, 2694881440, 4042322160, 2290649224, 3435973836, 2863311530, 4294967295,
        2147483648, 3221225472, 1610612736, 2415919104, 3892314112, 1543503872, 2382364672, 3305111552, 1753219072, 2629828608, 3999268864, 1435500544, 2154299392, 3231449088, 1626210304, 2421489664, 3900735488, 1556135936, 2388680704, 3314585600, 1751705600, 2627492864, 4008611328, 1431684352, 2147543168, 3221249216, 1610649184, 2415969680, 3892340840, 1543543964, 2382425838, 3305133397,
        2147483648, 3221225472, 536870912, 1342177280, 4160749568, 1946157056, 2717908992, 2466250752, 3632267264, 624951296, 1507852288, 3872391168, 2013790208, 3020685312, 2181169152, 3271884800, 546275328, 1363623936, 4226424832, 1977167872, 2693105664, 2437829632, 3689389568, 635137280, 1484783744, 3846176960, 2044723232, 3067084880, 2148008184, 3222012020, 537002146, 1342505107,
        2147483648, 1073741824, 536870912, 2952790016, 4160749568, 3690987520, 2046820352, 2634022912, 1518338048, 801112064, 2707423232, 4038066176, 3666345984, 1875116032, 2170683392, 1085997056, 579305472, 3016343552, 4217741312, 3719483392, 2013407232, 2617981952, 1510979072, 755882752, 2726789248, 4090085440, 3680870432, 1840435376, 2147625208, 1074478300, 537900666, 2953698205,
        2147483648, 1073741824, 1610612736, 805306368, 2818572288, 335544320, 2113929216, 3472883712, 2290089984, 3829399552, 3059744768, 1127219200, 3089629184, 4199809024, 3567124480, 1891565568, 394297344, 3988799488, 920674304, 4193267712, 2950604800, 3977188352, 3250028032, 129093376, 2231568512, 2963678272, 4281226848, 432124720, 803643432, 1633613396, 2672665246, 3170194367,
        2147483648, 3221225472, 2684354560, 3489660928, 1476395008, 2483027968, 1040187392, 3808428032, 3196059648, 599785472, 505413632, 4077912064, 1182269440, 1736704000, 2017853440, 2221342720, 3329785856, 2810494976, 3628507136, 1416089600, 2658719744, 864310272, 3863387648, 3076993792, 553150080, 272922560, 4167467040, 1148698640, 1719673080, 2009075780, 2149644390, 3222291575,
        2147483648, 1073741824, 2684354560, 1342177280, 2281701376, 1946157056, 436207616, 2566914048, 2625634304, 3208642560, 2720006144, 2098200576, 111673344, 2354315264, 3464626176, 4027383808, 2886631424, 3770826752, 1691164672, 3357462528, 1993345024, 3752330240, 873073152, 2870150400, 1700563072, 87021376, 1097028000, 1222351248, 1560027592, 2977959924, 23268898, 437609937
	};
	uint32 result = 0;
	uint32 offset = d * 32;
	for (uint32 j = 0; i; i >>= 1, j++)
		if (i & 1)
			result ^= Matrix[j + offset];
	return float(result) * (1.0f / float(0xFFFFFFFFU));
}

//Generate 2D sobol coordinates
FVector2D AAFPEnemySpawnerActor::SobolVec2D(uint32 i)
{
	float u = Sobol(1, i ^ (i >> 1));
	float v = Sobol(2, i ^ (i >> 1));
	return FVector2D(u, v);
}
```

The commit said it was a "low discrepancy random generator" that spawns enemies in a "controlled and weighted pattern." The magic numbers came from something called a "Sobol sequence," and there was this weird `i ^ (i >> 1)` thing that just annoys me:

I had no idea what the heck is this at that moment.

After going down a rabbit hole of mathematical papers, LFSRs, Galois fields, and primitive polynomials, I finally understand it. So here is my attempt to explain it to future-me (and anyone else who stumbles upon this sorcery).

## Part 1: The Core Problem - Why Random Sucks

Let's say you want to spawn 16 enemies around the player. Here are your options:

### Option 1: Pure Random

```cpp
for (int i = 0; i < 16; i++) {
    float x = RandomFloat(0, 1);
    float y = RandomFloat(0, 1);
    SpawnEnemy(x, y);
}
```

**Problem:** Random numbers cluster. You might get 3 enemies in the same corner and a huge empty region elsewhere. Players notice this. It feels unfair and looks bad.

### Option 2: Grid

```cpp
for (int i = 0; i < 16; i++) {
    float x = (i % 4) / 4.0f;
    float y = (i / 4) / 4.0f;
    SpawnEnemy(x, y);
}
```

**Problem:** Too obvious. Players immediately see the pattern. It feels artificial and predictable.

### Option 3: Sobol Sequence

Gives you points that:

- Spread out evenly (no clustering)
- Look random (no obvious pattern)
- Are deterministic (reproducible for replays)
- Fill space efficiently

This is called **quasi-random** or **low-discrepancy** sampling.

## Part 2: The Foundation - Van der Corput (1D)

Before we tackle 2D, let's understand how to distribute points evenly on a line.

### The naive approach: Just divide by count

Points: 0.0, 0.0625, 0.125, 0.1875, 0.25, 0.3125...

This adds points sequentially, always clustering near the start.

### Van der Corput's insight (1935): Reverse the bits!

```
Index 0: 0000 → reverse → 0000 → 0.0000 = 0.000
Index 1: 0001 → reverse → 1000 → 0.1000 = 0.500  (split in half!)
Index 2: 0010 → reverse → 0100 → 0.0100 = 0.250  (fill left gap!)
Index 3: 0011 → reverse → 1100 → 0.1100 = 0.750  (fill right gap!)
Index 4: 0100 → reverse → 0010 → 0.0010 = 0.125
Index 5: 0101 → reverse → 1010 → 0.1010 = 0.625
...
```

*This is already amazing, like what a genius! BTW just in case future-me somehow forget the algorithm, calculating the decimal of float-point binary is just the sum of 2^(-1), 2^(-2), etc, all the way to the LSB (Least Significant Bit) on the right side*

### Why this works:

When you count normally (0, 1, 2, 3...), bits change from right to left (LSB to MSB). When you reverse the bits and treat them as a fraction:

- The most significant bit becomes least significant (controls 0.5)
- Next bit controls 0.25
- Next controls 0.125

This means each new point always splits the LARGEST remaining gap in half. It's provably optimal for 1D! (Prove materials in the appendix in the end)

## Part 3: The Problem - Extending to 2D

### Naive attempt: Use bit reversal for both X and Y

```cpp
float x = BitReverse(i);
float y = BitReverse(i);  // Same function!
```

**Catastrophic failure:** All points lie on the diagonal line y=x!

If X and Y use the same transformation, they're perfectly correlated. You get a 1D line in 2D space.

### Slightly better attempt: Use different bit subsets

```cpp
float x = BitReverse(i & 0xF);       // Lower 4 bits
float y = BitReverse((i >> 4) & 0xF); // Upper 4 bits
```

This removes perfect correlation but still creates visible patterns because both dimensions use the same simple structure.

**What we need:** Each dimension must use a DIFFERENT mathematical structure that's provably independent.

## Part 4: Enter Sobol (1967) - The Breakthrough

Ilya Sobol, a Soviet mathematician, had a brilliant insight: What if we generate each dimension using a **different mathematical recipe**?

### The Magic Recipes: Primitive Polynomials

Think of primitive polynomials as special mathematical formulas that generate "maximally random-looking" bit patterns with perfect mathematical structure.

**You don't need to understand how they work to use Sobol sequences (For now)** - just know that:

1. Each polynomial generates a unique sequence of bit patterns
2. Different polynomials generate **uncorrelated** (independent) sequences
3. There are thousands of these polynomials available

**Example:**
- **Dimension 1 (X):** uses recipe #1 (x⁵ + x² + 1)
- **Dimension 2 (Y):** uses recipe #2 (x⁵ + x⁴ + x³ + x² + 1)
- **Dimension 3 (Z):** uses recipe #3 (x⁵ + x⁴ + x² + x + 1)
- etc.

Each "recipe" produces a different pattern of numbers that, when combined, create evenly-distributed points in multi-dimensional space.

> **Want to understand HOW these recipes work?** See Part 11 for the full technical explanation of primitive polynomials and LFSRs. For now, just trust that they work!
{: .prompt-tip }

## Part 5: Gray Code - The Missing Piece

Look at the code again:

```cpp
float u = Sobol(1, i ^ (i >> 1));  // What is this?
```

This `i ^ (i >> 1)` is **Gray code**.

### What is Gray code?

A way to reorder integers so that consecutive numbers differ by exactly ONE bit:

```
Regular:  Gray:
   0   →  0000  (0)
   1   →  0001  (1)  ← only bit 0 changed
   2   →  0011  (3)  ← only bit 1 changed
   3   →  0010  (2)  ← only bit 0 changed
   4   →  0110  (6)  ← only bit 2 changed
   5   →  0111  (7)  ← only bit 0 changed
   6   →  0101  (5)  ← only bit 1 changed
   7   →  0100  (4)  ← only bit 0 changed
```

### Why does Sobol need this?

Because each bit flip corresponds to adding or removing ONE direction vector. This creates a structured "walk" through space where each step changes by exactly one pre-calculated amount.

Without Gray code, multiple bits would change at once, causing large unpredictable jumps.

## Part 6: The Algorithm - Step by Step

Let's trace through what actually happens when you call `SobolVec2D(2)`:

### Step 1: Convert index to Gray code

```
i = 2
Gray = 2 ^ (2 >> 1) = 2 ^ 1 = 3 (binary: 0011)
```

### Step 2: Check which bits are set

```
Gray = 0011
Bits 0 and 1 are set
```

### Step 3: XOR corresponding direction numbers

For dimension 1:

```
Direction[0] = 2147483648  (binary: 10000000000000000000000000000000)
Direction[1] = 3221225472  (binary: 11000000000000000000000000000000)

result = Direction[0] XOR Direction[1]
       = 10000000000000000000000000000000
    XOR  11000000000000000000000000000000
       = 01000000000000000000000000000000
```

### Step 4: Normalize to [0, 1]

```
u = 1073741824 / 4294967295 = 0.25
```

### Step 5: Repeat for dimension 2 (with different direction numbers)

```
v = 0.25 (happens to be the same for this example)
```

### Result

Point (0.25, 0.25)

**The key insight:** Gray code tells you WHICH direction numbers to pick, then you XOR them together bitwise to get your coordinate.

## Part 7: Why XOR? (The Self-Inverse Property)

XOR has a magical property: **it's its own inverse**

```
A XOR B XOR B = A
```

This means:

- XORing something IN adds it
- XORing it again REMOVES it (same operation!)

Compare to addition:

```
A + B - B = A  (need different operations)
```

### Why this matters for Sobol:

When Gray code flips a bit from 1→0, we need to "remove" that direction vector. With XOR, we just... XOR it again. Same operation for add and remove!

```
Step 1: Gray = 001 → XOR Direction[0] → result = 10000000
Step 2: Gray = 011 → XOR Direction[1] → result = 11000000  (added)
Step 3: Gray = 010 → XOR Direction[0] → result = 01000000  (removed!)
```

This is why Gray code + XOR is the perfect pairing:

- **Gray code:** "Change one thing at a time"
- **XOR:** "Adding and removing use the same operation"

Together: incremental, reversible, structured navigation.

## Part 8: The Historical Context

This didn't come out of nowhere. Here's the lineage:

- **1935 - Van der Corput:** Bit reversal for 1D
  - → Provably optimal 1D distribution

- **1960 - Halton:** Extend to multiple dimensions using different prime bases
  - → Works but has correlation issues between dimensions

- **1967 - Sobol:** Use primitive polynomials instead of primes
  - → Each dimension gets mathematically independent structure
  - → This is the breakthrough

Sobol didn't discover primitive polynomials (known since 1800s for error-correcting codes). He didn't invent Gray code (known since 1950s for shaft encoders). He **combined existing mathematical tools in a novel way**.

The magic isn't in the individual pieces. It's in recognizing that:

- Primitive polynomials generate independent bit patterns
- Gray code enables incremental updates
- XOR enables reversible operations
- Together they create provably low-discrepancy sequences

## Part 9: Practical Tips for Game Developers

### When to use Sobol sequences:

**Good for:**

- Enemy spawning (as in the original code)
- Particle system emission points
- Procedural texture sampling
- Monte Carlo rendering
- Any time you need "random but evenly spread" points

**Overkill for:**

- Simple random events (coin flips, dice rolls)
- When clustering is desired
- High-frequency updates (compute cost matters)

### Implementation notes:

**The Matrix values are constants:** They were pre-computed decades ago using primitive polynomials. You can copy them from reference implementations (like the code at the top, or call `FSobol` in Unreal).

**Dimension limit:** The hardcoded Matrix typically supports 8-10 dimensions. For more, you'd need to generate additional direction numbers.

**Index matters:** Always increment the index sequentially (0, 1, 2, 3...). Don't skip around or you lose the low-discrepancy property.

**Resetting:** If you restart spawning, start from index 0 again. The sequence is deterministic.

### Common pitfalls:

```cpp
// WRONG - same index produces same point
for (int i = 0; i < count; i++) {
    Spawn(SobolVec2D(0));  // Always (0,0)!
}

// CORRECT - increment index
for (int i = 0; i < count; i++) {
    Spawn(SobolVec2D(i));
}
```

```cpp
// WRONG - random indices break the sequence
for (int i = 0; i < count; i++) {
    int randomIndex = rand();
    Spawn(SobolVec2D(randomIndex));  // Just random, not quasi-random!
}
```

---

## 🎓 Deep Dive Section - For the Curious

The sections below dive into the mathematical machinery behind Sobol sequences. **If you just want to use them effectively, you can skip to the [Conclusion](#conclusion).**

For those who want to understand *why* this works and *how* the magic numbers are generated, read on!

---

## Part 11: Primitive Polynomials & LFSRs - The Mathematical Machinery

Remember from Part 4 how we said each dimension uses a different "mathematical recipe" (primitive polynomial)? Now let's understand what these recipes actually are and how they work.

### What is a Primitive Polynomial?

**GF(2)** = "Galois Field of order 2" = fancy term for "binary arithmetic where addition is XOR"

```
0 + 0 = 0
0 + 1 = 1
1 + 1 = 0 (because XOR)
0 × 1 = 0 (AND)
1 × 1 = 1 (AND)
```

**Primitive polynomial** = a special polynomial that generates maximally long sequences in binary arithmetic.

Think of it like a recipe for creating "maximally random-looking" bit patterns that actually have deep mathematical structure.

### Example: x³ + x + 1

This is a primitive polynomial. When you use it in a Linear Feedback Shift Register (LFSR), it cycles through all 7 possible 3-bit states (excluding 000):

```
001 → 100 → 010 → 101 → 110 → 111 → 011 → (repeats)
```

That's 2³ - 1 = 7 states. Maximum possible!

### How Does an LFSR Actually Work?

**LFSR (Linear Feedback Shift Register)** is a shift register whose input bit is a linear function of its previous state. Think of it as a row of bits that:
1. Shifts one position each clock cycle
2. Feeds back a new bit calculated by XORing specific positions

For the primitive polynomial **x³ + x + 1**, here's the LFSR circuit:

```
┌────────────────────────────┐
│                            │
│  ┌───┐  ┌───┐  ┌───┐       │
└─►│ S₂│─►│ S₁│─►│ S₀│──────►│ Output
   └───┘  └─┬─┘  └─┬─┘       │
            │      │         │
            └──XOR─┘         │
                │            │
                └────────────┘
```

**Components:**
- **S₂, S₁, S₀** = three 1-bit storage cells (the "register")
- **Taps** at positions 1 and 0 (S₁ and S₀), determined by the polynomial coefficients x¹ and x⁰
- **Feedback** = S₁ ⊕ S₀

**Polynomial → Tap Positions:**

The polynomial **x³ + x + 1** tells us:
- **x³** → degree 3, so we need 3 bits
- **x¹** → tap at position 1 (from the right, counting from 0)
- **x⁰ (the +1)** → tap at position 0

**Tap rule:** XOR positions 1 and 0, feed back to the leftmost position

### Step-by-Step: Generating the Sequence

Let's trace through starting from state **001**:

```
Initial state: [S₂ S₁ S₀] = [0 0 1]
```

**Clock Cycle 1:**
```
Current state: [0 0 1]

Feedback calculation:
  new_bit = S₁ ⊕ S₀     (taps at x¹ and x⁰)
          = 0 ⊕ 1
          = 1

Shift right + insert feedback:
  [0 0 1] → shift → [? 0 0]
          → insert 1 → [1 0 0]

Next state: [1 0 0]
```

**Clock Cycle 2:**
```
Current state: [1 0 0]

Feedback:
  new_bit = S₁ ⊕ S₀ = 0 ⊕ 0 = 0

Next state: [0 1 0]
```

**Clock Cycle 3:** `[0 1 0]` → feedback = 1 ⊕ 0 = 1 → `[1 0 1]`

**Clock Cycle 4:** `[1 0 1]` → feedback = 0 ⊕ 1 = 1 → `[1 1 0]`

**Clock Cycle 5:** `[1 1 0]` → feedback = 1 ⊕ 0 = 1 → `[1 1 1]`

**Clock Cycle 6:** `[1 1 1]` → feedback = 1 ⊕ 1 = 0 → `[0 1 1]`

**Clock Cycle 7:** `[0 1 1]` → feedback = 1 ⊕ 1 = 0 → `[0 0 1]` ← Back to start!

### The Complete Cycle

```
001 → 100 → 010 → 101 → 110 → 111 → 011 → (001) ...
```

That's exactly **7 states** = 2³ - 1 = all possible non-zero 3-bit states!

**Why exclude 000?** Because `000 ⊕ 000 = 000` forever. The all-zeros state is a "dead state" that never escapes.

### Why Primitive Polynomials are Special

**Key property:** A primitive polynomial generates a **maximal-length sequence** (m-sequence).

For degree n:
- Total possible states: 2^n
- Non-zero states: 2^n - 1 (excluding all-zeros)
- A primitive polynomial cycles through ALL 2^n - 1 states before repeating

**Why x³ + x + 1 is primitive:**
1. It's **irreducible** (can't be factored over GF(2))
2. The period is exactly 2³ - 1 = 7 (we just proved this!)
3. It satisfies the mathematical test: it divides x^7 - 1 but no smaller x^k - 1

### Why is x⁴ + 1 NOT primitive?

Because it factors: x⁴ + 1 = (x + 1)⁴ in GF(2)

Since it has factors, it can't generate maximum-length sequences. Let's see what actually happens:

**LFSR for x⁴ + 1:**
```
Taps at position 0 only (since x⁴ + x⁰)
State: [S₃ S₂ S₁ S₀]
Feedback = S₀ (just copy the last bit!)

Starting from 0001:
0001 → 1000 → 0100 → 0010 → 0001  (period = 4, not 15!)
```

It only cycles through **4 states**, not the maximum 15 = 2⁴ - 1. That's why it's not primitive - it can't reach all possible states.

### Left-Shift vs Right-Shift: Does Direction Matter?

**Short answer:** Nope! The direction doesn't matter - you're just traversing the same cycle in reverse.

**Example with x⁴ + x + 1:**

**Right-shift LFSR:**
```
0001 → 1000 → 0100 → 0010 → 1001 → 1100 → 0110 → 1011
→ 0101 → 1010 → 1101 → 1110 → 1111 → 0111 → 0011 → (0001)
```

**Left-shift LFSR** (same polynomial, opposite direction):
```
0001 → 0011 → 0111 → 1111 → 1110 → 1101 → 1010 → 0101
→ 1011 → 0110 → 1100 → 1001 → 0010 → 0100 → 1000 → (0001)
```

Notice: **Same 15 states, just in reverse order!**

The choice of direction is purely a convention. Different implementations prefer different directions:
- **Right-shift:** More common in digital design textbooks
- **Left-shift:** Often used in software implementations (bit-shift operations feel more natural)

Both hit all 15 states and have the exact same period. You're walking around the same loop, just clockwise vs counterclockwise.

### Binary Space vs Decimal Space: Order vs Chaos

Here's where it gets interesting! Let's look at the **decimal values** of our x⁴ + x + 1 sequence:

```
Binary    Decimal
0001  →     1
1000  →     8
0100  →     4
0010  →     2
1001  →     9
1100  →    12
0110  →     6
1011  →    11
0101  →     5
1010  →    10
1101  →    13
1110  →    14
1111  →    15
0111  →     7
0011  →     3
```

**In decimal:** 1, 8, 4, 2, 9, 12, 6, 11, 5, 10, 13, 14, 15, 7, 3

This looks **completely random**! There's no obvious pattern.

**But in binary space?** The LFSR is performing a very structured walk:
- Each step flips exactly one or two specific bits (based on the XOR feedback)
- The bit patterns are maximally spread out
- The sequence systematically explores the entire binary state space

### Why This Matters for Sobol Sequences

This is the **key insight** behind Sobol sequences:

1. **In binary space:** The LFSR generates highly structured, evenly-distributed bit patterns
2. **In decimal/geometric space:** These patterns **appear** random and well-distributed
3. **Projected to [0,1]:** The direction numbers (scaled LFSR outputs) create low-discrepancy sequences

So when you use Sobol to spawn enemies:
- **The math sees:** A carefully orchestrated walk through 32D binary hypercube
- **The player sees:** "Random" but nicely spread out enemy positions
- **The developer sees:** Magic numbers that just work™

The chaos in decimal space is actually a **feature**, not a bug - it's what makes the points look random while maintaining perfect mathematical structure underneath!

## Part 10: The Hypercube Perspective (Mind-Bending Part)

Here's where it gets weird, but stick with me.

### XOR doesn't have geometric meaning

When you XOR two numbers, you're not adding vectors. You're not moving in space. You're operating in **32-dimensional binary space** where each bit is a separate axis.

```
10000000 XOR 10100000 = 00100000
```

This isn't "combine these directions." It's "flip specific bits on/off in a 32D hypercube."

### The projection trick

1. You navigate a 32D binary hypercube (one step along one axis at a time, thanks to Gray code)
2. Each position in the hypercube is a 32-bit integer
3. You PROJECT this down to [0, 1] by dividing by 2³² - 1
4. This projection, remarkably, produces evenly distributed points

### Why does this work?

The primitive polynomials ensure that as you walk through the 32D hypercube, the projected 1D coordinates systematically explore the entire [0, 1] interval without clustering or patterns.

It's like how a 3D helix looks random when projected onto 2D, but it's actually perfectly structured in 3D. Same idea, but 32D → 1D.

### The "direction numbers" misnomer

They're not geometric directions. They're **bit patterns in a 32D binary space**. The terminology stuck because it sounds intuitive, but it's technically inaccurate.

## Part 12: Synthesis - How All The Pieces Fit Together

Now that we've explored LFSRs, primitive polynomials, and the hypercube perspective, here's how everything connects:

### The Complete Picture

**At the surface (Part 6):**
- Gray code tells you which direction numbers to XOR
- Each dimension uses different direction numbers
- Result gets normalized to [0, 1]

**Underneath the hood (Parts 11-10):**
- Direction numbers come from primitive polynomials via LFSRs
- Each polynomial generates a maximal-length sequence in GF(2)
- Different polynomials = uncorrelated sequences = independent dimensions
- You're walking through a 32D binary hypercube, one bit-flip at a time
- The projection from hypercube → [0,1] creates the low-discrepancy property

### The Key Insight

**Don't think geometrically.** Think combinatorially:

You're not "moving through space" - you're **selecting and combining pre-computed bit patterns**. The even distribution in [0,1] is an emergent property of:
1. Maximal-length sequences (from primitive polynomials)
2. Single-bit transitions (from Gray code)
3. Reversible combination (from XOR)

The "magic" is that this mathematical structure, when projected to continuous space, produces provably optimal point distributions.

### Why This Matters for Game Development

Understanding this lets you:
- **Debug confidently**: Know why changing the index order breaks everything
- **Extend properly**: Generate your own dimensions using Joe & Kuo polynomials
- **Optimize intelligently**: Cache Gray code conversions, precompute XORs
- **Explain clearly**: "It's not random, it's a deterministic walk through binary space"

## Part 13: Demystifying the Magic Matrix - Where Do Those Numbers Come From?

You might be wondering: "Okay, I understand HOW to use the Matrix, but WHERE did those specific numbers come from? Did someone just make them up?"

No! They're systematically generated from primitive polynomials using a **recurrence relation**. Let me show you.

### The Bratley-Fox Algorithm (1988)

This is the standard algorithm for generating Sobol direction numbers:

```
Input: A primitive polynomial of degree s with coefficients a
Output: Direction numbers for one dimension
```

#### Step 1: Initialize the first s direction integers

These are called `m[1]`, `m[2]`, ..., `m[s]` and must be:

- Odd numbers
- `m[i] < 2^i`

Simple initialization: just use all 1s

```
m[1] = 1
m[2] = 1
m[3] = 1
...
```

(Production implementations use more sophisticated values for better distribution)

#### Step 2: Apply the recurrence relation

For primitive polynomial with binary representation `a`, compute remaining values:

```
m[i] = 2*a₁*m[i-1] ⊕ 4*a₂*m[i-2] ⊕ ... ⊕ 2^s*m[i-s] ⊕ m[i-s]
```

Where ⊕ is XOR and aⱼ is the j-th bit of `a`.

#### Step 3: Convert to direction numbers

The direction numbers are:

```
v[i] = m[i] * 2^(32-i)
```

This shifts `m[i]` to occupy the most significant bits of a 32-bit integer.

### Concrete Example: x³ + x + 1

Let's generate direction numbers for the primitive polynomial x³ + x + 1:

**Setup:**

- Degree `s = 3`
- Binary representation: `a = 1011` (bits for x³, x², x¹, x⁰)
- Coefficients: a₂ = 0 (no x² term), a₁ = 1 (x¹ term present)

**Step 1: Initialize**

```
m[1] = 1
m[2] = 1
m[3] = 1
```

**Step 2: Apply recurrence for m[4]**

For x³ + x + 1 (coefficients: a₂=0, a₁=1):

```
m[4] = 2*1*m[3] ⊕ 4*0*m[2] ⊕ 8*m[1] ⊕ m[1]
     = 2*1 ⊕ 0 ⊕ 8*1 ⊕ 1
     = 2 ⊕ 8 ⊕ 1
     = 11
```

Continue (note: a₂=0, so the `4*a₂*m[i-2]` term equals 0 and can be omitted):

```
m[5] = 2*1*m[4] ⊕ 4*0*m[3] ⊕ 8*m[2] ⊕ m[2] = 22 ⊕ 0 ⊕ 8 ⊕ 1 = 31
m[6] = 2*1*m[5] ⊕ 4*0*m[4] ⊕ 8*m[3] ⊕ m[3] = 62 ⊕ 0 ⊕ 8 ⊕ 1 = 55
m[7] = 2*1*m[6] ⊕ 4*0*m[5] ⊕ 8*m[4] ⊕ m[4] = 110 ⊕ 0 ⊕ 88 ⊕ 11 = 61
...
```

**Step 3: Convert to direction numbers**

```
v[0] = m[1] << 31 = 1 << 31 = 2147483648 = 0b10000000000000000000000000000000
v[1] = m[2] << 30 = 1 << 30 = 1073741824 = 0b01000000000000000000000000000000
v[2] = m[3] << 29 = 1 << 29 = 536870912  = 0b00100000000000000000000000000000
v[3] = m[4] << 28 = 11 << 28 = 2952790016
...
```

These are your direction numbers!

### Different Polynomials = Different Dimensions

The key to Sobol's multi-dimensional independence is using DIFFERENT primitive polynomials for each dimension:

| Dimension | Polynomial | Binary Representation |
|-----------|------------|----------------------|
| 0 | x² + x + 1 | 0b111 |
| 1 | x³ + x + 1 | 0b1011 |
| 2 | x⁴ + x + 1 | 0b10011 |
| 3 | x⁵ + x² + 1 | 0b100101 |
| 4 | x⁶ + x + 1 | 0b1000011 |
| ... | ... | ... |

Each polynomial generates its own set of direction numbers via the recurrence relation. These sets are mathematically independent, ensuring no correlation between dimensions.

### Why Pre-compute?

The direction numbers are:

- **Deterministic** - same polynomial always gives same numbers
- **Expensive to generate** - requires careful implementation
- **Used repeatedly** - every Sobol sample accesses them

So they're computed ONCE (offline, decades ago) and hardcoded as constants. The Matrix in your code is the result of running this algorithm for 8 dimensions, 32 bits each.

### Generating Your Own Matrix

If you need more dimensions or want to verify the numbers, here's simplified Python code:

```python
def generate_sobol_direction_numbers(s, a, num_bits=32):
    """
    Generate Sobol direction numbers.

    Args:
        s: degree of primitive polynomial
        a: coefficients as binary number (e.g., 0b101 for x^3+x+1)
        num_bits: how many direction numbers to generate
    """
    m = [0] * (num_bits + 1)  # 1-indexed

    # Initialize first s values (typically all 1s)
    for i in range(1, s + 1):
        m[i] = 1

    # Recurrence relation
    for i in range(s + 1, num_bits + 1):
        m[i] = m[i - s]
        for j in range(1, s):
            if a & (1 << (s - 1 - j)):
                m[i] ^= (1 << j) * m[i - j]
        m[i] ^= (1 << s) * m[i - s]

    # Convert to direction numbers
    return [m[i] << (32 - i) for i in range(1, num_bits + 1)]
```

### Production vs. Simple Implementation

**Important caveat:** The simplified algorithm above uses `m[i] = 1` for initialization. Production implementations (like the one in your game code) use carefully chosen initial values that provide better low-discrepancy properties.

The "magic" in the Matrix isn't just the recurrence relation - it's also the specific initialization values that were optimized by mathematicians. These values are published in papers (Bratley & Fox 1988, Joe & Kuo 2008) and widely reused.

### Where to Get Official Values

Don't generate your own unless you know what you're doing! Use published tables:

- **Joe & Kuo database:** Standard reference with up to 21,201 dimensions
  - Available at: [https://web.maths.unsw.edu.au/~fkuo/sobol/](https://web.maths.unsw.edu.au/~fkuo/sobol/)

- **Numerical Recipes:** Contains tables for common dimensions

- **Open source implementations:**
  - GSL (GNU Scientific Library)
  - `scipy.stats.qmc.Sobol` (Python)
  - Various C++ libraries

### The Takeaway

Those "magic numbers" aren't magic at all. They're:

- Generated from primitive polynomials via recurrence relations
- Optimized with carefully chosen initial values
- Pre-computed and published by researchers
- Used as constants in all implementations

You're standing on the shoulders of decades of mathematical research. The Matrix in your code represents hundreds of hours of optimization and verification work by mathematicians in the 1960s-2000s.

Use it with confidence - but also with respect for the sophistication behind those seemingly random numbers!

## Part 14: The Mathematical Foundations (For the Rigorous)

If you want the **formal mathematical proof** behind why Van der Corput and Sobol sequences work so well, here's the foundation from discrepancy theory.

### 1. The Radical Inverse Function (Formal Definition)

The Van der Corput sequence is formally defined using the **radical inverse function** φ_b(n):

For integer n with base-b representation:
```
n = Σ(i=0 to k) aᵢ · bⁱ  where 0 ≤ aᵢ < b
```

The radical inverse is:
```
φ_b(n) = Σ(i=0 to k) aᵢ · b⁽⁻ⁱ⁻¹⁾
```

For binary (b=2), this is exactly bit reversal:
```
n = aₖ·2ᵏ + aₖ₋₁·2ᵏ⁻¹ + ... + a₁·2 + a₀
φ₂(n) = a₀·2⁻¹ + a₁·2⁻² + ... + aₖ·2⁻⁽ᵏ⁺¹⁾
```

### 2. Discrepancy - The Formal Measure

**Star Discrepancy** D*_N measures how evenly distributed N points are:

```
D*_N = sup_{0≤x≤1} |A([0,x), N)/N - x|
```

Where:
- A([0,x), N) = number of points in [0, x)
- x = expected proportion if perfectly uniform

**Lower bound (proven):** For ANY sequence, D*_N ≥ C·log(N)/N

This is the **theoretical minimum** - you can't do better than O(log N / N).

### 3. Van der Corput Achieves Optimal Discrepancy

**Theorem (Van der Corput, 1935):**

For the Van der Corput sequence in base b:
```
D*_N ≤ (1/2 + (b-1)/(2b)) · log_b(N)/N + O(1/N)
```

For binary (b=2):
```
D*_N ≤ (3/4) · log₂(N)/N + O(1/N)
```

This matches the lower bound asymptotically → **provably optimal**!

### 4. Why Bit Reversal Specifically?

The proof relies on analyzing the **distribution in dyadic intervals** [k/2^m, (k+1)/2^m).

**Key Lemma:** For Van der Corput sequence, in ANY dyadic interval of length 2^(-m):
- Expected points: N/2^m
- Actual points: differs by at most O(log N)

**Why?** Because:

1. **Bit position i controls subdivision at scale 2^(-i)**
   - When bit i flips, it adds/removes 2^(-i-1) to the fraction
   - This corresponds to subdividing at that scale

2. **Bits flip in hierarchical order**
   - Bit 0 flips every step → finest subdivision
   - Bit k flips every 2^k steps → coarsest subdivision

3. **Inversion creates stratification**
   - Reversing maps: "flip frequency" → "subdivision scale"
   - Low frequency (coarse) flips control large jumps (0.5)
   - High frequency (fine) flips control small jumps (2^(-k))

**Formal statement:**

For N points generated by Van der Corput, the number of points in dyadic interval [k·2^(-m), (k+1)·2^(-m)) is:

```
A_{m,k} = N/2^m ± O(log N)
```

The O(log N) error is unavoidable (proven by lower bound), but Van der Corput achieves this bound.

### 5. The Proof Sketch

**Theorem:** Van der Corput sequence has discrepancy D*_N = O(log N / N).

**Proof outline:**

1. **Partition [0,1) into dyadic intervals** at scale 2^(-m):
   ```
   I_k = [k/2^m, (k+1)/2^m) for k = 0, 1, ..., 2^m - 1
   ```

2. **Count points in each interval:**
   - Van der Corput with N points: each interval gets N/2^m ± ε points
   - The ε error comes from boundary effects

3. **Key insight:** When you generate point n in Van der Corput:
   - Its position in base-2 is: n = Σ aᵢ·2ⁱ
   - Reversed position is: φ₂(n) = Σ aᵢ·2⁽⁻ⁱ⁻¹⁾
   - The coefficient aᵢ determines which dyadic subinterval at scale 2^(-i)

4. **Counting argument:**
   - Points 0 to 2^m - 1 hit EVERY dyadic interval exactly once at scale 2^(-m)
   - Points 2^m to 2^(m+1) - 1 hit every interval again
   - For general N, the "remainder" points cause at most log(N) error

5. **Bound the discrepancy:**
   ```
   For any x ∈ [0,1), pick dyadic approximation k/2^m with |x - k/2^m| < 2^(-m)

   |A([0,x), N)/N - x| ≤ |A([0, k/2^m), N)/N - k/2^m| + 2^(-m)
                       ≤ O(log N / N) + 1/2^m

   Choose m = log₂(N) → discrepancy = O(log N / N)
   ```

6. **Optimality:** Matches the lower bound → can't do better!

### The Key Mathematical Insight

The reason bit reversal works is **not geometric** - it's **number-theoretic**:

> **Base-b digit reversal creates equidistribution modulo 1 in base-b dyadic rationals.**

More formally:

> **The sequence {φ_b(n)} is equidistributed in [0,1) with discrepancy bounded by the sum of digit contributions at each scale, weighted by base^(-position).**

The hierarchical bit flipping ensures that:
- Coarse scales (large bits) are explored before fine scales (small bits)
- Each scale contributes additively to the discrepancy bound
- The total discrepancy sums to O(log N / N)

### Where to Find the Full Proof

The full rigorous proof uses:
- **Weyl's equidistribution criterion** (Fourier analysis approach)
- **Erdős-Turán inequality** (converts equidistribution to discrepancy bounds)
- **Dyadic partitioning argument** (combinatorial counting)

See the references section below for detailed sources.

**TL;DR:** The mathematical justification is **discrepancy theory**. Van der Corput proves that bit-reversal sequences achieve the theoretical minimum discrepancy of O(log N / N), which is proven impossible to beat. The "gap splitting" intuition is correct, but the formal proof uses measure theory and number-theoretic properties of base-2 representations.

## Conclusion

Sobol sequences are one of those "simple to use, hard to understand" algorithms. The implementation is ~10 lines of code, but the mathematical machinery underneath is deep.

You don't need to understand Galois fields or primitive polynomials to USE Sobol sequences. But if you're like me and you can't stand using "magic" without understanding it, hopefully this helps.

### Key takeaways:

- **Quasi-random ≠ random** - it's structured sampling that looks random
- **Gray code + XOR** is the perfect pair for incremental updates
- **Primitive polynomials** provide mathematical independence between dimensions
- **Think in hypercubes,** not geometric space
- **The Matrix values are pre-computed** - you're just looking them up and XORing

Now go spawn some evenly-distributed enemies!

## References and Further Reading

### Primary Sources

1. **Weyl, H. (1916).** "Ueber die Gleichverteilung von Zahlen mod. Eins" ("On the uniform distribution of numbers modulo one"). *Mathematische Annalen*, 77(3), 313-352.
   - The foundational paper on equidistribution theory

2. **van der Corput, J.G. (1935).** "Verteilungsfunktionen I-II." *Proceedings of the Koninklijke Nederlandse Akademie van Wetenschappen*, 38, 813-821, 1058-1066.
   - Introduced the radical inverse function and bit-reversal sequence

3. **Halton, J.H. (1960).** "On the efficiency of certain quasi-random sequences of points in evaluating multi-dimensional integrals." *Numerische Mathematik*, 2, 84-90.
   - Extended Van der Corput to multiple dimensions using different prime bases

4. **Sobol, I.M. (1967).** "Distribution of Points in a Cube and the Approximate Evaluation of Integrals" (in Russian). *Zhurnal Vychislitel'noi Matematiki i Matematicheskoi Fiziki*, 7, 784-802.
   - English translation: *USSR Computational Mathematics and Mathematical Physics*, 7, 86-112.
   - The breakthrough paper introducing primitive polynomial-based sequences

5. **Bratley, P. and Fox, B.L. (1988).** "Algorithm 659: Implementing Sobol's quasirandom sequence generator." *ACM Transactions on Mathematical Software*, 14(1), 88-100.
   - Standard algorithm for generating Sobol direction numbers up to 40 dimensions

6. **Joe, S. and Kuo, F.Y. (2008).** "Constructing Sobol sequences with better two-dimensional projections." *SIAM Journal on Scientific Computing*, 30, 2635-2654.
   - Comprehensive database extending Sobol sequences to 21,201 dimensions
   - Available at: [https://web.maths.unsw.edu.au/~fkuo/sobol/](https://web.maths.unsw.edu.au/~fkuo/sobol/)

### Textbooks and Comprehensive References

7. **Kuipers, L. and Niederreiter, H. (1974).** *Uniform Distribution of Sequences*. John Wiley & Sons, New York.
   - Reprint edition: Dover Publications (2006)
   - The definitive reference on uniform distribution theory
   - Chapter 2, Theorem 3.1 proves discrepancy bounds for radical inverse sequences

8. **Motwani, R. and Raghavan, P. (1995).** *Randomized Algorithms*. Cambridge University Press, New York.
   - Section 5.5 covers quasi-random sequences with accessible proofs
   - Excellent introduction for computer scientists

9. **Dick, J. and Pillichshammer, F. (2010).** *Digital Nets and Sequences: Discrepancy Theory and Quasi-Monte Carlo Integration*. Cambridge University Press.
   - Chapter 4 provides modern treatment of Sobol sequences
   - Comprehensive coverage of contemporary quasi-Monte Carlo methods

### Technical Resources

10. **Živković, M.** "A Table of Primitive Binary Polynomials." *Mathematics of Computation*.
    - Available at: [https://poincare.matf.bg.ac.rs/~ezivkovm/publications/primpol1.pdf](https://poincare.matf.bg.ac.rs/~ezivkovm/publications/primpol1.pdf)
    - Comprehensive tables of primitive polynomials for degrees n < 5000

11. **Partow.net Primitive Polynomial List**
    - Available at: [https://www.partow.net/programming/polynomials/](https://www.partow.net/programming/polynomials/)
    - List of primitive irreducible polynomials for GF(2^m), degrees 2-32

### Implementation References

12. **Joe, S. and Kuo, F.Y. (2003).** "Remark on algorithm 659: Implementing Sobol's quasirandom sequence generator." *ACM Transactions on Mathematical Software*, 29(1), 49-57.
    - Extended Bratley & Fox to 1111 dimensions

13. **SciPy implementation:** `scipy.stats.qmc.Sobol`
    - Production-quality Python implementation using Joe & Kuo parameters

14. **GNU Scientific Library (GSL):** Sobol sequence generator
    - C/C++ implementation with documentation

### Additional Reading

15. **Dick, J. and Pillichshammer, F. (2014).** "From van der Corput to modern constructions of sequences for quasi-Monte Carlo rules." *Indagationes Mathematicae*, 26(5), 760-822.
    - Excellent historical overview connecting classical and modern approaches
    - Available at: [https://arxiv.org/abs/1506.03764](https://arxiv.org/abs/1506.03764)

### Code Source

16. **Skylake-Official AFPEnemySpawner**
    - GitHub repository: [AFPEnemySpawner.cpp](https://github.com/SkylakeOfficial/AFPEnemySpawner/blob/1039767d3fbd9ccfe27e8a575bce6dfa4090b33d/Source/AFPEnemySpawner/Private/AFPEnemySpawnerActor.cpp#L18)
    - The original Unreal Engine implementation that inspired this deep dive

---

**Note:** The mathematical proofs cited above use techniques from:
- **Weyl's equidistribution criterion** (Fourier analysis)
- **Erdős-Turán inequality** (discrepancy bounds)
- **Dyadic partitioning arguments** (combinatorial counting)

For readers interested in the full rigorous proofs, start with Kuipers & Niederreiter (1974) or the more accessible Motwani & Raghavan (1995).

[Skylake-Official Github]:https://github.com/SkylakeOfficial/AFPEnemySpawner/blob/1039767d3fbd9ccfe27e8a575bce6dfa4090b33d/Source/AFPEnemySpawner/Private/AFPEnemySpawnerActor.cpp#L18
