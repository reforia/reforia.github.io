---
layout: post
title: Curve Based Exponential Fog
description: >-
  a flexible and believable exponential fog in Unreal Engine 4 based on Direct3D 9's Exponential Fog Equation
date: 2019-12-10 22:09 +0800
categories: [Unreal, Render]
tags: [Unreal, Render, Fog]
media_subpath: /assets/img/post-data/unreal/render/curve-exp-fog/
lang: en
---

## Final Result
{% include embed/youtube.html id="sJfHmWLncXk" %}

## Goal and Scope
The goal of this project is to create a flexible and believable exponential fog in Unreal Engine 4 based on Direct3D 9's Exponential Fog Equation

## Reference
[Direct3D 9's Exponential Fog Equation]
[AdvancedVillagePackage - Marketplace]

## Core Logic
First, implement the equation of exponential fog as a barebone:

![Exponential Fog Equation](exp_fog_1.webp)
_Exponential Fog Equation_

Then, blend the fog factor with:

![Fog Factor](exp_fog_2.webp)
_Fog Factor_

After that, use a curve to control the color based on the distance between the camera:

![Curve](exp_fog_3.webp)
_Curve_

## Execution
First, implement basic exponential fog:

![Basic Exponential Fog](exp_fog_4.webp)
_Basic Exponential Fog_

Then, the original color is simply the scene color:

![Original Color](exp_fog_5.webp)
_Original Color_

Here, a height based mask was calculated (use one minus because we want the bottom part to be opaque):

![Height Mask](exp_fog_6.webp)
_Height Mask_

Finally, blend them together:

![Final Result](exp_fog_7.webp)
_Final Result_

## Full Graph
{% include bpviewer.html id="6faqme5t" %}


[Direct3D 9's Exponential Fog Equation]: https://docs.microsoft.com/en-us/windows/win32/direct3d9/fog-formulas 

[AdvancedVillagePackage - Marketplace]: https://www.unrealengine.com/marketplace/advanced-village-pack