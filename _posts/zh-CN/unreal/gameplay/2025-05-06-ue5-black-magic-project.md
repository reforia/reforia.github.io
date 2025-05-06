---
layout: post
title: "Lyra技术解析 - 项目配置"
description:
  这是一系列关于我从Epic的Lyra项目中学到的知识笔记。该项目声称展示了当前虚幻引擎框架下的最佳实践。其中有些内容是我之前不了解的，有些则已经知晓，但认为仍然值得记录。
date: 2025-05-06 19:07 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor-project/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.5.4" %}

## 构建目标
只需快速浏览项目结构，我们就能发现`Lyra`包含6个不同的构建目标。每个目标都有特定用途，可用于以不同方式构建项目。

- `LyraEditor`
- `LyraClient`
- `LyraServer`
- `LyraServerEOS`
- `LyraGame`
- `LyraGameEOS`

![Lyra Build Target](build_target.png){: width="500"}

我们将逐一分析这些目标，但会把`LyraGame`留到最后讨论，因为该文件体量较大且包含大量项目信息。其他目标规模较小，更容易理解。

## LyraEditor
这个目标非常直白，`LyraEditor`用于构建编辑器。它包含`LyraGame`和`LyraEditor`模块，同时还启用了用于触屏开发的`RemoteSession`插件。因此如果我们不使用触屏设备，可以移除这个模块。

```cs
// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System.Collections.Generic;

public class LyraEditorTarget : TargetRules
{
    public LyraEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;

        ExtraModuleNames.AddRange(new string[] { "LyraGame", "LyraEditor" });

        if (!bBuildAllModules)
        {
            NativePointerMemberBehaviorOverride = PointerMemberBehavior.Disallow;
        }

        LyraGameTarget.ApplySharedLyraTargetSettings(this);

        // This is used for touch screen development along with the "Unreal Remote 2" app
        EnablePlugins.Add("RemoteSession");
    }
}
```

### 目标类型
目标定义的首行是`Type = TargetType.Editor;`，这是`TargetRules`类的属性，用于指定我们正在构建的目标类型。可选值包括：

- `Game`
- `Editor`
- `Client`
- `Server`
- `Program`

```cpp
/// <summary>
/// Static class wrapping constants aliasing the global TargetType enum.
/// </summary>
public static class TargetType
{
    /// <summary>
    /// Alias for TargetType.Game
    /// </summary>
    public const global::UnrealBuildTool.TargetType Game = global::UnrealBuildTool.TargetType.Game;

    /// <summary>
    /// Alias for TargetType.Editor
    /// </summary>
    public const global::UnrealBuildTool.TargetType Editor = global::UnrealBuildTool.TargetType.Editor;

    /// <summary>
    /// Alias for TargetType.Client
    /// </summary>
    public const global::UnrealBuildTool.TargetType Client = global::UnrealBuildTool.TargetType.Client;

    /// <summary>
    /// Alias for TargetType.Server
    /// </summary>
    public const global::UnrealBuildTool.TargetType Server = global::UnrealBuildTool.TargetType.Server;

    /// <summary>
    /// Alias for TargetType.Program
    /// </summary>
    public const global::UnrealBuildTool.TargetType Program = global::UnrealBuildTool.TargetType.Program;
}
```

大多数类型都无需解释，但`Program`类型用于构建独立于引擎或游戏之外的程序。这个类型适用于构建不属于游戏本身的工具或实用程序，例如`UnrealFrontend`工具。

```cs
// Copyright 1998-2018 Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System.Collections.Generic;

public class UnrealFrontendTarget : TargetRules
{
    public UnrealFrontendTarget( TargetInfo Target ) : base(Target)
    {
        Type = TargetType.Program;
        LinkType = TargetLinkType.Modular;
        AdditionalPlugins.Add("UdpMessaging");
        LaunchModuleName = "UnrealFrontend";

        bBuildEditor = false;
        bCompileAgainstEngine = false;
        bCompileAgainstCoreUObject = true;
        bForceBuildTargetPlatforms = true;
        bCompileWithStatsWithoutEngine = true;
        bCompileWithPluginSupport = true;

        bHasExports = false;
    }
}
```

### 目标依赖与全局依赖的区别
通常我们只需在`uproject`文件中启用插件，在`Target.cs`文件中声明依赖，就能使用该插件。这种操作几乎成为本能，但仔细想想，如果某些依赖仅对特定目标有效，我们本就不需要在一开始引入全局依赖。因此在上例中，我们可以针对特定目标单独启用插件——这里`RemoteSession`插件仅对`LyraEditor`目标启用，因为该目标专用于触屏开发。

