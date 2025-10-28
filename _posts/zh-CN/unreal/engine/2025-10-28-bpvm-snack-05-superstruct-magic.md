---
layout: post
title: "BPVM 小食包 #5 - SuperStruct: 基于指针的继承"
description: "蓝图类不使用 C++ 继承。它们通过 SuperStruct 使用基于指针的系统。这里解释为什么这种设计很重要。"
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

## C++ 继承 vs 蓝图继承

当你从 `AMyActor` 创建蓝图时,编辑器说你正在创建 `AMyActor` 的**子类**。

从 API 的角度来看这是对的——它*表现*像一个子类。但实现与 C++ 继承完全不同。

## 真正的 C++ 继承是什么样的

```cpp
// 真正的 C++ 继承
class AMyChildActor : public AMyActor  // ✅ 真正的继承
{
    // 编译器创建 vtable
    // 内存布局包括父级的数据
    // 链接器解析函数地址
};
```

使用真正的继承:
- **编译器**在编译时将关系烘焙到二进制中
- **vtable** 是静态链接的
- **内存布局**包括所有父级成员
- 一切都是**静态解析的**(快,但不灵活)

## 蓝图"继承"实际上是什么

```cpp
// 蓝图的方法
class UBlueprintGeneratedClass : public UClass  // 不是 AMyActor!
{
    // 这是一个 UClass,不是你的 actor!
};

// 在编译期间的某个地方:
GeneratedClass->SetSuperStruct(AMyActor::StaticClass());
```

这是关键见解:

1. `UBlueprintGeneratedClass` 从 `UClass` 继承(不是你的 actor!)
2. 它通过 `SetSuperStruct()` 存储指向父级的**指针**
3. 当你调用 `GetSuperClass()` 时,它跟随那个指针

这是**组合 + 委托**,不是传统继承。

## 指针链

这是实际的关系:

```cpp
UBlueprintGeneratedClass* GeneratedClass;
// |
// | SetSuperStruct()
// v
UClass* ParentClass = AMyActor::StaticClass();
// |
// | GetSuperClass()
// v
UClass* GrandParent = AActor::StaticClass();
// |
// v
UObject::StaticClass();
```

它是一个**指针的链表**,不是 C++ 继承!

## 为什么这很重要

**问题 1: 属性查找**

当你访问蓝图实例上的变量时:
```cpp
// BP_MyActor 有变量 "Health"
float MyHealth = MyActor->Health;
```

底层:
1. 在 `GeneratedClass` 属性中查找 `Health`
2. 没找到?跟随 `SuperStruct` 指针到父级
3. 重复直到找到或到达 `UObject`

这是**运行时反射**,不是编译时!

**问题 2: 函数调用**

当你调用函数时:
```cpp
MyActor->Foo();
```

引擎:
1. 检查 `GeneratedClass` 是否覆盖 `Foo`
2. 如果没有,跟随 `SuperStruct` 链
3. 在父类中找到函数
4. 执行(可能是字节码或原生 C++)

再次,**运行时查找**!

## 好处

为什么使用指针而不是真正的继承?

**1. 热重载**
```cpp
// 在游戏运行时重新编译蓝图
GeneratedClass->CleanAndSanitize();  // 清除旧数据
Compile(Blueprint);                   // 填充新数据
Reinstancer->UpdateInstances();       // 更新现有对象

// 仍然使用同一个 GeneratedClass 对象!
// 没有内存地址变化(有点...)
// 不需要指针修复
```

**2. 动态类创建**
```cpp
// 在运行时创建蓝图类!
UBlueprint* NewBP = CreateBlueprint(...);
Compile(NewBP);
// 现在你有一个新的"类"
```

**3. 循环依赖**
```cpp
BP_A->SetSuperStruct(BP_B);  // A "继承自" B
BP_B->SetSuperStruct(BP_A);  // 错误:会创建循环!

// 但指针系统可以检测到这一点
// 并创建骨架类作为中介
```

## 权衡

**C++ 继承(快):**
```cpp
class Child : public Parent {  };
// 编译时:vtable,内存布局
// 运行时:直接内存访问,无需查找
```

**蓝图 SuperStruct(灵活):**
```cpp
Generated->SetSuperStruct(Parent);
// 编译时:没有烘焙进去
// 运行时:指针追逐,反射查找
```

蓝图用性能换取灵活性——经典的游戏开发权衡。

## 如何思考它

**错误的心智模型:**
```cpp
BP_MyActor : public AMyActor  // ❌ 不是正在发生的事
```

**好的心智模型:**
```cpp
class BP_MyActor {
    UClass* Parent = AMyActor::StaticClass();  // ✅ 指针关系
    TArray<FProperty*> MyProperties;
    TArray<UFunction*> MyFunctions;
    TArray<uint8> Bytecode;
};
```

## 快速要点

- 蓝图类**不**使用 C++ 继承
- 它们使用 `SetSuperStruct()` / `GetSuperClass()`(指针链)
- 这使得**热重载**和**运行时类创建**成为可能
- 权衡:更灵活,但比 C++ 继承慢
- 反射系统使它对开发者**看起来像**继承

## 抽象起作用

从你的蓝图代码来看,它的行为完全像继承:
```cpp
// 在你的蓝图中,这就是有效的
Parent::MyFunction();  // 调用父级版本
Super::Tick();         // 调用父级 tick
```

但在底层,这都是指针追逐和反射查找。抽象非常好,以至于大多数开发者永远不需要知道区别。

## 想要更多细节?

有关代码的完整解释:
- [从蓝图到字节码 I - UBlueprintGeneratedClass](/posts/bpvm-bytecode-I/#ublueprintgeneratedclass)

下一份小食:神秘的类默认对象 (CDO)!

---

**🍿 BPVM 小食包系列**
- [← #4: 骨架类](/zh-CN/posts/bpvm-snack-04-skeleton-classes/)
- **#5: SuperStruct 魔法技巧** ← 你在这里
- [#6: CDO 之谜](/zh-CN/posts/bpvm-snack-06-cdo-mystery/) →
