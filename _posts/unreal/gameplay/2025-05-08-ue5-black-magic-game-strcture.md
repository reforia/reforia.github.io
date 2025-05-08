---
layout: post
title: "Lyra Breakdown - Game Structure"
description:
  This is a series of notes about what I've learned from Epic's Lyra project. Which claim to be the best practices under current unreal engine framework. Some I don't know about, some I already know but I thought it would still be good noting down.
date: 2025-05-08 1:18 +0800
categories: [Unreal, Gameplay]
published: false
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor-game-structure/
lang: en
---

{% include ue_version_disclaimer.html version="5.5.4" %}

## All Plugins and Categories
Lyra has enabled a huge amount of plugins, and they can be categorized into quite a few groups span across all the way from backend to frontend. The mindset here is, all these plugins are more or less contributing to the actual project features, so it's quite hard to talk about them without going through the actual project. Nevertheless, we will go through them thoroughly, and here's the first bite:

> Here's also some other posts about plugins at here [Lyra's Plugins] and here [Standard Plugins]
{: .prompt-tip }

### Settings

<div class="box-info" markdown="1">
<div class="title"> GameSettings </div>
From [Lyra's Plugins]:
Adds base classes for handling a settings screen in your project.

It builds off of `CommonUI`’s `ActivatableWidgets`, so it will be using that system for its base screen classes.

Something to note is all the settings data is declared in C++, meaning designers won’t be able to expand upon it without engineering help.
</div>


### Editor Tools

<div class="box-info" markdown="1">
<div class="title"> ActorPalette </div>
A plugin that adds a new tab to the editor that allows you to quickly add actors to your level. This will basically open up a new level and allowing us to drag and drop actors from one to another.

Simple Video Tutorial: https://www.youtube.com/watch?v=Ed2Ppnji4Tc
</div>

<div class="box-info" markdown="1">
<div class="title"> Lyra Ext Tool </div>
From [Lyra's Plugins]:
Adds EUW_MaterialTool, an editor widget seemingly useful in the Lyra Material editor.

Also adds a BP function Change Mesh Materials, which explicitly invokes PostEditChange when meshes change.
</div>


### Asset Management

<div class="box-info" markdown="1">
<div class="title"> AsyncMixin </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> DataRegistry </div>
An advanced system for managing data assets in Unreal Engine. It allows us to create a registry of data assets and provides a way to query and manipulate them at runtime. It advances the DataTable or CurveTable system, it's more like a database.

The biggest advantage of which is DataRegistry provides a decoupled way to pull data from any viable resources but with a unified API. We no longer need to read a hard reference to a DataTable or CurveTable, we can just use the DataRegistry API to pull data from any source. Sync or Async, and even cached.
</div>

<div class="box-info" markdown="1">
<div class="title"> AssetSearch </div>
This is a plugin that can used to enhance the search functionality in Unreal Engine. It allows us to search for assets in our project using various criteria, such as asset type, name, and tags. Or even parameters like const strings we are printing.
</div>

<div class="box-info" markdown="1">
<div class="title"> AssetReferenceRestrictions </div>
A plugin to block some asset from being referenced by other assets. This is useful for preventing circular dependencies or ensuring that certain assets are not used in specific contexts. Like a DLC data should reference the base game, but not the other way around.
</div>


### Geometry Tool

<div class="box-info" markdown="1">
<div class="title"> ModelingToolsEditorMode </div>
Add a new editor mode to Unreal Engine that allows us to create and manipulate 3D models directly in the editor. This is useful for creating custom assets or modifying existing ones without having to leave the editor. However, I think this is more a prototype tool than a production tool, as it doesn't have the same level of control and precision as a dedicated 3D modeling software like Blender or Maya.
</div>

<div class="box-info" markdown="1">
<div class="title"> GeometryScripting </div>
Very much alike houdini where procedural modeling can be achieved with this plugin. It could also be useful to do stuff like generate collision boxes or other geometry at runtime.
</div>

### Render & GFX
<div class="box-info" markdown="1">
<div class="title"> Volumetrics </div>
A library of volume creation and rendering tools using Blueprints.

The plugin provides a `VolumetricCloudFunctions.ush` file 
</div>

<div class="box-info" markdown="1">
<div class="title"> Niagara </div>
The VFX system in Unreal Engine, which is used for creating complex particle effects and simulations. It allows for real-time rendering of particles, fluids, and other visual effects.
</div>

<div class="box-info" markdown="1">
<div class="title"> Water </div>
The Water plugin in Unreal Engine is used for creating realistic water surfaces and effects. It provides tools for simulating water physics, reflections, refractions, and other water-related visual effects.
</div>

<div class="box-info" markdown="1">
<div class="title"> RuntimePhysXCooking </div>
Supports generate physx convex hull at runtime.
</div>


### Animations

<div class="box-info" markdown="1">
<div class="title"> AnimationLocomotionLibrary </div>
A Blueprint Library that provides a set of functions for DistanceMatching and CharacterMovement
</div>

<div class="box-info" markdown="1">
<div class="title"> AnimationWarping </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> ContextualAnimation </div>
C++ utility class for managing asynchronous operations like loading.
</div>


### Audio

<div class="box-info" markdown="1">
<div class="title"> Metasound </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioModulation </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioGameplayVolume </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioGameplay </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> SoundUtilities </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> Spatialization </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> ResonanceAudio </div>
C++ utility class for managing asynchronous operations like loading.
</div>


### Sequence

<div class="box-info" markdown="1">
<div class="title"> MovieRenderPipeline </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> MoviePipelineMaskRenderPass </div>
C++ utility class for managing asynchronous operations like loading.
</div>


### UI

<div class="box-info" markdown="1">
<div class="title"> CommonUI </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> CommonLoadingScreen </div>
From [Lyra's Plugins]:
Adds base classes and settings for handling a loading screen.

I haven’t looked into this plugin much, but from what I can remember you can also add an interface (ILoadingProcessInterface) to any class to show the loading screen when something needs to be loaded.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameSubtitles </div>
From [Lyra's Plugins]:
Provides Subtitle Display Subsystem.
</div>

<div class="box-info" markdown="1">
<div class="title"> UIExtension </div>
From [Lyra's Plugins]:
UI Extension Overview: https://x157.github.io/UE5/UIExtension/

Provides a map of Extension Point Gameplay Tag to Activatable Widget.

In this way you can access any widget you want/need via its Extension Point, and it is organized into your HUD as defined by the parent layout.

For example, you can load in different Widget classes depending on the type of Lyra Experience you load in a Game Feature Plugin. The score might go into the same location on the HUD, but be a different widget depending on the Experience.
</div>


### Input

<div class="box-info" markdown="1">
<div class="title"> EnhancedInput </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> WinDualShock </div>
C++ utility class for managing asynchronous operations like loading.
</div>


### Network

<div class="box-info" markdown="1">
<div class="title"> ReplicationGraph </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> AESGCMHandlerComponent </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> DTLSHandlerComponent </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> SteamSockets </div>
C++ utility class for managing asynchronous operations like loading.
</div>


### OSS

<div class="box-info" markdown="1">
<div class="title"> OnlineFramework </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> PlayFabParty </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineSubsystemEOS </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesEOS </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesNull </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesOSSAdapter </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineSubsystemSteam </div>
C++ utility class for managing asynchronous operations like loading.
</div>


### Authentication

<div class="box-info" markdown="1">
<div class="title"> CommonUser </div>
From [Lyra's Plugins]:
The Common User plugin provides a common interface between C++, Blueprint Scripting, and the [Online Subsystem] (OSS) or other online backends. It is a standalone plugin that can be used in any project.

Official Epic Docs: [Common User Plugin]

Provides Common User Subsystem, Common Session Subsystem and a Common User Initialize async action.
</div>


### DevOps

<div class="box-info" markdown="1">
<div class="title"> FunctionalTestingEditor </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> RuntimeTests </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> Gauntlet </div>
C++ utility class for managing asynchronous operations like loading.
</div>


### Performance

<div class="box-info" markdown="1">
<div class="title"> D3DExternalGPUStatistics </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> SignificanceManager </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> PocketWorlds </div>
From [Lyra's Plugins]:

This plugin allows for easy streaming of levels.

It is designed as a cleaner, compact solution for the classic way to render 3D characters in menus, which usually implies loading a map outside the normal gameplay boundaries.

Excellent Pocket Worlds Example and documentation:

https://gitlab.com/IsmaFilo/pocketworldexample
</div>


### Gameplay

<div class="box-info" markdown="1">
<div class="title"> GameFeatures </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> ModularGameplay </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> ModularGameplayActors </div>
From [Lyra's Plugins]:
Base classes that allow for Game Feature Plugins to have the ability to load components, widgets, etc at runtime.

All of Lyra’s base classes are themselves based on Modular Gameplay Actors.

Overview of a ModularGameplay Plugin: https://x157.github.io/UE5/ModularGameplay/
</div>

<div class="box-info" markdown="1">
<div class="title"> CommonGame </div>
From [Lyra's Plugins]:
Adds a system for utilizing CommonUI’s Activatable Widget Containers as “Layers”, and providing functions to push widgets to certain layers.

This is help for having your HUD on one layer and pushing a setting or pause menu to a layer above it.

This also makes it easy to use Gamepads to navigate your UI Menus, as they are all constructed using CommonUI Activatable Widgets in various Container layers.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayInteractions </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayBehaviors </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayBehaviorSmartObjects </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> SmartObjects </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayStateTree </div>
C++ utility class for managing asynchronous operations like loading.
</div>


<div class="box-info" markdown="1">
<div class="title"> GameplayAbilities </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayMessageRouter </div>
From [Lyra's Plugins]:
Adds a system for you to broadcast and receive events across the game by Gameplay Tag, optionally including a custom struct with event data.

An example is if you kill someone it could broadcast an event under a specific tag that provides the name of the person you killed, and a UI widget could receive that event to display the kill.

These events are local-player-only, a nice compliment to Gameplay Ability System’s Gameplay Event which is replicated over the network. The two systems are roughly analogous, Gameplay Message Subsystem being local-client only scope and Gameplay Event with network client scope.
</div>

<div class="box-info" markdown="1">
<div class="title"> CommonConversation </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayInsights </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> ControlFlows </div>
https://unrealengine.hatenablog.com/entry/2023/01/29/211937
</div>


### Gameplay Feature

<div class="box-info" markdown="1">
<div class="title"> ShooterCore </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> ShooterMaps </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> TopDownArena </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> ShooterExplorer </div>
C++ utility class for managing asynchronous operations like loading.
</div>

<div class="box-info" markdown="1">
<div class="title"> ShooterTests </div>
C++ utility class for managing asynchronous operations like loading.
</div>


## Project Structure
Project can be categorized into even more modules. Before we go through them in the following posts, let's first inspect them.

### Ability System
- /Abilities
  - AbilityCost
    - AbilityCost_InventoryItem
    - AbilityCost_ItemTagStack
    - AbilityCost_PlayerTagStack
  - AbilitySimpleFailureMessage
  - GameplayAbility
    - GameplayAbility_Death
    - GameplayAbility_Jump
    - GameplayAbility_Reset
- /Attributes
  - AttributeSet
  - CombatSet
  - HealthSet
- /Executions
  - DamageExecution
  - HealExecution
- /Phases
  - PhaseAbility
  - PhaseLog
  - PhaseSubsystem
- AbilitySet
- AbilitySourceInterface
- AbilitySystemComponent
- AbilitySystemGlobals
- AbilityTagRelationshipMapping
- GameplayCueManager
- GameplayEffectContext
- GlobalAbilitySystem
- TaggedActor
- GameplayAbilityTargetData_SingleTargetHit

### Audio
- /Audio
  - AudioMixEffectsSubsystem
  - AudioSettings

### Animations
- /Animation
  - AnimInstance

### Camera
- /Camera
  - CameraAssistInterface
  - CameraComponent
  - CameraMode
    - CameraMode_ThirdPerson
  - PenetrationAvoidanceFeeler
  - PlayerCameraManager
  - UICameraManagerComponent

### Character
- /Character
  - Pawn
  - PawnData
  - Character
  - CharacterWithAbilities
  - CharacterMovementComponent
  - HealthComponent
  - HeroComponent
  - PawnExtensionComponent

### (Separate) Cosmetics
- /Cosmetics
  - CharacterPartTypes
  - ControllerComponent_CharacterParts
  - CosmeticAnimationTypes
  - CosmeticCheats
  - CosmeticDeveloperSettings
  - PawnComponent_CharacterParts

### Development
- /Development
  - DeveloperSettings
  - PlatformEmulationSettings
  - BotCheats

### (Separate) Equipment
- /Equipment
  - EquipmentDefinition
  - EquipmentInstance
  - EquipmentManagerComponent
  - GameplayAbility_FromEquipment
  - PickupDefinition
  - QuickBarComponent

### Feedback
- /Feedback
  - /ContextEffects
    - ContextEffectsLibrary
    - ContextEffectComponent
    - ContextEffectsInterface
    - ContextEffectsSubsystem
    - AnimNotify_ContextEffect
  - /NumberPops
    - DamagePopStyle
    - NumberPopComponent
    - NumberPopComponent_MeshText
    - NumberPopComponent_NiagaraText

### GameFeatures
- /GameFeatures
  - GameFeaturePolicy
  - GameFeatureAction_AddInputContextMapping
  - GameFeatureAction_WorldActionBase
  - GameFeatureAction_AddAbilities
  - GameFeatureAction_AddGameplayCuePath
  - GameFeatureAction_AddInputBinding
  - GameFeatureAction_AddWidget
  - GameFeatureAction_SplitscreenConfig
  - GameFeatureAction_WorldActionBase

### GameModes
- /GameModes
  - GameMode
  - GameState
  - WorldSettings
  - UserFacingExperienceDefinition
  - ExperienceActionSet
  - ExperienceDefinition
  - ExperienceManager
  - ExperienceManagerComponent
  - AsyncAction_ExperienceReady
  - BotCreationComponent

### (Separate) Hotfix
- /Hotfix
  - HotfixManager
  - RuntimeOptions
  - TextHotfixConfig

### Input
- /Input
  - InputComponent
  - InputConfig

### (Separate) Interaction
- /Interaction
  - /Abilities
    - GameplayAbilityTargetActor_Interact
    - GameplayAbility_Interact
  - /Tasks
    - AbilityTask_GrantNearbyInteraction
    - AbilityTask_WaitForInteractableTargets
    - AbilityTask_WaitForInteractableTargets_SingleLineTrace
  - IInteractableTarget
  - IInteractionInstigator
  - InteractionOption
  - InteractionQuery
  - InteractionStatics
  - InteractionDurationMessage

### Inventory
- /Inventory
  - IPickupable
  - InventoryItemDefinition
  - InventoryItemInstance
  - InventoryManagerComponent
  - InventoryFragment_EquippableItem
  - InventoryFragment_PickupIcon
  - InventoryFragment_QuickBarIcon
  - InventoryFragment_SetStats

### Messages
- /Messages
  - VerbMessage
  - VerbMessageHelpers
  - VerbMessageReplication
  - NotificationMessage
  - GameplayMessageProcessor

### Performance
- /Performance
  - PerformanceSettings
  - PerformanceStatSubsystem
  - PerformanceStatTypes
  - MemoryDebugCommands

### Physics
- /Physics
  - CollisionChannels
  - PhysicalMaterialWithTags

### Player
- /Player
  - CheatManager
  - DebugCameraController
  - LocalPlayer
  - PlayerBotController
  - PlayerController
  - PlayerSpawningManagerComponent
  - PlayerStart
  - PlayerState

### Replays
- /Replays
  - ReplaySubsystem
  - AsyncAction_QueryReplays

### Settings
- /Settings
  - /CustomSettings
    - SettingKeyboardInput
    - SettingAction_SafeZoneEditor
    - SettingValueDiscrete_Language
    - SettingValueDiscrete_MobileFPSType
    - SettingValueDiscrete_OverallQuality
    - SettingValueDiscrete_PerfStat
    - SettingValueDiscrete_Resolution
    - SettingValueDiscreteDynamic_AudioOutputDevice
  - /Screens
    - BrightnessEditor
    - SafeZoneEditor
  - /Widgets
    - SettingsListEntrySetting_KeyboardInput
  - SettingsLocal
  - SettingsShared
  - GameSettingRegistry
    - GameSettingRegistry_Audio
    - GameSettingRegistry_Gamepad
    - GameSettingRegistry_Gameplay
    - GameSettingRegistry_MouseAndKeyboard
    - GameSettingRegistry_Video
    - GameSettingRegistry_PerfStats

### System
- /System
  - GameplayTagStack
  - AssetManager
  - AssetManagerStartupJob
  - GameData
  - GameSession
  - GameEngine
  - GameInstance
  - ReplicationGraph
  - ReplicationGraphSettings
  - ReplicationGraphType
  - SignificanceManager
  - SystemStatics
  - ActorUtilities
  - DevelopmentStatics

### Teams
- /Teams
  - TeamAgentInterface
  - TeamCheats
  - TeamCreationComponent
  - TeamDisplayAsset
  - TeamInfoBase
    - TeamPrivateInfo
    - TeamPublicInfo
  - TeamStatics
  - TeamSubsystem
  - AsyncAction_ObserveTeam
  - AsyncAction_ObserveTeamColors

### Tests
- /Tests
  - GameplayRpcRegistrationComponent
  - TestControllerBootTest

### UI
- /UI
  - /Basic
    - MaterialProgressBar
  - /Common
    - BoundActionButton
    - ListView
    - TabButtonBase
    - TabListWidgetBase
    - WidgetFactory
    - WidgetFactory_Class
  - /Foundation
    - ActionWidget
    - ButtonBase
    - ConfirmationScreen
    - ControllerDisconnectedScreen
    - LoadingScreenSubsystem
  - /Frontend
    - ApplyFrontendSettingsAction
    - FrontendStateComponent
    - LobbyBackground
  - /IndicatorSystem
    - IActorIndicatorWidget
    - IndicatorDescriptor
    - IndicatorLayer
    - IndicatorLibrary
    - IndicatorManagerComponent
    - SActorCanvas
  - /PerformanceStats
    - PerfStatContainerBase
    - PerfStatWidgetBase
  - /Subsystem
    - UIManagerSubsystem
    - UIMessaging
  - /Weapons
    - SCircumferenceMarkerWidget
    - CircumferenceMarkerWidget
    - SHitMarkerConfirmationWidget
    - HitMarkerConfirmationWidget
    - ReticleWidgetBase
    - WeaponUserInterface
  - HUD
  - HUDLayout
  - ActivatableWidget
  - GameViewportClient
  - JoystickWidget
  - SettingScreen
  - SimulatedInputWidget
  - TaggedWidget
  - TouchRegion

### (Separate) Weapons
- /Weapons
  - WeaponDebugSettings
  - WeaponInstance
  - WeaponSpawner
  - WeaponStateComponent
  - RangedWeaponInstance
  - GameplayAbility_RangedWeapon
  - DamageLogDebuggerComponent
  - InventoryFragment_ReticleConfig

[Lyra's Plugins]: https://x157.github.io/UE5/LyraStarterGame/Plugins/
[Online Subsystem]: https://dev.epicgames.com/documentation/en-us/unreal-engine/online-subsystem-in-unreal-engine?application_version=5.1
[Common User Plugin]: https://dev.epicgames.com/documentation/en-us/unreal-engine/common-user-plugin-in-unreal-engine-for-lyra-sample-game
[Standard Plugins]: https://argonauts.hatenablog.jp/entry/2021/12/23/083634