### 跨目标依赖
最后一行代码较为特殊：`LyraGameTarget.ApplySharedLyraTargetSettings(this);`。这是在调用`LyraGame`目标中定义的方法，用于向所有目标应用共享设置。我们稍后会分析该方法的实现，目前只需知道它负责为所有目标配置通用参数。

#### UBT的运作机制
但这里有个疑问：`LyraGameTarget`对象从何而来？为何能在不引入头文件的情况下直接调用其函数？要解答这个问题，需要理解`UBT（Unreal Build Tool）`的工作原理。我们不会深入探讨`UBT`，简而言之：

- `UBT`会收集所有`target.cs`文件及模块文件`（build.cs）`，并将它们编译为单一程序集：
  - 该程序集存储在`Intermediate/Build/BuildRule/LyraModuleRules.dll`目录
  - 注意：包括插件中的文件在内，所有`server.target.cs`、`game.target.cs`都会被合并到同一个程序集
  - 这就是为什么无需引入头文件即可使用`LyraGameTarget`——`UBT`已将其编译至程序集中，`LyraEditor`能感知`LyraGameTarget`的存在
  - 需要强调的是：将所有目标编译到同一程序集并不等同于构建它们。当构建`LyraEditor.Target.cs`时，系统只会检查`LyraGame.Build.cs`（因其列在`ExtraModuleNames`中），而`LyraServer.Target.cs`则完全不会被构建

但问题仍未解决：为何能直接调用该方法？`LyraGameTarget`对象实例从何获取？

答案是：我们根本不需要实例。该方法是静态函数，而C#不像C++那样使用`::`运算符调用静态函数——所有调用都通过`.`操作符完成。

```cs
internal static void ApplySharedLyraTargetSettings(TargetRules Target)
    {
        // ...
  }
```

简要流程如下：
- `RulesCompiler`收集所有文件并创建单一程序集目标`RulesAssembly`，将这些文件传递给它
- `RulesAssembly`编译这些文件并创建单个程序集，其他所有`Target.cs`在构建期间都能访问该程序集

我知道这听起来难以置信——为什么我的`Client`目标在构建时能感知`ServerEOS`目标？但这里有确凿证据（虽然直接进入`UBT`调试会更简单，但我更想亲眼验证）。以下是反编译后的`ModuleRules.dll`内容：

![Decompiled Dll 1](decompiled_dll_1.png)

确实，所有内容都在这个dll中。客户端、编辑器、服务器、游戏、所有插件等等。不仅如此，我们还能在这个dll中看到`ConfigureGameFeaturePlugins`函数。

![Decompiled Dll 2](decompiled_dll_2.png)

那么它在源代码中的位置呢？就在这里，位于`LyraGameTarget`类内部。这应该能完美解答我们的疑问。

```cs
    // Configures which game feature plugins we want to have enabled
    // This is a fairly simple implementation, but you might do things like build different
    // plugins based on the target release version of the current branch, e.g., enabling 
    // work-in-progress features in main but disabling them in the current release branch.
    static public void ConfigureGameFeaturePlugins(TargetRules Target)
    {
        // ...
  }
```

## LyraClient
老套路了，理解前面的内容后，这里就没有什么新花样了。

```cs
// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System.Collections.Generic;

public class LyraClientTarget : TargetRules
{
    public LyraClientTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Client;

        ExtraModuleNames.AddRange(new string[] { "LyraGame" });

        LyraGameTarget.ApplySharedLyraTargetSettings(this);
    }
}
```

## LyraServer
新目标带来新规则，这个目标引入了一个新属性`bUseChecksInShipping`，用于控制是否在发行版构建中启用检查。虽然主要用于调试，但也可以用来控制发行版的特定功能开关。

```cs
// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System.Collections.Generic;

[SupportedPlatforms(UnrealPlatformClass.Server)]
public class LyraServerTarget : TargetRules
{
    public LyraServerTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Server;

        ExtraModuleNames.AddRange(new string[] { "LyraGame" });

        LyraGameTarget.ApplySharedLyraTargetSettings(this);

        bUseChecksInShipping = true;
    }
}
```

类似的属性还有：

