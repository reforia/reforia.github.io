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

> I am not an expert in audio, so this post will be more of a summary of what I have learned from the Lyra project for my understanding. It could very likely be wrong at some aspects. Please take it with a grain of salt.
{: .prompt-warning }

## Audio structure in Unreal 5
Unlike what we used to see in UE4, which only have some basic built in features like sound cues, sound classes, and sound mix, without any proper DSP graph. Pretty much the heavy lifting is done by sending events to another audio engine, like `Wwise`, `FMOD`, etc. In UE5, the new audio engine is built-in, and it has a proper DSP graph which is called `MetaSound`. The audio system is more flexible and powerful, allowing for complex audio processing and manipulation.

The overall flow of the audio signal can be illustrated as follows:
- Sound Source Generates the dry signal
  - Sound Wave, Sound Cue, MetaSound, they produce the raw audio signal
- Mixing system mixes the dry signal to wet signal
  - Sound Class, Sound Mix, MetaSound Patch, Generators have done the first stage of processing, usually we categorize sound assets into different classes, and then the class will be mapped to a `Submix` class.
  - Submix, Control Bus, Control Bus Mix, Parameter Patch, Submix Effect Chains, etc, they are there to determine how the audio signal are being processed and mixed together
- Output to the output device
  - Eventually, the `Main Submix` will output the final audio signal to the output device, such as speakers or headphones.

## Sound Source
The first part is Sound Source, they are where the raw signal comes from. we have three types of sound sources in Lyra:
- `SoundWave`: The most basic sound source, it is a raw audio file, stored in 16-bit `WAV` format. It can be played back directly, but it doesn't have any processing or manipulation applied to it.
- `SoundCue`: A more advanced sound source, it is a container for multiple `SoundWave` assets. It allows for more complex audio processing and manipulation, such as randomization, looping, and fading.
- `MetaSound Source`: The most advanced sound source, it is a fully programmable audio engine that allows for complex audio processing and manipulation. It can be used to create custom audio effects, such as reverb, delay, and distortion.

But here's a bit more about it.

### MetaSounds Patch
A `MetaSound Source` can contain a lot of nodes, much alike a `Material` graph, and as a full functional DSP engine, a numerous amount of logic can be applied to the audio signal. So it's not a crazy idea to have some logic predefined as "Libraries" and when we need to use them, we can just jam them into the graph. This is where `MetaSound Patch` comes in, it is a collection of nodes that can be reused in different `MetaSound Source`. It is similar to a function library, but for audio processing.

Existing `MetaSound Patch` in Lyra:
- lib_StereoBalance
  - It has a `StereoPanner` node that will pan the audio signal to the left or right channel.
- lib_DovetailClip
  - Seems like it's trying to give the input audio a random pitch and then try to mix the new one with the already playing results together, with a Stereo Balance node in the end.
- lib_DovetailClipFromArray
  - Similarly, it allows to select wave from an array, and then apply the `DovetailClip` effect to it.
- lib_RandInterpTo
  - Gradually interpolate 
- lib_RandPanStereo
- lib_TriggerAfter
- lib_TriggerEvery
- lib_TriggerModulo
- lib_TriggerStopAfter
- lib_Whizby
- MS_Graph_RandomPitch_Stereo
- MS_Graph_TriggerDelayPitchShift_Mono
- mx_PlayAmbientChord
- mx_PlayAmbientElement
- mx_Stingers
- sfx_BaseLayer_Interactable_Pad_nl_meta

## Mixing

### Sound Class

### Sound Mix

### HDR and LDR
The next thing that worth noting is HDR and LDR, in a nutshell, players might have different audio output devices, some are fancy high-end devices, some are just cheap ones, it will differ from headphone and TV as well, they might even also have different preference or want to enable night mode. Anyway, we need to have different audio settings for different devices. The `AudioSettings` class has two properties for this purpose, `HDRAudioSubmixEffectChain` and `LDRAudioSubmixEffectChain`, which are both arrays of `FLyraSubmixEffectChainMap`. And we need to have a mechanic to switch them based on a setting that the player can config in a settings UI. If we don't do this, the audio might sound flat and dull on some devices, and too loud or quite on other ones.

