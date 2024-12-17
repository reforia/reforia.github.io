---
layout: post
title: Portal Shader - Unreal Engine 4
description: >-
  a shader that can mimic an illusion of portal through which another world is behind
date: 2018-11-12 09:00 +0800
categories: [Unreal, Render]
tags: [Unreal, Render, Portal]
image:
  path: portal_shader_1.gif
media_subpath: /assets/img/post-data/unreal/render/portal-shader/
---

## Goal and Scope
The goal of this project is simply to create a shader that can mimic an illusion of portal through which another world is behind. The method can be further developed to make functions like shifting world between each other.

## Core Logic
The core idea behind this project is to render an extra level and store the frame data in a render target, then, using depth buffer to mask out the portal area in post-process material as well as do some extra fixing(gamma correction, tone mapping, light channel etc.) Finally, apply the material on the portal.

## Render Target
![Render Target](portal_shader_2.webp)
_Render Target_

## Further Research
In the future, this can be used to switch between different worlds, like the effect used in Dishonored 2, also, the performance can be optimized without using full screen resolution render target.

