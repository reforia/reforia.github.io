---
layout: post
title: "Lyra Breakdown - 插件结构"
description:
  本文深入研究了Lyra中的插件，所以您就不用再遭罪了。这些插件已与相关文档一起整理编译，方便搜索。
date: 2025-05-08 1:18 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor-plugin-structure/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.5.4" %}

> 这是一系列关于我从Epic的Lyra项目中学到的知识笔记。该项目声称展示了当前虚幻引擎框架下的最佳实践。其中有些内容是我之前不了解的，有些则已经知晓，但认为仍然值得记录。
{: .prompt-info }

## 所有插件及分类
Lyra启用了大量插件，这些插件可分为若干组别，涵盖从后端到前端的全流程。其核心理念在于：所有插件都在不同程度上为实际项目功能服务，因此若不结合具体项目很难单独讨论。不过我们将进行全面梳理，以下是第一部分：

> 这里还有其他关于插件的文章：[Lyra's Plugins]、[UE5 Study]、[Zomg's Unreal Engine Notes] 和 [Standard Plugins]
{: .prompt-tip }

### 设置相关

<div class="box-info" markdown="1"> <div class="title"> GameSettings </div> 
来自[Lyra's Plugins]： "为项目中设置界面处理添加基类。
基于`CommonUI`的`ActivatableWidgets`构建，因此将使用该系统作为其基础界面类。

需注意所有设置数据均在C++中声明，这意味着设计人员在没有工程师协助的情况下无法扩展。"
</div>


### Editor Tools

<div class="box-info" markdown="1">
<div class="title"> ActorPalette </div>
该插件为编辑器添加新选项卡，可快速向关卡添加角色。本质上会打开新关卡，支持在不同关卡间拖放角色。

简易视频教程: https://www.youtube.com/watch?v=Ed2Ppnji4Tc
</div>

<div class="box-info" markdown="1">
<div class="title"> Lyra Ext Tool </div>
来自[Lyra's Plugins]： "添加`EUW_MaterialTool`，这是在Lyra材质编辑器中看似实用的编辑器控件。
同时添加BP函数`Change Mesh Materials`，该函数在网格体变更时显式调用`PostEditChange`。"
</div>


### 资产管理

<div class="box-info" markdown="1">
<div class="title"> AsyncMixin </div>
用于管理异步操作（如加载）的C++工具类。
</div>

<div class="box-info" markdown="1">
<div class="title"> DataRegistry </div>
虚幻引擎中管理数据资产的高级系统。允许创建数据资产注册表，并提供运行时查询和操作方式。这是对`DataTable`或`CurveTable`系统的升级，更接近数据库概念。

其最大优势在于`DataRegistry`以解耦方式通过统一API从任何可用资源获取数据。不再需要硬引用`DataTable`或`CurveTable`，只需使用`DataRegistry API`即可从任意来源同步/异步获取数据，甚至支持缓存。
</div>

<div class="box-info" markdown="1">
<div class="title"> AssetSearch </div>
该插件用于增强虚幻引擎的搜索功能。支持通过资产类型、名称、标签等多种条件搜索项目资源，甚至可搜索打印的常量字符串等参数。
</div>

<div class="box-info" markdown="1">
<div class="title"> AssetReferenceRestrictions </div>
用于阻止某些资产被其他资产引用的插件。可有效防止循环依赖或确保特定资产不在某些上下文中使用。例如`DLC`数据应引用基础游戏内容，但反之则不行。
</div>


### 几何工具

<div class="box-info" markdown="1">
<div class="title"> ModelingToolsEditorMode </div>
为虚幻引擎添加新编辑器模式，支持直接在编辑器中创建和操作3D模型。适用于无需离开编辑器即可创建自定义资产或修改现有资产。不过相比`Blender`或`Maya`等专业3D软件，该工具在控制和精度上有所欠缺，更像是原型工具而非生产工具。
</div>

<div class="box-info" markdown="1">
<div class="title"> GeometryScripting </div>
功能类似`Houdini`，可通过该插件实现程序化建模。也可用于运行时生成碰撞框或其他几何体。
</div>

### 渲染与图形
<div class="box-info" markdown="1">
<div class="title"> Volumetrics </div>
使用蓝图创建和渲染体积效果的工具库。

该插件提供`VolumetricCloudFunctions.ush`文件 
</div>

<div class="box-info" markdown="1">
<div class="title"> Niagara </div>
虚幻引擎中的VFX系统，用于创建复杂粒子效果和模拟。支持实时渲染粒子、流体等视觉效果。

官方文档: [Niagara]
</div>

<div class="box-info" markdown="1">
<div class="title"> Water </div>
用于创建逼真水面效果的插件。提供水物理模拟、反射、折射等水相关视觉效果工具。

官方文档：[Water]
</div>

### 动画系统

<div class="box-info" markdown="1">
<div class="title"> AnimationLocomotionLibrary </div>
提供距离匹配(DistanceMatching)和角色移动功能的蓝图函数库。

[Distance Maching] 文档展示了该库的实际应用案例。
</div>

<div class="box-info" markdown="1">
<div class="title"> AnimationWarping </div>
提供动画变形功能的工具库，包含方向变形(OrientationWarping)、坡度变形(SlopeWarping)、步幅变形(StrideWarping)等。
</div>

<div class="box-info" markdown="1">
<div class="title"> ContextualAnimation </div>
该插件实现了多角色动画在蒙太奇中的同步功能，可流畅制作处决技、坐下动作、扶墙动作等复杂互动动画。

推荐学习 [CAS Tutorial] 获取详细指导。
</div>


### 音频系统

<div class="box-info" markdown="1">
<div class="title"> Metasound </div>
无需赘述的知名复杂音频系统，Epic官方提供专属 [Metasound Documentation] 文档
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioModulation </div>
为引擎添加音频调制、控制总线(`Control Bus`)和混音总线功能，在概念上类似UE4的音频Ducking系统，但控制总线方案更灵活强大，操作体验接近`Wwise`等专业`DAW`。

入门推荐 [Audio Modulation Quick Start]
详细功能请参阅 [Audio Modulation Documentation]
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioGameplayVolume </div>
通过体积控件自动管理混响等音频特性的小型插件，替代传统蓝图/代码手动配置方案，已内置混响(`Reverb`)、子混音(`Submix`)、衰减(`Attennuation`)等功能。

相关文档 [Audio Gameplay Volume]
</div>

<div class="box-info" markdown="1">
<div class="title"> AudioGameplay </div>
类似`Gameplay Ability`的音频响应系统，使音频组件能根据游戏事件（如进入区域、交互行为、生命值变化等）触发特定音频逻辑。
</div>

<div class="box-info" markdown="1">
<div class="title"> SoundUtilities </div>
音频工具库，提供`GetQFromBandwidth`（通过带宽获取Q值）、`ConvertDecibelsToLinear`（分贝转线性值）、`GetFrequencyFromMIDPitch`（MIDI音高转频率）、`GetBeatTemp`（获取节拍速度）等功能。
</div>

<div class="box-info" markdown="1">
<div class="title"> Spatialization </div>
提供处理ITD（双耳时间差）空间化的`FSourceSpatializer`结构和`FITDSpatialization`类。
</div>

### 影视系统

<div class="box-info" markdown="1">
<div class="title"> MovieRenderPipeline </div>
虚幻引擎的离线渲染框架，专为电影、过场动画等线性内容的高质量渲染设计，提供专业级图像/视频输出工具。

官方文档：[Movie Render Pipeline]
</div>

<div class="box-info" markdown="1">
<div class="title"> MoviePipelineMaskRenderPass </div>
为电影渲染管线扩展渲染通道，新增`MoviePiplelineObjectIdPass`（对象ID通道）和`MoviePiplelinePanoramicPass`（全景通道）功能。 
</div>


### UI

<div class="box-info" markdown="1">
<div class="title"> CommonUI </div>
革命性UI解决方案，在UMG基础上全面革新，有效解决传统游戏UI痛点。网络有丰富学习资源。

官方文档：[CommonUI Plugin]
</div>

<div class="box-info" markdown="1">
<div class="title"> CommonLoadingScreen </div>
来自 [Lyra's Plugins]:
"提供加载屏幕的基类与设置框架"

包含`CommonStartupLoadingScreen`和`CommonLoadingScreen`模块，自动处理加载期间输入锁定，支持隐藏流式加载场景。通过逐帧查询从关卡到游戏状态，再到所有实现`ILoadingProcessInterface`的游戏对象，动态判断是否需要显示加载界面。
</div>

<div class="box-info" markdown="1">
<div class="title"> GameSubtitles </div>
来自 [Lyra's Plugins]:
"提供字幕显示子系统"

也支持将游戏字幕控件绑定至媒体播放器(Media Player)。
</div>

<div class="box-info" markdown="1">
<div class="title"> UIExtension </div>
来自 [Lyra's Plugins]:
""UI扩展系统概述: https://x157.github.io/UE5/UIExtension/

建立扩展点游戏标签(Extension Point Gameplay Tag)与可激活控件的映射关系。

通过扩展点即可访问所需控件，并按照父级布局自动整合到`HUD`中。例如：根据加载的游戏特性插件(`Game Feature Plugin`)类型，在`HUD`相同位置动态加载不同的得分控件。"

类似于HUD像一个港口，决定了布局与扩展点，而真正的UI通过挂载在对应的扩展点上来实现。
</div>


### 输入

<div class="box-info" markdown="1">
<div class="title"> EnhancedInput </div>
同样是一个著名的新系统，用于取代UE4中的旧输入系统。无需过多介绍。

官方文档：[Enhanced Input]
</div>

<div class="box-info" markdown="1">
<div class="title"> WinDualShock </div>
一个用于在`Windows`上检测`DualShock`控制器输入的插件。

虽然我不太确定为什么不直接使用`RawInput`插件。[Raw Input Documentation]可以在这里找到。
</div>


### 网络

<div class="box-info" markdown="1">
<div class="title"> ReplicationGraph </div>
一个新的网络同步系统，允许更精细地控制网络中数据的同步内容和方式。它利用复制图节点来确定哪些数据复制给哪些客户端，并缓存数据以实现更高效、可扩展的同步机制。借助此插件，FNBR可以支持100多名玩家和50000个同步Actor的会话，而不会挤爆网络和CPU的负担。

官方文档：[Replication Grpah]

官方直播：[Replication Graph Live Stream]
</div>

<div class="box-info" markdown="1">
<div class="title"> AESGCMHandlerComponent </div>
一个使用AES-GCM算法加密和解密网络数据包的组件。用于保护客户端和服务器之间的网络通信，确保数据传输安全，不会被恶意攻击者拦截或篡改。
</div>

<div class="box-info" markdown="1">
<div class="title"> DTLSHandlerComponent </div>
另一个用于加密网络的组件，但它不是针对单个数据包，而是使用DTLS（数据报传输层安全）协议保护整个网络连接。用于在客户端和服务器之间建立安全连接，确保所有传输的数据都经过加密和保护。
</div>

<div class="box-info" markdown="1">
<div class="title"> SteamSockets </div>
一个支持新版SteamSockets API的插件，这是在Unreal Engine中处理网络通信的更高效、更灵活的方式。

官方文档：[SteamSockets Documentation]

教程：[SteamSockets Tutorial]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineFramework </div>
顾名思义，该框架为在线游戏服务提供了一个标准的共享点。模块包括`HotFix`、`Lobby`、`LoginFlow`、`Party`、`PatchCheck`、`PlayTimeLimit`、`Qos`、`Rejoin`。

关于此模块的在线资料不多，我们需要自己深入研究代码，看看它在Lyra中是如何实现的。
</div>

<div class="box-info" markdown="1">
<div class="title"> PlayFabParty </div>
支持Microsoft Azure PlayFab Party SDK。与其他OSS不同，它更像是一个VOIP解决方案。

相关Github仓库：[PlayFabMultiplayerUnreal]

PlayFab OSS：[PlayFab OSS]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineSubsystemSteam </div>
支持`Steam OSS`。`OSS`本质上是一个抽象层，与第三方`SDK`（这里是Steam）协作，以便在Steam上正确分发游戏，并与`Steam SDK`的会话、认证功能挂钩。
需要区分`OnlineSubsystem Plugin`、`OnlineServices Plugin`和`OnlineServices`。`OnlineSubsystemPlugin`是Unreal的概念，封装了与引擎无关的第三方`OnlineServices SDK`。例如，`Steam Online Service`并不关心游戏是用哪个引擎制作的。而`OnlineServices Plugin`是UE5中新的抽象层，旨在取代旧的`OnlineSubsystem Plugin`。

官方文档：[Online Subsystem]

Steam OSS官方文档：[Online Subsystem Steam]

教程：[UE Online Subsystem Steam Tutorial]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineSubsystemEOS </div>
类似于Steam OSS，但服务提供商是EOS。

EOS OSS官方文档：[Online Subsystem EOS]

教程：[EOS OSS Tutorial]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesEOS </div>
 新的`OnlineServices`插件，旨在取代旧的`OnlineSubsystem`插件。它提供了更现代、更灵活的方式来处理Unreal Engine中的在线服务，便于与第三方服务集成，并更好地支持跨平台游戏。

官方文档：[Online Service EOS]
, [Online Sevice Overview]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesNull </div>
基本上是一个开发用的OS插件，没有真实的后端，而是模拟的。

教程：[Setup and Configure Online Services] and [Structure and Implement the Online Services Plugins]
</div>

<div class="box-info" markdown="1">
<div class="title"> OnlineServicesOSSAdapter </div>
一个兼容层，允许新的`OnlineServices`插件与旧的`OnlineSubsystem`插件协同工作。这对于正在从旧系统过渡到新系统的项目非常有用，因为它可以继续使用现有代码和资源，同时利用`OnlineServices`插件的新功能和改进。
</div>


### Gameplay
这是一个非常庞大的主题。在深入探讨任何插件之前，Epic 提供了一份优秀的文档帮助我们理解UE5中玩法框架的核心概念。[Making Interactive Experiences]

<div class="box-info" markdown="1">
<div class="title"> ModularGameplay </div>
玩法功能的基础框架，提供基类和子系统以支持玩法框架的模块化使用。例如支持在运行时动态注入组件到游戏中。
</div>

<div class="box-info" markdown="1">
<div class="title"> GameFeatures </div>
这是 UE5 实现模块化游戏功能的方式。它允许我们以模块化的方式创建和管理游戏功能，便于在不影响游戏其他部分的情况下添加、移除或修改功能。
</div>

<div class="box-info" markdown="1">
<div class="title"> ModularGameplayActors </div>
来自 [Lyra's Plugins]:
"提供基类，使得游戏功能插件能够在运行时加载组件、控件等。
Lyra 的所有基类本身都基于 Modular Gameplay Actors。"

模块化玩法插件概述：https://x157.github.io/UE5/ModularGameplay/
</div>

<div class="box-info" markdown="1">
<div class="title"> CommonGame </div>
来自 [Lyra's Plugins]:
"添加了一个系统，用于将 `CommonUI` 的可激活控件容器作为‘层级’使用，并提供将控件推送到特定层级的功能。
这有助于将 `HUD` 放在一个层级，而将设置菜单或暂停菜单推送到其上的另一个层级。

同时也便于使用手柄导航 `UI` 菜单，因为它们都是通过 `CommonUI` 可激活控件在不同容器层级中构建的。"
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayInteractions </div>
一个用于处理玩家和 AI 与世界交互的框架。尽管这是该插件的描述，但目前似乎仅支持 NPC AI的交互，大量代码与 `StateTree` 相关。
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayBehaviors </div>
根据 `uplugin` 描述："为 AI 代理封装的即发即弃行为"。从实际代码来看，它似乎是对行为树系统的封装，将黑板值与游戏标签（Gameplay Tags）结合使用。
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayBehaviorSmartObjects </div>
提供了一些 API 支持，用于通过 `Gameplay Behaviors` 与智能对象（`Smart Objects`）交互。
</div>

<div class="box-info" markdown="1">
<div class="title"> SmartObjects </div>
该插件提供了一套在虚幻引擎中创建和管理智能对象的系统。智能对象是可供 `AI` 代理使用的交互对象，用于执行特定动作或行为，比如找一个凳子坐下。插件提供了一系列工具和功能，用于在游戏中创建、管理和使用智能对象。

官方文档：[Smart Objects]
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayStateTree </div>
`State Tree` 是虚幻引擎中用于管理任何需要状态切换（目前主要用于 AI）的新系统。它简化了我们手动管理状态机的流程，并提供了一种统一的方式来处理状态转换、动作和条件。

官方文档：[State Tree]
</div>


<div class="box-info" markdown="1">
<div class="title"> GameplayAbilities </div>
`GAS`（`Gameplay Ability System`）是一个无需在此赘述的庞大主题。它是互联网上讨论和文档最多的系统之一，也是 `UE5` 中实现游戏交互的首选方式。

官方文档：[GAS]
社区文档：[GAS Community Docs]
</div>

<div class="box-info" markdown="1">
<div class="title"> GameplayMessageRouter </div>
来自 [Lyra's Plugins]:
"添加了一个系统，允许你通过游戏标签（`Gameplay Tag`）在游戏中广播和接收事件，并可选择附带包含事件数据的自定义结构体。
例如，如果你击杀了一个角色，可以广播一个特定标签下的事件，提供被击杀者的名称，而 UI 控件可以接收该事件以显示击杀信息。

这些事件仅限于本地玩家，是对 `Gameplay Ability System` 的 `Gameplay Event`（通过网络复制）的很好补充。这两个系统大致类似，`Gameplay Message Subsystem` 仅限本地客户端范围，而 `Gameplay Event` 则具有网络客户端范围。"
</div>

<div class="box-info" markdown="1"> <div class="title"> CommonConversation </div>
一个围绕`Gameplay Tags`和数据资产构建的模块化框架，用于管理游戏中的分支对话和会话。
它设计用于支持线性和分支对话树，允许 NPC 和玩家交换消息、做出选择并根据游戏状态做出响应。对话可以完全通过资产定义，使设计师无需编写代码即可编辑。
</div>

<div class="box-info" markdown="1"> <div class="title"> ControlFlows </div> 
该插件提供了一种模块化和声明式的方式在代码中定义流程任务。比如定义一个登录流程，或者加载一系列关卡内容等。

教程链接：[ControlFlows Tutorial]
</div>

### 认证系统

<div class="box-info" markdown="1">
<div class="title"> CommonUser </div>
来自 [Lyra's Plugins]:
"`CommonUser` 插件在 C++、蓝图脚本和 [Online Subsystem]（OSS）或其他在线后端之间提供了一个通用接口。它是一个独立的插件，可用于任何项目。

官方文档：[Common User Plugin]

提供 `Common User Subsystem`、`Common Session Subsystem` 以及一个` Common User Initialize` 异步操作。"
</div>


### QC
这里的插件对自动化测试非常有用，文档参见[Automation System Overview]。它们能让我们快速创建并运行单元测试。

<div class="box-info" markdown="1">
<div class="title"> FunctionalTestingEditor </div>
一个测试框架，允许我们在虚幻引擎中创建和运行功能测试。它提供了一套工具和功能，用于在游戏中创建、管理和运行测试。

官方文档：[Functional Testing]
</div>

<div class="box-info" markdown="1">
<div class="title"> RuntimeTests </div>
一个允许我们在运行时（无论是在编辑器还是打包版本中）执行测试的框架。
目前没有官方文档，因此最好直接阅读代码。我们会在分析Lyra实现时详细介绍它。
</div>

<div class="box-info" markdown="1">
<div class="title"> Gauntlet </div>
这是另一个可以运行测试的自动化测试框架。不同之处在于，Gauntlet的目标更宏观——它并非专注于为测试特定游戏功能构建框架，而是管理整个`Unreal Session`。例如，在需要运行4个客户端和1个服务器的多人游戏测试中，Gauntlet会获取正确的构建版本、启动所需进程、运行测试、等待会话结束，最后汇报结果。

官方文档：[Gauntlet], [Run Gauntlet Tests], [Gauntlet Primer]
</div>


### 性能

<div class="box-info" markdown="1"> <div class="title"> GameplayInsights </div> 来自 [Lyra's Plugins]: "`GameplayInsights`是一款强大的性能分析工具，可帮助分析和可视化与游戏玩法相关的数据，如复制、网络流量、技能使用情况等。

它与`Unreal`的`Trace`系统集成，提供时间线、事件追踪和统计跟踪功能，用于诊断游戏过程中的性能和逻辑问题。Lyra利用此工具来测量技能激活和消息路由性能。"
</div>

<div class="box-info" markdown="1">
<div class="title"> D3DExternalGPUStatistics </div>
`未知插件`，该插件在Lyra中启用，但既不存在于Unreal原生插件中，也不存在于Lyra项目中，可能是Epic内部用于追踪EGPU统计数据的插件。
</div>

<div class="box-info" markdown="1">
<div class="title"> SignificanceManager </div>
这是一个框架，用于基于场景中`Actor`的重要性（如某些小型VFX在重要性分数低于阈值时会停止播放）提供更精细的流式加载或其他自定义优化控制。

它允许我们根据`Actor`与摄像机的距离、可见性等因素定义和管理其重要性，从而通过减少需要渲染或更新的`Actor`数量来提升性能。

官方文档：[Significance Manager]
</div>

<div class="box-info" markdown="1">
<div class="title"> PocketWorlds </div>
来自 [Lyra's Plugins]:

“此插件简化了关卡流式加载。

它设计为一种更简洁、紧凑的解决方案，替代传统在菜单中渲染3D角色的方法（传统方法通常需要加载正常游戏边界外的地图）。

优秀的Pocket Worlds示例和文档:
https://gitlab.com/IsmaFilo/pocketworldexample"
</div>

## 项目结构
项目可以进一步划分为更多模块。在后续文章中深入探讨之前，我们先整体浏览它们。（标注为‘Separate’的类别表示它们或多或少是Lyra核心架构的扩展。即使没有这些模块，项目仍可编译，但它们对实际游戏内容至关重要。）

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