```cs
public bool bUseLoggingInShipping = true ;
public bool bUseChecksInShipping = true ;

// Engine\Source\Runtime\Core\Public\Misc\ Build.h
#define ALLOW_CONSOLE_IN_SHIPPING 1
#define FORCE_USE_STATS 1
```

实际上可配置的属性远不止这些。自动生成的文档`UnrealBuildTool.xml`足足有32000行内容，我已将其提交至[Github Repo]供参考。

> Epic 也提供了一大篇关于构建配置的文档 [Giant Page]
{: .prompt-info }

## LyraServerEOS & LyraGameEOS & CustomConfig
接近尾声了，这两个目标乍看很简单：它们分别继承自父目标`LyraServer`和`LyraGame`，仅新增了一个`CustomConfig`属性，用于指定目标使用的自定义配置文件。

```cs
// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System.Collections.Generic;

public class LyraServerEOSTarget : LyraServerTarget
{
    public LyraServerEOSTarget(TargetInfo Target) : base(Target)
    {
        CustomConfig = "EOS";
    }
}


// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System.Collections.Generic;

public class LyraGameEOSTarget : LyraGameTarget
{
    public LyraGameEOSTarget(TargetInfo Target) : base(Target)
    {
        CustomConfig = "EOS";
    }
}
```

`CustomConfig`的作用是告知引擎存在自定义配置文件，该文件需要被整合到构建流程中。具体路径定义在以下源码中：

```cpp
inline FConfigLayer GConfigLayers[] =
{
    /**************************************************
    **** CRITICAL NOTES
    **** If you change this array, you need to also change EnumerateConfigFileLocations() in ConfigHierarchy.cs!!!
    **** And maybe UObject::GetDefaultConfigFilename(), UObject::GetGlobalUserConfigFilename()
    **************************************************/

    // ...
    // Project/Custom/CustomConfig/Default*.ini only if CustomConfig is defined
    { TEXT("CustomConfig"),                TEXT("{PROJECT}/Config/Custom/{CUSTOMCONFIG}/Default{TYPE}.ini"), EConfigLayerFlags::RequiresCustomConfig },
    // ...
};
```

![Global Configs](global_configs.png)

从上面可以看出，除了带有`Config`元数据的类会读取的配置外，我们还为每个可能的平台准备了配置文件夹，其中就包含这个`Custom`专用目录。

### 配置层级
我们立即发现了一个问题：存在多个`Custom/EOS`文件夹，一个位于根目录，另一个在`Windows`文件夹内。那么实际使用的是哪个呢？

![Config Layer](config_layer.png)

根据[Config Documentation]和源码所示，Unreal引擎读取配置的顺序如下：

- Engine/Config/Base.ini
- Engine/Config/Base[Type].ini
- Engine/Config/[Platform]/Base[Platform][Type].ini
- [Project Directory]/Config/Default[Type].ini
- [Project Directory]/Config/Generated[Type].ini
- [Project Directory]/Config/Custom/[CustomConfig]/Default[Type].ini
- Engine/Config/[Platform]/[Platform][Type].ini
- [Project Directory]/Config/[Platform]/[Platform][Type].ini
- [Project Directory]/Config/[Platform]/Generated[Platform][Type].ini
- [Project Directory]/Config/[Platform]/Custom/[CustomConfig]/[Platform][Type].ini
- [User]/Unreal Engine/Engine/Config/User[Type].ini
- [Project Directory]/Config/User[Type].ini

