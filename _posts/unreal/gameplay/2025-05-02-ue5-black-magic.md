---
layout: post
title: "Lyra - Epic's Black Magic Spell Book"
description:
  This is a note about what I've learnd from the transition from UE4 to UE5. Most of the knowledge are from the Lyra Starter Game.
date: 2025-05-02 15:24 +0800
categories: [Unreal, Gameplay]
published: false
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic/
lang: en
---

{% include ue_version_disclaimer.html version="5.5.4" %}

## Localization
How does that pipeline looks like

## How common UI and fonts work

## Audio
How does all the audio files work

## Network EOS and their configs
How does all the network files as well as the configs work

## Developer Settings
Controls stuff like cheats, debug settings, etc.

## Experience Definition
Experience Definition acts like a decoupled "metadata" that described, in order to load an experience, what Game Feature Plugins to load, what Game Modes to use, what Maps to load, etc. The exotic logic can be considered as a bunch of Actions that are executed when the experience is loaded. In other word, in Epic's definition, an experience is consist of Game Features, Pawn Data, and Actions.

```cpp
/**
 * Definition of an experience
 */
UCLASS(BlueprintType, Const)
class ULyraExperienceDefinition : public UPrimaryDataAsset
{
    GENERATED_BODY()

public:
    ULyraExperienceDefinition();

    //~UObject interface
#if WITH_EDITOR
    virtual EDataValidationResult IsDataValid(class FDataValidationContext& Context) const override;
#endif
    //~End of UObject interface

    //~UPrimaryDataAsset interface
#if WITH_EDITORONLY_DATA
    virtual void UpdateAssetBundleData() override;
#endif
    //~End of UPrimaryDataAsset interface

public:
    // List of Game Feature Plugins this experience wants to have active
    UPROPERTY(EditDefaultsOnly, Category = Gameplay)
    TArray<FString> GameFeaturesToEnable;

    /** The default pawn class to spawn for players */
    //@TODO: Make soft?
    UPROPERTY(EditDefaultsOnly, Category=Gameplay)
    TObjectPtr<const ULyraPawnData> DefaultPawnData;

    // List of actions to perform as this experience is loaded/activated/deactivated/unloaded
    UPROPERTY(EditDefaultsOnly, Instanced, Category="Actions")
    TArray<TObjectPtr<UGameFeatureAction>> Actions;

    // List of additional action sets to compose into this experience
    UPROPERTY(EditDefaultsOnly, Category=Gameplay)
    TArray<TObjectPtr<ULyraExperienceActionSet>> ActionSets;
};
```

To reuse some common actions as well as cominition of game features to load, they were also being wrapped into an `ULyraExperienceActionSet` class

```cpp
/**
 * Definition of a set of actions to perform as part of entering an experience
 */
UCLASS(BlueprintType, NotBlueprintable)
class ULyraExperienceActionSet : public UPrimaryDataAsset
{
    GENERATED_BODY()

public:
    ULyraExperienceActionSet();

    //~UObject interface
#if WITH_EDITOR
    virtual EDataValidationResult IsDataValid(class FDataValidationContext& Context) const override;
#endif
    //~End of UObject interface

    //~UPrimaryDataAsset interface
#if WITH_EDITORONLY_DATA
    virtual void UpdateAssetBundleData() override;
#endif
    //~End of UPrimaryDataAsset interface

public:
    // List of actions to perform as this experience is loaded/activated/deactivated/unloaded
    UPROPERTY(EditAnywhere, Instanced, Category="Actions to Perform")
    TArray<TObjectPtr<UGameFeatureAction>> Actions;

    // List of Game Feature Plugins this experience wants to have active
    UPROPERTY(EditAnywhere, Category="Feature Dependencies")
    TArray<FString> GameFeaturesToEnable;
};
```

## Pawn Data
Epic consider a pawn to be defined by a `PrimaryDataAsset` pretty much the same with Experience, we can see that a pawn is consisted of
- PawnClass
- AbilitySets
- TagRelationshipMapping
- InputConfig
- DefaultCameraMode

They effectively decoupled input, controller, camera, the capabilities a pawn could perform, by leveraging GAS heavily, and used TagRelationshipMapping to resolve the interactions between different possible actions (Abilities)

```cpp
/**
 * ULyraPawnData
 *
 *    Non-mutable data asset that contains properties used to define a pawn.
 */
UCLASS(BlueprintType, Const, Meta = (DisplayName = "Lyra Pawn Data", ShortTooltip = "Data asset used to define a Pawn."))
class LyraGAME_API ULyraPawnData : public UPrimaryDataAsset
{
    GENERATED_BODY()

public:

    ULyraPawnData(const FObjectInitializer& ObjectInitializer);

public:

    // Class to instantiate for this pawn (should usually derive from ALyraPawn or ALyraCharacter).
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lyra|Pawn")
    TSubclassOf<APawn> PawnClass;

    // Ability sets to grant to this pawn's ability system.
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lyra|Abilities")
    TArray<TObjectPtr<ULyraAbilitySet>> AbilitySets;

    // What mapping of ability tags to use for actions taking by this pawn
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lyra|Abilities")
    TObjectPtr<ULyraAbilityTagRelationshipMapping> TagRelationshipMapping;

    // Input configuration used by player controlled pawns to create input mappings and bind input actions.
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lyra|Input")
    TObjectPtr<ULyraInputConfig> InputConfig;

    // Default camera mode used by player controlled pawns.
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lyra|Camera")
    TSubclassOf<ULyraCameraMode> DefaultCameraMode;
};
```

