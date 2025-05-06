---
layout: post
title: "Lyra技术解析 - 编辑器模块"
description:
  这是一系列关于我从Epic的Lyra项目中学到的知识笔记。该项目声称展示了当前虚幻引擎框架下的最佳实践。其中有些内容是我之前不了解的，有些则已经知晓，但认为仍然值得记录。
date: 2025-05-02 15:24 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.5.4" %}

## 分离的.uproject与模块命名
Epic可能采用了某种自动化项目设置方法，或是后期手动重命名了`uproject`文件。对比EGS平台预编译版本和Github上的Lyra项目，两者的项目名称并不一致——一个名为`LyraStarterGame`，另一个则简称为`Lyra`。

![From EGS](lyra-egs.png){: width="400"}
_Lyra from EGS_

![From Github](lyra-git.png){: width="400"}
_Lyra from Github_

虽然这并非关键问题，但观察`Source`目录会发现，无论是`Lyra`还是`LyraStarterGame`都不是实际模块名称（如果通过向导创建项目，模块名通常会与项目名相同）。真正的模块名为`LyraGame`和`LyraEditor`。这揭示了一个重要设计理念：`uproject`文件和文件夹名称代表的是项目本身，而在`Source`代码层面，开发者可以对模块名称进行更精细的控制，二者无需强制保持一致。

## 自定义引擎类
`Lyra`项目包含两个自定义引擎扩展类：`LyraGameEngine`和`LyraEditorEngine`。本文将重点解析`LyraEditorEngine`的实现。

### UGameEngine, UEditorEngine, UUnrealEdEngine
`UUnrealEdEngine`继承自`UEditorEngine`，用以专门处理编辑器内的交互逻辑（如选择Actor行为、在PIE前加入自定义代码等）。通常我们应该基于`UUnrealEdEngine`进行扩展，因为`UEditorEngine`是更高层次的抽象基类，而`UUnrealEdEngine`已实现了完整的编辑器功能。若直接继承`UEditorEngine`，可能需要重新实现大量已有功能。

> 当以`Commandlet`模式运行引擎时，`UEditorEngine`会更有价值（详见[Commandlet Documentation]）。这对RBS、DevOps等自动化流程非常有用。
{: .prompt-info }

Lyra扩展编辑器引擎主要出于两个目的：
- 游戏特性插件可见性：Lyra将所有核心玩法模块置于`Plugins/GameFeature`目录，利用`GameFeature`系统管理。默认在内容浏览器显示这些插件内容能提升开发体验。
- 临时解决方案：通过编辑器引擎在PIE启动时通知`ULyraDeveloperSettings`和`ULyraPlatformEmulationSettings`。这是过渡方案，Epic*可能*会在未来使用更完善的跨模块委托绑定。

### 首帧初始化逻辑
由于所有游戏模式都以`GameFeature`形式存在于`Plugins`目录，Lyra通过`ULyraEditorEngine`的`Tick`函数中的`FirstTickSetup`实现默认显示。这是虚幻引擎的常见模式——利用首帧`Tick`执行一次性初始化。

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

### 开发者设置与平台模拟配置
如代码注释所述，当前实现直接耦合了`ULyraDeveloperSettings`和`ULyraPlatformEmulationSettings`。更优解是通过可绑定委托让非编辑器模块进行订阅，但由于需要避免游戏模块对编辑器模块的依赖，这种实现会相对复杂。

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

### 配置自定义引擎类
定义完自定义的`GameEngine`和`EditorEngine`后，需要在`DefaultEngine.ini`文件的`[/Script/Engine.Engine]`节点下进行配置。

```ini
[/Script/Engine.Engine]
GameEngine=/Script/LyraGame.LyraGameEngine
UnrealEdEngine=/Script/LyraEditor.LyraEditorEngine
EditorEngine=/Script/LyraEditor.LyraEditorEngine
```

## 自定义可配置变量
`DefaultEngine.ini`是存储引擎设置的配置文件，但我们也可以创建项目专属的配置变量。只需在类声明中使用`config`说明符并指定目标配置文件，例如Lyra中的`ULyraDeveloperSettings`就配置为使用`EditorPerProjectUserSettings`文件。

```cpp
UCLASS(config=EditorPerProjectUserSettings, MinimalAPI)
class ULyraDeveloperSettings : public UDeveloperSettingsBackedByCVars
{
    //...
}
```

要使变量可配置，还需在属性声明中添加`config`说明符。以Lyra中的`CommonEditorMaps`数组为例：

