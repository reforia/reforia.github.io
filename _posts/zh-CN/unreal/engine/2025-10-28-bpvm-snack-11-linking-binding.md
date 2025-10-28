---
layout: post
title: "BPVM 小食包 #11 - 链接和绑定:最终组装"
description: "创建属性和函数后,它们只是松散的部件。链接和绑定将所有内容连接到一起,形成一个可工作的类。这就是最终的流水线。"
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

## 零散部件问题

编译后,你有:
- 属性已创建 ✓
- 函数已生成 ✓
- 内存已分配 ✓

但它们**没有连接**。就像拥有所有汽车零件但没有组装!

## 两步组装

虚幻使用两个操作来连接所有内容:

```cpp
// 步骤 1: 找到 C++ 连接
NewClass->Bind();

// 步骤 2: 链接所有属性
NewClass->StaticLink(true);
```

想象成:
1. **Bind**: 连接到引擎(找到方向盘)
2. **StaticLink**: 内部连接(连接仪表板)

## Bind(): 找到 C++ 函数

`Bind()` 搜索**三个关键事物**:

```cpp
void UClass::Bind()
{
    // 1. 找到构造函数
    ClassConstructor = FindConstructor();
    // "我如何创建实例?"

    // 2. 找到 VTable 辅助器
    ClassVTableHelperCtorCaller = FindVTableHelper();
    // "我如何设置虚函数?"

    // 3. 找到静态函数
    ClassCppStaticFunctions = FindStaticFunctions();
    // "我可以调用哪些 C++ 函数?"

    // 递归绑定父类
    if (GetSuperClass()) {
        GetSuperClass()->Bind();
    }
}
```

这就像为你的类找到**说明书**!

## 为什么 Bind 重要

没有 `Bind()`,蓝图无法:

```cpp
// 无法创建实例
AMyActor* Actor = NewObject<AMyActor>();  // 没有构造函数!

// 无法调用父函数
Super::BeginPlay();  // 没有 VTable!

// 无法调用静态函数
AMyActor::StaticFunction();  // 找不到!
```

`Bind()` 在蓝图和 C++ 之间创建了**桥梁**!

## StaticLink(): 属性链

`StaticLink()` 创建**属性链表**:

```cpp
void UStruct::StaticLink(bool bRelinkExistingProperties)
{
    // 将所有属性链接成一个链表
    FProperty* Previous = nullptr;
    for (FProperty* Prop : Properties) {
        if (Previous) {
            Previous->Next = Prop;
        }
        Prop->Offset = CalculateOffset(Prop);
        Previous = Prop;
    }

    // 计算总大小
    PropertiesSize = 0;
    for (FProperty* Prop : PropertyLink) {
        PropertiesSize += Prop->ElementSize;
    }
}
```

之前:属性存在但彼此不了解
之后:属性形成一个**链表**,具有计算的偏移量!

## 内存布局计算

`StaticLink()` 确定**所有内容存储的位置**:

```cpp
// StaticLink 之前
Property: Health (?)
Property: Armor (?)
Property: Name (?)

// StaticLink 之后
Property: Health → Offset: 0x0000 (4 字节)
Property: Armor  → Offset: 0x0004 (4 字节)
Property: Name   → Offset: 0x0008 (16 字节)
总大小: 0x0018 (24 字节)
```

现在引擎知道每个属性在内存中的**确切位置**!

## 引用链

属性可以相互引用:

```cpp
// 在 StaticLink 期间
FObjectProperty* MyActorRef;
MyActorRef->PropertyClass = AMyActor::StaticClass();
MyActorRef->LinkInternal();  // 连接到类!
```

这创建了对象之间的**引用网络**!

## 父类递归

两个操作都**递归**工作:

```cpp
// Bind() 向上遍历链
BP_MyActor::Bind()
  → AActor::Bind()
    → UObject::Bind()

// StaticLink() 也是
BP_MyActor::StaticLink()
  → AActor::StaticLink()
    → UObject::StaticLink()
```

继承的每一层都得到正确的连接!

## 对齐魔法

`StaticLink()` 还处理**内存对齐**:

```cpp
// 为 CPU 缓存优化
if (Property->Size == 1) {
    Alignment = 1;  // 字节可以放在任何地方
} else if (Property->Size <= 4) {
    Alignment = 4;  // 对齐到 4 字节
} else {
    Alignment = 8;  // 对齐到 8 字节
}
```

这使你的蓝图在运行时**更快**!

## 最终连接

两个操作之后:

```cpp
// 所有内容都连接了!
Class {
    Constructor: ✓ (由 Bind 找到)
    VTable: ✓ (由 Bind 找到)
    Properties: ✓ (由 StaticLink 链接)
    Size: 0x0018 ✓ (由 StaticLink 计算)
    Alignment: 8 ✓ (由 StaticLink 计算)
}
```

你的类现在是一台**完全功能的机器**!

## 真实世界示例

```cpp
// 你创建一个蓝图:
float Health = 100;
int32 Armor = 50;
AActor* Target;

// Bind() 和 StaticLink() 之后:
BP_MyClass {
    Constructor → AMyActor::AMyActor()  // 找到了!
    Properties → [
        0x00: Health (float, 4 字节)
        0x04: Armor (int32, 4 字节)
        0x08: Target (AActor*, 8 字节)
    ]
    总大小: 16 字节
    属性链: Health→Armor→Target→nullptr
}
```

## 快速要点

- **Bind()** 找到 C++ 函数(构造函数、VTable、静态函数)
- **StaticLink()** 连接属性并计算内存布局
- 属性变成具有偏移量的**链表**
- 内存被**对齐**以提高性能
- 两者都通过继承**递归**工作
- 它们一起将松散的部件转换为**可工作的类**!

## 组装完成

当编译完成 Bind() 和 StaticLink() 后,你的蓝图类不再是部件集合 - 它是一台完全组装的、准备运行的机器,每根线都连接好,每个螺栓都拧紧!

## 想要更多细节?

完整的链接过程:
- [从蓝图到字节码 III - 完成类编译](/zh-CN/posts/bpvm-bytecode-III/#finish-compiling-class)

下一篇:理解变成字节码的语句!

---

**🍿 BPVM 小食包系列**
- [← #10: 函数工厂](/zh-CN/posts/bpvm-snack-10-function-factory/)
- **#11: 链接和绑定** ← 你在这里
- [#12: 语句 101](/zh-CN/posts/bpvm-snack-12-statements/) →
