---
layout: post
title: "Lyra技术解析 - 核心动画"
description:
  长剑-斩击. 巨锤-猛砸. 手枪-射击. 弓箭-拉满. 法杖-吟唱. 大盾-格挡. 重拳-猛冲. 腿脚-踢击. 直觉又简单，这有什么问题？问题在于我们把他们写出来，不，不是在 Character 类里写七个 if-switch，我们已经不这么干了。现在的规则，是一件复杂十倍的事——系好安全带吧。
date: 2025-05-18 19:05 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-game-core-animation/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.5.4" %}

{% include ue_engine_post_disclaimer.html %}

> 这是一系列关于我从Epic的Lyra项目中学到的知识笔记。该项目声称展示了当前虚幻引擎框架下的最佳实践。其中有些内容是我之前不了解的，有些则已经知晓，但认为仍然值得记录。
{: .prompt-info }

## 动画系统框架
Epic 也写了一篇文档 [Animations In Lyra] 以供阅读. 总的来说，整个动画系统的架构可以被总结为:
- `Character BP` 引用 `Animation Blueprint` 以驱动角色骨骼；
- `Animation Blueprint` 是一个只包含动画状态逻辑和状态切换的框架，并不直接引用任何动画资源；
- 真正的动画资源是作为 `Animation Linked Layer` 动态注入进 `Animation Blueprint` 中的。这种设计方式允许我们用模块化方式处理动画，比如根据角色状态或所用武器切换不同的动画层。

简单来说，这个动画系统由四个核心部分构成：
- `Animation Linked Interface` - 各个动画蓝图之间共享的协议，定义了一套统一的接口。对于每个 `ALI` 函数，我们可以传入某些参数（通常为空），并返回一个动画姿势（Pose）；
- `Animation Blueprint` - 决定我们当前处于哪个状态，并调用某个 `ALI` 接口函数以假设未来某一时刻将注入一个姿势。这个类构建的是逻辑框架，通过虚拟钩子连接动画，仅关注“何时该播放什么样的动画”，而不关心实际动画资源是什么；
- `Animation Linked Layer Base` - 实现每个 `ALI` 接口的基础类，仍不包含动画资源，所有动画都只是变量。它构建的是数据绑定流程，将虚拟钩子点绑定到虚拟动画资源，只负责“该用什么动画资源”，而不管“谁使用这些动画”；
- `Animation Linked Layer` - 真正的动画资源所在，被注入到 `Animation Linked Layer Base` 中。因为继承自 `LLB`，不需要再实现任何逻辑，可以看作一个纯数据容器。它提供了所有 `AnimLLB` 需要的数据，`AnimLLB` 会通过 `ALI` 动态输出姿势给 `AnimBP`，最终驱动骨骼网格。

听上去有些复杂，但熟悉后其实很清楚。这种做法的优势非常明显：想支持 20 种武器又不想一个 `AnimBP` 加载所有资源？不想重复写相同逻辑？动画调试容易出错？想让多个队友并行工作？这就是解决方案。

## 动画蓝图（Animation Blueprint）
从引用链来看，这部分和 `UE4` 还是一样的：我们有一个 `Character BP`，其上会有 `Skeletal Mesh`，然后引用一个 `AnimBP` 作为 `AnimInstance`。一切正常。

![Animation BP Reference](animbp_reference.png){: width="800"}

检查这个资源时我们会发现它不是一个普通的 `AnimInstance`，而是继承自 `LyraAnimInstance` 的类。这个我们之后会详细讲。

![AnimBP Class](animbp_type.png){: width="600"}

## 动画蓝图结构（Animation Blueprint Structure）
这个类初看起来可能有些压迫感，的确内容不少。但我们不要被吓到，还是按照步骤慢慢拆解。

首先我们要明确一点，一个 `Animation Blueprint` 的根本职责其实很简单：告诉当前帧骨骼要做什么。每一帧，它只是在输出一个姿势（Pose）。这个姿势背后当然有一大堆逻辑，比如 IK、姿态切换、程序控制等等，但本质上它的任务没变——一个 `AnimGraph` 通常包括一个 `locomotion` 状态机，再经过一些预处理、后处理、混合、叠加等步骤，最后输出最终的姿势。

为了做出“播放哪个动画”的决策，我们会不断从角色身上，甚至是从整个游戏中拉取数据。

最终目标就是：根据已有的数据（来自 `Event Graph` 或 `functions`），决定此刻该播放哪个姿势（在 `AnimGraph` 中实现）。

呼应前文，我们提到这个类本身只是个框架，并不包含任何动画资源。实际动画资源是作为 `Animation Linked Layer` 被动态注入进 `Animation Blueprint` 的。这种方式允许我们按需加载，不用一次性把所有动画放进去。事实上，Epic 留下了这样一段注释：

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #3</div>
这个 `Anim Graph` 并不会直接引用任何动画资源。它只是在图中提供了用于播放 `Montages` 和 `Linked Animation Layers` 的入口点。这个图的主要目的就是把这些入口点混合在一起（例如混合上半身和下半身的姿势）。

这种做法的好处是，只有在真正需要的时候才加载动画资源。举个例子，一把武器会持有其所需的 `Montages` 和 `Linked Animation Layers` 的引用，这样只有在加载这把武器的时候，相关的数据才会被加载。

比如说，`B_WeaponInstance_Shotgun` 持有它所需的 `Montages` 和 `Linked Animation Layers`，这些数据只会在加载 `B_WeaponInstance_Shotgun` 时加载。而 `B_WeaponInstance_Base` 则负责将动画层链接到具体的武器上。
</div>

如果你熟悉 `UE4` 的动画系统，请准备好迎接一些差异。由于动画系统对 `CPU` 开销极大，为了最大化利用多线程，`Lyra` 中使用的很多做法参考了 [Animation Optimization] 一文，建议先阅读了解，否则后续内容可能较难消化。好了，我们继续进入 `AnimGraph` 的解剖过程。

## AnimGraph
`AnimGraph` 是动画蓝图的核心，它定义了动画数据的处理流程。整个 `AnimGraph` 被划分成若干部分，每一部分负责动画处理流程中的一个环节。

### 移动与左手覆盖（Locomotion And Left Hand Override）
第一部分是 `locomotion`，一个负责角色基本移动的状态机。一旦输出出一个姿势，它就会进入 `LeftHandPose_OverrideState` 并被缓存，供后续使用。

![Locomotion](locomotion.png){: width="800"}

`LeftHandPose_OverrideState` 是一个 `AnimationLinkedInterface`，如前所述，它定义了主动画蓝图和 `linked animation layers` 之间的通用协议。可以把它看作一个钩子，我们可以在这里插入其他动画资源，而主逻辑只负责接受传入的姿势。详细信息可参考官方文档 [Animation Linked Layer]。

![left hand pose override](left_hand_pose_override.png){: width="800"}

> 注意节点上的 `闪电` 图标？这是一个 `Fast Path` 节点，在 [Animation Optimization] 中有详细解释。
{: .prompt-info }