To accommodate this feature, the logic behind is:
- Having a mechanic for the user to config whether we should output `HDR` or `LDR` audio
- For all the sound output, we will apply a series of "Post-Process" (`SubmixEffectChain`) effect to achieve this.

The first part should be related to a UI, once UI reports the user has confirmed a preferred mode, we will have a way to operate all the sound outputs, this is where we need to utilize `Submix`

### Submix
`Submix` is a signal operation concept, imagine we have weapon, footstep, ambience and musics raw files, they are usually just `wav` files as raw files, then being wrapped up either in `SoundCue` or `metasound` class and do some processing there. (As known as per sound processing) It will also be quite helpful if we can say, OK, now I want these sounds to be grouped together, and we will add a shared effect like `EQ` to all of them, a shared treatment. This is where `Submix` comes in, each audio will be routed to a `Submix`, and the `Submix` will have a `SubmixEffectChain` applied to it. And different `Submix` can orchestrate together, eventually feed to the `MainSubmix`, and output from their, so all signals are being mixed.

It's important to note that the `Submix` only took a copy of the original signals. So like if we have a music playing, and send 100% of it to a `Mute Submix`, it will still be audible, since we are hearing a mix of the original music and a mix of "nothing", so it's still the original music.

We can send a portion of the original dry sound to submix, like 0.2 means we took 20% of the orignal wave signal amplitude, and apply a submix effect like EQ to them, and then they are mixed together when playback.

![Submix Details](submix_details.png){: .width="700"}

### Submix and Sound Class
`Sound Class` however, is more related to gameplay relationship rather than from a signal operation concept, each sound can be assigned to a `Sound Class`, and we can say: "When combat sound is playing, we will duck down musics to make combat SFX more prominent", and that's it, there aren't as many flexibility as `Submix`, but rather just volumes, often `Submix` and `Sound Class` are used together, which is also the case in Lyra

Note that `Sound Class` can be used to ducking down groups of sounds by `Sound Mix`, which is a passive operation, and it will really just alter the original signal, meaning `Sound Mix` would have higher priority than `Submix`, if we already ducked a sound down to -60db via `Sound Mix`, and we send 100% of it to a `Submix`, the `Submix` essentially just receives a flat, non audible signals.

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

### Dynamic Submix Effects
But here's a problem: A `Submix` can have it's own `SubmixEffectChain` configured in that `Submix` asset directly, so what's the whole point of wrapping it around again?

![EarlyReflection](submix_effect_chain_in_submix.png){: width="800" }

The answer is, in this case, the struct is really just used for `HDRAudioSubmixEffectChain` and `LDRAudioSubmixEffectChain`, so despite the struct seems to be for generic purpose per se, it really is just used to apply extra `SubmixEffectChain` to the `MainSubmix` class, the other `Submix` should just apply their own `SubmixEffectChain` in the `Submix` asset directly.

![HDR and LDR submix](hdr_ldr_submix.png){: width="800" }

As can be seen above, only the `MainSubmix` is being further processed, and the reason why we are doing this is also obvious, whether we apply HDR or LDR is defined at runtime, and normal `SubmixEffectChain` configured in `Submix` class is static.

### HDR Effect
HDR effect is a compressor type, it has a -10db input gain to shift the signal down to provide more headroom, and a -6db threshold to kick in the compressor. So that more dynamic range can be preserved. The logic behind this is, we try to keep as much sound as possible, and only smoothly compress the sounds that are too loud. It tries to keep the emotion and vividness of the experience, even though sounds might be hard to distinguish sometimes. Usually for a cinematic setup experience.

![HDR Effect](hdr_effect.png){: width="800" }