```cpp
#if WITH_EDITORONLY_DATA
    /** A list of common maps that will be accessible via the editor toolbar */
    UPROPERTY(config, EditAnywhere, BlueprintReadOnly, Category=Maps, meta=(AllowedClasses="/Script/Engine.World"))
    TArray<FSoftObjectPath> CommonEditorMaps;
#endif
```

在配置文件中，可以通过`+`符号添加数组元素。

```ini
; Some commonly used editor maps that will be displayed in the editor task bar
[/Script/LyraGame.LyraDeveloperSettings]
+CommonEditorMaps=/Game/System/FrontEnd/Maps/L_LyraFrontEnd.L_LyraFrontEnd
+CommonEditorMaps=/Game/System/DefaultEditorMap/L_DefaultEditorOverview.L_DefaultEditorOverview
+CommonEditorMaps=/ShooterMaps/Maps/L_Expanse.L_Expanse
+CommonEditorMaps=/ShooterCore/Maps/L_ShooterGym.L_ShooterGym
+CommonEditorMaps=/ShooterTests/Maps/L_ShooterTest_DeviceProperties.L_ShooterTest_DeviceProperties
```

## GetOptions 元数据
`GetOptions`元数据能让属性在编辑器中显示为下拉菜单，其选项由指定函数动态生成。例如`ULyraPlatformEmulationSettings`中的`PretendPlatform`成员，通过返回平台ID列表的函数实现下拉选项。

![Get Options](getoption_meta.png){: width="700"}
_GetOptions Meta_

```cpp
/**
 * Platform emulation settings
 */
UCLASS(config=EditorPerProjectUserSettings, MinimalAPI)
class ULyraPlatformEmulationSettings : public UDeveloperSettingsBackedByCVars
{
    // ...
private:
    UPROPERTY(EditAnywhere, config, Category=PlatformEmulation, meta=(GetOptions=GetKnownPlatformIds))
    FName PretendPlatform;

    // ...
    UFUNCTION()
    TArray<FName> GetKnownPlatformIds() const;
    
    //...
}

TArray<FName> ULyraPlatformEmulationSettings::GetKnownPlatformIds() const
{
    TArray<FName> Results;

#if WITH_EDITOR
    Results.Add(NAME_None);
    Results.Append(UPlatformSettingsManager::GetKnownAndEnablePlatformIniNames());
#endif

    return Results;
}
```

该特性同样适用于函数参数。如下例所示，通过`UPARAM`宏配合`Meta`说明符，`ProfileName`参数将显示为碰撞预设下拉菜单：

```cpp
UFUNCTION(BlueprintCallable, ...)
static ENGINE_API bool LineTraceSingleByProfile(..., UPARAM(Meta=(GetOptions="Engine.KismetSystemLibrary.GetCollisionProfileNames")) FName ProfileName, ...);
```

这种设计允许通过内联宏来修饰函数参数，极大提升了编辑器交互的灵活性。

## 编辑器Toast通知设置
有时我们需要在编辑器中显示Toast通知，这可以通过`FSlateNotificationManager`类实现。以下示例展示了如何在`ULyraDeveloperSettings`类中通知开发者某些设置已配置：通过创建`FNotificationInfo`对象并传递给`FSlateNotificationManager`类的`AddNotification`函数。

![Toast Notification](toast_notification.png){: width="400"}

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
}

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

## 创建新资产类
当现有类无法满足需求时，我们可能需要创建更特殊的类型，比如为自定义类创建专属编辑器，或者注册直接在内容浏览器中显示的新资产类型（作为新资产类型而非蓝图类）。

![New Asset Type](custom_asset_type.png){: width="700"}

本文不涉及具体创建方法，因为[Community Post]已有详细说明。

## 提升编译性能
UE5.1引入了`UE_INLINE_GENERATED_CPP_BY_NAME`宏来提升编译性能（参见[UE5.1 Official Release Note]）。Lyra中大多数类都在cpp文件开头包含其他头文件后使用这个宏，例如：

```cpp
// Copyright Epic Games, Inc. All Rights Reserved.

#include "LyraGameViewportClient.h"

#include "CommonUISettings.h"
#include "ICommonUIModule.h"

#include UE_INLINE_GENERATED_CPP_BY_NAME(LyraGameViewportClient)

//... Actual Class Implementation
```

## 自定义PIE行为
如前所述，我们可以为PIE模式编写不同的行为逻辑。由于PIE是仅发生在编辑器中的情况，我们可以在PIE启动时调用游戏模块函数。

