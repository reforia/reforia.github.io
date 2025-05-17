---
layout: post
title: "Lyra技术解析 - 核心音频"
description:
  音频的本质是信号，音频调制的本质是信号处理。
date: 2025-05-11 20:50 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-game-core-audio/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.5.4" %}

{% include ue_engine_post_disclaimer.html %}

> 这是一系列关于我从Epic的Lyra项目中学到的知识笔记。该项目声称展示了当前虚幻引擎框架下的最佳实践。其中有些内容是我之前不了解的，有些则已经知晓，但认为仍然值得记录。
{: .prompt-info }

> 我并不是音频专家，所以这篇文章更多是我从Lyra项目中学习到的内容总结，主要是为了加深自己的理解。某些地方很可能有误，请谨慎参考。
{: .prompt-warning }

## Unreal 5中的音频结构
与我们在UE4中常见的音频系统不同，UE4只有一些基础功能，比如`sound cues`、`sound class`es和`sound mix`，并没有真正的`DSP`图。大部分复杂的音频处理都是通过事件发送到其他音频引擎（如`Wwise`、`FMOD`等）来完成的。而在UE5中，全新的音频引擎是内置的，并且拥有一个完整的`DSP`图，称为`MetaSound`。音频系统变得更加灵活和强大，能够实现复杂的音频处理和操作。

音频信号的整体流程如下：
- `Sound Source` 生成干声信号
  - `Sound Wave`、`Sound Cue`、`MetaSound`等会产生原始音频信号
- 混音系统将干声信号混合为湿声信号
  - `Sound Class`、`Sound Mix`、`MetaSound Patch`完成第一阶段的处理，通常我们会将音频资源分到不同的类别，然后类别会映射到`Submix`类
  - `Submix`、`Submix Effect Chains`等决定音频信号如何被处理和混合
- 调制
  - `Control Bus`、`Control Bus Mix`、`Parameter Patch`用于调制我们已经混合好的湿声信号
- 输出到输出设备
  - 最终，`Main Submix`会将最终音频信号输出到输出设备，比如扬声器或耳机


## 声音源（Sound Source）
声音源是音频信号的起点。在Lyra中有三种类型的声音源：
- `SoundWave`: 最基础的声音源，是原始音频文件，存储为16位`WAV`格式。可以直接播放，但没有任何处理或操作
- `SoundCue`: 更高级的声音源，是多个`SoundWave`资源的容器。可以实现更复杂的音频处理，比如随机、循环、淡入淡出等。
- `MetaSound Source`: 最先进的声音源，是一个完全可编程的音频引擎，允许实现复杂的音频处理。可以用来创建自定义音效，比如混响、延迟、失真等。

这里还有一点：

### MetaSounds Patch
`MetaSound Source`可以包含很多节点，很像材质编辑器的图表。作为一个完整的DSP引擎，可以对音频信号做大量逻辑处理。因此，把一些常用逻辑预设为“库”，需要时直接插入图表是很自然的做法。这就是`MetaSound Patch`的作用——它是可以在不同`MetaSound Source`中复用的节点集合，有点类似于音频处理的函数库。

`Lyra`中现有的`MetaSound Patch`包括：
- `lib_StereoBalance`
  - 有一个`StereoPanner`节点，可以将音频信号左右声道平衡
- `lib_DovetailClip`
  - 将新音频信号与正在播放的音频进行混合处理，最终通过立体声平衡节点输出
  - 这也意味着：`metasound`节点与材质节点不同，它具有状态存储功能。只要`metasound`存在，节点就会持续维护内存中的变量状态
- `lib_DovetailClipFromArray`
  - 支持从数组中选择音频波形，并应用`DovetailClip`效果
- `lib_RandInterpTo`
  - 渐进式插值过渡到一个随机值
- `lib_RandPanStereo`
  - 为左右声道分别生成随机声像定位值
- `lib_TriggerAfter`
  - 在计数达到n次后触发一次