在具体实现中，我们会将 `locomotion` 状态机输出的姿势与一个 `left hand pose override` 变量进行混合，后接一个 `SequenceEvaluator(ByTime)` 节点，并将 `ExplicitTime` 设为 `0`，表示只取该动画的第一帧。接着两个姿势会通过一个 `LayeredBlendPerBone` 节点进行骨骼混合。那么混合的是哪些骨骼呢？是左手所有的手指。

![Left Fingers Blend Mask](left_fingers_blend_mask.png){: width="600"}

到这里，我们大致明白了这一段在做什么：不同武器可能有不同的握持方式，比如 AR 比较窄，Shotgun 比较厚。当左手吸附到武器上时，手指可能会穿模。所以我们通过程序对手指进行微调，使它们贴合武器模型。

那该混合多少？这里我们绑定了一个函数 `SetLeftHandPoseOverrideWeight`，每次该节点更新时都会调用它。逻辑不复杂，就是读取几个变量，这些变量是谁设置的？Shotgun。

![SetLeftHandPoseOverrideWeight](SetLeftHandPoseOverrideWeight.png){: width="800"}

![Shotgun Anim Layer](shotgun_anim_layer.png){: width="800"}

### 上下半身混合（Upper/Lower Body Blend）
搞定了 locomotion 的基础部分后，下一步就是把上半身和下半身的动画混合起来。背后的想法是：我们会播放大量的 `Montage`，这些动画往往很特殊，一般是配合 Gameplay Ability 的一次性动画等。

问题来了：我们不希望一个 `Montage` 占用整个角色动画。例如，角色在奔跑时射击，我们当然希望角色继续跑，而不是因为播放了一个“站立射击”动画而变成滑行状态。

为此，我们使用 `LayeredBlendPerBone` 节点，它允许我们根据骨骼层级来混合不同的动画层。这个节点接受两个姿势输入——一个是上半身，一个是下半身——并根据骨骼结构将它们融合。

![Upper Lower Body](upper_lower_body_blend.png){: width="800"}

在 Lyra 中，Montage 分为两种：Additive（叠加） 和 Regular（非叠加）。像射击这种通常属于 `Additive`（全身叠加），因为我们的 locomotion 已经控制了整个身体，所以我们只是在已有的姿势上添加一个射击动作。

在 Lyra 中，射击使用的是 `FullBodyAdditivePreAim` 的 slot。

另一类就是 Regular，比如跳舞的动作，它们不会考虑角色当前朝向，而是完全接管整个骨骼。比如 Emote 的跳舞动作会使用 `UpperBody` 这个 slot。

而像换弹或投掷手雷这类稍复杂的动作，则会同时使用 `UpperBody` 和 `UpperBodyAdditive` 两个 slot。

#### Additive Blend
首先我们使用缓存下来的 `Locomotion` 姿势，然后通过 `ApplyAdditive` 节点将其与 `UpperBodyAdditive` slot 的 Montage 叠加。这相当于说：“在当前 locomotion 姿势上，加上当前播放在上半身的 montage。”

注意我们在 slot 中传入了一个 `AdditiveIdentityPose` 节点，这个节点的作用是：当没有动画需要叠加时，保持原姿势不变。也就是说，identity pose 不会对目标姿势造成任何改动。

那这个叠加量是多少呢？是通过变量 `UpperbodyDynamicAdditiveWeight` 控制的，下面是它的更新逻辑：

![Upperbody Dynamic Additive Weight](upperbody_dynamic_additive_weight.png){: width="800"}

简单来说，如果我们在地面上播放某个 `Montage`，这个动画就会完整叠加；但如果我们在空中，则会自动过渡回 locomotion 姿势。

#### Regular Blend
对于非 Additive 的动画，比如跳舞，我们就使用普通的 `Slot` 节点来播放 `Montage`。

前面提到，像换弹这种动画会使用两个 slot：`UpperBody` 和 `UpperBodyAdditive`。

![Reload Montage Slots](reload_montage_slots.png)

`UpperBody` slot 用来播放换弹动画，而 `UpperBodyAdditive` 则播放叠加动画。但如果我们看一下 `LayeredBlendPerBone` 节点，会发现 `UpperBody` 的混合权重被设置为 `1`。那 `UpperBodyAdditive` 不就完全没用了吗？

其实不然。这个混合权重并不代表所有骨骼都使用 `Blend Pose 0`，因为我们还有一个叫 `Blend Profile` 的东西。它是一个定义混合权重在骨骼层级上如何分布的配置文件。

通过它，我们可以对每根骨骼设置不同的混合权重，从而精细控制动画的融合方式。

#### Blend Profile
从下图可以看到，从 `Spine1` 开始，一直到手臂，混合权重逐渐上升到 `1`。这意味着有些骨骼不会完全使用 `UpperBody` 动画，它们会继续与 `Additive` 姿势混合。

![Blend Profile](blend_profile.png){: width="800"}

#### FullBodyAdditivePreAim
我们已经将 `UpperBody` slot 分离出来，并与 `Locomotion` 姿势进行混合，接着 Lyra 会把一切再送入另一个 slot —— `FullBodyAdditivePreAim`。这个 slot 用于处理所有的射击动画、后坐力等效果。

这部分是通过在射击动画中添加一个 `AnimNotify` 来触发的，同时播放另一个 Montage 到 `FullBodyAdditivePreAim` slot 上。

![FullBodyAdditivePreAim](FullBodyAdditivePreAim.png)

#### 缓存上下身混合结果（Caching UpperBodyLowerBodySplit）
最后，我们将这些混合后的结果缓存到 `UpperBodyLowerBodySplit` 节点中。

虽然我们提到了射击，但从上图可以看出，这个部分主要是处理 `Grenade` 和 `Reloading` 这两类动画，因为它们是唯一使用了 `UpperBody` 相关 slot 的动画。

### 瞄准、全身叠加与全身 Montage（Aiming, Fullbody Additive and Fullbody Montage）
只剩下一些收尾的部分啦！接下来我们处理的是 `瞄准`。

显然，不同武器的瞄准姿势是不同的（想象一下用沙鹰像狙击枪那样瞄准，是不是有点离谱？）。凡是和具体武器绑定的动作，理应放到 `AnimLinkedLayer` 中处理。而这里我们确实也用了一个 `ALI` 钩子。

接着是 `Fullbody Additive`，这是另一个 `LinkedLayer`，专门处理跳跃落地的恢复动画。比如拿着手枪和拿着霰弹枪，跳跃落地时的姿势会不同。

![fullbody additive](fullbody_additive.png)

![aiming_fullbody_additive](aiming_fullbody_additive.png){: width="800"}

最后是 `FullBody` Montage slot。这个是给冲刺技能用的，当玩家朝任意方向冲刺时，会播放全身动画。

### Inertialization 与原地转向（Inertialization and Turn In Place）
快到终点了！接下来是 `Inertialization`，也就是惯性化处理。这个节点会在骨骼层级上平滑过渡两个不同的姿势。通常我们会在所有动画处理流程结束后使用它，所以它出现在图的末尾。