```cpp
/**
 * FLyraEditorModule
 */
class FLyraEditorModule : public FDefaultGameModuleImpl
{
    // ...
    virtual void StartupModule() override
    {
        FGameEditorStyle::Initialize();

        if (!IsRunningGame())
        {
            // ...
            FEditorDelegates::BeginPIE.AddRaw(this, &ThisClass::OnBeginPIE);
            FEditorDelegates::EndPIE.AddRaw(this, &ThisClass::OnEndPIE);
        }
        // ...
    }

    void OnBeginPIE(bool bIsSimulating)
    {
        ULyraExperienceManager* ExperienceManager = GEngine->GetEngineSubsystem<ULyraExperienceManager>();
        check(ExperienceManager);
        ExperienceManager->OnPlayInEditorBegun();
    }
    //...
}
```

## 自定义编辑器按钮扩展
我们可以创建自定义编辑器按钮来执行开发时验证或自动化任务，这基本上只需要我们创建`FToolMenuEntry`并将其添加到属于`UToolMenu`的`FToolMenuSection`中：`LevelEditor.LevelEditorToolBar.PlayToolBar`。

![Custom Toolbar Buttons](custom_toolbar_buttons.png){: width="700"}

```cpp
/**
 * FLyraEditorModule
 */
class FLyraEditorModule : public FDefaultGameModuleImpl
{
    // ...
    virtual void StartupModule() override
    {
        FGameEditorStyle::Initialize();

        if (!IsRunningGame())
        {
            // ...
            if (FSlateApplication::IsInitialized())
            {
                ToolMenusHandle = UToolMenus::RegisterStartupCallback(FSimpleMulticastDelegate::FDelegate::CreateStatic(&RegisterGameEditorMenus));
            }

            // ...
        }
    }
    // ...
}

static void RegisterGameEditorMenus()
{
    UToolMenu* Menu = UToolMenus::Get()->ExtendMenu("LevelEditor.LevelEditorToolBar.PlayToolBar");
    FToolMenuSection& Section = Menu->AddSection("PlayGameExtensions", TAttribute<FText>(), FToolMenuInsert("Play", EToolMenuInsertType::After));

    // Uncomment this to add a custom toolbar that is displayed during PIE
    // Useful for making easy access to changing game state artificially, adding cheats, etc
    // FToolMenuEntry BlueprintEntry = FToolMenuEntry::InitComboButton(
    //     "OpenGameMenu",
    //     FUIAction(
    //         FExecuteAction(),
    //         FCanExecuteAction::CreateStatic(&HasPlayWorld),
    //         FIsActionChecked(),
    //         FIsActionButtonVisible::CreateStatic(&HasPlayWorld)),
    //     FOnGetContent::CreateStatic(&YourCustomMenu),
    //     LOCTEXT("GameOptions_Label", "Game Options"),
    //     LOCTEXT("GameOptions_ToolTip", "Game Options"),
    //     FSlateIcon(FAppStyle::GetAppStyleSetName(), "LevelEditor.OpenLevelBlueprint")
    // );
    // BlueprintEntry.StyleNameOverride = "CalloutToolbar";
    // Section.AddEntry(BlueprintEntry);

    FToolMenuEntry CheckContentEntry = FToolMenuEntry::InitToolBarButton(
        "CheckContent",
        FUIAction(
            FExecuteAction::CreateStatic(&CheckGameContent_Clicked),
            FCanExecuteAction::CreateStatic(&HasNoPlayWorld),
            FIsActionChecked(),
            FIsActionButtonVisible::CreateStatic(&HasNoPlayWorld)),
        LOCTEXT("CheckContentButton", "Check Content"),
        LOCTEXT("CheckContentDescription", "Runs the Content Validation job on all checked out assets to look for warnings and errors"),
        FSlateIcon(FGameEditorStyle::GetStyleSetName(), "GameEditor.CheckContent")
    );
    CheckContentEntry.StyleNameOverride = "CalloutToolbar";
    Section.AddEntry(CheckContentEntry);

    FToolMenuEntry CommonMapEntry = FToolMenuEntry::InitComboButton(
        "CommonMapOptions",
        FUIAction(
            FExecuteAction(),
            FCanExecuteAction::CreateStatic(&HasNoPlayWorld),
            FIsActionChecked(),
            FIsActionButtonVisible::CreateStatic(&CanShowCommonMaps)),
        FOnGetContent::CreateStatic(&GetCommonMapsDropdown),
        LOCTEXT("CommonMaps_Label", "Common Maps"),
        LOCTEXT("CommonMaps_ToolTip", "Some commonly desired maps while using the editor"),
        FSlateIcon(FAppStyle::GetAppStyleSetName(), "Icons.Level")
    );
    CommonMapEntry.StyleNameOverride = "CalloutToolbar";
    Section.AddEntry(CommonMapEntry);
}
```

