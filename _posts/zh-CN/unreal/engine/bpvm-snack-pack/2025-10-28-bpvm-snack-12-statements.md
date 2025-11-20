---
layout: post
title: "BPVM 小食包 #12 - 语句 101:字节码之前的语言"
description: "在节点变成字节码之前,它们会变成语句。把它们想象成可视化节点和机器代码之间的中间语言。"
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

## 翻译流水线

你的蓝图节点经过**三种形式**:

```
可视化节点 → 语句 → 字节码
(你看到的) → (中间) → (运行的)
```

语句是**中间地带** - 比节点更结构化,比字节码更简单!

## 认识 FBlueprintCompiledStatement

每个操作都变成一个语句:

```cpp
struct FBlueprintCompiledStatement
{
    EKismetCompiledStatementType Type;  // 什么类型的操作?
    FBPTerminal* LHS;                    // 左侧(通常是输出)
    TArray<FBPTerminal*> RHS;            // 右侧(输入)
    UFunction* TargetFunction;           // 用于函数调用
    UEdGraphNode* SourceNode;            // 来自哪里
};
```

把它想象成一个操作的**食谱卡**!

## 语句类型

有**30 多种语句类型**。这里是核心的:

```cpp
enum EKismetCompiledStatementType
{
    KCST_Nop = 0,                // 什么都不做
    KCST_CallFunction = 1,       // 调用函数
    KCST_Assignment = 2,         // 设置变量
    KCST_CompileError = 3,       // 编译失败
    KCST_UnconditionalGoto = 4,  // 跳转到标签
    KCST_Return = 7,             // 从函数返回
    KCST_SwitchValue = 29,       // Select/switch 语句
    // ... 还有更多
};
```

每种类型告诉后端**确切**要生成什么!

## 真实示例:Print String

你的"Print String"节点变成:

```cpp
// 节点
UK2Node_CallFunction "PrintString"

// 变成这个语句
FBlueprintCompiledStatement {
    Type: KCST_CallFunction
    TargetFunction: "PrintString"
    RHS: [Terminal_StringValue]  // "Hello World"
}

// 最终变成字节码
0x44 EX_CallFunc
0x08 PrintString
"Hello World"
0x53 EX_Return
```

## 赋值语句

设置变量:

```cpp
// 蓝图: Health = 100

Statement {
    Type: KCST_Assignment
    LHS: Terminal_Health  // 目标变量
    RHS: [Terminal_100]   // 要赋的值
}
```

LHS = "左手边"(放在哪里)
RHS = "右手边"(放什么)

## 控制流语句

分支和跳转:

```cpp
// 分支节点
Statement {
    Type: KCST_GotoIfNot
    LHS: Terminal_Condition  // 检查什么
    TargetLabel: Label_False // 如果为假跳到哪里
}

// 无条件跳转
Statement {
    Type: KCST_UnconditionalGoto
    TargetLabel: Label_End
}
```

这些成为你的逻辑流的**骨架**!

## 终端系统

语句使用 `FBPTerminal` 来表示数据:

```cpp
FBPTerminal* Terminal = new FBPTerminal();
Terminal->Type = "int32";
Terminal->Name = "MyVariable";
Terminal->Source = OutputPin;  // 它连接到哪里
```

终端是值的**占位符** - 就像汇编中的变量!

## 为什么需要语句?

**为什么不直接变成字节码?**

1. **优化机会**
```cpp
// 优化前
Statement1: A = B + 1
Statement2: C = A
Statement3: D = C

// 优化后
Statement1: D = B + 1  // 合并了!
```

2. **平台独立性**
```cpp
// 相同的语句可以生成:
- 字节码(用于虚拟机)
- C++ 代码(用于本地化)
- 调试输出(用于工具)
```

3. **更容易验证**
```cpp
// 在语句级别检查错误
if (Statement.LHS == nullptr) {
    Error("赋值没有目标!");
}
```

## 编译流程

```cpp
void CompileNode(UK2Node* Node)
{
    // 步骤 1: 节点处理器创建语句
    FNodeHandlingFunctor* Handler = GetHandler(Node);
    Handler->Compile(Context, Node);

    // 步骤 2: 语句进入上下文
    Context.AllGeneratedStatements.Add(NewStatement);

    // 步骤 3: 后端转换为字节码(稍后)
    Backend.GenerateBytecode(Context.AllGeneratedStatements);
}
```

## 语句优化

在变成字节码之前,语句会被**优化**:

```cpp
// 相邻的 goto
Goto Label1
Label1:  // 移除!

// 死代码
Return
CallFunction  // 永远不会到达 - 移除!

// 冗余赋值
A = B
A = C  // 第一个移除!
```

## 调试站点

用于调试的特殊语句:

```cpp
Statement {
    Type: KCST_DebugSite
    SourceNode: MyNode  // 在这里设置断点!
}
```

这些成为调试器中的**断点位置**!

## 快速要点

- 语句是节点和字节码之间的**中间语言**
- 每个语句都有一个**类型**(做什么)和**终端**(数据)
- **LHS** = 输出/目标,**RHS** = 输入/源
- 语句在字节码生成前实现**优化**
- 它们是**平台独立的**(可以生成不同的输出)
- 把它们想象成蓝图的**汇编语言**!

## 流水线

你的节点经过这个流水线:
1. 可视化节点(你看到的)
2. 语句(结构化操作)
3. 字节码(运行的)

语句是**真正编译**发生的地方!

## 想要更多细节?

完整的语句分解:
- [从蓝图到字节码 I - FBlueprintCompiledStatement](/zh-CN/posts/bpvm-bytecode-I/#fblueprintcompiledstatement)
- [从蓝图到字节码 IV - 语句处理](/zh-CN/posts/bpvm-bytecode-IV/)

下一篇:DAG 调度器如何排序你的节点!

---

**🍿 BPVM 小食包系列**
- [← #11: 链接和绑定](/zh-CN/posts/bpvm-snack-11-linking-binding/)
- **#12: 语句 101** ← 你在这里
- [#13: DAG 调度器](/zh-CN/posts/bpvm-snack-13-dag-scheduler/) →