- `lib_TriggerEvery`
  - 每n次计数触发，但仅在首次计数时返回true。例如设置重置计数为4时：
    - true（计数=1）
    - false（计数=2）
    - false（计数=3）
    - false（计数=4）
    - true（计数=1，因已重置）
    - 以此类推
  - 注意计数值与实际数值不同。假设使用初始值0、步长1的计数器：
    - 数值=0（计数1）
    - 数值=1（计数2）
    - 数值=2（计数3）
    - 数值=3（计数4，触发重置）
    - 数值=0（计数1）
    - ...
- `lib_TriggerModulo`
  - 当计数器数值达到设定值n的模时为true
- `lib_TriggerStopAfter`
  - 仅在n次计数内触发，超过后停止（如n=4时仅触发4次）
- `lib_Whizby`
  - 模拟子弹近距离飞过的呼啸声效果。触发时随机播放带音高变化的接近音效，延迟片刻后播放随机选择的远离音效
- `MS_Graph_RandomPitch_Stereo`
  - 为输入音频波形添加随机音高变化后输出立体声
- `MS_Graph_TriggerDelayPitchShift_Mono`
  - 为输入音频波形添加随机延迟和音高变化后输出单声道
- `mx_PlayAmbientElement`
  - 从指定数组随机选择环境音效，添加初始延迟后经立体声平衡输出
- `mx_PlayAmbientChord`
  - 混合两个`mx_PlayAmbientElement`的输出（是的直接相加，根据相位关系会产生音量增减）
- `mx_Stingers`
  - 当音乐系统中触发`OnStingerPositive`时，会暴力混合5种类型的音效：
    - bass 贝斯
    - perc-deep 重型打击乐
    - perc-light 轻型打击乐
    - short-pad 短垫音
    - wet-lead 主奏湿音
- `sfx_BaseLayer_Interactable_Pad_nl_meta`
  - 仅是`sfx_Random_nl_meta`的封装。你可能会问为何不直接让后者成为预设模块？别问我，问Epic
  - `sfx_Random_nl_meta`会按配置权重和增益播放数组中的随机音效
  - 调用此节点会触发代码断言提示库已损坏...显然不是最佳实践

## Mixing
理清音源后，接下来是混音环节。混音本质是将多个音频信号合并为单一输出，但实际远不止简单相加（`MixAB = A + B`），而是通过`MixAB = f(A) + f(B)`实现。这个过程包括对原始信号施加混响、包络、均衡器、高低通滤波等处理生成`f(x)`，再以和谐方式组合——这正是混音既耗时又复杂的原因。

虽然大部分混音功能可通过`metasound`的`DSP`图表实现，但还有几个辅助系统：

### Sound Class
这是UE4遗留功能，音源通常会被分配到特定类别（如音乐类、音效类等）。在UE4中主要配合`Sound Mix`实现被动`Ducking`（即根据B通道音量自动降低A通道音量，如播放音效时压低背景音乐）。UE5中仍支持此功能，但新增了两个更强大的特性：
- 将信号发送到`Submix`
- 动态调制信号

本节先聚焦`Submix`功能

> 注意：使用被动`Ducking`的`Sound Mix`会直接修改原始信号。这意味着`Sound Mix`优先级高于`Submix`——如果已通过`Sound Mix`将音量降至`-60`分贝，此时即使发送`100%`信号到`Submix`，接收到的也只是近乎无声的平直信号
{: .prompt-info }

### Submix
`Submix` 是一种信号处理概念。想象一下，我们有武器音效、脚步声、环境声和音乐的原文件——它们通常只是原始的 `wav` 文件，随后会被封装到 `SoundCue` 或 `metasound` 类中进行单独处理（即“逐音效处理”）。但如果我们能将这些音效分组，并为它们统一添加共享效果（比如 `EQ` 或其它全局处理），会非常有用。这就是 `Submix` 的用武之地：任何音源或音效类别都可以部分或全部发送到某个 `Submix`，而该 `Submix` 会应用一条 `SubmixEffectChain` 效果链。不同的 `Submix` 可以协同运作，最终汇入 `MainSubmix` 并输出。

