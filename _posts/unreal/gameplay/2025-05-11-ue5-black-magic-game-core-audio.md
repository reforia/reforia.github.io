---
layout: post
title: "Lyra Breakdown - Game Core Audio"
description:
  Digital sound is a signal, and it's all about signal processing.
date: 2025-05-11 20:50 +0800
categories: [Unreal, Gameplay]
published: false
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-game-core-audio/
lang: en
---

{% include ue_version_disclaimer.html version="5.5.4" %}

{% include ue_engine_post_disclaimer.html %}

> This is a series of notes about what I've learned from Epic's Lyra project. Which claim to be the best practices under current unreal engine framework. Some I don't know about, some I already know but I thought it would still be good noting down.
{: .prompt-info }

## Preface
As mentioned in the last post [Plugin Structure], Lyra's source can be categorized into 4 different parts depending on their relationship to the game core, ordered from game agnostic to game specific.
- Full Core
  - The core objects of the project, most of them are game agnostic.
- Core Extensions (Strong Relationship)
  - Still core of the game, slightly more game specific comparing with the full core.
- Core Extensions (Weak Relationship)
  - Mostly game specific, but still share some core functionality. Most of the game contents are in this category.
- Full Extensions
  - Game specific, The project will still build just fine if all of them are removed. Most of the cosmetics are in this category.

> I want to reiterate that this category is only talking about the source code, not the project content perspective, from a project's perspective, nothing is project agnostic, all of these codes are more or less being used by specific classes or features.
{: .prompt-warning }

In the following posts, we will focus on the full core part first (as can be seen above), and examine them with project contents, without further ado, let's dive into the details of Audios:

```markdown
- /Audio
  - AudioMixEffectsSubsystem
  - AudioSettings
- /Animation
  - AnimInstance
- /Character
  - Pawn
  - PawnData
  - Character
  - CharacterWithAbilities
  - CharacterMovementComponent
  - HealthComponent
  - HeroComponent
  - PawnExtensionComponent
- /Input
  - InputComponent
  - InputConfig
- /Physics
  - CollisionChannels
  - PhysicalMaterialWithTags
- /Player
  - CheatManager
  - DebugCameraController
  - LocalPlayer
  - PlayerBotController
  - PlayerController
  - PlayerSpawningManagerComponent
  - PlayerStart
  - PlayerState
```

## Audio
Audio section only contains two classes in source, `AudioMixEffectsSubsystem` and `AudioSettings`. The `AudioSettings` class is used to store the audio settings for the game, such as volume levels and audio mix settings. Then the `AudioMixEffectsSubsystem` will load them into memory, to automatically apply related settings like submix buses.

## AudioSettings
Inspecting the class, we find out that it only has a meaning header file, while the `cpp` file is empty. The file itself is quite simple and we've covered most of the tricks in previous posts. Just a refresher:

- We need to have our settings class inherit from `UDeveloperSettings` to be auto discovered by the engine.
- Class Meta Specifier `config = Game, defualt config, meta = (DisplayName = "LyraAudioSettings")`
  - The content in this class will be saved in a config file, type is default game (`DefaultGame.ini`), and the section is `LyraAudioSettings`
- Property Meta Specifier `config, EditAnywhere, Category = MixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBusMix")`
  - The property will be saved in the config file mentioned above.
  - The property is editable on archetype, or instances
  - The property will be categorized to `MixSetting`
  - The property only acceept class is `SoundControlBusMix` from the `AudioModulation` plugin.

![Audio Settings](audio_settings.png){: width="700" }

