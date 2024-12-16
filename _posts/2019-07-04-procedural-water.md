---
layout: post
title: Procedurally Generated Water Shader in UE4
description: >-
  A procedural water shader based on GPU Gems
date: 2019-07-04 01:00 +0800
categories: [Unreal, Render]
tags: [Unreal, Render, Procedural, Water]
media_subpath: /assets/img/post-data/unreal/render/procedural-water/
image:
  path: procedural_water_1.gif
---

## Research Paper
[GPU Gems, Chapter 1. Effective Water Simulation from Physical Models, NVIDIA]


## Github Link
[Procedural Water Shader]

## Final Result
![Final Result](procedural_water_1.gif)
_The final result of the procedural water shader_

{% include embed/youtube.html id="0hdW7xoi7k0" %}

## Brief Introduction
This project is mainly trying to research and implement water shader based on GPU Gems Chapter 1 , the goal for the project is to create a believable, variant water shader that can provide dynamic visual looks, with large seamless scale water volume yet still have decent performance that can run on a modern GPU at realtime.

## Materials and Material Functions Structure
![Material Structure](procedural_water_2.webp)
_Material Structure_

## Core Material
{% include bpviewer.html id="8v_dumqt" %}

## MODULE BREAKDOWN
### Basic Mathematics / Algorithms / Terms
The biggest challenge is to implement the shader in Unreal, by manipulating the water surface vertex in real-time.

According to the book, the key to simulate realistic water waves is to blend multiple sine waves together, then manipulate them to give them a more natural look. (Gerstner Wave function for example)

#### Base Color
![Base Color](procedural_water_3.webp)
_Base Color_

Firstly, base color is simply just a tint of distorted scene color (which creates a refraction effect, see "Refraction" below), then it is interpolated by a depth test, to mimic the feeling of depth. 

#### Mathematically Generated Height: Gerstner
Since the wave function is using Gerstner:
![Mathematically Generated Height](procedural_water_4.webp)
_Mathematically Generated Height_

This function can be translated to unreal hlsl by:
```hlsl
float3 p;
p = WavePos;
p = float3( p.x + CigmaX, p.y + CigmaY, CigmaZ );
return p;
```

Where float3 WavePos; float CigmaX; float CigmaY and float CigmaZ are all inputs from outside

#### Procedurally Generated Normal
The normal will be:

![Procedurally Generated Normal](procedural_water_5.webp)
_Procedurally Generated Normal_

Which is the cross product of a vertex's Binormal and Tangent, in Unreal hlsl:
```hlsl
return float3(-1. DDX, -1. DDY, 1.);
```
![Procedurally Generated Normal](procedural_water_6.webp)
_Procedurally Generated Normal_

Here, DDX H(X,Y,T) is used to calculate the mix of all four curves:

```hlsl
// Wavelength
// Speed
// Direction
// K
float Phi;
float Freq;
//float w;
float Px;
float3 WorldPos;
float2 Dir;

Dir = Direction;
Freq = sqrt(9.8 2 3.1415 / Wavelength);
Phi = Speed * Freq;
WorldPos = GetWorldPosition(Parameters);

float tempFunc1;
tempFunc1 = (sin((dot(Dir, WorldPos.xy)) Freq + Time Phi) + 1.) / 2.;

float tempFunc2;
tempFunc2 = cos((dot(Dir, WorldPos.xy)) * Freq + Time * Phi);

Px = K * Freq * Dir.x * Amp * pow(tempFunc1, (K - 1)) * tempFunc2;
return Px;
```

#### Distance-Based Tessellation
![Distance-Based Tessellation](procedural_water_7.webp)
_Distance-Based Tessellation_

![Distance-Based Tessellation](procedural_water_8.gif)
_Distance-Based Tessellation_

#### Refraction
Refraction is using a distort of the sample uv of background scene color buffer:

![Refraction](procedural_water_9.webp)
_Refraction_









[GPU Gems, Chapter 1. Effective Water Simulation from Physical Models, NVIDIA]: https://developer.nvidia.com/gpugems/GPUGems/gpugems_ch01.html 
[Procedural Water Shader]: https://github.com/reforia/WaterProj
