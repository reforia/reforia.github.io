---
layout: post
title: "BPVM 小食包 #17 - 字节码中的函数调用:调用约定"
description: "蓝图字节码中的函数调用很复杂!参数需要复制,返回值需要处理,栈需要管理。这就是它的工作原理。"
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

## 函数调用问题

你调用 `PrintString("Hello")`。简单,对吧?

在底层,虚拟机需要:
1. **找到**函数
2. **复制**参数到函数的栈
3. **调用**函数
4. **复制**返回值回来
5. **清理**栈

它比看起来复杂得多!

## 字节码解剖

这是一个函数调用变成的样子:

```
$44: EX_CallFunction (FFrame::Step)
    $8: Function pointer → PrintString
    // 参数开始
    $1F: String "Hello"              // 参数 1
    $B: EX_Nothing                   // 参数结束
    // 现在执行函数
```

让我们分解它!

## 步骤 1: 函数识别

```cpp
$44: EX_CallFunction
    $8: Function PrintString
```

虚拟机需要:
```cpp
UFunction* Function = ReadPointerFromScript();
// 现在我们知道要调用什么
```

## 步骤 2: 参数空间分配

```cpp
// 分配临时参数缓冲区
uint8* ParamBuffer = (uint8*)FMemory_Alloca(Function->ParmsSize);

// 初始化为零
FMemory::Memzero(ParamBuffer, Function->ParmsSize);
```

虚拟机为参数创建一个**临时栈帧**!

## 步骤 3: 参数复制

对于每个参数:

```cpp
// 蓝图
PrintString("Hello", true, FLinearColor::Red)

// 字节码
$44: EX_CallFunction
    $8: PrintString
    $1F: String "Hello"          // 复制字符串
    $27: Bool true               // 复制布尔值
    $3A: Struct FLinearColor     // 复制结构体
    $B: EX_Nothing
```

每个参数都被**复制**到参数缓冲区!

## 步骤 4: 实际调用

```cpp
// ProcessInternal 是虚拟机的函数执行器
Function->ProcessInternal(Stack, ParamBuffer);

// 在 ProcessInternal 内部:
if (Function->IsNative()) {
    // 调用 C++ 函数
    Function->Invoke(Context, ParamBuffer);
} else {
    // 执行蓝图字节码
    ProcessScriptFunction(Context, Function);
}
```

本地函数跳转到 C++,蓝图函数执行更多字节码!

## 步骤 5: 返回值处理

```cpp
// 蓝图
Result = Add(5, 10)

// 字节码
$44: EX_CallFunction
    $8: Add
    $1C: Int 5           // 参数 1
    $1C: Int 10          // 参数 2
    $B: EX_Nothing
// 返回值复制到 Result 变量
$F: Let                  // 赋值
    $0: Local Result     // 目标
```

返回值被**复制回**你的变量!

## 隐藏的成本:复制

每个参数和返回值都被**复制**:

```cpp
// C++(快 - 无复制)
PrintString(MyString);  // 通过 const 引用传递

// 蓝图(慢 - 必须复制)
ParamBuffer.MyString = CopyString(MyString);
PrintString(ParamBuffer.MyString);
Result = CopyString(ParamBuffer.ReturnValue);
```

这就是为什么蓝图比 C++ 慢!

## 结构体参数很昂贵

```cpp
// 传递大结构体
CallFunction(FHitResult)

// 虚拟机必须:
CopyStruct(FHitResult, 200+ 字节)  // 昂贵!
CallFunction()
CopyStruct(ReturnValue, 200+ 字节) // 昂贵!
```

大结构体 = 大量复制!

## 引用参数

一些函数使用引用来避免复制:

```cpp
// C++ 签名
void ModifyActor(AActor*& OutActor);

// 字节码
$44: EX_CallFunction
    $8: ModifyActor
    $0: Reference to Local OutActor  // 无复制!只是指针!
    $B: EX_Nothing
```

引用是**指针**,不是副本(快得多)!

## 参数栈

虚拟机维护一个**参数栈**:

```cpp
// 嵌套调用
A( B( C(5) ) )

// 栈增长:
Push 5         // 用于 C
Call C()
Push result    // 用于 B
Call B()
Push result    // 用于 A
Call A()
Pop result     // 最终结果
```

深调用链 = 更深的栈!

## Out 参数

具有多个输出的函数:

```cpp
// 蓝图
GetPlayerController() → Controller, Index

// 字节码
$44: EX_CallFunction
    $8: GetPlayerController
    // Out 参数是地址!
    $0: Address of Controller    // 写结果 1 的地方
    $1: Address of Index          // 写结果 2 的地方
    $B: EX_Nothing
```

Out 参数接收**地址**,而不是值!

## 委托调用是特殊的

```cpp
// 委托调用
MyDelegate.Broadcast(Param)

// 字节码
$46: EX_CallMulticastDelegate  // 不同的操作码!
    $0: Delegate MyDelegate
    $1F: Param value
    $B: EX_Nothing
```

委托使用**特殊操作码**,因为它们调用多个函数!

## 快速要点

- 函数调用变成 **EX_CallFunction** 字节码
- **所有参数都被复制**到临时缓冲区
- **返回值被复制**回来
- 大结构体**很昂贵**(大量复制!)
- 引用避免复制(使用指针代替)
- Out 参数接收**地址**
- 本地函数跳转到 C++,蓝图函数执行更多字节码
- 深调用链创建**深栈**

## 隐藏的开销

每次调用蓝图函数,虚拟机:
1. 分配参数空间
2. 复制所有输入
3. 执行函数
4. 复制返回值
5. 清理栈

这个开销是蓝图比 C++ 慢的原因 - 不是因为逻辑慢,而是因为**参数传递**有开销!

## 想要更多细节?

完整的函数调用分解与示例:
- [从蓝图到字节码 V - 函数调用分析](/zh-CN/posts/bpvm-bytecode-V/)

下一篇:为什么蓝图本质上比 C++ 慢!

---

**🍿 BPVM 小食包系列**
- [← #16: 阅读字节码](/zh-CN/posts/bpvm-snack-16-reading-bytecode/)
- **#17: 字节码中的函数调用** ← 你在这里
- [#18: 为什么蓝图更慢](/zh-CN/posts/bpvm-snack-18-blueprint-slower/) →
