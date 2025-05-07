---
layout: post
title: "Lyra Breakdown - Plugins Overview"
description:
  This is a series of notes about what I've learned from Epic's Lyra project. Which claim to be the best practices under current unreal engine framework. Some I don't know about, some I already know but I thought it would still be good noting down.
date: 2025-05-08 1:18 +0800
categories: [Unreal, Gameplay]
published: false
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor-plugins/
lang: en
---

{% include ue_version_disclaimer.html version="5.5.4" %}

## All Plugins
Lyra has enabled a huge amount of plugins, but they can be categorized into a few groups.

Settings:
- GameSettings

Editor Tools:
- ActorPalette

Asset Management:
- DataRegistry
- AsyncMixin
- AssetSearch
- AssetReferenceRestrictions

Geometry Tool:
- ModelingToolsEditorMode
- GeometryScripting

Render & GFX:
- Volumetrics
- Niagara
- Water
- RuntimePhysXCooking

Animation:
- AnimationLocomotionLibrary
- AnimationWarping
- ContextualAnimation

Audio:
- Metasound
- AudioModulation
- AudioGameplayVolume
- AudioGameplay
- SoundUtilities
- Spatialization
- ResonanceAudio

Sequence:
- MovieRenderPipeline
- MoviePipelineMaskRenderPass

UI:
- CommonUI
- CommonLoadingScreen
- GameSubtitles
- UIExtension

Input:
- EnhancedInput
- WinDualShock

Network:
- ReplicationGraph
- AESGCMHandlerComponent
- DTLSHandlerComponent
- SteamSockets

OSS
- OnlineFramework
- PlayFabParty
- OnlineSubsystemEOS
- OnlineServicesEOS
- OnlineServicesNull
- OnlineServicesOSSAdapter
- OnlineSubsystemSteasm

Authentication:
- CommonUser

DevOps:
- FunctionalTestingEditor
- RuntimeTests
- Gauntlet

Performance:
- D3DExternalGPUStatistics
- SignificanceManager
- PocketWorlds

Gameplay:
- GameFeatures
- ModularGameplay
- ModularGameplayActors
- CommonGame
- GameplayInteractions
- SmartObjects
- GameplayBehaviorSmartObjects
- GameplayStateTree
- GameplayBehaviors
- GameplayAbilities
- GameplayMessageRouter
- CommonConversation
- GameplayInsights
- ControlFlows

Gameplay Feature:
- ShooterCore
- ShooterMaps
- TopDownArena
- ShooterExplorer
- ShooterTests









