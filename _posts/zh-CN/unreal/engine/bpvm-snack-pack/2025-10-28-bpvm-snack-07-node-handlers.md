---
layout: post
title: "BPVM 小食包 #7 - 节点处理器:翻译小队"
description: "你的蓝图中的每个节点都需要一个翻译器。认识节点处理器——将你的可视节点转换为可执行代码的无名英雄。"
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.6.0" %}

> **BPVM 小食包** - 快速蓝图知识投放![蓝图到字节码系列](/posts/bpvm-bytecode-I/)的一部分。
{: .prompt-tip }

## 翻译问题

你拖动一个"Select"节点到你的蓝图中。你连接一些引脚。你点击编译。

但等等——那个可视节点如何成为实际的可执行代码?

![Select node in Blueprint editor](bytecode_selectnode.png){: width="500" }

## 进入节点处理器

每个节点类型都有一个**专用翻译器**叫做节点处理器 (Node Handler):

```cpp
// 对于每个 UK2Node 类型...
UK2Node_Select  →  FKCHandler_Select
UK2Node_CallFunction  →  FKCHandler_CallFunction
UK2Node_VariableGet  →  FKCHandler_VariableGet
// ... 还有数百个!
```

把它们想象成联合国的**专业翻译**:
- 每个处理器讲一种"节点语言"
- 它们都翻译成相同的"字节码语言"
- 没有它们,你的节点只是漂亮的图片!

## 处理器模式

每个处理器遵循相同的模式:

```cpp
class FKCHandler_Select : public FNodeHandlingFunctor
{
public:
    // 步骤 1: "我需要什么数据?"
    virtual void RegisterNets(FKismetFunctionContext& Context, UEdGraphNode* Node);

    // 步骤 2: "我如何翻译这个?"
    virtual void Compile(FKismetFunctionContext& Context, UEdGraphNode* Node);
};
```

两个工作,清晰的关注点分离!

## RegisterNets: 设置阶段

在编译之前,处理器需要**注册它们的数据需求**:

```cpp
void FKCHandler_Select::RegisterNets(Context, Node)
{
    // "我需要这些引脚的存储!"

    // 注册索引引脚
    FBPTerminal* IndexTerm = Context.CreateLocalTerminal();
    Context.NetMap.Add(IndexPin, IndexTerm);

    // 注册每个选项引脚
    for (UEdGraphPin* Pin : OptionPins) {
        FBPTerminal* Term = Context.CreateLocalTerminal();
        Context.NetMap.Add(Pin, Term);
    }

    // 注册输出
    FBPTerminal* OutputTerm = Context.CreateLocalTerminal();
    Context.NetMap.Add(OutputPin, OutputTerm);
}
```

这就像在使用之前声明变量——**首先预留内存**!

## Compile: 翻译阶段

现在实际的翻译发生了:

```cpp
void FKCHandler_Select::Compile(Context, Node)
{
    // 创建字节码语句
    FBlueprintCompiledStatement* Statement = new FBlueprintCompiledStatement();
    Statement->Type = KCST_SwitchValue;  // "这是一个开关操作"

    // 获取我们注册的终端
    FBPTerminal* IndexTerm = Context.NetMap.FindRef(IndexPin);
    FBPTerminal* OutputTerm = Context.NetMap.FindRef(OutputPin);

    // 构建开关逻辑
    Statement->LHS = OutputTerm;  // 存储结果的地方
    Statement->RHS.Add(IndexTerm);  // 要开关的内容

    // 添加每个 case
    for (int32 i = 0; i < Options.Num(); i++) {
        Statement->RHS.Add(OptionTerms[i]);
    }
}
```

## 真实例子: Select 节点

让我们看看 Select 节点如何被翻译:

**你看到的:**
```
Index: 2
Option 0: "Hello"
Option 1: "World"
Option 2: "!"      <-- 被选中!
Output: "!"
```

**RegisterNets 做的:**
```cpp
// 预留内存槽
Terminal_0 = Index (integer)
Terminal_1 = Option0 (string)
Terminal_2 = Option1 (string)
Terminal_3 = Option2 (string)
Terminal_4 = Output (string)
```

