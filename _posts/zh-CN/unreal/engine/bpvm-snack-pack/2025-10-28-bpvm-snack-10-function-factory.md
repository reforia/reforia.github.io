---
layout: post
title: "BPVM 小食包 #10 - 函数工厂:图表变成函数"
description: "你的事件图在运行时实际上不是图表。它被转换成一个叫做 Ubergraph 的巨型函数。这就是函数工厂的魔法工作原理。"
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.6.0" %}

> **BPVM 小食包** - 蓝图知识快速投喂!是[蓝图到字节码系列](/zh-CN/posts/bpvm-bytecode-I/)的一部分。
{: .prompt-tip }

## 多图表问题

你为了组织创建了多个事件图页面:

- "玩家输入"页面
- "战斗逻辑"页面
- "UI 更新"页面

干净整洁,对吧?但这里有个秘密:**它们都变成一个函数**。

## 认识 Ubergraph

编译器将你所有的事件图合并:

```cpp
void CreateAndProcessUbergraph()
{
    // 创建一个大图表
    ConsolidatedEventGraph = NewObject<UEdGraph>("Ubergraph");

    // 将所有事件图页面复制进去
    for (UEdGraph* EventGraph : Blueprint->EventGraphs) {
        MergeIntoUbergraph(EventGraph, ConsolidatedEventGraph);
    }

    // 这现在是一个巨型函数!
}
```

想象一下,把多张食谱卡组合成一本烹饪书!

## 为什么要合并所有内容?

**虚拟机不理解"页面"** - 它只执行函数:

```cpp
// 你在编辑器中看到的:
EventGraph_Page1 → BeginPlay 节点
EventGraph_Page2 → Tick 节点
EventGraph_Page3 → OnDamaged 节点

// 虚拟机看到的:
Ubergraph() {
    BeginPlay_Implementation();
    Tick_Implementation();
    OnDamaged_Implementation();
}
```

页面是为了**人类**。机器想要**一个函数**。

## 函数创建流水线

工厂处理**四种类型**的图表:

```cpp
void CreateFunctionList()
{
    // 1. Ubergraph(所有事件图合并)
    if (DoesSupportEventGraphs(Blueprint)) {
        CreateAndProcessUbergraph();
    }

    // 2. 常规函数图
    for (UEdGraph* Graph : Blueprint->FunctionGraphs) {
        ProcessOneFunctionGraph(Graph);
    }

    // 3. 生成的函数图(来自宏等)
    for (UEdGraph* Graph : GeneratedFunctionGraphs) {
        ProcessOneFunctionGraph(Graph);
    }

    // 4. 接口函数
    for (auto& Interface : Blueprint->ImplementedInterfaces) {
        for (UEdGraph* Graph : Interface.Graphs) {
            ProcessOneFunctionGraph(Graph);
        }
    }
}
```

## 处理每个函数

每个图表都经过**相同的工厂流程**:

```cpp
void ProcessOneFunctionGraph(UEdGraph* SourceGraph)
{
    // 步骤 1: 克隆到临时图表
    UEdGraph* TempGraph = DuplicateGraph(SourceGraph);

    // 步骤 2: 展开节点(宏变成真实节点)
    ExpandAllMacroNodes(TempGraph);

    // 步骤 3: 创建函数上下文
    FKismetFunctionContext* Context = CreateFunctionContext();
    Context->SourceGraph = TempGraph;

    // 步骤 4: 添加到函数列表
    FunctionList.Add(Context);
}
```

## 事件节点魔法

图表中的每个事件都变成一个**函数桩**:

```cpp
// 你有一个 BeginPlay 事件节点
UK2Node_Event* BeginPlayNode;

// 编译器创建一个函数桩
void ReceiveBeginPlay() {
    // 跳转到 Ubergraph 中的正确位置
    Ubergraph(ENTRY_BeginPlay);
}
```

事件只是进入大函数的**入口点**!

## 函数上下文:蓝图

每个函数都获得一个 `FKismetFunctionContext`:

```cpp
struct FKismetFunctionContext
{
    UEdGraph* SourceGraph;           // 可视化图表
    TArray<FBPTerminal*> Parameters; // 输入引脚
    TArray<FBPTerminal*> Locals;     // 局部变量
    TArray<UEdGraphNode*> LinearExecutionList;  // 节点顺序
    TArray<FBlueprintCompiledStatement*> AllGeneratedStatements;  // 代码!
};
```

这个上下文是构建实际函数的**蓝图**(双关语有意为之)!

## 宏展开

宏在处理过程中被**内联**:

```cpp
// 展开前
CallMacro("MyUtilityMacro")

// 展开后(节点直接复制)
Node1 → Node2 → Node3 → Node4  // 宏的实际节点
```

宏**消失了** - 它们的节点被直接复制到你的函数中!

## Ubergraph 名称

在崩溃日志中见过这个吗?

```
ExecuteUbergraph_BP_MyActor
```

现在你知道它的含义了 - 这是包含所有事件的**大函数**!

## 函数类型解释

**常规函数:**
```cpp
ProcessOneFunctionGraph(MyFunction)
→ 创建: MyFunction()
```

**事件图事件:**
```cpp
CreateAndProcessUbergraph()
→ 创建: ExecuteUbergraph_BP_MyActor()
→ 带有桩: ReceiveBeginPlay()、ReceiveTick() 等
```

**接口函数:**
```cpp
ProcessOneFunctionGraph(InterfaceFunc)
→ 创建: InterfaceFunc_Implementation()
```

## 隐藏的优化

为什么要将所有内容合并到 Ubergraph?

**没有 Ubergraph(低效):**
```cpp
void BeginPlay() { /* 字节码 */ }
void Tick() { /* 字节码 */ }
void OnDamaged() { /* 字节码 */ }
// 三个独立的函数调用,三个上下文
```

**有 Ubergraph(优化):**
```cpp
void ExecuteUbergraph(int EntryPoint) {
    switch(EntryPoint) {
        case 0: /* BeginPlay 字节码 */
        case 1: /* Tick 字节码 */
        case 2: /* OnDamaged 字节码 */
    }
    // 一个函数,共享上下文!
}
```

## 快速要点

- 所有事件图页面都变成**一个函数**(Ubergraph)
- 常规函数各自获得**自己的函数**
- 宏被**内联展开**(它们消失了)
- 每个函数都获得一个 **FKismetFunctionContext**(它的蓝图)
- 事件只是进入 Ubergraph 的**入口点**
- 接口函数获得 **_Implementation** 后缀

## 工厂永不停歇

每次你编译时:
1. 事件图合并到 Ubergraph
2. 函数单独处理
3. 宏展开并消失
4. 为每个函数创建上下文
5. 工厂生产可执行的函数!

## 想要更多细节?

完整的函数创建过程:
- [从蓝图到字节码 III - 函数图](/zh-CN/posts/bpvm-bytecode-III/#function-graphs)

下一篇:所有内容如何链接在一起!

---

**🍿 BPVM 小食包系列**
- [← #9: 变量变成属性](/zh-CN/posts/bpvm-snack-09-variables-properties/)
- **#10: 函数工厂** ← 你在这里
- [#11: 链接和绑定](/zh-CN/posts/bpvm-snack-11-linking-binding/) →
