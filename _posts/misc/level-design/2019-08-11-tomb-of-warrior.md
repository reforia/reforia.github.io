---
layout: post
title: Tomb of Warrior
description: >-
  The Tomb of Warrior is a speedmap practice focus on lighting and level composition.
date: 2019-08-11 00:31 +0800
categories: [Misc, Level Design]
tags: [Archived]
image:
  path: tomb_of_warrior_4.webp
media_subpath: /assets/img/post-data/misc/tomb-of-warrior/
lang: en
---

{% include obsolete_warning.html %}

## Blockout
![Tomb of Warrior - Blockout](tomb_of_warrior_1.webp)
_Blockout_

## Screen Composition
![Tomb of Warrior - Screen Composition](tomb_of_warrior_2.webp)
_Screen Composition_

## Lighting Pass
![Tomb of Warrior - Lighting Pass](tomb_of_warrior_3.webp)
_Lighting Pass_

## Final Touch
![Tomb of Warrior - Final Touch](tomb_of_warrior_4.webp)
_Final Touch_

## Detail Breakdown
- Total Work: 6 Hrs
- Tools Used: Autodesk Maya, Quixel Bridge, Quixel Mixer, Adobe Photoshop, Free Fantasy Weapon Sample Pack (From Marketplace)
- Engine Used: Unreal Engine 4.22.3


## Post Mortem:
### What Went Well
- The workflow was pretty straight forward, doesn't encounter any technical issues in the project.
- A better understanding of lighting & level composition techniques was achieved by the project.
### What Went Wrong
- The scene layout doesn't quite fit well, objects in a distance were a bit crowded and disorganized.
- The different layers of distance can be better addressed, the left pillar was blended into the back scene a little bit.
- Transfer BSP into Static Mesh will result in lacking lightmass uv, recreated with static mesh that has UV0 channel.
- The weapon looks too clean in the final screenshot, expected to be a little bit worn out.
- The story was not well conveyed by the level itself.
- Lack of surprise.
  
### What I Learnt
- BSP can be used in blockout pass, but since BSP does not have UV0 information, it's better to blockout the level in Max/Maya.
- Modular Scene Composition (E.g Use Planes to build the Wall/Floor) is a fast approach, but also will result in incorrect rendering especially at the seam, Static Mesh performs better in such senario.
- Utilizing LOD is a good approach to optimize the performance, even in a small level.
- Have a brief idea of where the major light will come from at the very beginning of the level composition phase.
- Get rid of auto exposure (by set both Min/Max EV100 to 1.0) to get an un-biased lighting effect.
- If the directional light was not bright enough to lit up the whole scene, put some point lights at the window to mimic the sun effect.
- Volumetric Lighting is very good at creating the atmosphere, but also expensive.
- Consider the back story of the level, to make it more natural narrative-wise.
- Use reference to get a big picture of the final scene, as well as get inspired.
- Design a basic aesthetic papermap & concept art, to avoid getting lost when moving forward.
- Highlight should be added on the main object, too many highlighted objects will confuse the viewer.