**Compile 创建的:**
```cpp
Statement: KCST_SwitchValue
LHS: Terminal_4 (输出)
RHS: [
    Terminal_0,  // 索引
    Terminal_1,  // Case 0
    Terminal_2,  // Case 1
    Terminal_3   // Case 2
]
```

## 处理器注册表

编译器维护一个处理器的**巨大映射**:

```cpp
// 在编译器初始化期间
NodeHandlers.Add(UK2Node_Select::StaticClass(), new FKCHandler_Select());
NodeHandlers.Add(UK2Node_CallFunction::StaticClass(), new FKCHandler_CallFunction());
NodeHandlers.Add(UK2Node_VariableGet::StaticClass(), new FKCHandler_VariableGet());
// ... 还有数百个
```

编译你的图表时:
```cpp
for (UEdGraphNode* Node : Graph->Nodes) {
    // 找到正确的翻译器
    FNodeHandlingFunctor* Handler = NodeHandlers.FindRef(Node->GetClass());

    if (Handler) {
        Handler->RegisterNets(Context, Node);  // 设置
        Handler->Compile(Context, Node);        // 翻译
    }
}
```

## 为什么两个阶段?

**为什么不直接编译?**

编译器需要在生成代码之前了解所有变量:

```cpp
// 坏的:边走边编译
CompileNode(A);  // 创建变量 X
CompileNode(B);  // 需要变量 X... 它存在吗?

// 好的:两个阶段
RegisterNets(A);  // 声明变量 X
RegisterNets(B);  // 声明变量 Y
Compile(A);       // 使用变量 X(保证存在)
Compile(B);       // 使用变量 X 和 Y(都存在!)
```

## 特殊处理器能力

一些处理器有**特殊能力**:

```cpp
class FKCHandler_CallFunction : public FNodeHandlingFunctor
{
    // 特殊能力:可以优化某些调用!
    virtual void Transform(FKismetFunctionContext& Context, UEdGraphNode* Node) {
        // 如果可能,将 Print(String) 转换为快速路径
    }

    // 特殊能力:为签名提前运行!
    virtual bool RequiresRegisterNetsBeforeScheduling() {
        return true;  // 函数入口/出口节点需要这个
    }
};
```

## 语句输出

处理器产生**中间语句**(还不是字节码!):

```cpp
// 处理器产生这个:
Statement {
    Type: KCST_CallFunction
    Function: "PrintString"
    Parameters: ["Hello World"]
}

// 后端稍后转换为字节码:
0x44 (EX_CallFunc)
0x08 (Function ID)
"Hello World"
0x53 (EX_Return)
```

这是一个**两级火箭** - 处理器让你进入轨道,后端让你到达月球!

## 快速要点

- 每个节点类型都有一个**节点处理器**(它的个人翻译器)
- **RegisterNets**: "我需要这些变量"(设置阶段)
- **Compile**: "这是如何执行我"(翻译阶段)
- 处理器产生**语句**,不是字节码(那个稍后来)
- 两个阶段确保所有变量在使用前存在
- 这是**策略模式**在行动——每个节点类型一个处理器!

## 你的节点活起来了

下次你拖动一个节点到你的蓝图时,记住:
- 那个节点有一个专用的处理器等待翻译它
- RegisterNets 首先运行以设置工作空间
- Compile 其次运行以生成逻辑
- 没有处理器,你的节点只会是漂亮的图片!

## 想要更多细节?

有关完整的处理器深入:
- [从蓝图到字节码 I - 节点处理器](/posts/bpvm-bytecode-I/#fnodehandlingfunctor)
- [从蓝图到字节码 IV - 语句生成](/posts/bpvm-bytecode-IV/)

下一份小食:清理和净化的魔法!

---

**🍿 BPVM 小食包系列**
- [← #6: CDO 之谜](/zh-CN/posts/bpvm-snack-06-cdo-mystery/)
- **#7: 节点处理器解释** ← 你在这里
- [#8: 清理和净化魔法](/zh-CN/posts/bpvm-snack-08-clean-sanitize/) →
