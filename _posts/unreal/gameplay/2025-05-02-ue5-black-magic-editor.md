---
layout: post
title: "Unreal Black Magic Spell Book - Lyra Editor"
description:
  This is a series of notes about what I've learnd from Epic's Lyra project. Which claim to be the best practices under current unreal engine framework. Some I don't know about, some I already know but I thought it would still be good noting down.
date: 2025-05-02 15:24 +0800
categories: [Unreal, Gameplay]
published: false
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor/
---

{% include ue_version_disclaimer.html version="5.5.4" %}

## Seperated .uproject and Modules
Maybe Epic has a somewhat automated project setup method or manually renamed the `uproject` afterwards, but comparing with the pre-build Binary version of Lyra in EGS vs Github, the project name is different. One called `LyraStarterGame` and the other just called `Lyra`
![From EGS](lyra-egs.png){: width="500"}
_Lyra from EGS_

![From Github](lyra-git.png){: width="500"}
_Lyra from Github_

While this is not a big deal, if we then look at the `Source` folder, we would see that neither `Lyra` nor `LyraStarterGame` are the modules' name (Which it would be if we just create the project from setup wizard). Instead, they are `LyraGame` and `LyraEditor`. Again, not a big deal, but it also shows us that the `uproject` or the folder name is about the project itself. And in `Source` code, we can have a more granular control over the module name. They don't have to be the same.

## Custom Engine class
Lyra has 2 custom engine extensions, `LyraGameEngine` and `LyraEditorEngine`. In this post we will just focus on the `LyraEditorEngine`

### UGameEngine, UEditorEngine, UUnrealEdEngine
`UUnrealEdEngine` inherit from `UEditorEngine`, that governs the actual specialized interactions inside the Unreal Editor, like how select an actor would behave, jamming more custom code before a PIE session starts, etc. Normally we want to inherit our own editor engine under `UUnrealEdEngine`, because `UEditorEngine` is a higher level abstraction of the foundamental editor engine framework, and `UUnrealEdEngine` already inherits from it. otherwise we could end up with recreating the wheel.

The purpose behind this extension is simple:
- In Lyra, the actual gameplay related module (or `plugins`) are all under 'Plugins/GameFeature' folder, utilizing the `GameFeature` system. It would be a QoL improvement to have all these plugins content shown by default in the content browser.
- TEMP HACK: Another reason is to let `ULyraDeveloperSettings` and `ULyraPlatformEmulationSettings` to be notified from the editor engine when PIE starts. This is a temporary solution, as Epic is working on a better way to expose these settings to non-editor modules.

### Show Plugin Folder - FirstTickSetup
Because all the actual game modes resides in `Plugins` folder as `GameFeature`, so Lyra want to show them by default, this is done by a `FirstTickSetup` function that is called in the `Tick` function of `ULyraEditorEngine`. This is a common pattern in Unreal Engine, where we want to do something only once after the first tick. The `Tick` function is called every frame, so we can use it to check if we are on the first tick and do our setup there.

```cpp
void ULyraEditorEngine::Tick(float DeltaSeconds, bool bIdleMode)
{
	Super::Tick(DeltaSeconds, bIdleMode);
	
	FirstTickSetup();
}

void ULyraEditorEngine::FirstTickSetup()
{
	if (bFirstTickSetup)
	{
		return;
	}

	bFirstTickSetup = true;

	// Force show plugin content on load.
	GetMutableDefault<UContentBrowserSettings>()->SetDisplayPluginFolders(true);
}
```

### Call DeveloperSettings and PlactformEmulationSettings
As mentioned in the comment, it currently directly coupled `ULyraDeveloperSettings` and `ULyraPlatformEmulationSettings`, a better way would be expose a bindable delegate for a non-editor module to bind, this would be a bit more complicated because we don't want to have our game module depend on the editor module

```cpp
FGameInstancePIEResult ULyraEditorEngine::PreCreatePIEInstances(const bool bAnyBlueprintErrors, const bool bStartInSpectatorMode, const float PIEStartTime, const bool bSupportsOnlinePIE, int32& InNumOnlinePIEInstances)
{
	if (const ALyraWorldSettings* LyraWorldSettings = Cast<ALyraWorldSettings>(EditorWorld->GetWorldSettings()))
	{
		if (LyraWorldSettings->ForceStandaloneNetMode)
		{
			EPlayNetMode OutPlayNetMode;
			PlaySessionRequest->EditorPlaySettings->GetPlayNetMode(OutPlayNetMode);
			if (OutPlayNetMode != PIE_Standalone)
			{
				PlaySessionRequest->EditorPlaySettings->SetPlayNetMode(PIE_Standalone);

				FNotificationInfo Info(LOCTEXT("ForcingStandaloneForFrontend", "Forcing NetMode: Standalone for the Frontend"));
				Info.ExpireDuration = 2.0f;
				FSlateNotificationManager::Get().AddNotification(Info);
			}
		}
	}

	//@TODO: Should add delegates that a *non-editor* module could bind to for PIE start/stop instead of poking directly
	GetDefault<ULyraDeveloperSettings>()->OnPlayInEditorStarted();
	GetDefault<ULyraPlatformEmulationSettings>()->OnPlayInEditorStarted();

	//
	FGameInstancePIEResult Result = Super::PreCreatePIEServerInstance(bAnyBlueprintErrors, bStartInSpectatorMode, PIEStartTime, bSupportsOnlinePIE, InNumOnlinePIEInstances);

	return Result;
}
```

### Configure Custom Engine Class
Once we've defined our own Custom GameEngine and EditorEngine, they can be configured under `DefaultEngine.ini` - `[/Script/Engine.Engine]`
```ini
[/Script/Engine.Engine]
GameEngine=/Script/LyraGame.LyraGameEngine
UnrealEdEngine=/Script/LyraEditor.LyraEditorEngine
EditorEngine=/Script/LyraEditor.LyraEditorEngine
```

## To make a variable configurable in ini file, we can have a meta specifier with Config and a meta
```cpp
    UPROPERTY(config, EditAnywhere, Category = Lyra, meta = (ConsoleVariable = "LyraPC.ShouldAlwaysPlayForceFeedback"))
	bool bShouldAlwaysPlayForceFeedback = false;
```

## Set a toast notification
```cpp
void ULyraDeveloperSettings::OnPlayInEditorStarted() const
{
	// Show a notification toast to remind the user that there's an experience override set
	if (ExperienceOverride.IsValid())
	{
		FNotificationInfo Info(FText::Format(
			LOCTEXT("ExperienceOverrideActive", "Developer Settings Override\nExperience {0}"),
			FText::FromName(ExperienceOverride.PrimaryAssetName)
		));
		Info.ExpireDuration = 2.0f;
		FSlateNotificationManager::Get().AddNotification(Info);
	}
}
```

## Allow class to store data in a config
```cpp
/**
 * Platform emulation settings
 */
UCLASS(config=EditorPerProjectUserSettings, MinimalAPI)
class ULyraPlatformEmulationSettings : public UDeveloperSettingsBackedByCVars
{
	// ...
}
```

## GetOptions meta
GetOptions meta allow a property to be displayed as a dropdown in the editor. Based on a function that returns a list of options.

## Improve compile performance
```cpp
#include UE_INLINE_GENERATED_CPP_BY_NAME(LyraPawnData)
```

## Monitor Editor Performance
Enable editor performance tool in editor preference