需要注意的是，`Submix` 仅处理原始信号的副本。例如，如果有一段音乐正在播放，我们将其 `100%` 发送到一个 `Mute Submix`，它仍然能被听到——因为我们听到的是原始音乐与“无声”混合的结果，本质上仍是原音。

这种反直觉的行为可能导致问题，因此通常我们会选择只输出处理后的湿信号（`wet signal`），同时静音所有干信号（`dry sound`）。（具体取决于项目需求，有时也会将部分干音发送到混响中。）但在 `Lyra` 中，所有干信号均被静音。

![submix_mute_dry](submix_mute_dry.png){: .width="700"}

如前所述，我们也可以将部分干信号发送到 Submix。比如发送 `0.2` 表示取原始波形信号振幅的 `20%`，对其应用 `EQ` 等效果，最终在播放时混合。

![Submix Details](submix_details.png){: .width="700"}

### FLyraSubmixEffectChainMap
这里需要稍微涉及源码：这个结构体将 `Submix` 类与 `USoundEffectSubmixPreset` 绑定，便于定义每个 `Submix` 应应用哪些预设效果。之所以称为 `SubmixEffectChain`（效果链），是因为它是一个数组，意味着单个 `Submix` 可以叠加多个效果（如 `EQ`、`LPF` 等）。

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

### HDR 与 LDR
以 `HDR`（高动态范围）和 `LDR`（低动态范围）为例：玩家的音频输出设备可能千差万别（高端设备、廉价设备、耳机或电视），且个人偏好或夜间模式等需求各异。为此，`AudioSettings` 类提供了 `HDRAudioSubmixEffectChain` 和 `LDRAudioSubmixEffectChain` 两个属性（均为 `FLyraSubmixEffectChainMap` 数组），并需要一套机制让玩家通过设置 `UI` 切换。

实现逻辑分为两部分：
- 用户配置：提供 `UI` 让玩家选择 `HDR` 或 `LDR` 输出模式。
- 音频处理：对所有音效应用对应的“后处理”效果链（`SubmixEffectChain`）。

第二部分正是通过动态操作 `Submix` 实现的。

### 动态 Submix 效果
但问题来了：既然 `Submix` 本身可直接配置 `SubmixEffectChain`，为何还要封装成 `FLyraSubmixEffectChainMap`？

答案在于：该结构体实际仅用于 `HDRAudioSubmixEffectChain` 和 `LDRAudioSubmixEffectChain`，其他 `Submix` 的效果链是直接在资产中静态配置的。

![HDR and LDR submix](hdr_ldr_submix.png){: width="800" }

如上图所示，只有 `MainSubmix` 会进一步动态处理——因为 `HDR/LDR` 的选择是运行时决定的。

### HDR 效果
HDR 效果属于压缩器类型，其逻辑如下：
- 输入增益：降低 `10db` 以预留动态余量。
- 阈值：当信号超过 `-6db` 时触发压缩器，采用 `6:1` 压缩比（输入每增加 `6db`，输出仅增加 `1db`）。
- 平滑处理：通过 `Knee` 参数使阈值附近过渡自然，`Lookahead` 则通过短暂延迟预判信号以避免突变。
- 侧链(`SideChain`)输入：当侧链信号超过阈值时，可对当前输出实施增益或截断（类似`Ducking`效果）。

这种设计旨在保留尽可能多的动态范围，仅平滑压制过响部分，适合追求电影化体验的场景。

![HDR Effect](hdr_effect.png){: width="800" }

当声音作为输入增益降低`10db`后，系统会使用平均模式检测峰值音量（获取左右声道输入的平均值）。在绕过`-6db`阈值后，我们将应用`6:1`的压缩比，这意味着输入源每增加`6db`，输出源仅增加`1db`。如果这种处理让声音听起来被截断得太生硬，这时候`knee`（软拐点）和`lookahead`（预判）功能就派上用场了——`lookahead`能让我们稍微延迟声音信号，从而监测"未来"的信号并提前处理；而`knee`则意味着虽然我们以`-6db`作为阈值，但在`+-knee`的数值范围内，压缩器会渐进式地介入，让过渡更平滑。

