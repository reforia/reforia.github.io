---
layout: post
title: "Lyra Breakdown - Plugins Structure"
description:
  Looked into the Plugins in Lyra so you don't have to. They were compiled together with related documentations to ease searching 
date: 2025-05-08 1:18 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor-plugin-structure/
lang: en
---

{% include ue_version_disclaimer.html version="5.5.4" %}

> This is a series of notes about what I've learned from Epic's Lyra project. Which claim to be the best practices under current unreal engine framework. Some I don't know about, some I already know but I thought it would still be good noting down.
{: .prompt-info }

## All Plugins and Categories
Lyra has enabled a huge amount of plugins, and they can be categorized into quite a few groups span across all the way from backend to frontend. The mindset here is, all these plugins are more or less contributing to the actual project features, so it's quite hard to talk about them without going through the actual project. Nevertheless, we will go through them thoroughly, and here's the first bite:

> Here's also some other posts about plugins at here [Lyra's Plugins], here [UE5 Study], here [Zomg's Unreal Engine Notes] and here [Standard Plugins]
{: .prompt-tip }

## Settings

<div class="box-info" markdown="1">
<div class="title"> GameSettings </div>
From [Lyra's Plugins]:
"Adds base classes for handling a settings screen in your project.

It builds off of `CommonUI`’s `ActivatableWidgets`, so it will be using that system for its base screen classes.

Something to note is all the settings data is declared in C++, meaning designers won’t be able to expand upon it without engineering help."
</div>


## Editor Tools

<div class="box-info" markdown="1">
<div class="title"> ActorPalette </div>
A plugin that adds a new tab to the editor that allows you to quickly add actors to your level. This will basically open up a new level and allowing us to drag and drop actors from one to another.

Simple Video Tutorial:
{% include embed/youtube.html id="Ed2Ppnji4Tc" %}
</div>

<div class="box-info" markdown="1">
<div class="title"> Lyra Ext Tool </div>
From [Lyra's Plugins]:
"Adds `EUW_MaterialTool`, an editor widget seemingly useful in the Lyra Material editor.

Also adds a BP function Change Mesh Materials, which explicitly invokes PostEditChange when meshes change."
</div>


## Asset Management

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


## Geometry Tool

<div class="box-info" markdown="1">
<div class="title"> ModelingToolsEditorMode </div>
Add a new editor mode to Unreal Engine that allows us to create and manipulate 3D models directly in the editor. This is useful for creating custom assets or modifying existing ones without having to leave the editor. However, I think this is more a prototype tool than a production tool, as it doesn't have the same level of control and precision as a dedicated 3D modeling software like Blender or Maya.
</div>

<div class="box-info" markdown="1">
<div class="title"> GeometryScripting </div>
Very much alike houdini where procedural modeling can be achieved with this plugin. It could also be useful to do stuff like generate collision boxes or other geometry at runtime.
</div>

## Render & GFX
<div class="box-info" markdown="1">
<div class="title"> Volumetrics </div>
A library of volume creation and rendering tools using Blueprints.

The plugin provides a `VolumetricCloudFunctions.ush` file 
</div>

<div class="box-info" markdown="1">
<div class="title"> Niagara </div>
The VFX system in Unreal Engine, which is used for creating complex particle effects and simulations. It allows for real-time rendering of particles, fluids, and other visual effects.

Official documentation: [Niagara]
</div>

<div class="box-info" markdown="1">
<div class="title"> Water </div>
The Water plugin in Unreal Engine is used for creating realistic water surfaces and effects. It provides tools for simulating water physics, reflections, refractions, and other water-related visual effects.

Official documentation: [Water]
</div>

## Animations

<div class="box-info" markdown="1">
<div class="title"> AnimationLocomotionLibrary </div>
A Blueprint Library that provides a set of functions for DistanceMatching and CharacterMovement

[Distance Maching] Document is an example of how to use the library in action.
</div>

<div class="box-info" markdown="1">
<div class="title"> AnimationWarping </div>
A library to provide utilities about animation warping, such as OrientationWarping, SlopeWarping, StrideWarping, etc.
</div>

<div class="box-info" markdown="1">
<div class="title"> ContextualAnimation </div>
This plugin does all the heavy lifting for us to sync multiple characters' animations together in a montage, so that we can make cool execution finishers, sit down on a chair smoothly, pull our hands on a wall, to name a few.

A great [CAS Tutorial] can be found here
</div>


## Audio

<div class="box-info" markdown="1">
<div class="title"> Metasound </div>
No need to introduce this, cuz it's famous enough and complex enough to even start. Epic has a dedicated [Metasound Documentation] for it.
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioModulation </div>
This plugin adds Audio Modulation and Control Bus, as well as Control Bus Mix to Unreal Engine, function wise, it is slightly similar to what the previous UE4's audio duck down system does. But having a control bus is a more flexible and powerful way to manage audio in Unreal Engine. And the user experience is also much closer to a professional DAWs like Wwise.

[Audio Modulation Quick Start] is a good place to start.
[Audio Modulation Documentation] for more details.
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioGameplayVolume </div>
A small plugin that can allow a volume to control the audio features like reverb, etc. Which normally would be done manually with a blueprint or code. This plugin has already took care of stuff like Reverb, Submix, Attennuation, etc.

Related documentation [Audio Gameplay Volume]
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioGameplay </div>
This plugin is a little bit like Gameplay Ability, except that now it's the audio component that responding to (being triggered by) Gameplay events, so we can make stuff like when entered a place, interacted with something, looked at something, health below a certain threshold - to trigger a audio related logic.
</div>

<div class="box-info" markdown="1">
<div class="title"> SoundUtilities </div>
A utility library for sound related info, like `GetQFromBandwidth`, `ConvertDecibelsToLinear`, `GetFrequencyFromMIDPitch`, `GetBeatTemp`, etc.
</div>

<div class="box-info" markdown="1">
<div class="title"> Spatialization </div>
Provides a `FSourceSpatializer` struct and `FITDSpatialization` class for processing ITD spactialization.
</div>

## Cinematic

<div class="box-info" markdown="1">
<div class="title"> MovieRenderPipeline </div>
The framework is the Unreal way to offline render for linear content, such as movies, cinematics, and other high-quality visual content. It provides a set of tools and features for rendering high-quality images and videos from Unreal Engine.

Official documentation: [Movie Render Pipeline]
</div>

<div class="box-info" markdown="1">
<div class="title"> MoviePipelineMaskRenderPass </div>
Added additional render passes to the Movie Render Pipeline, such as `MoviePiplelineObjectIdPass` and `MoviePiplelinePanoramicPass`.
</div>


## UI

<div class="box-info" markdown="1">
<div class="title"> CommonUI </div>
A revolutionary plugin that solves the painpoints for most games UI system, an extension of UMG but kinda completely obsoletes UMG. There're plenty of resources on the internet.

Official documentation: [CommonUI Plugin]
</div>

<div class="box-info" markdown="1">
<div class="title"> CommonLoadingScreen </div>
From [Lyra's Plugins]:
"Adds base classes and settings for handling a loading screen."

A framework to handle loading screens, including `CommonStartupLoadingScreen` and ``CommonLoadingScreen` modules.

It took care of blocking inputs during loading, and can be used to hide streaming levels for X seconds as well. It will per tick query all the way from level to game state to each game actors that implemnted `ILoadingProcessInterface` to decide whether a loading screen is needed.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameSubtitles </div>
From [Lyra's Plugins]:
"Provides Subtitle Display Subsystem."

It also binds widgets of game substitles to a Media Player
</div>

<div class="box-info" markdown="1">
<div class="title"> UIExtension </div>
From [Lyra's Plugins]:
"UI Extension Overview: https://x157.github.io/UE5/UIExtension/

Provides a map of Extension Point Gameplay Tag to Activatable Widget.

In this way you can access any widget you want/need via its Extension Point, and it is organized into your HUD as defined by the parent layout.

For example, you can load in different Widget classes depending on the type of Lyra Experience you load in a Game Feature Plugin. The score might go into the same location on the HUD, but be a different widget depending on the Experience."

Think of this as a harbour, where the main UI will define a port - an arbitrary extension point (Health Bar Area, etc), then no matter what the actual UI is (From Game Feature Plugin or whatever), that UI will be hooked to the port and being rendered.
</div>


## Input

<div class="box-info" markdown="1">
<div class="title"> EnhancedInput </div>
Again, a famous new system that replaces the old input system in UE4. No need for introduction.

Official documentation: [Enhanced Input]
</div>

<div class="box-info" markdown="1">
<div class="title"> WinDualShock </div>
A plugin that detects the DualShock controller input on Windows.

Although I wasn't really sure why not just use `RawInput` plugin directly. [Raw Input Documentation] can be found here.
</div>


## Network

<div class="box-info" markdown="1">
<div class="title"> ReplicationGraph </div>
A new replication system that allow more granular and nuanced control over what and how data is replicated over the network. It leverages the replication graph nodes to determin what's being replciated to whom, and cache the data for much scalable and efficient replication. With this plugin, FNBR can support 100+ players and 50000 replicated actors in a session without bloating the network and CPU.

Offcial Documentation: [Replication Grpah]

Official Livestream: [Replication Graph Live Stream]
</div>

<div class="box-info" markdown="1">
<div class="title"> AESGCMHandlerComponent </div>
An component to encrypt and decrypt the network packet data using AES-GCM algorithm. It is used to secure the network communication between the client and server, ensuring that the data is transmitted securely and cannot be intercepted or tampered with by malicious actors.
</div>

<div class="box-info" markdown="1">
<div class="title"> DTLSHandlerComponent </div>
Another component used to encrypt the network, but instead of per packet data, it is used to secure the entire network connection using DTLS (Datagram Transport Layer Security) protocol. It is used to establish a secure connection between the client and server, ensuring that all data transmitted over the connection is encrypted and secure.
</div>

<div class="box-info" markdown="1">
<div class="title"> SteamSockets </div>
A plugin that supports the newer SteamSockets API, which is a more efficient and flexible way to handle network communication in Unreal Engine.

Official documentation: [SteamSockets Documentation]

Tutorial: [SteamSockets Tutorial]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineFramework </div>
As the name implies, this framework provides a standard shared point for online game services. Modules include `HotFix`, `Lobby`, `LoginFlow`, `Party`, `PatchCheck`, `PlayTimeLimit`, `Qos`, `Rejoin`

There aren't many details available for this module online, so we will have to dig into the code ourselves and see how it's been implemented in Lyra.
</div>

<div class="box-info" markdown="1">
<div class="title"> PlayFabParty </div>
Support for Microsoft Azure PlayFab Party SDK. Unlike the other OSS, this one is more a VOIP solution.

Related Github repo: [PlayFabMultiplayerUnreal]

PlayFab OSS: [PlayFab OSS]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineSubsystemSteam </div>
Support for Steam OSS. An OSS essentially is an abstraction layer that cooperates with the third party SDK, in this case, Steam, to properly distribute the game on steam and hook with Steam SDK's session, authentication features.

It's important to distinguish between `OnlineSubsystem Plugin`, `OnlineServices Plugin` and `OnlineServices`, `OnlineSubsystemPlugin` is an unreal concept that wraps up the third party, engine agnostic `OnlineServices` SDK. like `Steam Online Service` doesn't really care which engine the game was made with. And then the `OnlineServices Plugin` is the modern UE5 abstraction layer that meant to replace the old `OnlineSubsystem Plugin`.

OS Official Documentation: [Online Subsystem]

Steam OSS Official Documentation: [Online Subsystem Steam]

Tutorial: [UE Online Subsystem Steam Tutorial]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineSubsystemEOS </div>
Similar to Steam OSS, with the EOS as service provider.

EOS OSS Official Documentation: [Online Subsystem EOS]

Tutorial: [EOS OSS Tutorial]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesEOS </div>
The newer `OnlineServices` plugin that is meant to replace the old `OnlineSubsystem` plugin. It provides a more modern and flexible way to handle online services in Unreal Engine, allowing for easier integration with third-party services and better support for cross-platform play.

Official Documentation: [Online Service EOS]
, [Online Sevice Overview]

</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesNull </div>
Basically a development OS plugin that doesn't have a real backend but simulated one.

Tutorial: [Setup and Configure Online Services] and [Structure and Implement the Online Services Plugins]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesOSSAdapter </div>
A compatibility layer that allows the new `OnlineServices` plugin to work with the old `OnlineSubsystem` plugin. This is useful for projects that are transitioning from the old system to the new one, as it allows them to continue using their existing code and assets while taking advantage of the new features and improvements in the `OnlineServices` plugin.
</div>


## Gameplay
This is a huge topic, before we dive into any of the plugins, Epic has a greate documentation that helps us wrap our head around the gameplay framework in UE5. [Making Interactive Experiences]

<div class="box-info" markdown="1">
<div class="title"> ModularGameplay </div>
The foundation work for gameplay features, it m	provides Base classes and subsystems to support modular use of the gameplay framework. Like supporting injecting components into the game at runtime.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameFeatures </div>
The UE5 way to implement modular game features. It allows us to create and manage game features in a modular way, making it easier to add, remove, or modify features without affecting the rest of the game.
</div>

<div class="box-info" markdown="1">
<div class="title"> ModularGameplayActors </div>
From [Lyra's Plugins]:
"Base classes that allow for Game Feature Plugins to have the ability to load components, widgets, etc at runtime.

All of Lyra’s base classes are themselves based on Modular Gameplay Actors."

Overview of a ModularGameplay Plugin: https://x157.github.io/UE5/ModularGameplay/
</div>

<div class="box-info" markdown="1">
<div class="title"> CommonGame </div>
From [Lyra's Plugins]:
"Adds a system for utilizing CommonUI’s Activatable Widget Containers as “Layers”, and providing functions to push widgets to certain layers.

This is help for having your HUD on one layer and pushing a setting or pause menu to a layer above it.

This also makes it easy to use Gamepads to navigate your UI Menus, as they are all constructed using CommonUI Activatable Widgets in various Container layers."
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayInteractions </div>
A framework for handling interactions for players and AI. Although it is the description of this plugin, but seems currently only NPC AI is supported, a huge amount of code is realted to StateTree
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayBehaviors </div>
From the `uplugin` description it sais: 	"Encapsulated fire-and-forget behaviors for AI agents". From the actual code it seems to be a wrap up of the behavior tree system. Combines blackboard values to gameplay tags.
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayBehaviorSmartObjects </div>
Provide some API support for interacting with Smart Objects via Gameplay Behaviors.
</div>

<div class="box-info" markdown="1">
<div class="title"> SmartObjects </div>
This plugin provides a system for creating and managing smart objects in Unreal Engine. Smart objects are interactive objects that can be used by AI agents to perform specific actions or behaviors. The plugin provides a set of tools and features for creating, managing, and using smart objects in your game.

Official documentation: [Smart Objects]
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayStateTree </div>
State Tree is a new system for managing the state of anything that needs states switch (Even mainly used for AI) in Unreal Engine. It streamlines the process of we manually manage a state machine and provides a unified way to handle state transitions, actions, and conditions.

Official Documentation: [State Tree]
</div>


<div class="box-info" markdown="1">
<div class="title"> GameplayAbilities </div>
GAS is a huge topic that doesn't need further introduction here. It's one of the most discussed and documented system on the internet and is the go-to way of implementing interactions in a game in UE5.

Official Documentation: [GAS]
Community Documentation: [GAS Community Docs]
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayMessageRouter </div>
From [Lyra's Plugins]:
"Adds a system for you to broadcast and receive events across the game by Gameplay Tag, optionally including a custom struct with event data.

An example is if you kill someone it could broadcast an event under a specific tag that provides the name of the person you killed, and a UI widget could receive that event to display the kill.

These events are local-player-only, a nice compliment to Gameplay Ability System’s Gameplay Event which is replicated over the network. The two systems are roughly analogous, Gameplay Message Subsystem being local-client only scope and Gameplay Event with network client scope."
</div>

<div class="box-info" markdown="1"> <div class="title"> CommonConversation </div>
A modular framework built around Gameplay Tags and Data Assets for managing branching dialogue and conversations in gameplay.

Designed to support both linear and branching dialogue trees, it allows NPCs and players to exchange messages, make choices, and respond based on gameplay state. Conversations can be defined entirely in assets, making them editable by designers without code.
</div>

<div class="box-info" markdown="1"> <div class="title"> ControlFlows </div> 
A plugin that enables a modular and declarative way to define flow tasks in code. Like define a user login flow, or a series of steps to load a level, a quest line, whatever, you name it.

Tutorial can be found here: [ControlFlows Tutorial]
</div>

## Authentication

<div class="box-info" markdown="1">
<div class="title"> CommonUser </div>
From [Lyra's Plugins]:
"The Common User plugin provides a common interface between C++, Blueprint Scripting, and the [Online Subsystem] (OSS) or other online backends. It is a standalone plugin that can be used in any project.

Official Epic Docs: [Common User Plugin]

Provides Common User Subsystem, Common Session Subsystem and a Common User Initialize async action."
</div>


## QC
The plugins here are really useful for the Automation System, docoumented here [Automation System Overview] That can allow us to quickly create and run unit tests.

<div class="box-info" markdown="1">
<div class="title"> FunctionalTestingEditor </div>
A testing framework that allows us to create and run functional tests in Unreal Engine. It provides a set of tools and features for creating, managing, and running tests in your game.

Official Documentation: [Functional Testing]
</div>

<div class="box-info" markdown="1">
<div class="title"> RuntimeTests </div>
A framework that allows us to perform tests during runtime, whether in editor or cooked build.

There aren't any officual documentations for this, so it would be better to just read from code, we will cover it when we go through the Lyra implementation.
</div>

<div class="box-info" markdown="1">
<div class="title"> Gauntlet </div>
This is another automation test framework that can run tests. Differnece is Gauntlet is targeting a broader picture, it's not amiming for build the framework to test a specific gameplay feature, but rather to manage a whole `Unreal Session`, consider a multiplayer game test where we need to run 4 clients and 1 server, Gauntlet will get to correct build, fire up needed processes, run the tests, waiting for session quit, and then report the results.

Offifcial Documentation: [Gauntlet], [Run Gauntlet Tests], [Gauntlet Primer]
</div>


## Performance

<div class="box-info" markdown="1"> <div class="title"> GameplayInsights </div> From Gameplay Insights is a powerful profiling tool that helps analyze and visualize gameplay-related data such as replication, network traffic, ability usage, and more.

It integrates with Unreal's Trace system and provides timelines, event traces, and stat tracking to diagnose performance and logic issues during gameplay. Lyra makes use of this for measuring ability activations and message routing performance.
</div>

<div class="box-info" markdown="1">
<div class="title"> D3DExternalGPUStatistics </div>
`Unknown Plugin`, this plugin is enabled in Lyra, but does not exist in Unreal native plugins nor Lyra projects, prob. an Epic internal plugin that used to trace EGPU statistics.
</div>

<div class="box-info" markdown="1">
<div class="title"> SignificanceManager </div>
This is a framework to provide more granular control over streaming or other custom treatments based on the significance of actors in a scene for optimization (Like some small VFX would just stop playing when the significance score is lower than a threshold). 

It allows us to define and manage the significance of actors based on their distance from the camera, their visibility, and other factors. This can help improve performance by reducing the number of actors that need to be rendered or updated at any given time.

Official Documentation: [Significance Manager]
</div>

<div class="box-info" markdown="1">
<div class="title"> PocketWorlds </div>
From [Lyra's Plugins]:

"This plugin allows for easy streaming of levels.

It is designed as a cleaner, compact solution for the classic way to render 3D characters in menus, which usually implies loading a map outside the normal gameplay boundaries.

Excellent Pocket Worlds Example and documentation:

https://gitlab.com/IsmaFilo/pocketworldexample"
</div>

## Project Structure
Project can be categorized into even more modules. Before we go through them in the following posts, let's first inspect them. (Some categories marked with "Separate" means they are more or less an extension of the core Lyra architecture. The project could still compile without them, they are crucial to the actual game content.)

## Ability System
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

## Audio
- /Audio
  - AudioMixEffectsSubsystem
  - AudioSettings

## Animations
- /Animation
  - AnimInstance

## Camera
- /Camera
  - CameraAssistInterface
  - CameraComponent
  - CameraMode
    - CameraMode_ThirdPerson
  - PenetrationAvoidanceFeeler
  - PlayerCameraManager
  - UICameraManagerComponent

## Character
- /Character
  - Pawn
  - PawnData
  - Character
  - CharacterWithAbilities
  - CharacterMovementComponent
  - HealthComponent
  - HeroComponent
  - PawnExtensionComponent

## (Separate) Cosmetics
- /Cosmetics
  - CharacterPartTypes
  - ControllerComponent_CharacterParts
  - CosmeticAnimationTypes
  - CosmeticCheats
  - CosmeticDeveloperSettings
  - PawnComponent_CharacterParts

## Development
- /Development
  - DeveloperSettings
  - PlatformEmulationSettings
  - BotCheats

## (Separate) Equipment
- /Equipment
  - EquipmentDefinition
  - EquipmentInstance
  - EquipmentManagerComponent
  - GameplayAbility_FromEquipment
  - PickupDefinition
  - QuickBarComponent

## Feedback
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

## GameFeatures
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

## GameModes
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

## (Separate) Hotfix
- /Hotfix
  - HotfixManager
  - RuntimeOptions
  - TextHotfixConfig

## Input
- /Input
  - InputComponent
  - InputConfig

## (Separate) Interaction
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

## Inventory
- /Inventory
  - IPickupable
  - InventoryItemDefinition
  - InventoryItemInstance
  - InventoryManagerComponent
  - InventoryFragment_EquippableItem
  - InventoryFragment_PickupIcon
  - InventoryFragment_QuickBarIcon
  - InventoryFragment_SetStats

## Messages
- /Messages
  - VerbMessage
  - VerbMessageHelpers
  - VerbMessageReplication
  - NotificationMessage
  - GameplayMessageProcessor

## Performance
- /Performance
  - PerformanceSettings
  - PerformanceStatSubsystem
  - PerformanceStatTypes
  - MemoryDebugCommands

## Physics
- /Physics
  - CollisionChannels
  - PhysicalMaterialWithTags

## Player
- /Player
  - CheatManager
  - DebugCameraController
  - LocalPlayer
  - PlayerBotController
  - PlayerController
  - PlayerSpawningManagerComponent
  - PlayerStart
  - PlayerState

## Replays
- /Replays
  - ReplaySubsystem
  - AsyncAction_QueryReplays

## Settings
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

## System
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

## Teams
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

## Tests
- /Tests
  - GameplayRpcRegistrationComponent
  - TestControllerBootTest

## UI
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

## (Separate) Weapons
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
[Zomg's Unreal Engine Notes]: https://zomgmoz.tv/unreal/
[UE5 Study]: https://ue5study.com/
[Online Subsystem]: https://dev.epicgames.com/documentation/en-us/unreal-engine/online-subsystem-in-unreal-engine?application_version=5.1
[Common User Plugin]: https://dev.epicgames.com/documentation/en-us/unreal-engine/common-user-plugin-in-unreal-engine-for-lyra-sample-game
[Standard Plugins]: https://argonauts.hatenablog.jp/entry/2021/12/23/083634
[Distance Maching]: https://dev.epicgames.com/documentation/en-us/unreal-engine/distance-matching-in-unreal-engine?application_version=5.0
[CAS Tutorial]: https://vorixo.github.io/devtricks/contextual-anim/#how-to-play-a-contextual-animation-during-gameplay
[Metasound Documentation]: https://dev.epicgames.com/documentation/en-us/unreal-engine/metasounds-in-unreal-engine
[Audio Modulation Quick Start]: https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-modulation-quick-start-guide
[Audio Modulation Documentation]: https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-modulation-overview?application_version=4.27
[Audio Gameplay Volume]: https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-gameplay-volumes-quick-start
[Movie Render Pipeline]: https://dev.epicgames.com/documentation/en-us/unreal-engine/movie-render-pipeline-in-unreal-engine
[CommonUI Plugin]: https://dev.epicgames.com/documentation/en-us/unreal-engine/common-ui-plugin-for-advanced-user-interfaces-in-unreal-engine
[Enhanced Input]: https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine
[Raw Input Documentation]: https://dev.epicgames.com/documentation/en-us/unreal-engine/rawinput-plugin?application_version=4.27
[Replication Graph]: https://dev.epicgames.com/documentation/en-us/unreal-engine/replication-graph-in-unreal-engine
[Replication Graph Live Stream]: https://www.unrealengine.com/en-US/tech-blog/replication-graph-overview-and-proper-replication-methods
[SteamSockets Documentation]: https://dev.epicgames.com/documentation/en-us/unreal-engine/steam-sockets-in-unreal-engine
[SteamSockets Tutorial]: https://dev.epicgames.com/community/learning/tutorials/8Jm6/unreal-engine-setup-steam-sockets-for-oss-steam
[PlayFab OSS]: https://learn.microsoft.com/en-us/gaming/playfab/multiplayer/networking/party-unreal-engine-oss-quickstart
[PlayFabMultiplayerUnreal]: https://github.com/PlayFab/PlayFabMultiplayerUnreal
[Online Subsystem Steam]: https://dev.epicgames.com/documentation/en-us/unreal-engine/online-subsystem-steam-interface-in-unreal-engine
[UE Online Subsystem Steam Tutorial]: https://tech.dentsusoken.com/entry/onlinemultiplay-cpp
[EOS OSS Documentation]: https://dev.epicgames.com/documentation/en-us/unreal-engine/online-subsystem-eos-plugin-in-unreal-engine
[EOS OSS Tutorial]: https://dev.epicgames.com/community/learning/courses/1px/unreal-engine-the-eos-online-subsystem-oss-plugin/Lnjn/unreal-engine-introduction
[Online Service EOS]: https://dev.epicgames.com/documentation/en-us/unreal-engine/online-services-eos-plugins-in-unreal-engine
[Online Sevice Overview]: https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-online-services-in-unreal-engine
[Setup and Configure Online Services]: https://dev.epicgames.com/documentation/en-us/unreal-engine/setup-and-configure-the-online-services-plugins-in-unreal-engine
[Structure and Implement the Online Services Plugins]: https://dev.epicgames.com/documentation/en-us/unreal-engine/structure-and-implement-the-online-services-plugins-in-unreal-engine
[Make Interactive Experiences]: https://dev.epicgames.com/documentation/en-us/unreal-engine/making-interactive-experiences-and-gameplay-in-unreal-engine
[Smart Objects]: https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine
[State Tree]: https://dev.epicgames.com/documentation/en-us/unreal-engine/state-tree-in-unreal-engine
[GAS]: https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-ability-system-for-unreal-engine
[GAS Community Docs]: https://github.com/tranek/GASDocumentation
[ControlFlows Tutorial]: https://unrealengine.hatenablog.com/entry/2023/01/29/211937
[Funciontal Testing]: https://dev.epicgames.com/documentation/en-us/unreal-engine/functional-testing-in-unreal-engine
[Automation System Overview]: https://dev.epicgames.com/documentation/en-us/unreal-engine/automation-system-overview?application_version=4.27
[Gauntlet]: https://dev.epicgames.com/documentation/en-us/unreal-engine/gauntlet-automation-framework-in-unreal-engine
[Run Gauntlet Tests]: https://dev.epicgames.com/documentation/en-us/unreal-engine/running-gauntlet-tests-in-unreal-engine
[Gauntlet Primer]: https://dev.epicgames.com/community/learning/knowledge-base/9yod/unreal-engine-gauntlet-primer
[Significance Manager]: https://dev.epicgames.com/documentation/en-us/unreal-engine/significance-manager-in-unreal-engine
[Niagara]: https://dev.epicgames.com/documentation/en-us/unreal-engine/creating-visual-effects-in-niagara-for-unreal-engine
[Water]: https://dev.epicgames.com/documentation/en-us/unreal-engine/water-system-in-unreal-engine