原地转向是另一个常见处理，用于解决脚部滑动的问题。Epic 留下了如下注释：

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #1 (also see ABP_ItemAnimLayersBase)</div>
当 Pawn 旋转时，Mesh 组件也会跟着旋转，这会导致脚部滑动。
我们在这里通过反向抵消角色旋转，来保持脚的位置不变。
</div>

![Inertialization Turn In Place](inertialization_turn_in_place.png)

### 程序修正：手、腿与脚（Procedural Fixup - Hand Leg and Foot）
还是老规矩，我们通过调用 `AnimLinkedLayer` 来根据武器做 IK 修正，不同武器可能会需要不同的手部 IK 权重。

同时我们还要处理角色脚的贴地问题，这部分包含两个方面：

#### DisableHandIKRetargeting
第一部分是 `DisableHandIKRetargeting`，这是一个曲线，用来临时关闭左右手的 IK 功能。虽然目前没有发现有哪段 montage 使用了它，但它可以在全局级别上禁用手部 IK。

#### DisableLHandIK 和 DisableRHandIK
第二部分是 `DisableLHandIK` 和 `DisableRHandIK`，通常用于装备和卸载装备动画中。也可以用在手枪的近战动画中，例如角色用拿着手枪的那只手击打敌人。

![Disable L Hand IK](disable_l_hand_ik.png){: width="800"}

这些值会从曲线中读取，并分别更新为 `HandIKLeftAlpha` 和 `HandIKRightAlpha` 变量，最终驱动 `TwoBoneIK` 节点来控制 IK。

![TwoBone IK](two_bone_ik.png) {: width="600"}

#### 脚步贴地 & 禁用腿 IK（Foot Placement & DisableLegIK）
接下来处理脚的贴地问题。这是通过一个 `FootPlacement` 节点实现的。该节点会获取当前脚的位置与地面法线，然后根据地形计算新的脚部位置。这样角色在走不平的地面时，脚部依然能正确贴地。

然后是 `DisableLegIK`，这也是一条曲线，通常用于冲刺动画中。当玩家在空中冲刺时，我们不希望应用腿部 IK。

![Foot Placement](foot-placement.png){: width="600"}

#### 武器缩放（Scaling Down Weapon）
最后一个部分是 `ScalingDownWeapon`，这是一条在装备动画中使用的曲线。在玩家抽出武器时，实际上是把武器从缩放为 0 的状态放大到正常大小。我不太确定这是不是最佳实践，但至少它能实现目标……

![Scaling Down Weapon](scaling_down_weapon.png){: width="800"}

#### 程序修正：膝盖（Procedural Fixup - Knee）
我们还调用了 `Control Rig`，主要是为了在角色下蹲并站在斜坡时防止膝盖穿进躯干里。终于讲完了！这还只是“动画框架”的冰山一角（毕竟 AAA 游戏的复杂程度真不是开玩笑的）。

![Procedural Fixup](procedural_fixup.png){: width="800"}

## Locomotion 状态机（Locomotion State Machine）
现在我们进入 `Locomotion` 状态机内部，Epic 留下了一段注释如下：

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #4</div>
这个状态机负责高层级角色状态之间的切换。
每个状态的具体行为主要由 `ABP_ItemAnimLayersBase` 中的动画层处理。
</div>

关于如何使用这个状态机的基本方法，这里就不展开了，因为和 UE4 几乎一样。官方文档也可以参考 [Animation State Machine]。

总体来说，这个状态机分为两大部分：移动（Movement）与跳跃（Jumping）。

### 移动（Movement）
进入状态机后，初始状态是 `Idle`（站立）：

![Movement Locomotion](movement_locomotion.png){: width="800"}

#### Idle 状态
会调用 `ALI_ItemAnimLayers - FullBody_IdleState`，并在更新状态时执行 `UpdateIdleState`

![Idle State](idle_state.png){: width="800"}

#### Idle -> Start
- `Idle`
    - 切换到 `Start` 状态：
        - 如果 `HasAcceleration` || `(GameplayTag_IsMelee && HasVelocity)`

也就是说，只要玩家有加速，或是近战状态下有速度，就会从 `Idle` 切换到 `Start` 状态。

#### Start 状态
会将 `BS_MM_Rifle_Jog_Leans` 动画（带有 `AdditiveLeanAngle`）作为叠加姿势应用到 `ALI_ItemAnimLayers - FullBody_StartState`，进入状态时调用 `SetUpStartState`，更新时调用 `UpdateStartState`。

这个状态代表角色起步跑动，`BecomeRelevant` 类似于 “进入状态时”，而 `OnInitialUpdate` 更像是 “刚刚进入状态前的一帧”。

我们在这里加入了一个 Lean（倾斜）动画，让角色起步时身体朝一个方向倾斜，看起来更自然。

![Start State](start_state.png){: width="800"}

#### Start -> Cycle / Stop
- `Start`
    - 进入 `Cycle` 状态：
        - 如果 `Abs(RootYawOffset)` > 60（优先级 1）
        - 或者 `LinkedLayerChanged`（优先级 1）
        - 或者 `AutomaticRule`（优先级 2）
        - 或者 `(StartDirection != LocalVelocityDirection)` || `CrouchStateChange` || `ADSStateChanged` || `(CurrentStateTime(LocomotionSM) > 0.15 && DisplacementSpeed < 10.0)`
    - 进入 `Stop` 状态（优先级 3）：
        - 如果不是 (`HasAcceleration` || `(GameplayTag_IsMelee && HasVelocity)`)

从上面可以看到，`Start` 状态可以转向 `Cycle` 或 `Stop` 状态。注意我们为不同的切换条件设置了不同的优先级，这样可以精细地控制状态切换逻辑，比如指定过渡时间或混合方式。

`AutomaticRule` 是保证不会卡在 `Start` 状态的一种手段——总要有个出口。

还有一点要提：如果你看到某些过渡线是暗红色的，那说明它们共享了相同的条件，这是为了提升条件复用和维护性。

#### Cycle 状态
会将 `BS_MM_Rifle_Jog_Leans` 动画（带有 `AdditiveLeanAngle`）作为叠加姿势应用到 `ALI_ItemAnimLayers - FullBody_CycleState`。这样可以让跑步时的 Lean 动作在整个 locomotion 状态中都保留。

![Cycle State](cycle_state.png){: width="800"}

#### Cycle -> Stop
- `Cycle`
    - 进入 `Stop` 状态：
        - 如果不是 (`HasAcceleration` || `(GameplayTag_IsMelee && HasVelocity)`)

这里就比较简单了，和从 `Start` 到 `Stop` 的条件是共用的。

#### Stop 状态
会调用 `ALI_ItemAnimLayers - FullBody_StopState`，更新时执行 `UpdateStopState`

![Stop State](stop_state.png){: width="800"}

