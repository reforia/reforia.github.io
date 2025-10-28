---
layout: post
title: "BPVM 小食包 #1 - 蓝图到底是什么?"
description: "你刚创建的蓝图?它其实不是类。更像是一份配方。这里揭示它背后的真实结构。"
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.6.0" %}

> **BPVM 小食包**是深度系列文章[蓝图到字节码](/posts/bpvm-bytecode-I/)的配套系列。每一份小食都是3-5分钟快速阅读,拆解一个概念。非常适合咖啡休息时间!
{: .prompt-tip }

## 资产 vs 类

当你在内容浏览器中右键点击,基于 `AMyAwesomeActor` 创建一个"蓝图类"时,UI 告诉你正在创建 `AMyAwesomeActor` 的**子类**。

但实际情况是:你创建的是一个 `UBlueprint` 资产,它会在编译时*生成*一个类。

## 你实际创建了什么

你创建了一个 `UBlueprint` 对象。它不是你选择的那个类——它是制作你想要的类的*配方*。

它们的关系是:
- `UBlueprint` = 源资产(编辑器时数据,存在于内容浏览器)
- `UBlueprintGeneratedClass` = 编译后的类(运行时可执行,用于生成实例)
- 你的 `.uasset` 文件 = 磁盘上序列化的蓝图

![Blueprint Structure](bytecode_blueprintstructure.png)
_底层实际发生的事情_

## 真实的关系

当你从 `AMyAwesomeActor` 创建 `BP_MyAwesomeActor` 时,实际发生的是:

```cpp
// 你以为发生的事
class UBlueprintGeneratedClass : public AMyAwesomeActor  // ❌ 不对!

// BlueprintGeneratedClass.h 中实际发生的事
class UBlueprintGeneratedClass : public UClass  // ✅ 从 UClass 继承!
{
    // 没有从 AMyAwesomeActor 的 C++ 继承!
};

// 父级关系通过指针管理:
UBlueprint* Blueprint;
Blueprint->ParentClass = AMyAwesomeActor::StaticClass();  // 指向父级
Blueprint->GeneratedClass = GeneratedClass;               // 指向生成的类

GeneratedClass->SetSuperStruct(AMyAwesomeActor::StaticClass());  // 父级关系!
```

**关键见解:** `UBlueprint` 和 `UBlueprintGeneratedClass` 在 C++ 中都不是真正从 `AMyAwesomeActor` 继承的。它们使用虚幻的反射系统 (`SuperStruct`) 来*模拟*继承!

## 为什么这很重要

**在编辑器中:**
- 你使用 `UBlueprint`(配方)
- 你编辑图表、变量、组件
- 一切只存在于编辑器中

**在运行时:**
- 引擎使用 `UBlueprintGeneratedClass`(编译好的蛋糕)
- 这个类通过 `SetSuperStruct()` / `GetSuperClass()` **看起来像**继承
- 它**不是**真正的 C++ 继承(`class Generated : public Parent`)!
- 它是一个由反射系统管理的基于指针的父级关系
- 你的实例从这个生成的类中生成

## 热重载技巧

当你点击"编译"时,蓝图编辑器:
1. 获取你的 `UBlueprint` 配方
2. 将其编译为字节码
3. 把字节码塞进 `UBlueprintGeneratedClass`
4. **每次重新编译都重用同一个类对象**!

它不会创建新类——而是清空旧类并重新填充。这与热重载游戏内容的模式相同:保持内存地址稳定,在底层交换数据。这就是为什么重新编译时引用不会断裂。

(嗯,理论上是这样。Live Coding 有很大帮助但并不完美。传统热重载往往会留下到处散落的 `HOTRELOAD` 标记,如果你改变了任何结构性的东西,你可能需要重启编辑器。经常保存。)

## 快速要点

- **UBlueprint** = 仅编辑器的配方(你在内容浏览器中看到的)
- **UBlueprintGeneratedClass** = 运行时类(实际运行你的游戏的)
- 它们是连接的但**完全不同**的对象

## 想要更多细节?

这只是个开胃菜!如需完整深入了解,请查看:
- [从蓝图到字节码 I - 但蓝图是什么?](/posts/bpvm-bytecode-I/#ublueprint)

下一份小食:我们将探索那些彩色节点和连线*真正*是什么!

---

**🍿 BPVM 小食包系列**
- **#1: 蓝图到底是什么?** ← 你在这里
- [#2: 图表系统解码](/zh-CN/posts/bpvm-snack-02-graph-system/) →
