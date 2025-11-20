---
layout: post
title: "BPVM 小食包 #8 - 清理和净化:内存回收技巧"
description: "蓝图类在编译期间不会被删除和重新创建。它们像白板一样被清理和重用。这里介绍使热重载成为可能的聪明技巧。"
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

## 重新编译问题

你点击蓝图上的编译按钮。类需要用新的属性、函数和逻辑重新构建。

**天真的方法:**
```cpp
// 删除旧类
delete OldBlueprintClass;

// 创建新类
UClass* NewClass = new UBlueprintGeneratedClass();

// 现在修复引擎中的每个指针...
UpdateMillionsOfPointers(OldClass, NewClass);  // 噩梦!
```

这将是一场**灾难**。每个 actor、每个引用、每个指针都会断裂!

## 白板解决方案

虚幻的聪明技巧:**不要删除类。清理它并重用它**!

```cpp
void CleanAndSanitizeClass(UBlueprintGeneratedClass* ClassToClean)
{
    // 相同的内存地址,相同的指针
    // 只是擦除内容并写入新东西!
}
```

把它想象成白板:
- 当你需要写新东西时,你不会扔掉白板
- 你只是擦除它并再次书写
- 白板(内存地址)停留在同一个地方!

## 瞬态垃圾类

但等等——你不能只是删除属性和函数。其他系统可能正在使用它们!

进入 **TRASHCLASS**:

```cpp
// 创建临时垃圾桶
FName TrashName = "TRASHCLASS_MyBlueprint";
UClass* TransientClass = NewObject<UBlueprintGeneratedClass>(
    GetTransientPackage(),  // 特殊的临时包
    TrashName,
    RF_Transient  // 将被垃圾回收
);

// 将旧东西移到垃圾桶
MovePropertiesToTrash(ClassToClean, TransientClass);
MoveFunctionsToTrash(ClassToClean, TransientClass);
```

这就像为类成员有一个**"回收站"**!

## 什么被移到垃圾桶?

所有将被重新生成的东西:

```cpp
// 获取所有子对象
TArray<UObject*> ClassSubObjects;
GetObjectsWithOuter(ClassToClean, ClassSubObjects);

for (UObject* SubObj : ClassSubObjects) {
    if (ShouldBeSaved(SubObj)) {
        continue;  // 保留特殊对象
    }

    // 移到垃圾桶
    SubObj->Rename(nullptr, TransientClass);
}
```

垃圾桶将包含:
- 旧属性(变量)
- 旧函数
- 旧组件
- 旧元数据
- 基本上除了 CDO 之外的一切!

## CDO 保护

类默认对象获得**特殊待遇**:

```cpp
// 保存旧 CDO(它有用户的默认值!)
UObject* OldCDO = ClassToClean->GetDefaultObject();

// 重命名它以保护它
FName OldCDOName = "BPGC_ARCH_OldCDO";
OldCDO->Rename(*OldCDOName, TransientClass);

// 稍后,重新编译后...
// 从旧 CDO 复制默认值到新 CDO
FBlueprintEditorUtils::PropagateDefaultValueChange(OldCDO, NewCDO);
```

你的默认值存活是因为 CDO 被**保护和复制**!

## 干净的石板

将所有东西移到垃圾桶后:

```cpp
// 清空所有数组
ClassToClean->NetFields.Empty();
ClassToClean->ClassReps.Empty();
ClassToClean->FuncMap.Empty();

// 重置所有指针
ClassToClean->Children = nullptr;
ClassToClean->PropertiesSize = 0;
ClassToClean->MinAlignment = 0;

// 清除所有标志
ClassToClean->ClassFlags &= ~BadFlags;

// 类现在是一块空白的石板!
```

这就像进行**出厂重置**但保留序列号!

## 为什么这很重要

**1. 指针保持有效**
```cpp
AActor* MyActor = GetActor();
// 重新编译发生...
MyActor->GetClass();  // 仍然有效!相同的内存地址!
```

**2. 热重载工作**
```cpp
// 在游戏中,蓝图被重新编译
CleanAndSanitizeClass(BlueprintClass);
RegenerateClass(BlueprintClass);
// 游戏不会崩溃!所有引用仍然有效!
```

**3. 循环依赖解决**
```cpp
// BP_A 引用 BP_B
// BP_B 引用 BP_A
// 两者都可以重新编译,因为地址不变!
```

## 垃圾回收魔法

垃圾桶会怎样?

```cpp
// TransientClass 标记为 RF_Transient
// 下次垃圾回收...
if (Object->HasAnyFlags(RF_Transient)) {
    delete Object;  // 垃圾被回收!
}
```

垃圾类在下一个 GC 周期**自动消失**!

## 视觉类比

想象翻新房子:

**糟糕的方式(新地址):**
1. 拆除房子
2. 在新位置建造新房子
3. 更新每个人的地址簿
4. 转发所有邮件
5. 更新 GPS 系统

**虚幻的方式(相同地址):**
1. 将家具移到仓库(垃圾桶)
2. 清空内部(清理)
3. 重建内部(净化)
4. 搬入新家具
5. 地址从未改变!

## 快速要点

- 蓝图类在编译期间被**重用,不是重新创建**
- 旧成员移动到瞬态包中的 **TRASHCLASS**
- **CDO 被保护**以保留默认值
- 内存地址保持不变(不需要指针修复!)
- 垃圾被**自动垃圾回收**
- 这使得**热重载**不会崩溃!

## 回收冠军

下次你在游戏运行时重新编译蓝图而它没有崩溃时,感谢清理和净化系统。它是使虚幻的热重载感觉像魔法的无名英雄!

## 想要更多细节?

有关完整的清理和净化分解:
- [从蓝图到字节码 III - 清理和净化](/posts/bpvm-bytecode-III/#clean-and-sanitize-class)

下一个:你的蓝图变量如何成为真正的属性!

---

**🍿 BPVM 小食包系列**
- [← #7: 节点处理器解释](/zh-CN/posts/bpvm-snack-07-node-handlers/)
- **#8: 清理和净化魔法** ← 你在这里
- [#9: 变量变成属性](/zh-CN/posts/bpvm-snack-09-variables-properties/) →