#### Stop -> Start / Idle
- `Stop`
    - 进入 `Start` 状态：
        - 如果 `HasAcceleration`
    - 进入 `Idle` 状态：
        - 如果 `LinkedLayerChanged`（优先级 1）
        - 或者 `CrouchStateChange` || `ADSStateChanged`（优先级 2）
        - 或者 `AutomaticRule`（优先级 3）

逻辑基本一致，同样通过 `AutomaticRule` 保证状态不会卡死。目前为止，我们已经形成一个非常清晰的循环结构：

`Idle` → `Start` → `Cycle` → `Stop` → `Idle`，易于理解和扩展。

#### PivotSources -> Pivot
- `PivotSources`
    - 切换到 `Pivot` 状态：
        - 如果 ((`LocalVelocity2D` dot `LocalAcceleration2D`) < 0.0) && !`IsRunningIntoWall`

`PivotSources` 是一个 `State Alias`，表示可以从 `Start` 和 `Cycle` 状态切入。

![Pivot Sources](pivot_sources.png){: width="800"}

这个状态用于处理“反向加速”的场景，即朝当前移动方向的反方向加速，适用于急转身动作。

顺带一提，编辑器中可以在 Details 面板中列出所有状态别名（State Alias），这些是通过自定义的 Editor Slate 实现的。

```cpp
void FAnimStateAliasNodeDetails::GenerateStatePickerDetails(UAnimStateAliasNode& AliasNode, IDetailLayoutBuilder& DetailBuilder)
{
	ReferenceableStates.Reset();
	GetReferenceableStates(AliasNode, ReferenceableStates);

	if (ReferenceableStates.Num() > 0)
	{
		IDetailCategoryBuilder& CategoryBuilder = DetailBuilder.EditCategory(FName(TEXT("State Alias")));
		CategoryBuilder.AddProperty(GET_MEMBER_NAME_CHECKED(UAnimStateAliasNode, bGlobalAlias));

		FDetailWidgetRow& HeaderWidgetRow = CategoryBuilder.AddCustomRow(LOCTEXT("SelectAll", "Select All"));

		HeaderWidgetRow.NameContent()
			[
				SNew(STextBlock)
				.Text(LOCTEXT("StateName", "Name"))
				.Font(IDetailLayoutBuilder::GetDetailFontBold())
			];

		HeaderWidgetRow.ValueContent()
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot()
				.AutoWidth()
				.VAlign(VAlign_Center)
				[
					SNew(STextBlock)
					.Text(LOCTEXT("SelectAllStatesPropertyValue", "Select All"))
					.Font(IDetailLayoutBuilder::GetDetailFontBold())
				]
				+ SHorizontalBox::Slot()
				.FillWidth(1.0f)
				.HAlign(HAlign_Right)
				.VAlign(VAlign_Center)
				[
					SNew(SCheckBox)
					.IsChecked(this, &FAnimStateAliasNodeDetails::AreAllStatesAliased)
					.OnCheckStateChanged(this, &FAnimStateAliasNodeDetails::OnPropertyAliasAllStatesCheckboxChanged)
					.IsEnabled_Lambda([this]() -> bool 
						{
							return !IsGlobalAlias();
						})
				]
			];

		for (auto StateIt = ReferenceableStates.CreateConstIterator(); StateIt; ++StateIt)
		{
			const TWeakObjectPtr<UAnimStateNodeBase>& StateNodeWeak = *StateIt;
			if (const UAnimStateNodeBase* StateNode = StateNodeWeak.Get())
			{
				FString StateName = StateNode->GetStateName();
				FText StateText = FText::FromString(StateName);

				FDetailWidgetRow& PropertyWidgetRow = CategoryBuilder.AddCustomRow(StateText);

				PropertyWidgetRow.NameContent()
					[
						SNew(STextBlock)
						.Text(StateText)
						.ToolTipText(StateText)
						.Font(IDetailLayoutBuilder::GetDetailFont())
					];

				PropertyWidgetRow.ValueContent()
					[
						SNew(SHorizontalBox)
						+ SHorizontalBox::Slot()
						.FillWidth(1.0f)
						.HAlign(HAlign_Right)
						.VAlign(VAlign_Center)
						[
							SNew(SCheckBox)
							.IsChecked(this, &FAnimStateAliasNodeDetails::IsStateAliased, StateNodeWeak)
							.OnCheckStateChanged(this, &FAnimStateAliasNodeDetails::OnPropertyIsStateAliasedCheckboxChanged, StateNodeWeak)
							.IsEnabled_Lambda([this]() -> bool 
								{
								return !IsGlobalAlias();
								})
						]
					];
			}
		}
	}
}
```

#### Pivot 状态
会将 `BS_MM_Rifle_Jog_Leans` 动画（带有 `AdditiveLeanAngle`）作为叠加姿势应用到 `ALI_ItemAnimLayers - FullBody_PivotState`，进入状态时调用 `SetUpPivotState`，更新时调用 `UpdatePivotState`。

![Pivot State](pivot_state.png){: width="600"}

#### Pivot -> Cycle / Stop
- `Pivot`
    - 进入 `Cycle` 状态：
        - 如果 `LinkedLayerChanged`（优先级 1）
        - 或者 `WasAnimNotifyStateActiveInSourceState(TransitionToLocomotion)`（优先级 2）
        - 或者 `CrouchStateChange` || `ADSStateChanged` || (`IsMovingPerpendicularToInitialPivor` && (`LastPivotTime <= 0.0)`))（优先级 3）
    - 进入 `Stop` 状态：
        - 如果不是 `HasAcceleration`

也就是说，当我们做出急转向操作时会进入 `Pivot` 状态；如果立即停下，就会直接进入 `Stop` 状态，取消复杂动画过渡，让控制更加灵活。而如果转向角度从反方向变为垂直方向，也会进入 `Cycle` 状态。只有在持续沿反方向运动的情况下，`Pivot` 动画才会继续保留。

### 跳跃（Jumping）
`Locomotion` 状态机的另一部分是跳跃行为，它使用了一个基于时间推进的状态链来描述从起跳到落地的完整过程：

`JumpStart` → `JumpStartLoop` → `JumpApex` → `FallLoop` → `FallLand` → `EndInAir`

![Jump States](jump_states.png){: width="800"}

#### Jump Sources
这是一个包含了 Movement 所有状态的 `StateAlias`，意味着只要角色处于移动状态，就可以进入跳跃流程。

![Jump Sources](jump_sources.png){: width="600"}

#### JumpSources -> JumpSelector
- `JumpSources`
    - 进入 `JumpSelector` 状态：
        - 如果 `True`

没错，这里始终会进入 `JumpSelector`，原因如下所述。

#### JumpSelector Conduit
`JumpSelector` 是一个 `Conduit` 节点，它并不代表具体的动画状态，而是一个用于控制状态机流程的过渡节点。

#### JumpSelector -> JumpStart / JumpApex
实际跳跃逻辑就落在这里：

- `JumpSelector`
    - 进入 `JumpStart` 状态：
        - 如果 `IsJumping`
    - 进入 `JumpApex` 状态：
        - 如果 `IsFalling`

