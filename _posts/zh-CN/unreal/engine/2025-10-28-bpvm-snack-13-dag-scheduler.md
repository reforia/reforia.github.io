---
layout: post
title: "BPVM 小食包 #13 - DAG 调度器:排序混沌"
description: "你的蓝图节点可以以复杂的方式连接,但它们必须按顺序执行。DAG 调度器将你的节点网络转变为线性执行列表。"
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

## 执行顺序问题

看看你的蓝图图表。节点以各种方式连接。但 CPU 一次只能做**一件事**。

谁先?谁接着?这就是调度器的工作!

## 什么是 DAG?

DAG = **有向无环图 (Directed Acyclic Graph)**
- **有向 (Directed)**: 箭头指向一个方向(数据向前流动)
- **无环 (Acyclic)**: 没有循环(不能绕圈)
- **图 (Graph)**: 由边连接的节点

你的蓝图就是一个 DAG(如果它能编译)!

## 拓扑排序

调度器使用**拓扑排序**来排序节点:

```cpp
void CreateExecutionSchedule(Nodes, LinearExecutionList)
{
    // 拓扑排序算法
    while (NodesLeft) {
        // 找到没有依赖的节点
        Node = FindNodeWithNoDependencies();

        // 添加到执行列表
        LinearExecutionList.Add(Node);

        // 从图中移除
        RemoveNode(Node);
    }
}
```

就像穿衣服 - 袜子在鞋子前,衬衫在领带前!

## 可视化示例

**你的图表:**
```
A → B → D
    ↓
    C → E
```

**调度后:**
```
线性顺序: A → B → C → D → E
```

调度器找到了依赖关系被尊重的**唯一有效顺序**!

## 检测循环

如果你不小心创建了一个循环怎么办?

```cpp
// 循环依赖!
A → B → C → A

// 调度器检测到:
if (NodesLeft && NoDependencyFreeNodes) {
    Error("在图中检测到循环!");
    // 准确显示哪些节点形成循环
}
```

调度器在循环发生之前**防止无限循环**!

## 数据依赖

调度器跟踪**两种类型**的连接:

```cpp
// 执行引脚(白色箭头)
BeginPlay → PrintString → SetVariable

// 数据引脚(彩色线)
GetVariable → Add → SetVariable
```

两者都创建影响排序的依赖关系!

## 纯节点是特殊的

纯节点(没有执行引脚)按**需求调度**:

```cpp
// 你的图表
[Exec] → PrintString(GetRandomFloat() + 10)

// 调度顺序
1. GetRandomFloat()  // 首先计算(Print 需要)
2. Add(result, 10)   // 然后加
3. PrintString()     // 最后打印
```

纯节点在需要它们的输出时**及时**运行!

## 调度算法

```cpp
LinearExecutionList = [];
DependencyCount = {};

// 为每个节点计数依赖
for (Node in Nodes) {
    DependencyCount[Node] = CountIncomingEdges(Node);
}

// 处理没有依赖的节点
Queue = GetNodesWithZeroDependencies();

while (!Queue.Empty()) {
    Node = Queue.Pop();
    LinearExecutionList.Add(Node);

    // 减少连接节点的依赖计数
    for (ConnectedNode in Node.Outputs) {
        DependencyCount[ConnectedNode]--;
        if (DependencyCount[ConnectedNode] == 0) {
            Queue.Push(ConnectedNode);
        }
    }
}
```

## 真实世界调度

**复杂图表:**
```
BeginPlay → GetActor → IsValid → Branch
                ↓                    ↓
           GetLocation          [True] SetLocation
                                [False] PrintError
```

**调度顺序:**
1. BeginPlay
2. GetActor
3. IsValid
4. Branch
5. GetLocation(即使未使用)
6. SetLocation 或 PrintError

所有内容在需要**之前**就准备好了!

## 为什么线性很重要

虚拟机不能很好地处理分支:

```cpp
// 对虚拟机不好(分支)
if (Condition) {
    Path A 节点...
} else {
    Path B 节点...
}

// 对虚拟机好(带跳转的线性)
CheckCondition
JumpIfFalse Label_B
Path A 节点...
Jump Label_End
Label_B:
Path B 节点...
Label_End:
```

带**跳转**的线性执行比真正的分支更快!

## 调度错误

当调度失败时:

```cpp
// 错误类型
"检测到循环" → 你有 A→B→A 循环
"孤立节点" → 节点没有连接到任何东西
"多个入口点" → 两个 BeginPlays?
```

调度器在**编译时**捕获这些,而不是运行时!

## 快速要点

- DAG 调度器将你的**节点网络**转变为**操作线**
- 使用**拓扑排序**来尊重所有依赖关系
- 在循环导致无限循环之前**检测循环**
- **纯节点**按需及时调度
- 为虚拟机创建一个 **LinearExecutionList**
- 使分支图表成为**带跳转的线性**

## 从混沌到秩序

你美丽、蔓延的节点图可能看起来像有组织的混沌,但 DAG 调度器将其转换为虚拟机可以逐步执行的完美有序列表。它是使可视化脚本真正工作的无名英雄!

## 想要更多细节?

完整的调度算法:
- [从蓝图到字节码 IV - 创建执行调度](/zh-CN/posts/bpvm-bytecode-IV/#create-execution-schedule)

下一篇:后端如何将语句转换为字节码!

---

**🍿 BPVM 小食包系列**
- [← #12: 语句 101](/zh-CN/posts/bpvm-snack-12-statements/)
- **#13: DAG 调度器** ← 你在这里
- [#14: 后端魔法](/zh-CN/posts/bpvm-snack-14-backend/) →