```cpp
// See FConfigContext.cpp for the types here

inline FConfigLayer GConfigLayers[] =
{
	/**************************************************
	**** CRITICAL NOTES
	**** If you change this array, you need to also change EnumerateConfigFileLocations() in ConfigHierarchy.cs!!!
	**** And maybe UObject::GetDefaultConfigFilename(), UObject::GetGlobalUserConfigFilename()
	**************************************************/

	// Engine/Base.ini
	{ TEXT("AbsoluteBase"),				TEXT("{ENGINE}/Config/Base.ini"), EConfigLayerFlags::NoExpand},

	// Engine/Base*.ini
	{ TEXT("Base"),						TEXT("{ENGINE}/Config/Base{TYPE}.ini") },
	// Engine/Platform/BasePlatform*.ini
	{ TEXT("BasePlatform"),				TEXT("{ENGINE}/Config/{PLATFORM}/Base{PLATFORM}{TYPE}.ini")  },
	// Project/Default*.ini
	{ TEXT("ProjectDefault"),			TEXT("{PROJECT}/Config/Default{TYPE}.ini"), EConfigLayerFlags::AllowCommandLineOverride },
	// Project/Generated*.ini Reserved for files generated by build process and should never be checked in 
	{ TEXT("ProjectGenerated"),			TEXT("{PROJECT}/Config/Generated{TYPE}.ini") },
	// Project/Custom/CustomConfig/Default*.ini only if CustomConfig is defined
	{ TEXT("CustomConfig"),				TEXT("{PROJECT}/Config/Custom/{CUSTOMCONFIG}/Default{TYPE}.ini"), EConfigLayerFlags::RequiresCustomConfig },
	// Engine/Platform/Platform*.ini
	{ TEXT("EnginePlatform"),			TEXT("{ENGINE}/Config/{PLATFORM}/{PLATFORM}{TYPE}.ini") },
	// Project/Platform/Platform*.ini
	{ TEXT("ProjectPlatform"),			TEXT("{PROJECT}/Config/{PLATFORM}/{PLATFORM}{TYPE}.ini") },
	// Project/Platform/GeneratedPlatform*.ini Reserved for files generated by build process and should never be checked in 
	{ TEXT("ProjectPlatformGenerated"),	TEXT("{PROJECT}/Config/{PLATFORM}/Generated{PLATFORM}{TYPE}.ini") },
	// Project/Platform/Custom/CustomConfig/Platform*.ini only if CustomConfig is defined
	{ TEXT("CustomConfigPlatform"),		TEXT("{PROJECT}/Config/{PLATFORM}/Custom/{CUSTOMCONFIG}/{PLATFORM}{TYPE}.ini"), EConfigLayerFlags::RequiresCustomConfig },
	// UserSettings/.../User*.ini
	{ TEXT("UserSettingsDir"),			TEXT("{USERSETTINGS}Unreal Engine/Engine/Config/User{TYPE}.ini"), EConfigLayerFlags::NoExpand },
	// UserDir/.../User*.ini
	{ TEXT("UserDir"),					TEXT("{USER}Unreal Engine/Engine/Config/User{TYPE}.ini"), EConfigLayerFlags::NoExpand },
	// Project/User*.ini
	{ TEXT("GameDirUser"),				TEXT("{PROJECT}/Config/User{TYPE}.ini"), EConfigLayerFlags::NoExpand },
};
```

这很好地解释了不同`EOS`文件夹的使用方式：Unreal会先加载`Custom/EOS`文件夹，然后加载`Windows/EOS`文件夹.

## `;` 不是注释？！
> 这部分内容来自Epic官方文档，但是在我的测试中，似乎已经不是这么回事了。
{: .prompt-warning }

从上述文档中，Epic提出了一个有趣的话题：`;`字符。我们本能地会认为`;`是注释符号，但实际上并非如此。它"大多数情况下"能像注释一样工作，是因为在解析过程中，`FConfigFile::ProcessInputFileContents`并不会处理那些不包含`=`符号来构成键值对的行。因此这些行会被跳过。然而，如果我们遇到这种情况：

```ini
;A = 1
```

那么实际上我们定义了一个键为`;A`，值为`1`的键值对。因此这是一个有效的配置行，它将会被正常解析。

但是！`FConfigFile::ProcessInputFileContents`的实现如下：从中我们可以看到它明确检查了`;`并忽略它。这意味着上面的说法并不成立。

```cpp
    // ...
    // ignore [comment] lines that start with ;
    if(*Start != (TCHAR)';')
    {
        // If we're in python mode and the line starts with whitespace
        // then we should consider it a part of the prior key
        if (File->bPythonConfigParserMode && !CurrentKeyName.IsNone() && FChar::IsWhitespace(*Start))
        {
            Value = Start;
        }
        else
        {
            Value = FCString::Strstr(Start,TEXT("="));
        }
    }

    // Ignore any lines that don't contain a key-value pair
    if( Value )
    {
        // ...
    }
```

## LyraGame与共享目标设置
我们终于来到了`LyraGame`目标，凭借之前的知识，这个文件应该不难理解。除了常规的目标属性外，它还公开了一些静态函数供其他目标使用。由此可见，我们可以将通用目标设置集中管理，避免代码重复。

这里有个有趣的细节：我们可以通过将某台机器的`IsBuildMachine`环境变量设为`1`，从而让该机器执行特殊操作，这对DevOps非常实用。尤其适用于那些需要启用所有插件进行测试的构建机器。