非常直观：如果玩家按下了跳跃键，就进入 `JumpStart`，然后沿着跳跃抛物线运动；但如果是从高处掉下（没有跳跃动作），就会直接进入 `JumpApex`，因为此时已经处于最高点。

#### Jump Start 状态
直接将 `ALI_ItemAnimLayers - FullBody_JumpStartState` 的姿势输出。

![Jump Start State](jump_start_state.png){: width="800"}

#### JumpStart -> JumpStartLoop
- `JumpStart`
    - 进入 `JumpStartLoop` 状态：
        - 使用 `AutomaticRule`

当起跳动画播放完后，就会切入 `JumpStartLoop`，这里的 `AutomaticRule` 保证状态机能自动推进。

#### Jump Start Loop 状态
继续输出 `ALI_ItemAnimLayers - FullBody_JumpStartLoopState` 的姿势。

![Jump Start Loop State](jump_start_loop_state.png){: width="800"}

#### JumpStartLoop -> JumpApex
- `JumpStartLoop`
    - 进入 `JumpApex` 状态：
        - 如果 `TimeToJumpApex` < 0.4

`TimeToJumpApex` 是在 `UpdateJumpFallData` 中计算的。如果角色处于跳跃状态，它的计算方式是：`-WorldVelocity.Z / GravityZ`。否则值为 `0`。这种方式非常巧妙：随着上升速度逐渐减为 0，角色自然就进入了跳跃顶点状态。

#### Jump Apex 状态
输出 `ALI_ItemAnimLayers - FullBody_JumpApexState`。

![Jump Apex State](jump_apex_state.png){: width="800"}

#### JumpApex -> FallLoop
- `JumpApex`
    - 进入 `FallLoop` 状态：
        - 使用 `AutomaticRule`

跳跃顶点状态完成后，状态机会自动进入 `FallLoop`。

#### Fall Loop 状态
输出 `ALI_ItemAnimLayers - FullBody_FallLoopState`。

![Fall Loop State](fall_loop_state.png){: width="800"}

#### FallLoop -> FallLand
- `FallLoop`
    - 进入 `FallLand` 状态：
        - 如果 `GroundDistance` < 200.0

当即将落地时，会播放新的动画过渡着陆。

#### Fall Land 状态
输出 `ALI_ItemAnimLayers - FullBody_FallLandState`。

![Fall Land State](fall_land_state.png){: width="800"}

#### FallLand -> EndInAir
- `FallLand`
    - 进入 `EndInAir` Conduit：
        - 如果 `IsOnGround`

落地动画完成后，进入 `EndInAir` 过渡节点。

#### Jump Fall Interrupt Sources
这是跳跃中所有状态的 `StateAlias`，意味着在跳跃任意阶段都可以中断。

![Jump Fall Interrupt Sources](jump_fall_interrupt_sources.png){: width="600"}

#### JumpFallInterruptSources -> EndInAir
- `JumpFallInterruptSources`
    - 进入 `EndInAir` Conduit：
        - 如果 `IsOnGround`

也就是说，只要我们还在跳跃状态中，某些突发情况（如被强制落地）会让我们直接跳转到 `EndInAir`，跳过其余所有中间状态。

#### EndInAir Conduit
又是一个 Conduit 节点，不执行具体动画。

#### EndInAir -> CycleAlias / IdleAlias
- `EndInAir`
    - 进入 `CycleAlias`：
        - 如果 `HasAcceleration`（优先级 1）
    - 进入 `IdleAlias`：
        - 始终成立（优先级 2）

落地后如果仍在移动，就转入 `CycleAlias`；否则就进入 `IdleAlias`。

![Cycle Alias](cycle_alias.png){: width="600"}

![Idle Alias](idle_alias.png){: width="600"}

## BlueprintThreadsafeUpdateAnimation

至此我们完成了整个 `Locomotion State Machine` 的分析，它读取和更新了大量变量——这些变量有的是来自游戏世界，有的是来自角色本身。那么这些变量是在哪里更新的呢？在 UE4 中我们习惯在 `Event Graph` 中进行更新，而在 Lyra 中，如果打开 `Event Graph`，你会看到如下注释：

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #1  (also see `ABP_ItemAnimLayersBase`) </div>
这个 `AnimBP` 在 `Event Graph` 中不执行任何逻辑。
`Event Graph` 中的逻辑运行在 Game Thread 上。每帧都必须顺序执行每一个 AnimBP 的 Event Graph，这会带来性能瓶颈。
在这个项目中，我们改用新的 `BlueprintThreadsafeUpdateAnimation` 函数（可在 My Blueprint 标签页中找到）。这个函数的逻辑可以并行执行多个 AnimBP，从而减少对 Game Thread 的开销。
</div>

也就是说，`Event Graph` 什么都不做了，因为它在性能上不够友好。我们用的是 `BlueprintThreadsafeUpdateAnimation` 函数，它支持多线程并发运行多个 AnimBP 的更新逻辑，从而显著减轻主线程负担。如果你打开这个函数，还会看到 Epic 留下的说明：

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #2</div>
这个函数的主要职责是收集游戏数据，并将其处理成可用于选择和驱动动画的信息。
需要注意的是，Threadsafe 函数中不能像 Event Graph 那样直接访问游戏对象的数据。这是因为其他线程可能在同时修改这些数据。
我们使用 Property Access 系统来访问这些属性，它会在安全的时机自动复制数据。
比如获取 Pawn 所在位置时，就可以在右键菜单中查找 “Property Access”。
</div>

这些函数都很直观，因此我们不展开每个节点的细节，下面是一个简要总览：

- `UpdateLocationData`  
  - 更新当前角色的位置与位移增量（delta displacement）

- `UpdateRotationData`  
  - 更新当前旋转角度及 `delta yaw`，然后除以 `DeltaSeconds` 得到 `yaw 变化速度`，用于计算 `AdditiveLeanAngle`

- `UpdateVelocityData`  
  - 更新 `WorldVelocity`, `LocalVelocity`, `LocalVelocity2D`, `LocalVelocityDirectionAngle`, `LocalVelocityDirectionAngleWithOffset`（与 `RootYawOffset` 对比）
  - 同时更新速度的方向信息（前后左右），有无偏移两个版本

- `UpdateAccelerationData`  
  - 更新 `WorldAcceleration`, `LocalAcceleration`, `PivotDirection2D`, `CardinalDirectionFromAcceleration`
  - `Pivot` 状态依赖该数据，Epic 注释：“加速度比速度更能反映玩家意图，因此用于判断 Pivot 更为合适。”

- `UpdateWallDetectionHeuristic`  
  - 如果我们有加速度但速度没起来，而且速度方向与目标方向差距很大，可能说明撞墙了

- `UpdateCharacterStateData`  
  - 更新角色状态，包括 `OnGround`, `Crouch`, `ADSState`, `WeaponFiredState`, `IsJumping`, `IsFalling`

