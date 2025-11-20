---
layout: post
title: "BPVM 小食包 #2 - 图表系统解码"
description: "你看到的节点图表实际上是两个系统:数据 (UEdGraph) 和渲染 (Slate)。这里解释为什么这种分离很重要。"
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.6.0" %}

> **BPVM 小食包**是深度系列文章[蓝图到字节码](/posts/bpvm-bytecode-I/)的配套系列。每一份小食都是快速的3-5分钟阅读。拿上你的咖啡!
{: .prompt-tip }

## 模型-视图分离(虚幻方式)

当你打开蓝图看到这个节点图表时:

![UEdGraph](bytecode_uedgraph.png)

你看到的是经典的 MVC 架构在起作用:

1. **模型** (`UEdGraph` - 数据结构)
2. **视图** (`SGraphEditor` - Slate 渲染)

## 数据层: UEdGraph

图表数据存储在一个 `UEdGraph` 对象中。把它想象成一个**JSON 结构**,描述:
- 存在哪些节点
- 它们连接到什么
- 它们有什么值

```cpp
class UEdGraph
{
    TArray<UEdGraphNode*> Nodes;     // 你所有的节点
    // 核心基本就是这样!
};
```

没有渲染代码。没有 UI。只有纯数据。

## 视觉层: SGraphEditor

当你在屏幕上看到漂亮的图表时,那是一个名为 `SGraphEditor` 的 Slate 控件。它:
- 读取 `UEdGraph` 数据
- 绘制盒子和线条
- 处理你的鼠标点击
- 当你改变东西时更新 `UEdGraph`

**重要:** 图表可以在没有任何视觉效果的情况下存在!当你打包游戏时,`UEdGraph` 被编译为字节码,视觉层被剥离。你发布的游戏只包含可执行代码,而不是漂亮的节点编辑器。

## 节点: 数据遇见逻辑

每个节点都是一个 `UEdGraphNode` 对象(或者更具体地说,蓝图用的是 `UK2Node`):

![UK2 Nodes](bytecode_uk2nodes.png){: width="500"}

```cpp
class UEdGraphNode
{
    TArray<UEdGraphPin*> Pins;       // 输入/输出连接
    FString NodeComment;             // 你可以添加的黄色注释
    // 节点特定数据在这里
};
```

是的,它也有一个视觉表示: `SGraphNode`(另一个 Slate 控件)。

## 引脚: 连接点

引脚是魔法发生的地方:

```cpp
class UEdGraphPin
{
    FName PinName;                   // "Target"、"Return Value" 等
    EPinDirection Direction;         // 输入还是输出?
    TArray<UEdGraphPin*> LinkedTo;   // 连接到我的是什么?
    FString DefaultValue;            // 如果没有连接的话的默认值
};
```

当你在节点之间拖动连线时,你在创建两个引脚之间的 `LinkedTo` 关系。

## 规则手册: Schema

你不能把 `Integer` 引脚连接到 `String` 引脚。那是 `UEdGraphSchema` 在强制类型安全:

```cpp
class UEdGraphSchema
{
    // 定义规则:
    // - 允许哪些节点?
    // - 哪些连接是有效的?
    // - 右键菜单显示什么?
};
```

不同的图表类型有不同的 schema:
- **蓝图**使用 `UEdGraphSchema_K2`
- **动画蓝图**使用 `UAnimationGraphSchema`
- **行为树**使用 `UBehaviorTreeGraphSchema`

每个都强制执行自己的规则!

## 为什么这种分离很重要

**数据易于存储和编译:**
```cpp
// 易于保存、加载和处理
UEdGraph* Graph = LoadGraphFromAsset();
CompileToByteCode(Graph);
```

**视觉效果很昂贵:**
```cpp
// 只在编辑器打开时创建
SGraphEditor* VisualGraph = CreateWidget();
VisualGraph->SetGraphToVisualize(Graph);
```

在运行时,你的游戏永远不会加载视觉层。它只关心编译后的字节码!

## 快速要点

- **UEdGraph** = 你的节点数据(在 .uasset 中序列化)
- **UEdGraphNode** = 单个节点数据(Print String、Branch 等)
- **UEdGraphPin** = 带有类型信息的连接点
- **SGraphEditor / SGraphNode** = 漂亮的视觉效果(仅编辑器)
- **UEdGraphSchema** = 规则手册(允许什么?)

## 想要更多细节?

有关所有这些系统的完整分解:
- [从蓝图到字节码 I - 图表系统深入](/posts/bpvm-bytecode-I/#uedgraph)

下一份小食:这些节点如何变成可执行代码!

---

**🍿 BPVM 小食包系列**
- [← #1: 蓝图到底是什么?](/zh-CN/posts/bpvm-snack-01-what-is-blueprint/)
- **#2: 图表系统解码** ← 你在这里
- [#3: 编译启动](/zh-CN/posts/bpvm-snack-03-compilation-kickoff/) →
