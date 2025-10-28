---
layout: post
title: "BPVM 小食包 #18 - 为什么蓝图更慢:性能真相"
description: "蓝图比 C++ 慢,但不是你可能想的那些原因。不是虚拟机 - 而是复制!这是真实的性能故事。"
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

## 性能问题

"为什么蓝图比 C++ 慢?"

你会听到的大多数答案都是**错的**。让我们破除一些神话!

## 神话 #1: "解释代码很慢"

**错!** 蓝图不是解释的 - 它被**编译为字节码**。

虚拟机非常高效地执行这个字节码。蓝图中的简单循环几乎和 C++ 一样快!

## 神话 #2: "可视化脚本有开销"

**错!** 可视化节点在编译时消失。

运行编译的蓝图有**零可视化开销**。那些节点只是编辑器表示!

## 真正的罪魁祸首:复制

这是真正的性能杀手:

```cpp
// C++(快)
void MyFunction(const FVector& Location) {
    // 直接内存访问,无复制
    UseLocation(Location);
}

// 蓝图(慢)
void MyFunction(FVector Location) {
    // 步骤 1: 将 FVector 复制到参数栈(12 字节)
    memcpy(ParamBuffer, &Location, sizeof(FVector));

    // 步骤 2: 执行函数

    // 步骤 3: 清理栈
    // 总计: 约 100 纳秒的复制开销!
}
```

每个函数调用都**复制数据**!

## 复制开销

让我们测量一下:

```cpp
// C++ 函数调用
MyFunc(Vector, Actor, String);
// 时间: 约 10 纳秒

// 蓝图函数调用
MyFunc(Vector, Actor, String);
// 时间: 约 50-100 纳秒
// 额外时间 = 复制参数!
```

蓝图仅从复制就**慢 5-10 倍**!

## 栈管理成本

虚拟机维护一个运行时栈:

```cpp
// C++(编译的栈管理)
void Call() {
    int Local = 5;  // 栈指针在编译时调整
}

// 蓝图(运行时栈管理)
void Call() {
    // 虚拟机在运行时分配栈空间
    uint8* Stack = AllocateStack(FunctionStackSize);

    // 虚拟机管理局部变量
    int* Local = (int*)(Stack + LocalOffset);

    // 虚拟机清理
    FreeStack(Stack);
}
```

运行时栈管理每次调用增加**微秒**!

## 类型检查开销

虚拟机进行**运行时类型检查**:

```cpp
// C++(编译时,零成本)
AActor* MyActor = GetActor();  // 编译器验证类型

// 蓝图(运行时成本)
AActor* MyActor = GetActor();
// 虚拟机检查:"这真的是 AActor* 吗?"
if (!MyActor->IsA(AActor::StaticClass())) {
    Error();
}
```

安全有一个**小成本**!

## 反射系统使用

蓝图对**所有事情**都使用反射:

```cpp
// C++(直接访问)
float Health = Actor->Health;  // 直接内存读取
// 时间: 1 纳秒

// 蓝图(反射)
FProperty* Prop = FindProperty("Health");  // 查找!
float Health = Prop->GetFloatValue(Actor);  // 间接读取!
// 时间: 10-50 纳秒
```

反射灵活但**更慢**!

## 真实性能数字

让我们对常见操作进行基准测试:

**变量访问:**
- C++: 1-2 ns
- 蓝图: 5-10 ns
- **开销: 5-10 倍**

**函数调用:**
- C++: 5-10 ns
- 蓝图: 50-100 ns
- **开销: 10 倍**

**数学操作:**
- C++: 1 ns
- 蓝图: 2-5 ns
- **开销: 2-5 倍**

## 当蓝图足够快时

开销是**绝对时间**,不是百分比:

```cpp
// 昂贵的操作(1 毫秒)
RenderComplexMesh();

// 添加蓝图开销(100 纳秒)
// 总计: 1.0001 毫秒
// 差异: 0.01%(察觉不到!)
```

如果你的函数做**实际工作**,蓝图开销就消失了!

## 当蓝图受伤时

**紧循环是痛苦的:**

```cpp
// 蓝图(坏!)
For i = 0 to 10000:
    Result = Result + Array[i]
// 10,000 次函数调用 × 100ns = 损失 1 毫秒!

// C++(好)
for (int i = 0; i < 10000; i++) {
    Result += Array[i];
}
// 直接内存访问 = 微秒,而且现代编译器会直接优化为 O(1),因为我们有等差数列求和公式!
```

**热路径很重要:** 每帧调用的函数"应该"是 C++!但这真的取决于这些函数中实际做了什么。

## 优化策略

**保留在蓝图中:**
- 高级游戏逻辑
- 事件处理器
- UI 更新
- 不频繁的操作

**移到 C++:**
- 紧循环
- 数学密集型算法
- 每帧计算
- 性能关键路径

## 本地化(RIP)

虚幻有**蓝图本地化**:
- 将蓝图转换为 C++
- 编译为本地代码
- 移除所有开销!

它被**移除**是因为:
- 难以维护
- 二进制膨胀
- 调试困难

热重载比本地化更有价值!

## 未来:Verse

Epic 的新语言 **Verse** 旨在解决这个问题:
- 编译时优化
- 零复制函数调用
- 本地性能
- 可视化脚本的好处

蓝图不会消失,但 Verse 将处理性能关键代码!

## 快速要点

- 蓝图的慢来自**复制**,而不是解释
- 每个函数调用复制**所有参数**
- 运行时**栈管理**增加开销
- **反射**灵活但比直接访问慢
- 典型开销:**简单操作慢 5-10 倍**
- 开销对昂贵的操作**不重要**
- **紧循环**和**热路径**应该是 C++
- 为**高级逻辑**保留蓝图

## 性能权衡

蓝图用**原始速度**交换:
- 可视化编辑
- 快速迭代
- 热重载
- 对设计师友好
- 反射能力

对于大多数游戏逻辑,这种权衡**绝对值得**。只有当性能分析显示重要时才优化到 C++!

## 想要更多细节?

完整的性能分析:
- [从蓝图到字节码 V - 性能讨论](/zh-CN/posts/bpvm-bytecode-V/)

下一篇:创建你自己的自定义蓝图节点!

---

**🍿 BPVM 小食包系列**
- [← #17: 字节码中的函数调用](/zh-CN/posts/bpvm-snack-17-function-calls/)
- **#18: 为什么蓝图更慢** ← 你在这里
- [#19: 自定义蓝图](/zh-CN/posts/bpvm-snack-19-custom-blueprints/) →