- `UpdateBlendWeightData`  
  - 前文提过：如果播放某个 Montage 并且我们处于地面，则将 `UpperbodyDynamicAdditiveWeight` 设置为 1；否则逐渐插值为 0

- `UpdateRootYawOffset`  
  - 此函数负责在不同情况下更新 `RootYawOffset`
  - Epic 注释：
    - 情况1：脚部不动时（例如 Idle），将根骨旋转方向与 Pawn 反向对齐，避免角色 Mesh 跟着旋转；
    - 情况2：角色移动中，平滑减去 Offset；
    - 情况3：默认每帧都朝 BlendOut 过渡，除非状态主动设置为 Hold 或 Accumulate；
  - `RootYawOffsetMode` 有三种模式：`Hold`, `Accumulate`, `BlendOut`

- `UpdateAimingData`  
  - 更新 `AimPitch`，它是 `BaseAimRotation.Pitch` 的归一化值

- `UpdateJumpFallData`  
  - 更新 `TimeToJumpApex`，前文已讲，不再赘述

### 原地转向（Turn In Place）

在我们更新 `RootYawOffset` 时，最终会调用 `SetRootYawOffset` 来写入变量。Epic 对此也留下了几点说明：

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #3</div>
我们对 yaw 偏移做了限制，因为当偏移角度过大时，角色必须把武器瞄得很靠后，会导致脊椎过度扭曲。虽然原地转向动画通常能跟得上偏移，但这个限制依然会导致快速旋转摄像机时脚步滑动。
如果愿意，这个限制也可以替换成更大角度的瞄准动画，或者更频繁地触发转身动画。
</div>

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #4</div>
我们希望瞄准动作能抵消 yaw 偏移，从而保证武器始终与摄像机方向保持一致。
</div>

也就是说，当偏移角度过大时，我们会播放一个转身修正动画来恢复角色朝向。这时就会用到一个曲线，名为 `TurnYawAnimationModifier`。Epic 还在文档中提到：

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #5</div>
当 yaw 偏移过大时，我们会触发 TurnInPlace 动画，让角色转回来。例如，摄像机向右转了 90 度，会让角色正对摄像机的右肩。如果我们播放一个向左转 90 度的动画，角色又会回到面对镜头的方向。
我们使用 "`TurnYawAnimModifier`" 这个动画修饰器，在每个 `TurnInPlace` 动画中生成所需的曲线。
具体触发逻辑可以参考 `ABP_ItemAnimLayersBase`。
</div>

### ULyraAnimInstance

说到这里，我们基本上已经把这个 `AnimBP` 讲完了。再回顾一下前面提到的一个细节：这个 `AnimBP` 并不是从普通的 `Animation Instance` 继承，而是继承自 `ULyraAnimInstance`。

从它的头文件中，我们能看出一些关键点：

- 重写了 `IsDataValid` 函数，这是编辑器在验证资源数据时调用的，可以确保动画蓝图中引用的数据设置正确，所有必需内容齐全；
- 当然，也实现了常规的 `NativeInitializeAnimation` 和 `NativeUpdateAnimation` 函数；
- 定义了一个 `InitializeWithAbilitySystem` 函数，我们稍后会讲它的作用；
- 还声明了 `GameplayTagPropertyMap` 和 `GroundDistance` 两个属性，前者用于将 Gameplay Tag 映射到蓝图变量，后者表示角色离地的距离。

```cpp
UCLASS(Config = Game)
class ULyraAnimInstance : public UAnimInstance
{
    GENERATED_BODY()

public:

    ULyraAnimInstance(const FObjectInitializer& ObjectInitializer);

    virtual void InitializeWithAbilitySystem(UAbilitySystemComponent* ASC);

protected:

#if WITH_EDITOR
    virtual EDataValidationResult IsDataValid(class FDataValidationContext& Context) const override;
#endif // WITH_EDITOR

    virtual void NativeInitializeAnimation() override;
    virtual void NativeUpdateAnimation(float DeltaSeconds) override;

protected:

    // Gameplay tags that can be mapped to blueprint variables. The variables will automatically update as the tags are added or removed.
    // These should be used instead of manually querying for the gameplay tags.
    UPROPERTY(EditDefaultsOnly, Category = "GameplayTags")
    FGameplayTagBlueprintPropertyMap GameplayTagPropertyMap;

    UPROPERTY(BlueprintReadOnly, Category = "Character State Data")
    float GroundDistance = -1.0f;
};
```

### GameplayTagPropertyMap

要理解这个类的意义，我们需要先看看它的初始化流程：在 `NativeInitializeAnimation` 中，我们从角色中获取 `ASC`（Ability System Component），并调用 `InitializeWithAbilitySystem` 来初始化 `GameplayTagPropertyMap`。

这会创建一个 `FGameplayTag` 到类内变量的映射，每当 Tag 状态发生变化时，系统就会自动同步对应的属性值。这就像我们平常写的 `OnTagChanged` 回调，只不过这里是自动处理的。

```cpp
void ULyraAnimInstance::NativeInitializeAnimation()
{
    Super::NativeInitializeAnimation();

    if (AActor* OwningActor = GetOwningActor())
    {
        if (UAbilitySystemComponent* ASC = UAbilitySystemGlobals::GetAbilitySystemComponentFromActor(OwningActor))
        {
            InitializeWithAbilitySystem(ASC);
        }
    }
}

// ...

void ULyraAnimInstance::InitializeWithAbilitySystem(UAbilitySystemComponent* ASC)
{
    check(ASC);

    GameplayTagPropertyMap.Initialize(this, ASC);
}
```


![Tag Property Mapping](tag_property_mapping.png){: width="800"}

比较有意思的一点是这个 `PropertyToEdit` 字段 —— 它是如何实现下拉菜单动态列出蓝图变量的呢？答案是在 `FGameplayTagBlueprintPropertyMapping` 结构体中定义的：

- `TFieldPath<FProperty>` 是一种可以通过名字引用类成员变量的字段路径类型。

```cpp
/**
 * Struct used to update a blueprint property with a gameplay tag count.
 * The property is automatically updated as the gameplay tag count changes.
 * It only supports boolean, integer, and float properties.
 */
USTRUCT()
struct GAMEPLAYABILITIES_API FGameplayTagBlueprintPropertyMapping
{
    GENERATED_BODY()

public:
    // ...
    /** Property to update with the gameplay tag count. */
    UPROPERTY(VisibleAnywhere, Category = GameplayTagBlueprintProperty)
    TFieldPath<FProperty> PropertyToEdit;
    // ...
};
```

虽然通过“名字”来引用变量听起来有点不稳定（重命名就可能失效），但其实即便是通过引用方式也同样存在空指针风险。真正重要的是：系统能不能在出错时提醒用户。这正是校验（validation）机制发挥作用的地方。

每次蓝图保存或我们手动触发验证时，都会调用 `IsDataValid` 函数来检查这些字段是否有效。如果无效，就会返回错误提示。