和常规包络效果器类似，压缩器也有启动时间（`attack`）和释放时间（`release`）。它还具有侧链输入功能——当侧链输入信号超过阈值时，系统会对当前输出信号进行增益或截断处理，就像闪避效果（`ducking effect`）那样。

### LDR 效果
与`HDR`非常相似，但这次是限制器（`limiter`）类型，意味着当声音超过阈值时会直接截断。背后的逻辑是：我们要不惜一切代价确保声音不超过特定电平，避免削波（`clip`）或失真。虽然有时会让声音听起来略显平淡，但目的是尽可能保持声音干净一致。通常用于电视或扬声器系统场景。

![LDR Effect](ldr_effect.png){: width="800" }

### 可用子混音系统
![Sound Submix Structure](submix_structure.png){: width="800" }

上图是`Lyra`中的子混音结构，所有`Submix`最终都会路由到`MainSubmix`：
- `UISubmix`
- `SFXSubmix`
- `MusicSubmix`
- `SendEffectSubmix`
- `ReverbSubmix`
- `VoiceSubmix`
- `EarlyReflectionSubmix`

### 声音衰减
声音衰减（Sound Attenuation）用于模拟声音在环境中的传播特性，可表现声源的距离和方向变化，也能模拟墙壁等障碍物对声音的影响。

`Sound Cue`或`Meta Sound`音源会引用`Sound Attenuation Presets`（声音衰减预设）

#### Attenuation Presets
衰减预设通常包含以下参数：
- `Volume`
  - 声音随距离增加而衰减的曲线
- `Spatialization`
  - 通过左右声道平衡实现3D空间中的声源定位
- `Air Absorption`
  - 根据距离和声音频率，高频部分会被空气更多吸收
- `Focus`
  - 摄像机焦点内的声音会有更高优先级和突出表现
- `Reverb`
  - 受环境混响影响（如房间尺寸/形状、墙面材质等）
- `Occlusion`
  - 受墙壁等障碍物遮挡影响，材质吸收会导致高频衰减
- `Priority`
  - 决定声音在环境中与其他音源的混合权重
- `Submix`
  - 可将声音发送到指定`Submix`进行后续处理

#### ITD 声源空间化设置
`Attenuation Presets`可以引用`ITD`空间化设置，这是通过声源距离和方向来控制声道平衡算法的进阶方案。可用于模拟3D空间中的移动声源（如车辆经过或人物走动）。

![ITD_settings](itd_settings.png){: width="700" }

### Concurrency 并发控制
`Sound Source`可引用`Concurrency Settings`来控制同时播放的音源数量，超限时会切断某些声音。适合模拟人群或繁忙街道等多声源场景。

![concurrency](concurrency.png){: width="700" }

默认策略是最远优先→最早优先，即优先切断距离最远的声源，距离相同时则切断最早播放的声音。其他策略包括:
- 阻止新增
- 停止最早
- 最远优先→阻止新增
- 最低优先级
- 最弱音量
- 最低优先级→阻止新增

### Effects
`Lyra` 内置了几种音频特效，它们都属于 `SubmixEffect` 类型，用于 `Submix` 中的 `SubmixEffectChain`。这些特效可以对音频信号进行处理，比如添加 混响（`reverb`）、延迟（`delay`） 或 失真（`distortion`），从而在游戏中营造特定的氛围或增强沉浸感。

#### 卷积混响（Convolution Reverb）
`Convolution Reverb` 是一种高级混响效果，它使用 `IR`（脉冲响应） 资源。这种资源由 `WAV` 文件生成，通过分析录制的"啪"声波形，捕捉空间特征（包括材质、早期反射、能量空气吸收等），从而指导输入声源模拟出该空间中的声音行为。

官方文档：[Convolution Reverb]

不过有趣的是，`Lyra` 虽然将 `Convolution Reverb` 用在 `ReverbSubmix` 中，但这个子混音并未被实际调用。或许它是为游戏功能插件（`Game Feature plugins`）预留的内容。

