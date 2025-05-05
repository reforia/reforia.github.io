---
layout: post
title: Network Ability Framework in Unreal Engine 4
description: 
  An Ability Framework in Unreal Engine 4 that fully supports Networks. The framework is intended for Designers to expand with and create new abilities without worrying about network and basic setups. The system should work on LAN and/or other Online Subsystems (Steam etc.)
date: 2020-08-20 12:00 +0800
categories: [Unreal, Network]
tags: [Unreal, Network]
media_subpath: /assets/img/post-data/unreal/network/nas/
lang: en
---

> At the time of writing, unreal GAS already existed but in an early stage. This project was inspired by GAS, but didn't use GAS
{: .prompt-warning }

> In 2024, GAS can fully replace this project, but it's still a good reference for the thinking process
{: .prompt-info }

## Final Result
### COOP Demo
{% include embed/youtube.html id="mnNPKg-N_bQ" %}

### PVP Demo
{% include embed/youtube.html id="4ZOjvLOf-7E" %}

## Download Link
[GitHub - Network Ability Framework]

## Description
An Ability Framework in Unreal Engine 4 that fully supports Networks. The framework is intended for Designers to expand with and create new abilities without worrying about network and basic setups. The system should work on LAN and/or other Online Subsystems (Steam etc.)

## Role & Responsibility
- Technical Designer/System Designer/Programmer
Design, create and implement Ability   
- System Framework for various game genres to use
- Design architecture of logic flow and all classes as well as communication standards.
Optimize Network performance
- Provide easy configs for Designers

## Ability Example Snippet (For Designers)
{% include bpviewer.html id="x-d1d4rr" %}

![Example](nas_1.webp)
_Example_ 

## Ability Set
![Ability Set](nas_2.webp)
_Ability Set_

## Modifier Example
{% include bpviewer.html id="4f-fp9z1" %}

![Modifier Example](nas_3.webp)
_Modifier Example_

## Logic Flow
![Logic Flow](nas_4.webp)
_Logic Flow_

Following along the red line, Actor A activates an ability, after checked by server, the ability called `ApplyModifierTo(AActor Target, AModifier NewModifier, float Duration)` function through interface, by doing so, a modifier was applied to Actor B’s `UModifierTargetComp`, through a bunch of checks, the modifier was successfully applied, then the modifier did corresponding functions and garbage collected.

## ACustomActor : AActor
![ACustomActor](nas_5.webp)
_ACustomActor_

As shown above, `ACustomActor` is the basic object in this framework, which performs as a simple startup point for all actors in this framework. The main reason for using AActor instead of UObject is to use the network supporting feature.

## UAttributeComp : UActorComponent
![UAttributeComp](nas_6.webp)
_UAttributeComp_

As mentioned above, `UAttributeComp` has 2 member properties: `AttributeClass` and `StatusClass`, It also performs `InitializeAttributePreset()` and `InitializeStatusPreset()` after `BeginPlay()`, which passes the outer Actor to AAttributePreset and AStatusPreset. This component is replicated.

## AAttributePreset
User define any property in this class, such as Health, Mana, etc. It also contains a list of polymorphic functions:
```cpp
AddAttribute ( Template<T> TargetProperty , Template<T> DeltaValue )
MultiplyAttribute ( Template<T> TargetProperty , Template<T> Multiplier )
SetAttribute ( Template<T> TargetProperty , Template<T> NewValue )
```

These functions can be called by anything that wants to change these attributes, such as receiving damage, or responses to the `Enum_ModifyMethod` in `FCostStruct`, see below:

![ACustomActor](nas_7.webp)
_ACustomActor_

## AStatusPreset
`AStatusPreset` stores a bunch of predefined Booleans, which could be anything similar to Stun, Drunk, Fly, Sleep, Run, Heal, etc. By default, a couple check functions are created, and user can override them freely. If one of them return true. For example:

```cpp
virtual bool AStatusPreset::CheckStun() override
{
    Super::CheckStun();
    return true;
}

void AStatusPreset::OnRep_StunChanged(bool Stun)
{
    //Do Something
    return;
}
```

