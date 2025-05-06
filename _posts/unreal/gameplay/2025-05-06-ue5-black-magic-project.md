---
layout: post
title: "Lyra Breakdown - Project Config"
description:
  This is a series of notes about what I've learned from Epic's Lyra project. Which claim to be the best practices under current unreal engine framework. Some I don't know about, some I already know but I thought it would still be good noting down.
date: 2025-05-02 15:24 +0800
categories: [Unreal, Gameplay]
published: false
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor/
lang: en
---

{% include ue_version_disclaimer.html version="5.5.4" %}

## Build Targets and CustomConfigs

`{PROJECT}/Config/Custom/EOS/DefaultGame.ini`

```cpp
inline FConfigLayer GConfigLayers[] =
{
    /**************************************************
    **** CRITICAL NOTES
    **** If you change this array, you need to also change EnumerateConfigFileLocations() in ConfigHierarchy.cs!!!
    **** And maybe UObject::GetDefaultConfigFilename(), UObject::GetGlobalUserConfigFilename()
    **************************************************/

    // ...
    // Project/Custom/CustomConfig/Default*.ini only if CustomConfig is defined
    { TEXT("CustomConfig"),                TEXT("{PROJECT}/Config/Custom/{CUSTOMCONFIG}/Default{TYPE}.ini"), EConfigLayerFlags::RequiresCustomConfig },
    // ...
};
```