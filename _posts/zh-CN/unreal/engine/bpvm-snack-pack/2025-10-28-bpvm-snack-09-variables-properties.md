---
layout: post
title: "BPVM 小食包 #9 - 变量变成属性:转变过程"
description: "当你在蓝图中创建一个变量时,它还不是真正的变量。它只是一个等待变成真正属性的描述。这就是它的蜕变过程。"
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

## 变量的假象

在蓝图编辑器中,你点击"+变量"并创建 `Health`:

![蓝图编辑器中的变量创建]

你以为刚刚创建了一个变量。**并没有。**

你创建的是一个变量的**描述**。真正的变量还不存在!

## 认识 FBPVariableDescription

当你创建一个蓝图变量时,实际存储的是这个:

```cpp
struct FBPVariableDescription
{
    FName VarName;           // "Health"
    FEdGraphPinType VarType; // Float
    FString Category;        // "Stats"
    uint64 PropertyFlags;    // EditAnywhere, BlueprintReadWrite, 等等

    // 元数据
    FString Tooltip;         // "玩家的当前生命值"
    FName RepNotifyFunc;     // "OnRep_Health"

    // 还不是真正的属性!
};
```

它只是**关于变量的数据**,不是变量本身!

## 编译转换

在编译期间,这些描述变成了**真正的属性**:

```cpp
void CreateClassVariablesFromBlueprint()
{
    // 遍历所有变量描述
    for (FBPVariableDescription& Variable : Blueprint->NewVariables)
    {
        // 将描述转换为真正的属性!
        FProperty* NewProperty = CreateVariable(Variable.VarName, Variable.VarType);

        // 现在它是类上的真实属性了!
    }
}
```

## 属性的诞生

这是神奇的时刻:

```cpp
FProperty* CreateVariable(FName VarName, FEdGraphPinType& VarType)
{
    // 确定属性类型
    if (VarType.PinCategory == "Float") {
        // 创建真实的浮点数属性
        FFloatProperty* NewProp = new FFloatProperty(
            NewClass,     // 所有者类
            VarName,      // "Health"
            RF_Public     // 标志
        );

        // 它活了!真实的内存将被分配!
        return NewProp;
    }
}
```

## 为什么要两步流程?

**为什么不立即创建真实属性?**

**1. 编辑器性能**
```cpp
// 坏做法:每次编辑都创建真实属性
点击 +变量 → 分配内存
输入名称 → 重新分配
更改类型 → 再次重新分配
设置工具提示 → 再次重新分配

// 好做法:只更新描述
点击 +变量 → 创建描述
输入名称 → 更新字符串
更改类型 → 更新枚举
设置工具提示 → 更新字符串
// 只在编译时创建真实属性!
```

**2. 热重载安全**
```cpp
// 编辑期间(安全)
VariableDescription.VarName = "NewName";  // 只是数据

// 编译期间(小心!)
OldProperty->Destroy();
NewProperty = CreateProperty("NewName");  // 真实的内存操作
```

**3. 先验证**
```cpp
// 创建属性之前检查所有描述
for (auto& Desc : Variables) {
    if (IsDuplicate(Desc)) return;  // 造成破坏前就停止!
    if (IsInvalid(Desc)) return;
}
// 一切正常?现在创建真实属性
```

## 属性创建流水线

**步骤 1: 收集描述**
```cpp
TArray<FBPVariableDescription> Descriptions;
Descriptions.Add("Health", Float);
Descriptions.Add("Armor", Int32);
Descriptions.Add("Name", String);
```

**步骤 2: 按大小排序(优化!)**
```cpp
// 大属性在前,以获得更好的内存对齐
Descriptions.Sort([](auto& A, auto& B) {
    return GetSize(A) > GetSize(B);
});
```

**步骤 3: 创建真实属性**
```cpp
for (auto& Desc : Descriptions) {
    FProperty* Prop = CreatePropertyOnScope(
        NewClass,           // 它生活的地方
        Desc.VarName,       // 它的名字
        Desc.VarType        // 它的类型
    );

    // 配置属性
    Prop->SetPropertyFlags(Desc.PropertyFlags);
    Prop->SetMetaData("Tooltip", Desc.Tooltip);
}
```

**步骤 4: 链接到类**
```cpp
// 添加到类的属性链
NewClass->AddCppProperty(NewProperty);

// 计算内存偏移
NewProperty->Offset = CurrentOffset;
CurrentOffset += NewProperty->ElementSize;
```

## 特殊属性类型

一些变量需要**额外的转换**:

**时间轴变量:**
```cpp
// 你在编辑器中创建一个时间轴
"MyTimeline"

// 编译器创建多个属性:
FTimelineComponent* MyTimeline;        // 组件
FOnTimelineFloat MyTimeline_UpdateFunc; // 委托
FOnTimelineEvent MyTimeline_FinishFunc; // 委托
```

**组件变量:**
```cpp
// 你添加一个组件变量
"MyMeshComp" (StaticMeshComponent)

// 编译器做额外的工作:
CreateComponentProperty("MyMeshComp");
RegisterComponent("MyMeshComp");
SetupComponentDefaults("MyMeshComp");
```

## 内存布局

所有属性创建完成后:

```cpp
class BP_MyActor {
    // 内存布局(按大小排序!)
    0x0000: UStaticMeshComponent* MyMesh;  // 8 字节
    0x0008: FString Name;                   // 16 字节 (TArray)
    0x0018: float Health;                   // 4 字节
    0x001C: int32 Armor;                    // 4 字节
    0x0020: bool bIsAlive;                  // 1 字节
    0x0021: [填充]                          // 7 字节
    // 总大小: 0x0028 (40 字节)
}
```

编译器**优化布局**以提高缓存效率!

## 快速要点

- 蓝图变量从 **FBPVariableDescription** 开始(只是元数据)
- 在编译期间,它们变成 **FProperty** 对象(真实内存)
- 这个两步流程实现了**安全编辑**和**热重载**
- 属性**按大小排序**以获得最佳内存布局
- 特殊类型(Timeline、Component)创建**多个属性**
- 转换发生在 `CreateClassVariablesFromBlueprint()` 中

## 从描述到现实

下次你在蓝图中创建变量时,请记住:
- 你正在创建一个描述,而不是变量
- 真正的属性在编译期间诞生
- 两步流程使编辑器保持快速和安全
- 你的"简单"变量可能创建多个属性!

## 想要更多细节?

完整的属性创建分解:
- [从蓝图到字节码 III - 变量和组件](/zh-CN/posts/bpvm-bytecode-III/#variables-and-components)

接下来:函数是如何制造的!

---

**🍿 BPVM 小食包系列**
- [← #8: 清理和净化魔法](/zh-CN/posts/bpvm-snack-08-clean-sanitize/)
- **#9: 变量变成属性** ← 你在这里
- [#10: 函数工厂](/zh-CN/posts/bpvm-snack-10-function-factory/) →