#### 创建脉冲响应（Audio Impulse Response）
新建 `Audio Impulse Response` 资源很简单：在内容浏览器中右键点击录制好的 `WAV` 文件，选择 `Create Audio Impulse Response` 即可自动生成。

注意：`WAV`文件必须是立体声，且理想情况下是1-2秒的"啪"声。文件需要包含清晰的全能量峰值，随后衰减至静默——这些信息将用于计算混响的脉冲响应。

![Create IR](create_ir_asset.png){: width="700" }

#### 动态处理（Dynamics Process）
这部分内容已在 `HDR` 和 `LDR` 章节中涵盖。

#### 滤波器特效（Effect Filter）
滤波器特效用于根据特定频率范围处理音频信号。

![Effect Filter](effect_filter.png)

可选类型包括：
- 低通滤波（low pass）
  - 允许低频通过，截断高频。适合制造闷响或低沉隆隆声
- 高通滤波（high pass）
  - 允许高频通过，截断低频。适合制造明亮或尖锐音效
- 带通滤波（band pass）
  - 仅允许特定频段通过。适合制造特殊音效或共振效果
- 带阻滤波（band stop）
  - 截断特定频段，允许其他频率通过。用途与带通滤波类似

#### 分拍延迟（Effect Tap Delay）
分拍延迟特效可为音频信号添加延迟效果，用于制造回声或混响。`Lyra` 在 `TAP_EarlyReflection` 中配置了8个分拍（默认静音），`WeaponAudioFunctions` 会根据射击事件的射线检测结果动态更新这些分拍值。

### 早期反射（Early Reflection）
`Lyra` 使用 `SubmixEffectTapDelay` 和 `SubmixEffectFilter` 构建早期反射系统。早期反射是指声音经短延迟后到达听者的现象，能增强空间纵深感。每次开火时，系统会发射一系列射线（含若干反弹射线），根据射线传播距离和能量吸收判定空间特征。

![EarlyReflection](submix_effect_chain_in_submix.png){: width="800" }

两个滤波器的参数设置为：
- 高通截止频率 = 300Hz
- 低通截止频率 = 10000Hz

相当于将声音限制在 `300Hz` 至 `10kHz` 的人声频率范围内。

![Early Reflections](early_reflection_submix.png){: width="700" }

#### 多频段压缩器（Multiband Compressor）
项目中还存在一个未被引用的 `low multiband compressor`，它可以根据不同频段压缩音频信号。这个 多频段压缩器 包含4个频段（`2.5kHz` 至 `20kHz`），每个频段可独立设置 阈值（`threshold`）、压缩比（`ratio`）、启动时间（`attack`） 和 释放时间（`release`）。

![multiband compressor](multiband_compressor.png)

## 调制系统（Modulation）
现在正好可以回顾已学内容。整个音频流程可简述为：
- 用 `sound class` 对声音分类（如 `music`、`sfx`、`footsteps` 等）
- 通过 `sound mix` 实现被动`Ducking`（Unreal 4的传统方案，`Lyra`未实际使用）
- 将声音发送至 `Submix` 进行深度处理
- 每个声音的音量由 参数补丁类（`Parameter Patch`, `PP`） 进一步调制
- `PP` 类会将多个 `Control Bus` 的输入值相乘，输出最终值供 `sound class` 读取
- `Control Bus` 本质是包含参数的调音台推子，关键问题在于：谁在操控这些推子？
- 操控方式多样：可直接通过 `C++` 或 蓝图 修改单个 `Control Bus`；若需要根据场景（如Boss战）批量控制多个总线，则可使用 `Control Bus Mix`（同样支持代码/蓝图激活）

#### 控制总线（Control Bus）
`Control Bus` 并不复杂，它是一个包含参数的类，可用于调制音频信号的 音量、音高 等属性。

![Control Bus](control_bus.png){: width="700" }

#### 控制总线混音（Control Bus Mix）
正如前文所述，`Control Bus Mix` 是一组针对控制总线的操作集合，用于同时调控多个 `Control Bus`。但要注意：设置混音后仍可单独调整总线值，两种调控方式可以共存。