```cs
// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;
using System;
using System.IO;
using EpicGames.Core;
using System.Collections.Generic;
using UnrealBuildBase;
using Microsoft.Extensions.Logging;

public class LyraGameTarget : TargetRules
{
    public LyraGameTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;

        ExtraModuleNames.AddRange(new string[] { "LyraGame" });

        LyraGameTarget.ApplySharedLyraTargetSettings(this);
    }

    private static bool bHasWarnedAboutShared = false;

    internal static void ApplySharedLyraTargetSettings(TargetRules Target)
    {
    // ... See Appendix: ApplySharedLyraTargetSettings
    }

    static public bool ShouldEnableAllGameFeaturePlugins(TargetRules Target)
    {
        if (Target.Type == TargetType.Editor)
        {
            // With return true, editor builds will build all game feature plugins, but it may or may not load them all.
            // This is so you can enable plugins in the editor without needing to compile code.
            // return true;
        }

        bool bIsBuildMachine = (Environment.GetEnvironmentVariable("IsBuildMachine") == "1");
        if (bIsBuildMachine)
        {
            // This could be used to enable all plugins for build machines
            // return true;
        }

        // By default use the default plugin rules as set by the plugin browser in the editor
        // This is important because this code may not be run at all for launcher-installed versions of the engine
        return false;
    }

    private static Dictionary<string, JsonObject> AllPluginRootJsonObjectsByName = new Dictionary<string, JsonObject>();

    // Configures which game feature plugins we want to have enabled
    // This is a fairly simple implementation, but you might do things like build different
    // plugins based on the target release version of the current branch, e.g., enabling 
    // work-in-progress features in main but disabling them in the current release branch.
    static public void ConfigureGameFeaturePlugins(TargetRules Target)
    {
    // ... See Appendix: ConfigureGameFeaturePlugins
    }
}
```

## Appendix: `ApplySharedLyraTargetSettings`
```cs
internal static void ApplySharedLyraTargetSettings(TargetRules Target)
    {
        ILogger Logger = Target.Logger;
        
        Target.DefaultBuildSettings = BuildSettingsVersion.V5;
        Target.IncludeOrderVersion = EngineIncludeOrderVersion.Latest;

        bool bIsTest = Target.Configuration == UnrealTargetConfiguration.Test;
        bool bIsShipping = Target.Configuration == UnrealTargetConfiguration.Shipping;
        bool bIsDedicatedServer = Target.Type == TargetType.Server;
        if (Target.BuildEnvironment == TargetBuildEnvironment.Unique)
        {
            Target.ShadowVariableWarningLevel = WarningLevel.Error;

            Target.bUseLoggingInShipping = true;

            if (bIsShipping && !bIsDedicatedServer)
            {
                // Make sure that we validate certificates for HTTPS traffic
                Target.bDisableUnverifiedCertificates = true;

                // Uncomment these lines to lock down the command line processing
                // This will only allow the specified command line arguments to be parsed
                //Target.GlobalDefinitions.Add("UE_COMMAND_LINE_USES_ALLOW_LIST=1");
                //Target.GlobalDefinitions.Add("UE_OVERRIDE_COMMAND_LINE_ALLOW_LIST=\"-space -separated -list -of -commands\"");

                // Uncomment this line to filter out sensitive command line arguments that you
                // don't want to go into the log file (e.g., if you were uploading logs)
                //Target.GlobalDefinitions.Add("FILTER_COMMANDLINE_LOGGING=\"-some_connection_id -some_other_arg\"");
            }

            if (bIsShipping || bIsTest)
            {
                // Disable reading generated/non-ufs ini files
                Target.bAllowGeneratedIniWhenCooked = false;
                Target.bAllowNonUFSIniWhenCooked = false;
            }

            if (Target.Type != TargetType.Editor)
            {
                // We don't use the path tracer at runtime, only for beauty shots, and this DLL is quite large
                Target.DisablePlugins.Add("OpenImageDenoise");

                // Reduce memory use in AssetRegistry always-loaded data, but add more cputime expensive queries
                Target.GlobalDefinitions.Add("UE_ASSETREGISTRY_INDIRECT_ASSETDATA_POINTERS=1");
            }

            LyraGameTarget.ConfigureGameFeaturePlugins(Target);
        }
        else
        {
            // !!!!!!!!!!!! WARNING !!!!!!!!!!!!!
            // Any changes in here must not affect PCH generation, or the target
            // needs to be set to TargetBuildEnvironment.Unique

            // This only works in editor or Unique build environments
            if (Target.Type == TargetType.Editor)
            {
                LyraGameTarget.ConfigureGameFeaturePlugins(Target);
            }
            else
            {
                // Shared monolithic builds cannot enable/disable plugins or change any options because it tries to re-use the installed engine binaries
                if (!bHasWarnedAboutShared)
                {
                    bHasWarnedAboutShared = true;
                    Logger.LogWarning("LyraGameEOS and dynamic target options are disabled when packaging from an installed version of the engine");
                }
            }
        }
  }
```