```cpp
// ...
USTRUCT()
struct LYRAGAME_API FLyraSubmixEffectChainMap
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, meta = (AllowedClasses = "/Script/Engine.SoundSubmix"))
	TSoftObjectPtr<USoundSubmix> Submix = nullptr;

	UPROPERTY(EditAnywhere, meta = (AllowedClasses = "/Script/Engine.SoundEffectSubmixPreset"))
	TArray<TSoftObjectPtr<USoundEffectSubmixPreset>> SubmixEffectChain;

};

UCLASS(config = Game, defaultconfig, meta = (DisplayName = "LyraAudioSettings"))
class LYRAGAME_API ULyraAudioSettings : public UDeveloperSettings
{
	GENERATED_BODY()

public:

	/** The Default Base Control Bus Mix */
	UPROPERTY(config, EditAnywhere, Category = MixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBusMix"))
	FSoftObjectPath DefaultControlBusMix;

	/** The Loading Screen Control Bus Mix - Called during loading screens to cover background audio events */
	UPROPERTY(config, EditAnywhere, Category = MixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBusMix"))
	FSoftObjectPath LoadingScreenControlBusMix;

	/** The Default Base Control Bus Mix */
	UPROPERTY(config, EditAnywhere, Category = UserMixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBusMix"))
	FSoftObjectPath UserSettingsControlBusMix;

	/** Control Bus assigned to the Overall sound volume setting */
	UPROPERTY(config, EditAnywhere, Category = UserMixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBus"))
	FSoftObjectPath OverallVolumeControlBus;

	/** Control Bus assigned to the Music sound volume setting */
	UPROPERTY(config, EditAnywhere, Category = UserMixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBus"))
	FSoftObjectPath MusicVolumeControlBus;

	/** Control Bus assigned to the SoundFX sound volume setting */
	UPROPERTY(config, EditAnywhere, Category = UserMixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBus"))
	FSoftObjectPath SoundFXVolumeControlBus;

	/** Control Bus assigned to the Dialogue sound volume setting */
	UPROPERTY(config, EditAnywhere, Category = UserMixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBus"))
	FSoftObjectPath DialogueVolumeControlBus;

	/** Control Bus assigned to the VoiceChat sound volume setting */
	UPROPERTY(config, EditAnywhere, Category = UserMixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBus"))
	FSoftObjectPath VoiceChatVolumeControlBus;

	/** Submix Processing Chains to achieve high dynamic range audio output */
	UPROPERTY(config, EditAnywhere, Category = EffectSettings)
	TArray<FLyraSubmixEffectChainMap> HDRAudioSubmixEffectChain;
	
	/** Submix Processing Chains to achieve low dynamic range audio output */
	UPROPERTY(config, EditAnywhere, Category = EffectSettings)
	TArray<FLyraSubmixEffectChainMap> LDRAudioSubmixEffectChain;
    // ...
};
```

## HDR and LDR
The first thing that worth noting is HDR and LDR, in a nutshell, players might have different audio output devices, some are fancy high-end devices, some are just cheap ones, it will differ from headphone and TV as well, they might even also have different preference or want to enable night mode. Anyway, we need to have different audio settings for different devices. The `AudioSettings` class has two properties for this purpose, `HDRAudioSubmixEffectChain` and `LDRAudioSubmixEffectChain`, which are both arrays of `FLyraSubmixEffectChainMap`. And we need to have a mechanic to switch them based on a setting that the player can config in a settings UI. If we don't do this, the audio might sound flat and dull on some devices, and too loud or quite on other ones.

To accomodate this feature, the logic behind is:
- Having a mechanic for the user to config whether we should output `HDR` or `LDR` audio
- For all the sound output, we will apply a series of "Post-Process" (`SubmixEffectChain`) effect to achieve this.

The first part should be related to a UI, once UI reports the user has confirmed a preferred mode, we will have a way to operate all the sound outputs, this is where we need to utilize `Submix`

### Submix
`Submix` is a signal operation concept, imagine we have weapon, footstep, ambience and musics raw files, they are usually just `wav` files, while we can wrap them up in a `metasound` class and do some processing there. (As known as per sound processing) It will also be quite helpful if we can say, OK, now I want these sounds to be grouped together, and we will add a shared effect like `EQ` to all of them, I don't care what "gameplay relationship" do they have. I just want all of them to have a shared treatment. This is where `Submix` comes in, each audio will be routed to a `Submix`, and the `Submix` will have a `SubmixEffectChain` applied to it. And different `Submix` can orchestrate together, eventually feed to the `MainSubmix`, and output from their, so all signals are being mixed.

It's important to note that unless we changed the original sound's output channel, otherwise the `Submix` it sends to really just took a copy of the original signals. So like if we have a music playing, and send 100% of it to a `Mute Submix`, it will still be audible, since we are hearing a mix of the original music and a mix of "nothing", so it's still the original music.

We can send a portion of the original dry sound to submix, like 0.2 means we took 20% of the orignal wave signal amplitude, and apply a submix effect like EQ to them, and then they are mixed together when playback.