```cpp
#if WITH_EDITOR
EDataValidationResult ULyraAnimInstance::IsDataValid(FDataValidationContext& Context) const
{
    Super::IsDataValid(Context);

    GameplayTagPropertyMap.IsDataValid(this, Context);

    return ((Context.GetNumErrors() > 0) ? EDataValidationResult::Invalid : EDataValidationResult::Valid);
}
#endif // WITH_EDITOR
```

这个机制确保了：哪怕字段失效了，编译时也能及时报错，不会悄悄出 Bug。

![Invalid Mapping](invalid_mapping.png){: width="800"}

![Invalid Mapping Error](invalid_mapping_error.png){: width="800"}

### GroundDistance
这个类中还剩下一个属性：`GroundDistance`。它是一个简单的 float，表示角色当前离地的垂直距离。这个值用于判断角色是否“在地面上”，从而决定是否要从跳跃状态过渡到落地状态。它会在每一帧的 `NativeUpdateAnimation` 中更新：

```cpp
void ULyraAnimInstance::NativeUpdateAnimation(float DeltaSeconds)
{
    Super::NativeUpdateAnimation(DeltaSeconds);

    const ALyraCharacter* Character = Cast<ALyraCharacter>(GetOwningActor());
    if (!Character)
    {
        return;
    }

    ULyraCharacterMovementComponent* CharMoveComp = CastChecked<ULyraCharacterMovementComponent>(Character->GetCharacterMovement());
    const FLyraCharacterGroundInfo& GroundInfo = CharMoveComp->GetGroundInfo();
    GroundDistance = GroundInfo.GroundDistance;
}
```

## ABP_ItemAnimLayersBase

我们还没结束！继续出发！（当然，想歇一歇也可以，的确信息量有点大 :D）

我们可以先看 Epic 为这部分留下的介绍：

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #6</div>
这个 `animbp` 是为常见武器类型（如 `Rifles` 和 `Pistols`）设计的逻辑框架。如果某种武器（例如 `bow`）需要自定义逻辑，可以创建另一个实现 `ALI_ItemAnimLayers` 接口的 animbp。
它并不会直接引用动画资源，而是通过一组变量实现“子动画蓝图重写”，这些变量分布在 My Blueprint 面板的 "`Anim Set - X`" 分类下。
这种结构允许我们复用相同的逻辑，同时避免将所有武器的动画内容都加载进同一个 animbp 中。
你可以参考 `ABP_RifleAnimLayers`，它就是一个通过变量提供动画资源的子动画蓝图。
</div>

一个比较酷的功能是，虽然 `ABP_ItemAnimLayersBase` 并没有继承自 `ULyraAnimInstance`，但它却实现了访问 `ABP_Mannequin_Base` 的能力。因此两个蓝图之间的变量是共享的。

### Item Anim Layers

现在我们已经了解了前置架构，下面来看具体每个 `ALI` 接口是如何实现的。

#### LeftHandPose_OverrideState
这个我们前面已经讲过了：会把 `LeftHandPoseOverride` 动画资源的第一帧叠加到输入的姿势上。

动画资源是一个变量：`LeftHandPoseOverride`

![Left Hand Pose Override State](left_hand_pose_override_state.png){: width="800"}

#### FullBody_SkeletalControls
在 IK 修正的章节中已经分析过，此处不再重复。

#### FullBodyAdditives
这里有三个状态机，`Identity` 和 `AirIdentity` 状态中是空的，正如其名，它们代表“无动作”，也就是 Identity Pose，加到任何姿势上都不会产生变化。

![Full Body Additives SM](full_body_addtives_sm.png){: width="800"}

它们存在的意义是为了播放“跳跃落地恢复动画”。

![Jump Recovery](jump_recovery.png){: width="800"}

#### FullBody_IdleState
这个状态机控制站立和原地转身行为。

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #7</div>
这个 animbp 为 `AnimBP_Mannequin_Base` 中的每个状态实现了对应的 Layer。
每个 Layer 可以是一个简单动画，也可以是像状态机那样的复杂逻辑。
</div>

![Idle SM](idle_sm.png){: width="800"}

- `Idle`
    - 进入 `IdleBreak` 状态：
        - 如果 `TimeUntilIdleBreak` < 0.0
    - 进入 `TurnInPlace` 状态：
        - 如果 `Abs(RootYawOffset)` > 50.0（共享）

![Idle SM Subsm](idlesm_subsm.png){: width="800"}

进入 `Idle Sub SM` 后，会根据是否蹲伏状态切换不同的动画。

- `IdleBreak`
    - 进入 `Idle` 状态：
        - 如果不是 `GameplayTag_IsFiring`（优先级 1）
        - 或者不能播放 IdleBreak 或动画播放完成（优先级 2）
        - 或者 `AutomaticRule`（优先级 2）
    - 进入 `TurnInPlace` 状态：
        - 如果 `Abs(RootYawOffset)` > 50.0（共享）

![Idle Break State](idlebreak_state.png){: width="800"}

`IdleBreak` 动画用于角色长时间站立不动后的动态补间效果。

触发条件依赖于变量 `TimeUntilIdleBreak`。如果角色没有在射击且 `CanPlayIdleBreak` 为真，就会播放；否则由 `AutomaticRule` 保底过渡。

一个有趣的地方是，这里的 Sequence Player 并没有直接引用动画资源，而是在 `OnBecomeRelevant` 时调用 `SetUpIdleBreakAnim` 函数，根据 `IdleBreak` 数组选择合适的动画。

![SetUpIdleBreakAnim](SetUpIdleBreakAnim.png){: width="800"}

- `TurnInPlace`
    - 进入 `TurnInPlaceRecovery` 状态：
        - 如果 `GetCurveValue(TurnYawWeight)` == 0.0

类似地，我们会调用 `SetUpTurnInPlaceAnim` 来设置动画资源。动画播放过程中会根据角色朝向更新 `Direction` 变量，从而选择正确的转身动画。

![Turn In Place State](turn_in_place_state.png){: width="800"}

- `TurnInPlaceRecovery`
    - 进入 `Idle` 状态：
        - 使用 `AutomaticRule`
    - 进入 `TurnInPlace` 状态：
        - 如果 `Abs(RootYawOffset)` > 50.0（共享）

![Turn In Place Recovery](turn_in_place_recovery.png){: width="800"}

Epic 对这部分也有解释：

<div class="box-info" markdown="1">
<div class="title"> TurnInPlace #6 (also see AnimBP_Mannequin_Base)</div>
当 yaw 偏移足够大时，我们会触发一个 TurnInPlace 动画将角色转回来。
这些动画通常在转身结束时还会有一个收尾动作。此时我们会切换到 TurnInPlaceRecovery 状态。
如果此时角色又继续转动摄像机，我们会直接回到 TurnInPlace 状态，避免必须等收尾动作播完。
</div>

#### FullBody_StartState

在这个状态中，Epic 留下了两条注释：

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #8</div>
这是一个使用 Anim Node Functions 的示例。
Anim Node Functions 可以在动画节点中运行，并且只在节点激活时执行，这样可以将逻辑局部化到特定节点或状态。
在这个例子中，一个 Anim Node Function 会在节点变为有效时选择要播放的动画，另一个用于控制播放速率。
</div>

