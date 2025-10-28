---
layout: post
title: "BPVM 小食包 #3 - 编译启动"
description: "你点击'编译'。这个按钮背后是一个处理依赖、生成代码和更新实时实例的16阶段流水线。这里介绍它的工作原理。"
date: 2025-10-28 00:00 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint, BPVM-Snack-Pack]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.6.0" %}

> **BPVM 小食包**是深度系列文章[蓝图到字节码](/posts/bpvm-bytecode-I/)的配套系列。每一份小食都是3-5分钟的纯知识!
{: .prompt-tip }

## 编译按钮

![Compile Button](bytecode_hitcompile.png){: width="500"}

你点击它。它变绿了。发布吧!

但在那次点击和绿色勾选之间,有一个**16阶段的编译流水线**在精确顺序中执行。把它想象成游戏的渲染管线,但用于代码生成。

## 阶段 0: 按钮点击

当你点击"编译"时,你会触发来自这个函数的命令:

```cpp
FBlueprintEditorToolbar::AddCompileToolbar()
{
    // 创建编译按钮
    FToolMenuEntry& CompileButton = InSection.AddEntry(
        FToolMenuEntry::InitToolBarButton(
            Commands.Compile,  // ← 这是命令
            ...
        )
    );
}
```

这启动了 `FBlueprintEditor::Compile()`,它将你的蓝图添加到**编译队列**。

## 队列系统

虚幻不会一次编译一个蓝图——它使用 `FBlueprintCompilationManager` 批量处理它们:

```cpp
QueueForCompilation(YourBlueprint);
// ... 也将依赖项排队 ...
FlushCompilationQueueImpl();  // ← 真正的工作从这里开始
```

**为什么批处理?** 原因与游戏批处理绘制调用相同:如果蓝图 A 依赖于蓝图 B,而 B 依赖于 C,你需要解析依赖关系图并按拓扑顺序处理它们。

## 16个阶段(高层次)

这是 `FlushCompilationQueueImpl()` 做的事:

![Compilation Flow](bytecode_compilationflow.png){: width="500"}

**准备 (阶段 I-VII):**
1. **GATHER** - 查找所有依赖蓝图
2. **FILTER** - 删除重复和无效的
3. **SORT** - 按依赖排序(C → B → A)
4. **SET FLAGS** - 标记为"正在编译"
5. **VALIDATE** - 检查错误
6. **PURGE** - 清理旧数据(仅加载时)
7. **DISCARD SKELETON CDO** - 准备重新生成

**编译 (阶段 VIII-XIII):**
8. **RECOMPILE SKELETON** - 创建类头文件
9. **RECONSTRUCT NODES** - 更新已弃用的节点
10. **CREATE REINSTANCER** - 准备更新实例
11. **CREATE CLASS HIERARCHY** - 链接父/子类
12. **COMPILE CLASS LAYOUT** - 生成属性和函数 ⚡
13. **COMPILE CLASS FUNCTIONS** - 生成字节码 ⚡⚡

**最终化 (阶段 XIV-XVI):**
14. **REINSTANCE** - 更新所有现有实例
15. **POST CDO COMPILED** - 完成类默认对象
16. **CLEAR FLAGS** - 标记为"完成"

## 两个关键阶段

阶段 12 和 13 是代码生成发生的地方:

**阶段 XII - COMPILE CLASS LAYOUT:**
- 为你的变量创建 `UProperties`
- 为你的函数创建 `UFunctions`
- 设置类结构(就像生成 C++ 头文件)

**阶段 XIII - COMPILE CLASS FUNCTIONS:**
- 将你的节点转换为中间语句
- 从这些语句生成字节码
- 将字节码链接到类中(就像编译 .cpp 文件)

## 为什么这么多阶段?

每个阶段处理一个特定的问题:

**循环依赖?**
- 阶段 I-III (Gather/Sort) 处理这个

**蓝图 A 引用尚未编译的蓝图 B?**
- 阶段 VIII (Skeleton) 首先创建"头文件",这样 B 可以引用 A

**关卡中的现有实例?**
- 阶段 XIV (Reinstance) 更新它们全部

**来自上次编译的旧数据?**
- 阶段 VII (Purge) 清理它

## 快速要点

当你点击"编译"时:
1. 你的蓝图加入**编译队列**
2. 队列**按依赖排序**
3. **16个阶段**按顺序执行
4. 阶段 12-13 进行**实际编译**
5. 结果:新鲜的字节码准备运行!

## 前方的旅程

在接下来的小食中,我们将放大:
- **阶段 XII** - 如何创建变量和函数
- **阶段 XIII** - 节点如何成为字节码
- **重新实例化** - 现有实例如何更新

## 想要更多细节?

有关完整的16阶段分解和代码:
- [从蓝图到字节码 II - FlushCompilationQueueImpl](/posts/bpvm-bytecode-II/#flushcompilationqueueimpl---the-heavy-lifter)

下一份小食:神秘的"骨架类"!

---

**🍿 BPVM 小食包系列**
- [← #2: 图表系统解码](/zh-CN/posts/bpvm-snack-02-graph-system/)
- **#3: 编译启动** ← 你在这里
- [#4: 骨架类解释](/zh-CN/posts/bpvm-snack-04-skeleton-classes/) →