![Submix Details](submix_details.png){: .width="700"}

### Submix and Sound Class
`Sound Class` however, is more related to gameplay relationship rather than from a signal operation concept, each sound can be assigned to a `Sound Class`, and we can say: "When combat sound is playing, we will duck down musics to make combat SFX more prominent", and that's it, there aren't as many flexibility as `Submix`, but rather just volumes, often `Submix` and `Sound Class` are used together, which is also the case in Lyra

### FLyraSubmixEffectChainMap
This struct binds a `Submix` class to a `USoundEffectSubmixPreset`, so that we can easily define which `Submix` would have what kind of `SubmixPresets`, the reason it's called `SubmixEffectChain` is because it's an array, meaning we can have multiple `SubmixPresets` applied for a single `Submix`.

```cpp
USTRUCT()
struct LYRAGAME_API FLyraSubmixEffectChainMap
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, meta = (AllowedClasses = "/Script/Engine.SoundSubmix"))
	TSoftObjectPtr<USoundSubmix> Submix = nullptr;

	UPROPERTY(EditAnywhere, meta = (AllowedClasses = "/Script/Engine.SoundEffectSubmixPreset"))
	TArray<TSoftObjectPtr<USoundEffectSubmixPreset>> SubmixEffectChain;

};
```

But here's a problem: A `Submix` can have it's own `SubmixEffectChain` configured in that `Submix` asset directly, so what's the whole point of wrapping it around again?

![EarlyReflection](submix_effect_chain_in_submix.png){: width="800" }

The answer is, in this case, the struct is really just used for `HDRAudioSubmixEffectChain` and `LDRAudioSubmixEffectChain`, so despite the struct seems to be for generic purpose per se, it really is just used to apply extra `SubmixEffectChain` to the `MainSubmix` class, the other `Submix` should just apply their own `SubmixEffectChain` in the `Submix` asset directly.

![HDR and LDR submix](hdr_ldr_submix.png){: width="800" }

As can be seen above, only the `MainSubmix` is being further processed, and the reason why we are doing this is also obvious, whether we apply HDR or LDR is defined at runtime, and normal `SubmixEffectChain` configured in `Submix` class is static.

![Sound Submix Structure](submix_structure.png){: width="800" }

Above is the Submix Structure in Lyra, a bunch of `Submix`es eventually being routed to `MainSubmix`

## Available Submix
### UISubmix

### SFXSubmix

### MusicSubmix

### SendEffectSubmix

### ReverbSubmix

### VoiceSubmix

### EarlyReflectionSubmix

## Available Settings
### DefaultControlBusMix

### LoadingScreenControlBusMix

### UserSettingsControlBusMix

### OverallVolumeControlBus

### MusicVolumeControlBus

#### SoundFXVolumeControlBus

#### DialogueVolumeControlBus

#### VoiceChatVolumeControlBus

#### HDRAudioSubmixEffectChain

#### LDRAudioSubmixEffectChain

## Attenuation Presets

### Sound Attenuation

### ITD Source Spatialization Settings

## Classes

## Concurrency

## Effects

### Convolution Reverb

### Dynamics Process

### Effect Filter

### Effect Tap Delay

### Multiband Compressor

## Impulses

### Audio Impulse Response

## MetaSounds

### MetaSounds Patch

### MetaSounds Source

## Modulation

### Control Bus

### Control Bus Mix

### Parameter Patch

## Sounds

## SoundWaves

## Music Manager Component
https://disasterpeace.com/blog/epic-games.lyra

## Wind System

## Whizby System

## Emote

## Utilities

## Takeaways
Decoupling the settings, with default and user saved data to a config file, a UI to let the player do the changes, and loaded back by WorldSubsystem for other systems

[Plugin Structure]: https://jaydengames.com/posts/ue5-black-magic-plugins-strcture/
{: .prompt-info }

Attenuation Settings
Attenuation referencing ITD specialization settings

Sound Wave or Meta Sound Source referencing Sound Attenuation settings

MusicManagerComponent Base
Add to PS as component
Manage Intensity, fire will increase it, death will set it to 1, and gradually decrease overtime.
Manager Look Direction

When fire stinger happens, set it to 0 as out ot combat

