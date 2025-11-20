---
layout: post
title: "BPVM 小食包 #6 - CDO 之谜:你的类的秘密模板"
description: "每个蓝图类都有一个没人谈论的隐藏模板对象。认识 CDO——定义'默认'真正含义的神秘实例。"
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

## 神秘对象

你创建了一个蓝图类。你还没有生成任何实例。但惊喜——**一个实例已经存在**。

它叫做类默认对象 (Class Default Object, CDO),自从你的类加载以来,它一直静静地存在于内存中。

## CDO 是什么?

把 CDO 想象成你的类的**主模具**:

```cpp
// 当你创建 BP_MyActor...
UClass* MyClass = BP_MyActor::StaticClass();

// 这已经存在了!
AActor* CDO = MyClass->GetDefaultObject();  // 秘密实例
```

CDO 是:
- 你的类的**真实实例**(它是内存中的实际对象!)
- 类加载时**自动创建**
- 从不在世界中生成(它存在于虚无中)
- 所有未来实例的**模板**

## 为什么每个类都需要一个?

**问题:** 当你生成一个 actor 时,它的默认值从哪里来?

**糟糕的解决方案:** 将默认值存储为元数据
```cpp
// 想象中的糟糕设计
class ClassMetadata {
    float DefaultHealth = 100;
    FString DefaultName = "Player";
    // 数百个属性...
};
```

**虚幻的解决方案:** 只需创建一个"完美"实例并从中复制!
```cpp
// CDO 就是默认值
AActor* CDO = GetDefault<AActor>();
CDO->Health = 100;  // 设置一次
CDO->Name = "Player";

// 生成从 CDO 复制
AActor* NewActor = SpawnActor();  // 从 CDO 复制所有属性
```

## 魔法时刻

当你在蓝图编辑器中编辑"默认"值时:

![Blueprint Editor showing default values](bytecode_hitcompile.png){: width="500" }

你不是在编辑元数据。**你在直接编辑 CDO**!

```cpp
// 在蓝图编辑器中,当你设置 Health = 100 时
CDO->Health = 100;  // 你确实在 CDO 上设置属性

// 稍后,生成时
NewInstance->Health = CDO->Health;  // 从 CDO 复制
```

## CDO 在行动

这是生命周期:

**1. 类创建**
```cpp
// 蓝图被编译
UBlueprintGeneratedClass* NewClass = CompileBlueprint();

// CDO 立即创建
UObject* CDO = NewClass->GetDefaultObject();
```

**2. 设置默认值**
```cpp
// 你在蓝图编辑器中编辑
CDO->MaxHealth = 150;
CDO->TeamColor = FColor::Red;
CDO->WeaponClass = AK47::StaticClass();
```

**3. 实例创建**
```cpp
// 玩家生成你的 actor
AActor* Instance = World->SpawnActor<AActor>(BP_MyActor);

// 底层:
// 1. 分配内存
// 2. 从 CDO 复制所有属性
// 3. 运行构造函数
```

## 恢复按钮之谜

曾经想知道"恢复到默认值"按钮是如何工作的吗?

它只是与 CDO 比较:
```cpp
bool IsModified = (Instance->Health != CDO->Health);
// 如果为真,显示黄色恢复按钮

void RevertToDefault() {
    Instance->Health = CDO->Health;  // 只是从 CDO 复制!
}
```

## CDO vs 构造函数默认值

**C++ 构造函数:**
```cpp
AMyActor::AMyActor() {
    Health = 100;  // 每次生成都运行
}
```

**CDO 系统:**
```cpp
// 在 CDO 上设置一次
CDO->Health = 100;

// 生成只是复制内存(更快!)
memcpy(NewInstance, CDO, sizeof(AActor));
```

CDO 方法对于生成许多实例**快得多**!

## 隐藏的 CDO 生命周期

**在编译期间:**
```cpp
void CompileBlueprint() {
    // 旧 CDO 仍然有玩家配置的默认值
    UObject* OldCDO = OldClass->GetDefaultObject();

    // 清理类
    CleanAndSanitizeClass(OldClass);

    // 重新编译一切
    CompileClass(NewClass);

    // 从旧 CDO 复制默认值到新 CDO!
    CopyPropertiesFrom(OldCDO, NewCDO);
}
```

这就是为什么你的默认值在重新编译后仍然存在!

## CDO 陷阱

**1. CDO 在编辑器和运行时都存在**
```cpp
// 在编辑器中
CDO->SomeProperty = 10;  // 编辑默认值

// 在打包的游戏中
CDO->SomeProperty;  // 仍然是 10!(现在只读)
```

**2. 永远不要在运行时修改 CDO**
```cpp
// 不要在游戏代码中这样做!
CDO->Health = 200;  // 你刚刚改变了所有未来生成的默认值!
```

**3. CDO 和热重载**
```cpp
// 在热重载期间
OldCDO->SaveDefaults();
RecompileClass();
NewCDO->RestoreDefaults();  // 你的设置保留了!
```

## 快速要点

- 每个类都有一个 **CDO** (类默认对象) - 一个隐藏的模板实例
- 当你在蓝图中编辑默认值时,你在**编辑 CDO**
- 生成 actor **从 CDO 复制属性**(快!)
- CDO 在重新编译中存活(这就是为什么默认值持久)
- **永远不要在运行时修改 CDO**(它影响所有未来的生成)

## CDO 无处不在

下次你:
- 在蓝图中设置默认值
- 点击恢复按钮
- 生成一个 actor
- 重新编译蓝图

记住:你在与 CDO 交互,这个秘密模板对象使虚幻的类系统工作!

## 想要更多细节?

有关代码的完整解释:
- [从蓝图到字节码 I - CDO 深入](/posts/bpvm-bytecode-I/#cdo)
- [从蓝图到字节码 III - 编译中的 CDO](/posts/bpvm-bytecode-III/#clean-and-sanitize-class)

下一个:节点处理器如何将你的图表变成代码!

---

**🍿 BPVM 小食包系列**
- [← #5: SuperStruct 魔法](/zh-CN/posts/bpvm-snack-05-superstruct-magic/)
- **#6: CDO 之谜** ← 你在这里
- [#7: 节点处理器解释](/zh-CN/posts/bpvm-snack-07-node-handlers/) →
