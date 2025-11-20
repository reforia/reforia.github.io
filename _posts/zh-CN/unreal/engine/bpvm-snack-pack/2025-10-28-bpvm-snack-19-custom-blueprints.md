---
layout: post
title: "BPVM 小食包 #19 - 自定义蓝图:扩展系统"
description: "现在你理解了蓝图如何编译。想要创建你自己的具有特殊编译规则的自定义蓝图类型吗?这就是扩展系统的工作原理。"
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

## 超越常规蓝图

动画蓝图、Widget 蓝图、游戏能力蓝图 - 它们都使用**自定义编译**!

你也可以创建自己的!

## 扩展点

蓝图系统到处都有**钩子**:

```cpp
class UBlueprint {
    // 自定义蓝图类型
    TSubclassOf<UBlueprint> BlueprintClassType;

    // 自定义编译器
    TSubclassOf<FKismetCompilerContext> CompilerType;

    // 自定义节点
    TArray<UEdGraphNode*> CustomNodes;

    // 扩展钩子
    TArray<UBlueprintExtension*> Extensions;
};
```

你可以自定义**每个阶段**!

## 自定义蓝图类

创建你自己的蓝图类型:

```cpp
// YourCustomBlueprint.h
UCLASS()
class UCustomBlueprint : public UBlueprint
{
    GENERATED_BODY()

    // 自定义数据
    UPROPERTY()
    TArray<FCustomData> SpecialData;

    // 覆盖编译
    virtual FKismetCompilerContext* CreateCompilerContext() override;
};
```

现在你在编辑器中有一个**新的资产类型**!

## 自定义编译器上下文

控制你的蓝图如何编译:

```cpp
class FCustomCompilerContext : public FKismetCompilerContext
{
public:
    FCustomCompilerContext(UCustomBlueprint* Blueprint)
        : FKismetCompilerContext(Blueprint)
    {}

    // 覆盖编译阶段
    virtual void SpawnNewClass(const FString& NewClassName) override;
    virtual void CreateFunctionList() override;
    virtual void CompileClassLayout() override;

    // 添加自定义验证
    virtual void ValidateCustomData();

    // 添加自定义节点
    virtual void RegisterCustomNodes();
};
```

对**每个编译阶段**完全控制!

## 自定义节点类型

为你的蓝图创建特殊节点:

```cpp
UCLASS()
class UK2Node_CustomOperation : public UK2Node
{
    GENERATED_BODY()

    // 自定义节点行为
    virtual void ExpandNode(FKismetCompilerContext& Context) override;

    // 自定义编译
    virtual FNodeHandlingFunctor* CreateNodeHandler(FKismetCompilerContext& Context) override;
};

// 自定义处理器
class FKCHandler_CustomOperation : public FNodeHandlingFunctor
{
    virtual void RegisterNets(Context, Node) override {
        // 注册自定义终端
    }

    virtual void Compile(Context, Node) override {
        // 生成自定义语句
    }
};
```

你的节点可以做**任何事情**!

## 真实示例:动画蓝图

动画蓝图扩展系统:

```cpp
class UAnimBlueprint : public UBlueprint
{
    // 自定义图表类型
    UPROPERTY()
    UAnimationGraph* AnimGraph;

    UPROPERTY()
    UAnimationStateMachineGraph* StateMachineGraph;

    // 自定义编译器
    virtual FKismetCompilerContext* CreateCompilerContext() override {
        return new FAnimBlueprintCompilerContext(this);
    }
};
```

编译器添加**状态机编译**!

## 动画编译器扩展

```cpp
class FAnimBlueprintCompilerContext : public FKismetCompilerContext
{
    virtual void CreateFunctionList() override {
        // 调用基础实现
        FKismetCompilerContext::CreateFunctionList();

        // 添加自定义:处理状态机!
        ProcessStateMachines();
        ProcessAnimationNodes();
    }

    void ProcessStateMachines() {
        // 将状态机图转换为字节码
        for (auto* StateMachine : AnimBP->StateMachines) {
            CompileStateMachine(StateMachine);
        }
    }
};
```

