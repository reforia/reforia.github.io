---
layout: post
title: "BPVM 小食包 #4 - 骨架类:隐藏的英雄"
description: "当蓝图 B 还没编译时,蓝图 A 如何引用蓝图 B?骨架类——蓝图版本的前向声明。"
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.6.0" %}

> **BPVM 小食包** - 小口大小的蓝图知识![蓝图到字节码系列](/posts/bpvm-bytecode-I/)的一部分。
{: .prompt-tip }

## 循环依赖问题

这是多人游戏中的常见场景:

```
Blueprint_PlayerController 引用 Blueprint_GameMode
Blueprint_GameMode 引用 Blueprint_PlayerState
Blueprint_PlayerState 引用 Blueprint_PlayerController
```

经典的循环依赖。如何在不死锁的情况下编译这些?

## C++ 方式(在这里不起作用)

在 C++ 中,你会使用前向声明:

```cpp
class AMyGameMode;  // 前向声明

class AMyPlayerController : public APlayerController
{
    AMyGameMode* GameMode;  // 使用前向声明
};
```

但蓝图在运行时(或在编辑器中按需)编译。你不能只是"前向声明"一个蓝图!

## 解决方案:骨架类

虚幻通过两遍方法解决这个问题。在**阶段 VIII (重新编译骨架)**期间,它为每个蓝图类创建一个"骨架"版本:

```cpp
// 骨架类:只有结构,没有实现
class BP_PlayerController_SKEL : public APlayerController
{
    // 有所有属性
    UPROPERTY()
    ABP_GameMode* GameMode;

    // 有所有函数签名
    void DoSomething();

    // 但还没有字节码!
};
```

把它想象成 C++ 中的**头文件** (`.h`),但在编译时为蓝图生成。

## 它如何解决循环依赖

**阶段 1 - 创建骨架:**
```cpp
// 对于每个蓝图,首先创建骨架
BP_PlayerController_SKEL  // 只是形状
BP_GameMode_SKEL          // 只是形状
BP_PlayerState_SKEL       // 只是形状
```

**阶段 2 - 完整编译:**
```cpp
// 现在每个人都可以引用骨架!
BP_PlayerController 引用 BP_GameMode_SKEL ✅
BP_GameMode 引用 BP_PlayerState_SKEL ✅
BP_PlayerState 引用 BP_PlayerController_SKEL ✅
```

没有循环依赖!每个人都有东西可以引用。

## 骨架里有什么?

骨架类包含:

✅ **变量声明**(带类型)
```cpp
UPROPERTY()
float Health;  // 类型已知

UPROPERTY()
ABP_Enemy* Enemy;  // 类型已知
```

✅ **函数签名**(参数和返回类型)
```cpp
UFUNCTION()
void TakeDamage(float Amount);  // 签名已知

UFUNCTION()
float GetHealth();  // 返回类型已知
```

❌ **没有字节码**(实际的函数实现)
```cpp
// 函数存在但函数体是空的:
void TakeDamage(float Amount)
{
    // 这里还什么都没有!
}
```

## 两遍编译

这就是为什么蓝图编译分两个主要阶段进行:

**第一遍 - 仅骨架(快速):**
- 创建类结构
- 添加所有属性
- 添加所有函数签名
- **不生成字节码**

**第二遍 - 完整编译(较慢):**
- 为所有函数生成字节码
- 填充实现细节
- 更新所有实例

## 什么时候你会看到骨架?

你很少直接看到骨架类,但它们在幕后工作:

**场景 1 - 打开蓝图:**
```cpp
OpenBlueprint(BP_MyActor);
// 快速骨架编译发生
// → 现在可以在编辑器中看到变量/函数
// 当你点击"编译"时进行完整编译
```

**场景 2 - 循环引用:**
```cpp
BP_A 引用 BP_B
BP_B 引用 BP_A
// 两者首先都获得骨架类
// 然后两者都完全编译
// → 没有死锁!
```

**场景 3 - 加载游戏:**
```cpp
LoadLevel(MyLevel);
// 所有蓝图的骨架首先加载
// 然后按依赖顺序进行完整编译
```

## SKEL 命名约定

如果你在日志或崩溃中看到这个:

```
BP_MyActor_C_SKEL
```

那个 `_SKEL` 后缀意味着你正在查看一个骨架类。`_C` 是生成类的后缀。

## 快速要点

- **骨架类** = 类头文件(属性 + 函数签名,没有实现)
- 在编译的**阶段 VIII**创建
- 通过提供"可以引用的东西"解决**循环依赖**
- 把它想象成**智能前向声明**
- 在字节码生成后被完整类替换

## 为什么这很重要

理解骨架帮助你:
- 调试"缺少函数"错误(骨架编译了,完整编译失败了)
- 理解为什么编译分阶段进行
- 知道为什么循环依赖*通常*有效(但如果不小心仍然会导致问题)

## 想要更多细节?

有关代码示例的完整解释:
- [从蓝图到字节码 I - 骨架类](/posts/bpvm-bytecode-I/#skeleton-class)

下一份小食:我们将窥视"清理和净化"过程!

---

**🍿 BPVM 小食包系列**
- [← #3: 编译启动](/zh-CN/posts/bpvm-snack-03-compilation-kickoff/)
- **#4: 骨架类解释** ← 你在这里
- [#5: SuperStruct 魔法](/zh-CN/posts/bpvm-snack-05-superstruct-magic/) →