这一点我们已经在前面多个状态中看到过了，现在应该已经不陌生了。

![Animation Node Functions](anim_node_function.png){: width="800"}

接下来是两个与距离匹配相关的功能函数：`DistanceMatching` 和 `StrideWarper`。

- `DistanceMatching`：用于确保动画中角色前进的距离与角色实际移动的距离相匹配，从而避免脚滑；
- `StrideWarper`：在动画播放速度与实际速度不一致时对步伐进行拉伸或压缩，确保动作自然。

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #9</div>
这是使用 Distance Matching 的一个示例，它可以确保起步动画中移动的距离和角色实际移动距离一致。这种做法可以让动画和运动模型保持同步，从而消除脚部滑动。
这实际上等于通过动画播放速度的控制来匹配运动。虽然我们对播放速度做了限制，但如果速度还是不对，就用 Stride Warping 来进一步修正。
要使用这些函数需要启用 Animation Locomotion Library 插件。
</div>

幸运的是，Epic 已经将这些复杂功能封装成了两个节点：`Orientation Warping` 和 `Stride Warping`。

![Distance Matching](distance_matching.png){: width="800"}

![Warping](warping.png){: width="800"}

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #10</div>
这是一个对角色动画姿势进行 Warp 的示例，确保角色动画方向与实际运动方向一致。
Orientation Warping 会旋转角色下半身，使其朝向和实际移动方向一致。我们只需要提供前/后/左/右四个基础方向，其余通过 Warping 插值完成。
它还会重新对齐角色上半身，保证角色依然面朝摄像机方向。
Stride Warping 用于调整步伐长度，当动画的预设速度和角色真实速度不一致时尤为重要。
这些功能需要启用 Animation Warping 插件。
</div>

#### FullBody_CycleState

在 UE4 中，我们可能会用一个 2D Blendspace 来处理角色奔跑动画。但在 Lyra 中，这个状态处理得更精细。

除了继续使用 `Stride Warping` 和 `Orientation Warping` 外，动画资源的选择是通过一个叫 `UpdateCycleAnim` 的函数完成的，它会根据当前计算出的 `CardinalDirection`（方向象限）来选择动画。

同时也会调用 `SetPlayrateToMatchSpeed`，通过动态调整播放速度来匹配移动速度（与传统 Blendspace 的思路类似）。

![Set Playrate](set_cycle_anim_playrate.png)

#### FullBody_StopState

这一部分就没什么新内容了，所有的逻辑都已经在前文介绍过。

![FullBody StopState](fullbody_stop_state.png){: width="800"}

#### FullBody_PivotState

`PivotState` 是通过一个内部状态机 `PivotSM` 控制的，逻辑与 `CycleState` 类似，也是通过函数选择动画资源。

![FullBody PivotState](fullbody_pivot_state.png){: width="800"}

![Pivot State SM](pivot_state_sm.png){: width="800"}

#### FullBody_JumpStartState

播放 `JumpStart` 动画，并根据当前武器叠加 `HipFireRaiseWeaponPose` 姿势。

![FullBody Jump Start State](fullbody_jump_start_state.png){: width="800"}

#### FullBody_JumpStartLoopState

播放 `JumpStartLoop` 动画，并叠加 `HipFireRaiseWeaponPose`。

![FullBody Jump Start Loop State](fullbody_jump_start_loop_state.png){: width="800"}

#### FullBody_JumpApexState

播放 `JumpApex` 动画，并叠加 `HipFireRaiseWeaponPose`。

![FullBody Jump Apex State](fullbody_jump_apex_state.png){: width="800"}

#### FullBody_FallLoopState

播放 `JumpFallLoop` 动画，并叠加 `HipFireRaiseWeaponPose`。

![FullBody Fall Loop State](fullbody_fall_loop_state.png){: width="800"}

#### FullBody_FallLandState

播放 `JumpFallLand` 动画，并叠加 `HipFireRaiseWeaponPose`。

同时每帧调用 `UpdateFallLandAnim`，进行落地距离匹配修正。

![FullBody Fall Land State](fullbody_fall_land_state.png){: width="800"}

#### FullBody_Aiming

这是传统的 `AnimOffset` 实现方式，在这里没什么新内容。

![FullBody Aiming State](fullbody_aiming_state.png){: width="800"}

### 动画更新逻辑（Update Animations）

以上就是整个 `AnimGraph` 的结构分析。接下来，和之前的模式一样，我们还需要提供并更新支撑这些动画逻辑所需的变量。

这一部分的更新依然是在 `BlueprintThreadsafeUpdateAnimation` 中完成的，`Event Graph` 依然是空的。Epic 在这部分也留下了备注：

<div class="box-info" markdown="1">
<div class="title"> AnimBP Tour #5</div>
就像 `AnimBP_Mannequin_Base` 一样，这个 animbp 的逻辑全部写在 `BlueprintThreadSafeUpdateAnimation` 中。
此外，该 animbp 还可以使用 `Property Access` 和 `GetMainAnimBPThreadSafe` 函数访问 `AnimBP_Mannequin_Base` 中的数据。下面就是一个例子。
</div>

整体来说，这部分逻辑比 `ABP_Mannequin_Base` 中的简单一些。我们概括几个关键函数：

- `UpdateBlendWeightData`
  - 更新 `UpperbodyDynamicAdditiveWeight`（上半身叠加权重）
  - 更新 `AimOffsetBlendWeight`（瞄准姿势偏移的混合权重）

- `UpdateJumpFallData`
  - 更新 `TimeFalling`，记录角色最近一次在空中的持续时间

- `UpdateSkelControlsData`
  - 根据 `DisableLHandIK` 和 `DisableRHandIK` 的值，更新 `HandIKLeftAlpha` 和 `HandIKRightAlpha`，用于控制 IK 插值

### 总结（Takeaways）

呼——终于讲完了！虽然过程挺硬核的，但能看到 Epic 是怎么实现这样一个完整动画系统的，确实非常让人受益。

虽然这些技术在 AAA 项目中可能很常见，但对于独立开发者来说，显然远远超出了实际所需的复杂度。

所以如果你在做一个个人或小团队的项目，建议是**学习这个架构背后的工程思维**，而不是照搬这套系统本身。比如：

- 如何把逻辑和数据解耦；
- 如何按需加载动画资源；
- 如何通过接口让多个系统协作；
- 如何设计动画更新的线程安全结构；
- 以及如何利用曲线和变量控制动画行为。

这些理念远比代码实现更值得借鉴。

[Animation Optimization]: https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-optimization-in-unreal-engine#aniamtionfastpath
[Animations In Lyra]: https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-in-lyra-sample-game-in-unreal-engine?application_version=5.0
[Animation Linked Layer]: https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-linking-in-unreal-engine
[Animation State Machine]: https://dev.epicgames.com/documentation/en-us/unreal-engine/state-machines-in-unreal-engine