## 自定义验证

添加特殊检查:

```cpp
class FCustomCompilerContext : public FKismetCompilerContext
{
    virtual void ValidateLink() override {
        // 基础验证
        FKismetCompilerContext::ValidateLink();

        // 自定义验证
        if (!Blueprint->HasSpecialProperty()) {
            Error("自定义蓝图需要 SpecialProperty!");
        }

        if (FunctionCount > MAX_FUNCTIONS) {
            Warning("函数太多,无法获得最佳性能");
        }
    }
};
```

## 蓝图扩展

在不子类化的情况下添加功能:

```cpp
UCLASS()
class UMyBlueprintExtension : public UBlueprintExtension
{
    GENERATED_BODY()

    // 在编译期间调用
    virtual void HandleBeginCompilation(FCompilerContext& Context) override {
        // 注入自定义行为
    }

    virtual void HandleEndCompilation(FCompilerContext& Context) override {
        // 后处理编译的类
    }
};

// 注册扩展
MyBlueprint->Extensions.Add(NewObject<UMyBlueprintExtension>());
```

扩展是**模块化的**!

## 自定义生成的类

控制生成的类:

```cpp
UCLASS()
class UCustomBlueprintGeneratedClass : public UBlueprintGeneratedClass
{
    GENERATED_BODY()

    // 自定义运行时数据
    UPROPERTY()
    TArray<FRuntimeData> SpecialRuntimeData;

    // 自定义初始化
    virtual void InitializeCustomData();
};
```

## 图表模式自定义

控制允许哪些节点:

```cpp
class UCustomGraphSchema : public UEdGraphSchema_K2
{
    // 覆盖节点创建
    virtual void GetGraphContextActions(FGraphContextMenuBuilder& Context) override {
        // 添加自定义节点到上下文菜单
        Context.AddAction(NewCustomNodeAction());
    }

    // 覆盖连接规则
    virtual bool CanCreateConnection(const UEdGraphPin* A, const UEdGraphPin* B) override {
        // 自定义连接验证
        return IsValidCustomConnection(A, B);
    }
};
```

## 真实世界用例

**状态机蓝图:**
- 状态的自定义图表类型
- 转换的特殊编译
- 运行时状态执行

**游戏能力蓝图:**
- 能力特定的节点
- 预测编译
- 网络复制处理

**行为树蓝图:**
- 自定义任务节点
- 特殊装饰器
- AI 特定的编译

## 快速要点

- 蓝图系统是**完全可扩展的**
- 创建自定义**蓝图子类**
- 覆盖**编译器上下文**以进行自定义编译
- 添加带有处理器的**自定义节点类型**
- 使用**蓝图扩展**实现模块化
- 控制允许的节点的**模式**
- 示例:动画、Widget、游戏能力蓝图
- 对**编译流水线**的完全控制!

## 扩展的力量

蓝图系统不仅仅是用于游戏玩法 - 它是**可视化脚本系统**的框架。理解编译流水线让你创建功能强大的自定义工具,看起来和感觉起来像原生虚幻功能!

## 想要更多细节?

完整的自定义蓝图指南:
- [虚幻文档:自定义蓝图](https://dev.epicgames.com/documentation/en-us/unreal-engine/custom-blueprints-in-unreal-engine)
- 动画蓝图源代码
- Widget 蓝图源代码

最后一份小食:从这里去哪里!

---

**🍿 BPVM 小食包系列**
- [← #18: 为什么蓝图更慢](/zh-CN/posts/bpvm-snack-18-blueprint-slower/)
- **#19: 自定义蓝图** ← 你在这里
- [#20: 前方的旅程](/zh-CN/posts/bpvm-snack-20-journey-ahead/) →