## Appendix: `ConfigureGameFeaturePlugins`
```cs
    // Configures which game feature plugins we want to have enabled
    // This is a fairly simple implementation, but you might do things like build different
    // plugins based on the target release version of the current branch, e.g., enabling 
    // work-in-progress features in main but disabling them in the current release branch.
    static public void ConfigureGameFeaturePlugins(TargetRules Target)
    {
        ILogger Logger = Target.Logger;
        Log.TraceInformationOnce("Compiling GameFeaturePlugins in branch {0}", Target.Version.BranchName);

        bool bBuildAllGameFeaturePlugins = ShouldEnableAllGameFeaturePlugins(Target);

        // Load all of the game feature .uplugin descriptors
        List<FileReference> CombinedPluginList = new List<FileReference>();

        List<DirectoryReference> GameFeaturePluginRoots = Unreal.GetExtensionDirs(Target.ProjectFile.Directory, Path.Combine("Plugins", "GameFeatures"));
        foreach (DirectoryReference SearchDir in GameFeaturePluginRoots)
        {
            CombinedPluginList.AddRange(PluginsBase.EnumeratePlugins(SearchDir));
        }

        if (CombinedPluginList.Count > 0)
        {
            Dictionary<string, List<string>> AllPluginReferencesByName = new Dictionary<string, List<string>>();

            foreach (FileReference PluginFile in CombinedPluginList)
            {
                if (PluginFile != null && FileReference.Exists(PluginFile))
                {
                    bool bEnabled = false;
                    bool bForceDisabled = false;
                    try
                    {
                        JsonObject RawObject;
                        if (!AllPluginRootJsonObjectsByName.TryGetValue(PluginFile.GetFileNameWithoutExtension(), out RawObject))
                        {
                            RawObject = JsonObject.Read(PluginFile);
                            AllPluginRootJsonObjectsByName.Add(PluginFile.GetFileNameWithoutExtension(), RawObject);
                        }

                        // Validate that all GameFeaturePlugins are disabled by default
                        // If EnabledByDefault is true and a plugin is disabled the name will be embedded in the executable
                        // If this is a problem, enable this warning and change the game feature editor plugin templates to disable EnabledByDefault for new plugins
                        bool bEnabledByDefault = false;
                        if (!RawObject.TryGetBoolField("EnabledByDefault", out bEnabledByDefault) || bEnabledByDefault == true)
                        {
                            //Log.TraceWarning("GameFeaturePlugin {0}, does not set EnabledByDefault to false. This is required for built-in GameFeaturePlugins.", PluginFile.GetFileNameWithoutExtension());
                        }

                        // Validate that all GameFeaturePlugins are set to explicitly loaded
                        // This is important because game feature plugins expect to be loaded after project startup
                        bool bExplicitlyLoaded = false;
                        if (!RawObject.TryGetBoolField("ExplicitlyLoaded", out bExplicitlyLoaded) || bExplicitlyLoaded == false)
                        {
                            Logger.LogWarning("GameFeaturePlugin {0}, does not set ExplicitlyLoaded to true. This is required for GameFeaturePlugins.", PluginFile.GetFileNameWithoutExtension());
                        }

                        // You could read an additional field here that is project specific, e.g.,
                        //string PluginReleaseVersion;
                        //if (RawObject.TryGetStringField("MyProjectReleaseVersion", out PluginReleaseVersion))
                        //{
                        //        bEnabled = SomeFunctionOf(PluginReleaseVersion, CurrentReleaseVersion) || bBuildAllGameFeaturePlugins;
                        //}

                        if (bBuildAllGameFeaturePlugins)
                        {
                            // We are in a mode where we want all game feature plugins, except ones we can't load or compile
                            bEnabled = true;
                        }

                        // Prevent using editor-only feature plugins in non-editor builds
                        bool bEditorOnly = false;
                        if (RawObject.TryGetBoolField("EditorOnly", out bEditorOnly))
                        {
                            if (bEditorOnly && (Target.Type != TargetType.Editor) && !bBuildAllGameFeaturePlugins)
                            {
                                // The plugin is editor only and we are building a non-editor target, so it is disabled
                                bForceDisabled = true;
                            }
                        }
                        else
                        {
                            // EditorOnly is optional
                        }

                        // some plugins should only be available in certain branches
                        string RestrictToBranch;
                        if (RawObject.TryGetStringField("RestrictToBranch", out RestrictToBranch))
                        {
                            if (!Target.Version.BranchName.Equals(RestrictToBranch, StringComparison.OrdinalIgnoreCase))
                            {
                                // The plugin is for a specific branch, and this isn't it
                                bForceDisabled = true;
                                Logger.LogDebug("GameFeaturePlugin {Name} was marked as restricted to other branches. Disabling.", PluginFile.GetFileNameWithoutExtension());
                            }
                            else
                            {
                                Logger.LogDebug("GameFeaturePlugin {Name} was marked as restricted to this branch. Leaving enabled.", PluginFile.GetFileNameWithoutExtension());
                            }
                        }

                        // Plugins can be marked as NeverBuild which overrides the above
                        bool bNeverBuild = false;
                        if (RawObject.TryGetBoolField("NeverBuild", out bNeverBuild) && bNeverBuild)
                        {
                            // This plugin was marked to never compile, so don't
                            bForceDisabled = true;
                            Logger.LogDebug("GameFeaturePlugin {Name} was marked as NeverBuild, disabling.", PluginFile.GetFileNameWithoutExtension());
                        }

                        // Keep track of plugin references for validation later
                        JsonObject[] PluginReferencesArray;
                        if (RawObject.TryGetObjectArrayField("Plugins", out PluginReferencesArray))
                        {
                            foreach (JsonObject ReferenceObject in PluginReferencesArray)
                            {
                                bool bRefEnabled = false;
                                if (ReferenceObject.TryGetBoolField("Enabled", out bRefEnabled) && bRefEnabled == true)
                                {
                                    string PluginReferenceName;
                                    if (ReferenceObject.TryGetStringField("Name", out PluginReferenceName))
                                    {
                                        string ReferencerName = PluginFile.GetFileNameWithoutExtension();
                                        if (!AllPluginReferencesByName.ContainsKey(ReferencerName))
                                        {
                                            AllPluginReferencesByName[ReferencerName] = new List<string>();
                                        }
                                        AllPluginReferencesByName[ReferencerName].Add(PluginReferenceName);
                                    }
                                }
                            }
                        }
                    }
                    catch (Exception ParseException)
                    {
                        Logger.LogWarning("Failed to parse GameFeaturePlugin file {Name}, disabling. Exception: {1}", PluginFile.GetFileNameWithoutExtension(), ParseException.Message);
                        bForceDisabled = true;
                    }

                    // Disabled has priority over enabled
                    if (bForceDisabled)
                    {
                        bEnabled = false;
                    }

                    // Print out the final decision for this plugin
                    Logger.LogDebug("ConfigureGameFeaturePlugins() has decided to {Action} feature {Name}", bEnabled ? "enable" : (bForceDisabled ? "disable" : "ignore"), PluginFile.GetFileNameWithoutExtension());

                    // Enable or disable it
                    if (bEnabled)
                    {
                        Target.EnablePlugins.Add(PluginFile.GetFileNameWithoutExtension());
                    }
                    else if (bForceDisabled)
                    {
                        Target.DisablePlugins.Add(PluginFile.GetFileNameWithoutExtension());
                    }
                }
            }

            // If you use something like a release version, consider doing a reference validation to make sure
            // that plugins with sooner release versions don't depend on content with later release versions
        }
    }
```

[Github Repo]: https://github.com/reforia/UnrealGeneratedDoc/blob/main/UnrealBuildTool.xml
[Giant Page]: https://dev.epicgames.com/documentation/en-us/unreal-engine/build-configuration-for-unreal-engine?application_version=5.5
[Config Documentation]: https://dev.epicgames.com/documentation/zh-CN/unreal-engine/configuration-files-in-unreal-engine?application_version=5.0