### 检查内容按钮 - 工具栏按钮
检查内容按钮的实现很直接，点击时会执行验证任务，通过调用`CheckGameContent_Clicked`函数实现。在本例中，它调用了`UEditorValidator::ValidateCheckedOutContent`函数。

```cpp
FToolMenuEntry CheckContentEntry = FToolMenuEntry::InitToolBarButton(
    "CheckContent",
    FUIAction(
        FExecuteAction::CreateStatic(&CheckGameContent_Clicked),
        // ...
        ),
        // ...
        FSlateIcon(FGameEditorStyle::GetStyleSetName(), "GameEditor.CheckContent")
    );

static void CheckGameContent_Clicked()
{
    UEditorValidator::ValidateCheckedOutContent(/*bInteractive=*/true, EDataValidationUsecase::Manual);
}
```

### 常用地图下拉菜单 - 组合按钮
这个实现会复杂些。点击按钮时不会立即执行操作，而是显示包含所有相关地图的下拉菜单。当用户点击某个地图时，才会调用`OpenCommonMap_Clicked`。

这里的逻辑是创建一个`ComboButton`而非普通`ToolBarButton`，并使用`FOnGetContent`创建下拉菜单。`FMenuBuilder`类用于构建菜单，我们可以用`AddMenuEntry`函数添加条目。每个条目包含显示名称、工具提示和点击时要执行的操作。点击选项时会响应`OpenEditorForAsset`函数，在编辑器中打开选中的地图。

```cpp
static TSharedRef<SWidget> GetCommonMapsDropdown()
{
    FMenuBuilder MenuBuilder(true, nullptr);
    
    for (const FSoftObjectPath& Path : GetDefault<ULyraDeveloperSettings>()->CommonEditorMaps)
    {
        if (!Path.IsValid())
        {
            continue;
        }
        
        const FText DisplayName = FText::FromString(Path.GetAssetName());
        MenuBuilder.AddMenuEntry(
            DisplayName,
            LOCTEXT("CommonPathDescription", "Opens this map in the editor"),
            FSlateIcon(),
            FUIAction(
                FExecuteAction::CreateStatic(&OpenCommonMap_Clicked, Path.ToString()),
                FCanExecuteAction::CreateStatic(&HasNoPlayWorld),
                FIsActionChecked(),
                FIsActionButtonVisible::CreateStatic(&HasNoPlayWorld)
            )
        );
    }

    return MenuBuilder.MakeWidget();
}

static void OpenCommonMap_Clicked(const FString MapPath)
{
    if (ensure(MapPath.Len()))
    {
        GEditor->GetEditorSubsystem<UAssetEditorSubsystem>()->OpenEditorForAsset(MapPath);
    }
}
```

注意`for (const FSoftObjectPath& Path : GetDefault<ULyraDeveloperSettings>()->CommonEditorMaps)`这行代码，它获取的是之前提到的`CommonEditorMaps`属性，即`ULyraDeveloperSettings`类中的可配置属性。这是使用`GetDefault`函数从`ini`文件访问类默认设置的好例子。

```ini
; Some commonly used editor maps that will be displayed in the editor task bar
[/Script/LyraGame.LyraDeveloperSettings]
+CommonEditorMaps=/Game/System/FrontEnd/Maps/L_LyraFrontEnd.L_LyraFrontEnd
+CommonEditorMaps=/Game/System/DefaultEditorMap/L_DefaultEditorOverview.L_DefaultEditorOverview
+CommonEditorMaps=/ShooterMaps/Maps/L_Expanse.L_Expanse
+CommonEditorMaps=/ShooterCore/Maps/L_ShooterGym.L_ShooterGym
+CommonEditorMaps=/ShooterTests/Maps/L_ShooterTest_DeviceProperties.L_ShooterTest_DeviceProperties
```

## 编辑器样式的单例模式
在上面的例子中，我们创建按钮时也定义了它们的图标外观。

```cpp
    FToolMenuEntry CheckContentEntry = FToolMenuEntry::InitToolBarButton(
        "CheckContent",
        // ...
        FSlateIcon(FGameEditorStyle::GetStyleSetName(), "GameEditor.CheckContent")
    );
```

虽然可以直接定义按钮图标，但我们也可以将它们集中管理。在本例中，`GameEditor.CheckContent`实际上是在简单的`FGameEditorStyle`单例中设置的。初始化时，它创建`StyleInstance`并注册到`FSlateStyleRegistry`。这是虚幻引擎中的常见模式，用于集中管理样式和资源。实际图标位于`Content/Editor/Slate/Icons/CheckContent.svg`。

