---
layout: post
title: "Lyra Breakdown - Game Core Animation"
description:
  Sword? Slash. Hammer? Smash. Gun? Shoot. Bow? Draw. Staff? Cast. Shield? Block. Fist? Punch. Foot? Kick. Intuitive and simple, what's the problem? Well we need to program it, no, not 7 if-swtiches in Character class, we don't do that anymore.
date: 2025-05-18 19:05 +0800
categories: [Unreal, Gameplay]
published: false
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-game-core-audio/
lang: en
---

{% include ue_version_disclaimer.html version="5.5.4" %}

{% include ue_engine_post_disclaimer.html %}

> This is a series of notes about what I've learned from Epic's Lyra project. Which claim to be the best practices under current unreal engine framework. Some I don't know about, some I already know but I thought it would still be good noting down.
{: .prompt-info }

## Animation System Stcture

## Anim Graph

## Locomotion State Machine

## BlueprintThreadsafeUpdateAnimation

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #1  (also see ABP_ItemAnimLayersBase) </div>
This `AnimBP` does not run any logic in its Event Graph.
Logic in the Event Graph is processed on the Game Thread. Every tick, the Event Graph for each `AnimBP` must be run one after the other in sequence, which can be a performance bottleneck.
For this project, we've instead used the new `BlueprintThreadsafeUpdateAnimation` function (found in the My Blueprint tab). Logic in `BlueprintThreadsafeUpdateAnimation` can be run in parallel for multiple `AnimBP`'s simultaneously, removing the overhead on the Game Thread.
</div>

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #2</div>
This function is primarily responsible for gathering game data and processing it into useful information for selecting and driving animations.
A caveat with Threadsafe functions is that we can't directly access data from game objects like we can in the Event Graph. This is because other threads could be running at the same time and they could be changing that data. Instead, we use the Property Access system to access data. The Property Access system will copy the data automatically when it's safe.
Here's an example where we access the Pawn owner's location (search for "Property Access" from the context menu).
</div>

## Animation Graph Structure

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #3</div>
This Anim Graph does not reference any animations directly. It instead provides entry points for Montages and Linked Animation Layers to play poses at certain points in the graph. This graph's main purpose is to blend those entry points together (e.g. blending upper and lower body poses together).
This approach allows us to only load animations when they're needed. For example, a weapon will hold references to the required Montages and Linked Animation Layers, so that data will only be loaded when the weapon is loaded.
E.g. B_WeaponInstance_Shotgun holds references to Montages and Linked Animation Layers. That data will only be loaded when B_WeaponInstance_Shotgun is loaded.
B_WeaponInstance_Base is responsible for linking animation layers for weapons.
</div>

## Locomotion State Machine

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #4</div>
This state machine handles the transitions between high level character states.
The behavior of each state is mostly handled by the layers in ABP_ItemAnimLayersBase.
</div>

## Animation Layers

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #5</div>
As with AnimBP_Mannequin_Base, this animbp performs its logic in BlueprintThreadSafeUpdateAnimation.
Also, this animbp can access data from AnimBP_Mannequin_Base using Property Access and the GetMainAnimBPThreadSafe function. An example is below.
</div>

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #6</div>
This animbp was authored to handle the logic for common weapon types, like Rifles and Pistols. If custom logic is needed (e.g. for a weapon like a bow), a different animbp could be authored that implements the ALI_ItemAnimLayers interface.
Rather than referencing animation assets directly, this animbp has a set of variables that can be overriden by Child Animation Blueprints. These variables can be found in the "Anim Set - X" categories in the My Blueprint tab.
This allows us to reuse the same logic for multiple weapons without referencing (and thus loading) the animation content for each weapon in one animbp.
See ABP_RifleAnimLayers for an example of a Child Animation Blueprint that provides values for each "Anim Set" variable.
</div>

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #7</div>
This animbp implements a layer for each state in AnimBP_Mannequin_Base.
Layers can play a single animation, or contain complex logic like state machines.
</div>

## Anim Node Functions

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #8</div>
This is an example use case of Anim Node Functions.
Anim Node Functions can be run on animation nodes. They will only run when the node is active, which allows us to localize logic to specific nodes or states.
In this case, an Anim Node Function selects an animation to play when the node become relevant. Another Anim Node Function manages the play rate of the animation.
</div>

## Distance Matching

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #9</div>
This is an example of using Distance Matching to ensure that the distance traveled by the Start animation matches the distance traveled by the Pawn owner. This prevents foot sliding by keeping the animation and the motion model in sync.
This effectively controls the play rate of the Start animation. We clamp the effective play rate to prevent the animation from playing too slowly or too quickly.
If the effective play rate is clamped, we will still see some sliding. To fix this, we use Stride Warping later to adjust the pose to correct for the remaining difference.
The Animation Locomotion Library plugin is required to have access to Distance Matching functions.
</div>

## Animation Warping

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #10</div>
This is an example of warping the authored pose of the animation to match what the Pawn owner is actually doing.
Orientation Warping will rotate the lower body of the pose to align to the direction the Pawn owner is moving. We only author Forward/Back/Left/Right directions and rely on warping to fill in the gaps.
Orientation Warping will then realign the upper body so that the character continues to aim where the camera is looking.
Stride Warping will shorten or lengthen the stride of the legs when the authored speed of the animation doesn't match the actual speed of the Pawn owner.
The Animation Warping plugin is required to have access to these nodes.
</div>

## Turn In Place

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #1 (also see ABP_ItemAnimLayersBase)</div>
When the Pawn owner rotates, the mesh component rotates with it, which causes the feet to slide.
Here we counter the character's rotation to keep the feet planted.
</div>

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #2</div>
This function handles updating the yaw offset depending on the current state of the Pawn owner.
</div>

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #3</div>
We clamp the offset because at large offsets the character has to aim too far backwards, which over twists the spine. The turn in place animations will usually keep up with the offset, but this clamp will cause the feet to slide if the user rotates the camera too quickly.
If desired, this clamp could be replaced by having aim animations that can go up to 180 degrees or by triggering turn in place animations more aggressively.
</div>

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #4</div>
We want aiming to counter the yaw offset to keep the weapon aiming in line with the camera.
</div>

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #5</div>
When the yaw offset gets too big, we trigger TurnInPlace animations to rotate the character back. E.g. if the camera is rotated 90 degrees to the right, it will be facing the character's right shoulder. If we play an animation that rotates the character 90 degrees to the left, the character will once again be facing away from the camera.
We use the "TurnYawAnimModifier" animation modifier to generate the necessary curves on each TurnInPlace animation.
See ABP_ItemAnimLayersBase for examples of triggering TurnInPlace animations.
</div>

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #6 (also see AnimBP_Mannequin_Base)</div>
When the yaw offset gets big enough, we trigger a TurnInPlace animation to reduce the offset.
TurnInPlace animations often end with some settling motion when the rotation is finished. During this time, we move to the TurnInPlaceRecovery state, which can transition back to the TurnInPlaceRotation state if the offset gets big again.
This way we can keep playing the rotation part of the TurnInPlace animations if the Pawn owner keeps rotating, without waiting for the settle to finish.
</div>