## Ability Set
The `ULyraAbilitySet` basically described when this set is being granted to the pawn, what ability does the pawn have (In other word, what can the pawn do?) What effect and what attribute the pawn would have.
```cpp
/**
 * ULyraAbilitySet
 *
 *    Non-mutable data asset used to grant gameplay abilities and gameplay effects.
 */
UCLASS(BlueprintType, Const)
class ULyraAbilitySet : public UPrimaryDataAsset
{
    GENERATED_BODY()

public:

    ULyraAbilitySet(const FObjectInitializer& ObjectInitializer = FObjectInitializer::Get());

    // Grants the ability set to the specified ability system component.
    // The returned handles can be used later to take away anything that was granted.
    void GiveToAbilitySystem(ULyraAbilitySystemComponent* LyraASC, FLyraAbilitySet_GrantedHandles* OutGrantedHandles, UObject* SourceObject = nullptr) const;

protected:

    // Gameplay abilities to grant when this ability set is granted.
    UPROPERTY(EditDefaultsOnly, Category = "Gameplay Abilities", meta=(TitleProperty=Ability))
    TArray<FLyraAbilitySet_GameplayAbility> GrantedGameplayAbilities;

    // Gameplay effects to grant when this ability set is granted.
    UPROPERTY(EditDefaultsOnly, Category = "Gameplay Effects", meta=(TitleProperty=GameplayEffect))
    TArray<FLyraAbilitySet_GameplayEffect> GrantedGameplayEffects;

    // Attribute sets to grant when this ability set is granted.
    UPROPERTY(EditDefaultsOnly, Category = "Attribute Sets", meta=(TitleProperty=AttributeSet))
    TArray<FLyraAbilitySet_AttributeSet> GrantedAttributes;
};
```
### Ability Set GameplayAbility
As can be seen above, the granted data aren't just an array of GameplayAbilities, but instead a custom struct `FLyraAbilitySet_GameplayAbility`, which contains the ability class, the level of the ability, and an input tag.

This means we can couple input tag to an ability, so the binding between input and ability is done at the data level and can be handled under a universal architecture
```cpp
/**
 * FLyraAbilitySet_GameplayAbility
 *
 *    Data used by the ability set to grant gameplay abilities.
 */
USTRUCT(BlueprintType)
struct FLyraAbilitySet_GameplayAbility
{
    GENERATED_BODY()

public:

    // Gameplay ability to grant.
    UPROPERTY(EditDefaultsOnly)
    TSubclassOf<ULyraGameplayAbility> Ability = nullptr;

    // Level of ability to grant.
    UPROPERTY(EditDefaultsOnly)
    int32 AbilityLevel = 1;

    // Tag used to process input for the ability.
    UPROPERTY(EditDefaultsOnly, Meta = (Categories = "InputTag"))
    FGameplayTag InputTag;
};
```
### Ability Set GameplayEffect
Similarly, the granted gameplay effects are also stored in a custom struct `FLyraAbilitySet_GameplayEffect`, which contains the gameplay effect class and the level of the effect.
```cpp
/**
 * FLyraAbilitySet_GameplayEffect
 *
 *    Data used by the ability set to grant gameplay effects.
 */
USTRUCT(BlueprintType)
struct FLyraAbilitySet_GameplayEffect
{
    GENERATED_BODY()

public:

    // Gameplay effect to grant.
    UPROPERTY(EditDefaultsOnly)
    TSubclassOf<UGameplayEffect> GameplayEffect = nullptr;

    // Level of gameplay effect to grant.
    UPROPERTY(EditDefaultsOnly)
    float EffectLevel = 1.0f;
};
```

### Ability Set Attribute Set
So far this is just a wrapper of Attribute Set, but wrapping it up like GA and GE allows us to further extend it in the future
```cpp
/**
 * FLyraAbilitySet_AttributeSet
 *
 *    Data used by the ability set to grant attribute sets.
 */
USTRUCT(BlueprintType)
struct FLyraAbilitySet_AttributeSet
{
    GENERATED_BODY()

public:
    // Gameplay effect to grant.
    UPROPERTY(EditDefaultsOnly)
    TSubclassOf<UAttributeSet> AttributeSet;

};
```

### Ability Set Granted Handles
This stores the actual underlying GAS data of GA, GE and Attribute Sets, after these data has been granted to the target Pawn ASC from our wrapped data structs
```cpp
/**
 * FLyraAbilitySet_GrantedHandles
 *
 *    Data used to store handles to what has been granted by the ability set.
 */
USTRUCT(BlueprintType)
struct FLyraAbilitySet_GrantedHandles
{
    GENERATED_BODY()

public:

    void AddAbilitySpecHandle(const FGameplayAbilitySpecHandle& Handle);
    void AddGameplayEffectHandle(const FActiveGameplayEffectHandle& Handle);
    void AddAttributeSet(UAttributeSet* Set);

    void TakeFromAbilitySystem(ULyraAbilitySystemComponent* LyraASC);

protected:

    // Handles to the granted abilities.
    UPROPERTY()
    TArray<FGameplayAbilitySpecHandle> AbilitySpecHandles;

    // Handles to the granted gameplay effects.
    UPROPERTY()
    TArray<FActiveGameplayEffectHandle> GameplayEffectHandles;

    // Pointers to the granted attribute sets
    UPROPERTY()
    TArray<TObjectPtr<UAttributeSet>> GrantedAttributeSets;
};
```