After the sound was shift down by 10db as input gain, it checks the peak sound using average mode(get the average of left and right channel input). bypassing -6db, we will apply a 6:1 ratio, meaning the output source will increase 1db for every 6db of input source. This might sounds weird if it cuts off the sound too drastically, so that's where the knee and lookahead comes, look ahead allows us to delay the sound a bit so we can monitor the "Future" signal and act ahead of time. Knee is basically saying, although we are using -6db as threshold, but within the +-knee value range, our compressor can gradually kick in, make the transition smoother.

Just like normal envelop effect, we also have attack and release time for compressor. It also has a sidechain input, which is saying, when the sidechain input is playing above the threshold, we will give a gain or cutoff to the current output signal, just like a ducking effect.

### LDR Effect
Very similar to HDR, except this time it's a limiter type, which means we are trying to limit the sound by cutting off the sound if it exceeds threshold. The logic behind this is, we want to make sure that the sound doesn't exceed a certain level at all cost, so that it won't clip or distort. The intention is to keep the sound as clean and consistent as possible, even though it might sound a bit flat sometimes. Usually for a TV or speaker setup experience.

![LDR Effect](ldr_effect.png){: width="800" }

### Available Submix
![Sound Submix Structure](submix_structure.png){: width="800" }

Above is the Submix Structure in Lyra, a bunch of `Submix`es eventually being routed to `MainSubmix`
- UISubmix
- SFXSubmix
- MusicSubmix
- SendEffectSubmix
- ReverbSubmix
- VoiceSubmix
- EarlyReflectionSubmix


### Sound Attenuation
Attenuation Settings
Attenuation referencing ITD specialization settings

Sound Wave or Meta Sound Source referencing Sound Attenuation settings

#### Attenuation Presets

#### ITD Source Spatialization Settings

### Concurrency
Sound Concurrency don't have any referencers other than the sound per se

### Effects

### Convolution Reverb
Convolution Reverb is using a IR asset, which is created from a wav file, it essentially captured the spatial representation, include material, early reflection, energy air absorption, etc through analysis of the recorded pop sound wave. To guide the input sound source how to behave as if it was in that space.

#### Audio Impulse Response

### Dynamics Process

### Effect Filter

### Effect Tap Delay

### Multiband Compressor

### Impulses

### Modulation

#### Control Bus

#### Control Bus Mix

#### Parameter Patch

## AudioSettings
Inspecting the `AudioSettings` class, we can see that it only has a meaningful header file, while the `cpp` file is empty. The file itself is quite simple and we've covered most of the tricks in previous posts. Just a refresher:

- We need to have our settings class inherit from `UDeveloperSettings` to be auto discovered by the engine.
- Class Meta Specifier `config = Game, default config, meta = (DisplayName = "LyraAudioSettings")`
  - The content in this class will be saved in a config file, type is default game (`DefaultGame.ini`), and the section is `LyraAudioSettings`
- Property Meta Specifier `config, EditAnywhere, Category = MixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBusMix")`
  - The property will be saved in the config file mentioned above.
  - The property is editable on archetype, or instances
  - The property will be categorized to `MixSetting`
  - The property only accept class is `SoundControlBusMix` from the `AudioModulation` plugin.

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

## Available Settings
- DefaultControlBusMix

- LoadingScreenControlBusMix

- UserSettingsControlBusMix

- OverallVolumeControlBus

- MusicVolumeControlBus

- SoundFXVolumeControlBus

- DialogueVolumeControlBus

- VoiceChatVolumeControlBus

## Applications
### Music Manager Component
https://disasterpeace.com/blog/epic-games.lyra
MusicManagerComponent Base
Add to PS as component
Manage Intensity, fire will increase it, death will set it to 1, and gradually decrease overtime.
Manager Look Direction

When fire stinger happens, set it to 0 as out of combat
### Wind System

### Whizby System

### Emote

### Utilities

## Takeaways
Decoupling the settings, with default and user saved data to a config file, a UI to let the player do the changes, and loaded back by WorldSubsystem for other systems