```cpp
TSharedPtr< FSlateStyleSet > FGameEditorStyle::StyleInstance = nullptr;

void FGameEditorStyle::Initialize()
{
    if ( !StyleInstance.IsValid() )
    {
        StyleInstance = Create();
        FSlateStyleRegistry::RegisterSlateStyle( *StyleInstance );
    }
}

TSharedRef< FSlateStyleSet > FGameEditorStyle::Create()
{
    TSharedRef<FSlateStyleSet> StyleRef = MakeShareable(new FSlateStyleSet(FGameEditorStyle::GetStyleSetName()));
    StyleRef->SetContentRoot(FPaths::EngineContentDir() / TEXT("Editor/Slate"));
    StyleRef->SetCoreContentRoot(FPaths::EngineContentDir() / TEXT("Slate"));

    FSlateStyleSet& Style = StyleRef.Get();

    const FVector2D Icon16x16(16.0f, 16.0f);
    const FVector2D Icon20x20(20.0f, 20.0f);
    const FVector2D Icon40x40(40.0f, 40.0f);
    const FVector2D Icon64x64(64.0f, 64.0f);

    // Toolbar 
    {
        Style.Set("GameEditor.CheckContent", new GAME_IMAGE_BRUSH_SVG("Icons/CheckContent", Icon20x20));
    }

    return StyleRef;
}
```

这个模式适用于多种情况。我们只需要找到合适的地方进行`Initialize`初始化。对`Lyra`来说，这实际上就是`FLyraEditorModule`的`StartupModule`函数的第一行。

```cpp
    virtual void StartupModule() override
    {
        FGameEditorStyle::Initialize();
        // ...
    }
```

## 自动控制台命令
`FAutoConsoleCommandWithWorldArgsAndOutputDevice`类让我们可以轻松创建可执行的控制台命令，典型语法如下：

```cpp
FAutoConsoleCommandWithWorldArgsAndOutputDevice GCreateRedirectorPackage(
    TEXT("Lyra.CreateRedirectorPackage"),
    TEXT("Usage:\n")
    TEXT("  Lyra.CreateRedirectorPackage RedirectorName TargetPackage"),
    FConsoleCommandWithWorldArgsAndOutputDeviceDelegate::CreateStatic(
        [](const TArray<FString>& Params, UWorld* World, FOutputDevice& Ar)
    {
        // ... Implementation
    }));
```

如上所示，实际实现是通过绑定到`FConsoleCommandWithWorldArgsAndOutputDeviceDelegate`的`lambda`函数完成的。`WithWorldArgsAndOutputDevice`部分描述了委托签名：第一个参数是`TArray<FString>`，第二个是`UWorld*`，第三个是`FOutputDevice&`。用户在控制台输入的所有参数都会作为`TArray<FString>`传递给第一个参数，我们可以像普通数组一样提取参数。

Lyra中有三个示例命令：
- GCheckChaosMeshCollisionCmd
  - 用于检查给定资产的网格碰撞
- GCreateRedirectorPackage
  - 为给定资产创建重定向器包
- GDiffCollectionReferenceSupport
  - 检查新旧集合间的引用差异

## MinimalAPI和LYRAGAME_API
这里没有太多复杂内容，只需注意需要使用`PROJECT_API`宏来导出函数，而`MinimalAPI`用于导出类。

```cpp
/**
 * Manager for experiences - primarily for arbitration between multiple PIE sessions
 */
UCLASS(MinimalAPI)
class ULyraExperienceManager : public UEngineSubsystem
{
    GENERATED_BODY()

public:
#if WITH_EDITOR
    LYRAGAME_API void OnPlayInEditorBegun();
    // ...
}
```

## 监控编辑器性能
虚幻引擎内置了编辑器性能监控器，可以在编辑器偏好设置中启用。这个工具可以监控编辑器性能并识别潜在瓶颈，特别适用于大型项目或需要优化游戏性能的情况。

在编辑器偏好设置中启用性能工具：
![Enable Editor Performance Monitor](editorperf_monitor_enable.png){: width="700"}

然后，我们可以在底部工具栏查看性能报告：
![Editor Performance Monitor](editorperf_monitor_1.png){: width="700"}

每个相关类别都有提示说明潜在问题是什么。
![Editor Performance Monitor](editorperf_monitor_2.png){: width="700"}



[Community Post]: https://dev.epicgames.com/community/learning/tutorials/vyKB/unreal-engine-creating-a-custom-asset-type-with-its-own-editor-in-c
[UE5.1 Official Release Note]: https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-5.1-release-notes?application_version=5.1
[Commandlet Documentation]: https://zhuanlan.zhihu.com/p/512610557

