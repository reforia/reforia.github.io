---
layout: post
title: "BPVM 小食包 #16 - 阅读字节码:矩阵揭秘"
description: "曾经想知道你编译的蓝图实际是什么样子吗?这里教你如何阅读字节码输出并理解你的节点变成了什么。"
tldr: >-
  在 [Kismet] 配置下设置 CompileDisplaysBinaryBackend=True，即可将编译后的蓝图字节码
  以可读的反汇编形式输出到日志:其中 $XX 十六进制标记是 EExprToken 操作码(如 $44
  EX_CallFunction),Label_0xXX 按字节偏移标记跳转目标,而每个 Ubergraph 都以一张计算跳转表
  开头,在这台栈机器虚拟机上将各事件路由到对应的入口点。
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

## 启用字节码输出

首先,你需要看到字节码!将这个添加到你的配置:

```ini
[Kismet]
CompileDisplaysBinaryBackend=True
```

现在当你编译时,输出日志会显示**实际的字节码**!

## 字节码格式

你的蓝图变成这样的文本:

```
LogK2Compiler: [function ExecuteUbergraph_BPA_MyActor]:
Label_0x0:
    $4E: Computed Jump, offset specified by expression:
        $0: Local variable of type int32 named EntryPoint
Label_0x10:
    $44: EX_CallFunction (FFrame::Step)
        $8: Function PrintString
        $B: EX_Nothing
    $4: Return expression
        $B: EX_Nothing
Label_0x20:
    $53: EX_EndOfScript
```

它看起来像蓝图的**汇编语言**!

## 理解符号

**$XX:** EExprToken(指令或数据)
```cpp
$44 = EX_CallFunction  // 调用函数
$0  = EX_LocalVariable // 局部变量
$4  = EX_Return        // 从函数返回
$53 = EX_EndOfScript   // 字节码结束
```

这些是**虚拟机操作码**!

## 标签是跳转目标

```
Label_0x0:   // 偏移 0 字节
Label_0x10:  // 偏移 16 字节
Label_0x20:  // 偏移 32 字节
```

标签标记**跳转去的地方**。数字是从函数开始的字节偏移!

## 阅读函数调用

```
$44: EX_CallFunction (FFrame::Step)
    $8: Function PrintString
    "Hello World"
    $B: EX_Nothing
```

翻译:
1. **$44** = "我在调用一个函数"
2. **$8** = "这是函数指针"
3. **"Hello World"** = "这是参数"
4. **$B** = "参数结束"

## Ubergraph 之谜

```
[function ExecuteUbergraph_BPA_MyActor]:
Label_0x0:
    $4E: Computed Jump, offset specified by expression:
        $0: Local variable of type int32 named EntryPoint
```

记得 Ubergraph 吗?它从**跳转表**开始:
- EntryPoint 0 = BeginPlay
- EntryPoint 1 = Tick
- EntryPoint 2 = 你的自定义事件

虚拟机根据触发的事件**跳转到正确的入口**!

## 阅读变量

```
$0: Local variable of type float named Health
$1A: Self
$11: Object variable Property /Script/Engine.Actor:RootComponent
```

变量显示:
- **类型**(float、int、object)
- **名称**(Health、RootComponent)
- **作用域**(Local、Self、Property)

## 常见 EExprToken 值

这是一个速查表($ 前缀表示反汇编中显示的十六进制值):

```cpp
$00 = EX_LocalVariable       // 局部变量 (hex: 0x00)
$0B = EX_Nothing             // Null/空 (hex: 0x0B)
$04 = EX_Return              // 返回 (hex: 0x04)
$06 = EX_Jump                // 无条件跳转 (hex: 0x06)
$07 = EX_JumpIfNot           // 条件跳转 (hex: 0x07)
$1A = EX_Self                // 'this' 指针 (hex: 0x1A)
$1C = EX_IntConst            // 整数字面量 (hex: 0x1C)
$1F = EX_StringConst         // 字符串字面量 (hex: 0x1F)
$27 = EX_ObjectConst         // 对象引用 (hex: 0x27)
$44 = EX_CallFunction        // 函数调用 (hex: 0x44)
$4E = EX_ComputedJump        // 跳转表 (hex: 0x4E)
$53 = EX_EndOfScript         // 结束标记 (hex: 0x53)
```

## 完整示例

**你的蓝图:**
```
BeginPlay → Print("Hello")
```

**字节码:**
```
[function ExecuteUbergraph_BP_MyActor]:
Label_0x0:
    $4E: Computed Jump            // 入口跳转表
        $0: EntryPoint

Label_0x10:                       // BeginPlay 入口
    $44: EX_CallFunction          // 调用函数
        $8: PrintString           // 要调用的函数
        $1F: String "Hello"       // 参数
        $B: EX_Nothing            // 参数结束
    $4: Return                    // 返回
        $B: EX_Nothing

Label_0x30:
    $53: EX_EndOfScript           // 全部完成
```

## 栈机器

虚拟机是一个**栈机器**:

```cpp
// 你的代码: A = B + 5

// 字节码:
Push B        // 将 B 放到栈上
Push 5        // 将 5 放到栈上
Add           // 弹出两个,相加,推送结果
Pop A         // 将结果弹出到 A
```

大多数操作在**虚拟栈**上工作!

## 为什么偏移量重要

```
Label_0x10: CallFunction
Label_0x20: Return
Label_0x22: EX_EndOfScript
```

虚拟机使用**字节偏移量**进行跳转:
```cpp
// 向前跳转 16 字节
JumpIfFalse 0x10  // 去到 Label_0x10
```

这全都是底层的**指针算术**!

## 阅读复杂逻辑

**分支节点:**
```
$7: EX_JumpIfNot              // 如果条件为假
    $0: Local bool Condition   // 检查这个变量
    Label_0x30                 // 跳到这里

// True 路径
CallFunction(DoSomething)

Label_0x30:                    // False 路径
CallFunction(DoSomethingElse)
```

分支变成**条件跳转**!

## 快速要点

- 在 **DefaultEngine.ini** 中启用字节码输出
- **$XX** = EExprToken(指令/数据)
- **Label_0xXX** = 字节偏移 XX 处的跳转目标
- **Ubergraph** 从计算的跳转表开始
- 虚拟机是一个**栈机器**(推送/弹出操作)
- 函数调用显示**函数 + 参数 + 结束标记**
- 分支变成**条件跳转**

## 看见矩阵

一旦你启用了字节码输出,你就可以准确地看到你的蓝图变成了什么。就像看见矩阵 - 那些漂亮的节点只是底层原始字节码的外表!

## 想要更多细节?

完整的字节码深入剖析与真实示例:
- [从蓝图到字节码 V - 字节码分析](/zh-CN/posts/bpvm-bytecode-V/)

下一篇:函数调用在字节码中如何工作!

---

**🍿 BPVM 小食包系列**
- [← #15: 优化解释](/zh-CN/posts/bpvm-snack-15-optimizations/)
- **#16: 阅读字节码** ← 你在这里
- [#17: 字节码中的函数调用](/zh-CN/posts/bpvm-snack-17-function-calls/) →