`OnRep_StunChanged(bool)` will be called, allow corresponding logic to be applied to the caster, for example, disable player’s input when stunned. Usually, status is being changed by an `AModifier`, the reset function should be handled in `AModifier`’s `OnPreExpire()` function.

## UModifierTargetComp : UActorComponent
![UModifierTargetComp](nas_8.webp)
_UModifierTargetComp_

`UModifierTargetComp` responds to interface message call `ApplyModifierTo(Modifier, Duration)`. It first checks if the modifier type or modifier itself, is explicitly blocked by any existing modifier. Otherwise the modifier will be added to modifier list (call `OnReapply()` if the modifier is already in the list) Then, the `BlockType` and `BlockList` from this modifier will be registered into this component, for future modifier apply check.

After modifier has been added to `ModifierList`, corresponding `LifeCycleHandler(float Duration)` will be called to control the life cycle of this modifier, user can manually start `tick()` by calling `StartIntervalThink()`.

Eventually `LifeCycleHandler(float Duration)` fires `OnPreExpire() –> OnReadyToExpire()` call chain when duration ended, given user the last chance to do any logic before the modifier is being removed, then `RemoveFromModifierList(Modifier)` will be called by `AModifierTargetComp`, the modifier will be pop out from Modifier List and GCed in next GC cycle (Or manually GCed).

## AModifier : ACustomActor
![AModifier](nas_9.webp)
_AModifier_

Once `LifeCycleHandler(float Duration)` is being called from `UModifierTargetComp`, `OnApplied()` will be fired first to do any initialization logic. By default, the modifier will not tick on its own, unless user manually calls `StartIntervalThink(float DeltaTime)` `AModifier` class has a bunch of events to respond to `UModifierTargetComp` events:

```cpp
OnApplied()
OnReapplied()
OnBlocked()
OnStackChanged(UInt8 NewStack)
LifeCycleHandler(float Duration)
```

eventually fires `OnPreExpire() -> OnReadyToExpire()` call chain.

## UAbilitySetComp : UActorComponent, AAbilitySet : ACustomActor
![UAbilitySetComp](nas_10.webp)
_UAbilitySetComp_

UAbilitySetComp and AAbilitySet are simple classes, UAbilitySetComp holds an AAbilitySet, and an InitializeAbilitySet() function to pass parent actor into AAbilitySetAAbilitySet stores a TArray<AAbility*> as well as an InitializeAbilities() function, which passes both BelongingActor and BelongingAbilitySet to each AAbility class

## AAbility : ACustomActor
![AAbility](nas_11.webp)
_AAbility_

When activating an Ability, `TryActivate()` is fired, results in a function call chain, `ActivatePrecheck()` is called first, to ensure the Ability is not in cooldown, not in use or disabled by modifiers. Then followed with `CostPrecheck()` to sync with server and see if caster has enough stats to perform this action. 

If both passed, `CommitAbility()` is called, and this is the last chance server can abort this behavior.Once committed, `ApplyCost()` is called to modify caster’s stats as ability cost, then the actual lifecycle of performing the ability is started:

- `OnActivated()` is called immediately when the ability is activated, allowing initialization logic to run here
- `OnTakeEffectNotifyActivated()` is called when ability montage reaches `TakeEffect` Notify, since an `AnimMontage` can have multiple notifies, so this ability supports combo attack
- `StartIntervalThink(float DeltaTime)` is manually called to constantly fire `OnIntervalThink()` based on DeltaTime
- `OnIntervalThink()` is constantly fired by `StartIntervalThink` every fixing amount of time
- `StartCooldown()` is manually called to start cooldown, based on whether user wants the ability to cooldown at the start of this ability or at the end. After cooldown finished, `bInCooldown` is set to false
- `EndAbility()` is manually called to finish this ability, it has to be called otherwise the ability will last forever!
- `OnAbilityPreEnd()` is called after user manually called `EndAbility()`, allowing any last logic to perform before the ability stops
- `OnAbilityReadyToEnd()` is followed by `OnAbilityPreEnd()`, which sets `bCanActivate` to true and stops `OnIntervalThink()`


[GitHub - Network Ability Framework]: https://github.com/reforia/NetworkAbilityKit