![Control Bus Mix](control_bus_mix.png){: width="700" }

#### 参数补丁（Parameter Patch）
不同混音之间的关系由 `Parameter Patch` 控制，这个类包含一组 `Control Bus` 和一组参数。例如：
- 用 `PP_Music` 混合 `CB_Main`（主音量）和 `CB_Music`（音乐音量）
- 用户既能在设置中调节主音量，也可单独调整音乐音量
- 可以将 `CBM` 视为总控面板，调节时会按比例影响所有关联总线值
- 而单个 `Control Bus` 则用于精确控制特定参数

![Paremeter Patch](parameter_patch.png){: width="700" }

## 音频设置（AudioSettings）
让我们回到源码分析。查看 `AudioSettings` 类会发现，它只有有意义的头文件，`cpp` 文件是空的。这个文件本身很简单，且大部分技巧已在先前文章中介绍过，简单回顾：

- 设置类需继承 `UDeveloperSettings` 才能被引擎自动发现
- 类元标记 `config = Game, default config, meta = (DisplayName = "LyraAudioSettings")` 表示：
  - 类内容将保存在 D`efaultGame.ini` 配置文件的 `LyraAudioSettings` 章节
- 属性元标记 `config, EditAnywhere, Category = MixSettings, meta = (AllowedClasses = "/Script/AudioModulation.SoundControlBusMix")`表示：
  - 属性会存入上述配置文件
  - 可在原型或实例上编辑
  - 归入 `MixSetting` 分类
  - 仅接受 `AudioModulation` 插件的 `SoundControlBusMix` 类

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

## 可用设置项
Lyra当前支持的设置包括:
- `DefaultControlBusMix`
- `LoadingScreenControlBusMix`
- `UserSettingsControlBusMix`
- `OverallVolumeControlBus`
- `MusicVolumeControlBus`
- `SoundFXVolumeControlBus`
- `DialogueVolumeControlBus`
- `VoiceChatVolumeControlBus`

## 应用场景
我们已经深入了解了音频系统，现在只剩下几个零散的子系统。

> 没有比系统原作者更好的解释方式了 [Lyra Audio System]
{: .prompt-info }

### 音乐管理组件（Music Manager Component）
[Lyra Audio System] 已详细解释了音乐系统。它位于名为 `mx_system` 的元声音类中，被封装成组件以便不同游戏功能（如触发战斗插曲）调用。

由于游戏功能在运行时向目标对象加载组件，将其设计为组件非常自然。该组件会被注入到 `PlayerState`，主要功能包括：
- 管理战斗强度：开火和战斗行为会增加强度值，随时间衰减
- 高强度时进入战斗模式，背景音乐减弱以突出枪声
- 低强度时进入探索模式，背景音乐增强并切换至环境音效
- 更新玩家视角方向（虽然游戏中未发现实际用途）
- 比赛结束时重置强度值为0（清理）

### 风声系统（Wind System）
[Lyra Audio System] 同样解释了风声系统，它更为复杂：

- 通过射线检测环境形状
  - 系统会向四周发射射线判定环境轮廓，据此调制风声
- 根据玩家当前 速度（`velocity`） 调整音量，奔跑时风声更大

### 子弹呼啸系统（Whizby System）
[Lyra Audio System] 也涵盖了这个系统。当子弹从玩家附近飞过时，系统会计算子弹轨迹与玩家的垂直向量，根据角度和距离播放声音（越近声音越大）。我们在 `lib_Whizby` 元声音资源中已见过其实现。

`Whizby` 是全局蓝图函数，在各武器的 `OnBurst` 开火事件中被调用。它会确定生成呼啸声的位置，最终通过 `lib_Whizby` 播放音效。

[Convolution Reverb]: https://dev.epicgames.com/documentation/en-us/unreal-engine/convolution-reverb-in-unreal-engine
[Lyra Audio System]: https://disasterpeace.com/blog/epic-games.lyra