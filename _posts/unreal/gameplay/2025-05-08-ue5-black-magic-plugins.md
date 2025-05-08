---
layout: post
title: "Lyra Breakdown - Game Structure"
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

## All Plugins and Categories
Lyra has enabled a huge amount of plugins, but they can be categorized into a few groups.

### Settings:
- GameSettings

### Editor Tools:
- ActorPalette

### Asset Management:
- DataRegistry
- AsyncMixin
- AssetSearch
- AssetReferenceRestrictions

### Geometry Tool:
- ModelingToolsEditorMode
- GeometryScripting

### Render & GFX:
- Volumetrics
- Niagara
- Water
- RuntimePhysXCooking

### Animation:
- AnimationLocomotionLibrary
- AnimationWarping
- ContextualAnimation

### Audio:
- Metasound
- AudioModulation
- AudioGameplayVolume
- AudioGameplay
- SoundUtilities
- Spatialization
- ResonanceAudio

### Sequence:
- MovieRenderPipeline
- MoviePipelineMaskRenderPass

### UI:
- CommonUI
- CommonLoadingScreen
- GameSubtitles
- UIExtension

### Input:
- EnhancedInput
- WinDualShock

### Network:
- ReplicationGraph
- AESGCMHandlerComponent
- DTLSHandlerComponent
- SteamSockets

### OSS
- OnlineFramework
- PlayFabParty
- OnlineSubsystemEOS
- OnlineServicesEOS
- OnlineServicesNull
- OnlineServicesOSSAdapter
- OnlineSubsystemSteam

### Authentication:
- CommonUser

### DevOps:
- FunctionalTestingEditor
- RuntimeTests
- Gauntlet

### Performance:
- D3DExternalGPUStatistics
- SignificanceManager
- PocketWorlds

### Gameplay:
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

### Gameplay Feature:
- ShooterCore
- ShooterMaps
- TopDownArena
- ShooterExplorer
- ShooterTests

## Project Structure
These categories span across almost all the aspects a project needs to take care of. We will go through each of them in the following posts. Before that, let's first inspect the project structure and see how plugins are contributing to the projects.

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

### Animation 
- /Animation
  - AnimInstance

### Audio
- /Audio
  - AudioMixEffectsSubsystem
  - AudioSettings

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

