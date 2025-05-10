---
layout: post
title: "从蓝图到字节码 V - 字节码与游戏实战"
description:
  "强大的敌人已然倒下，冒险者们继续前进。城堡深处，一台巨型机器正处理着无数微小零件，指针来回跳动，搬运着EExprToken。我们即将触及这个秘密的核心——字节码"
date: 2024-12-29 11:27 +0800
categories: [Unreal, Engine]
published: true
tags: [Unreal, Engine, Blueprint]
media_subpath: /assets/img/post-data/unreal/engine/bpvm-bytecode/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## 前情提要
我们一直在探索虚幻引擎中蓝图的编译过程，从点击·按钮开始，直到无数·被序列化输出。但还没有在实际案例中观察过它们。本文将创建一个简单蓝图，添加逻辑后分析生成的字节码，并讨论这些知识在实际游戏开发中的应用。话不多说，让我们开始吧。

## 准备工作
根据前文章节 [section in previous post]，只要将`bDisplayBytecode`设为`true`，生成的字节码就会被反序列化为人类可读形式。该值读取自`CompileDisplaysBinaryBackend`，因此我们需要在`DefaultEngine.ini`中设置此标志。

```cpp
bool bDisplayBytecode = false;

if (!Blueprint->bIsRegeneratingOnLoad)
{
    GConfig->GetBool(TEXT("Kismet"), TEXT("CompileDisplaysBinaryBackend"), /*out*/ bDisplayBytecode, GEngineIni);
}
```

```ini
[Kismet]
CompileDisplaysBinaryBackend=True
```
{: file="DefaultEngine.ini" }

![Enable Log](bytecode_enablelog.png){: width="500" }
_Enabling bytecode log in DefaultEngine.ini_

## 创建蓝图资产
剩下的很简单：在内容浏览器右键新建蓝图，选择`Actor`作为父类，命名为`BPA_ByteCode`（或其他你喜欢的名字）。

![Create Blueprint](bytecode_create.png){: width="500" }
_Creating a new blueprint asset_

本示例将创建一个包含`StringToPrint`（`FString`类型变量）和自定义函数`CustomPrintString`的蓝图`Actor`，该函数会将字符串输出到日志和屏幕，并在`BeginPlay`事件中调用它们。

![Add Variable](bytecode_newvariable.png){: width="500" }
_Adding a new variable to the blueprint_

## 添加自定义函数
新建名为`CustomPrintString`的函数，设置返回类型为`FString`。该函数接收`FString`类型输入参数，将其赋值给局部变量并打印，最后将局部变量值传递给输出参数。

![Add Function](bytecode_customfunc.png)
_Adding a custom function to the blueprint_

## 在事件图表中调用函数
在事件图表中，从`BeginPlay`事件拖出连线，调用`CustomPrintString`函数，并传入`StringToPrint`变量作为输入参数。

![Call Function](bytecode_callfunc.png){: width="500" }
_Calling the custom function in event graph_

## 编译
现在点击编译按钮，等待魔法发生。

![Compile](bytecode_hitcompile.png){: width="500" }
_Compiling the blueprint_

注意：编译完成后移动节点不会使蓝图变为"Dirty"（需要重新编译），因为只有节点连接关系被改变时才会触发重新编译。任何真正需要重新编译的操作都会显式将蓝图状态设为`BS_Dirty`。

```cpp
/**
 * Enumerates states a blueprint can be in.
 */
UENUM()
enum EBlueprintStatus : int
{
    /** Blueprint is in an unknown state. */
    BS_Unknown,
    /** Blueprint has been modified but not recompiled. */
    BS_Dirty,
    /** Blueprint tried but failed to be compiled. */
    BS_Error,
    /** Blueprint has been compiled since it was last modified. */
    BS_UpToDate,
    /** Blueprint is in the process of being created for the first time. */
    BS_BeingCreated,
    /** Blueprint has been compiled since it was last modified. There are warnings. */
    BS_UpToDateWithWarnings,
    BS_MAX,
};
```

![Blueprint Dirty](bytecode_movenodearound.png)
_Moving nodes around doesn't make the blueprint dirty_

## 检查输出
根据你的IDE和平台，字节码的视觉呈现可能略有不同（颜色、额外空行等），但内容应该一致（下图来自Mac OS的JetBrains Rider）。

![Bytecode](bytecode_output2.png)

在IDE控制台中可以看到如下文本墙，这就是生成的字节码！让我们来分析它。

## 字节码解析
首先能快速注意到一些明显模式：
- LogK2Compiler: [function XXX]
  - 表示函数块，XXX是函数名
- Label_0xXX:
  - 表示标签，XX是距函数起始处的字节码偏移量
- $X:
  - 表示EExprToken，可能是数据或指令
- EX_EndOfScript:
  - 表示当前函数字节码结束

```bash
LogK2Compiler:
[function ExecuteUbergraph_BPA_ByteCode]:
Label_0x0:
     $4E: Computed Jump, offset specified by expression:
         $0: Local variable of type int32 named EntryPoint. Parameter flags: (Parameter).
{...}
Label_0x38:
     $4: Return expression
       $B: EX_Nothing
Label_0x3A:
     $53: EX_EndOfScript

LogK2Compiler:
[function ReceiveBeginPlay]:
{...}
Label_0x13:
     $4: Return expression
       $B: EX_Nothing
Label_0x15:
     $53: EX_EndOfScript
     
LogK2Compiler:
[function CustomPrintString]:
{...}
Label_0x88:
     $4: Return expression
       $B: EX_Nothing
Label_0x8A:
     $53: EX_EndOfScript
```
{: file="Bytecode Output" }

需要特别注意的是，整个字节码的执行并非从头开始（本例中的`ExecuteUbergraph_BPA_ByteCode`），而是会来回跳转，因此需要找出入口点。

## 从BeginPlay到ReceiveBeginPlay
当Actor生成并准备就绪后，会触发`BeginPlay`。有经验的虚幻开发者会意识到，这里调用的`BeginPlay`并非C++端的原生函数，而是一个名为"`BeginPlay`"的`BlueprintImplementableEvent`。这就是我们字节码执行的起点（我们将在后续文章中详细讨论这个过程）。

```cpp
void AActor::BeginPlay()
{
    // Other code
    // Also call BeginPlay() for components

    ReceiveBeginPlay();

    ActorHasBegunPlay = EActorBeginPlayState::HasBegunPlay;
}

/** Event when play begins for this actor. */
UFUNCTION(BlueprintImplementableEvent, meta=(DisplayName = "BeginPlay"))
ENGINE_API void ReceiveBeginPlay();
```

观察逻辑流：函数启动后会跳转到`Label_0x0`，接着到`Label_0x1`，然后回到`Label_0x2`，依此类推。可以看到这个函数只是`Ubergraph`实际实现的包装器。这对理解`BlueprintImplementableEvent`和`BlueprintNativeEvent`非常重要——我们在事件图表中的实现只是它们的实现体，编译时会创建独立的函数图，在执行时将逻辑连接到`Ubergraph`中。

- 0x0:
  - 调试站点，不影响执行，用于断点映射
- 0x1:
  - 连线调试站点，不影响执行，用于断点映射
- 0x2:
  - 调试站点，不影响执行，用于断点映射
- 0x3:
  - 本地最终脚本函数 (栈节点 `BPA_ByteCode_C::ExecuteUbergraph_BPA_ByteCode`)
    - 字面量 int32 49
    - `EX_EndFunctionParms`
  - 压入新栈，进入`BPA_BytecCode_C::ExecuteUbergraph_BPA_ByteCode`函数，传入参数值`49`。转换为十六进制是`0x31`
- 0x12:
  - 此时函数栈弹出，表示执行完成。另一个连线调试站点，不影响执行. 另一个连线调试站点，不影响执行
- 0x13:
  - 返回表达式，无返回值（这与函数的"返回节点"无关，后续详述）
- 0x15:
  - 脚本结束，函数终止

```bash
LogK2Compiler:
[function ReceiveBeginPlay]:
Label_0x0:
     $5E: .. debug site ..
Label_0x1:
     $5A: .. wire debug site ..
Label_0x2:
     $5E: .. debug site ..
Label_0x3:
     $46: Local Final Script Function (stack node BPA_ByteCode_C::ExecuteUbergraph_BPA_ByteCode)
       $1D: literal int32 49
       $16: EX_EndFunctionParms
Label_0x12:
     $5A: .. wire debug site ..
Label_0x13:
     $4: Return expression
       $B: EX_Nothing
Label_0x15:
     $53: EX_EndOfScript
```
{: file="ReceiveBeginPlay" }

看起来很简单。现在仔细观察`0x3`处：我们为执行`Ubergraph`压入栈时，传入了字面量`int32 49`，其十六进制值为`0x31`，对应`ExecuteUbergraph_BPA_ByteCode`中的字节码偏移量。这就是字节码跳转到`BeginPlay`事件实际实现的方式。

## ExecuteUbergraph_BPA_ByteCode
从名称和前文知识可知，`ExecuteUbergraph_BPA_ByteCode`表示合并后的事件图。它需要传入参数`EntryPoint`才能跳转到字节码的不同部分。以下是模拟字节码执行流程：
- 0x0:
  - 计算跳转，由表达式指定偏移量:
    - 评估输入参数，跳转到 `0x31`.
- 0x31:
  - 调试站点，不影响执行
- 0x32:
  - 连线调试站点，不影响执行
- 0x33:
  - 跳转到偏移量0xA
- 0xA:
  - 调试站点，不影响执行
- 0xB:
  - 名为`CustomPrintString`的本地虚拟脚本函数
    - `FString`类型的实例变量`StringToPrint`
    - `FString`类型的局部变量`CallFunc_CustomPrintString_NewString`
    - `EX_EndFunctionParms`
  - 此处调用`CustomPrintString`函数，传入`StringToPrint`变量作为参数
- 0x2B:
  - 内部函数执行完成。连线调试站点，不影响执行
- 0x2C:
  - 跳转到0x38
- 0x38:
  - 返回表达式，无返回值
- 0x3A:
  - 脚本结束，函数终止

```bash
LogK2Compiler:
[function ExecuteUbergraph_BPA_ByteCode]:
Label_0x0:
     $4E: Computed Jump, offset specified by expression:
         $0: Local variable of type int32 named EntryPoint. Parameter flags: (Parameter).
Label_0xA:
     $5E: .. debug site ..
Label_0xB:
     $45: Local Virtual Script Function named CustomPrintString
       $1: Instance variable of type FString named StringToPrint.
       $0: Local variable of type FString named CallFunc_CustomPrintString_NewString.
       $16: EX_EndFunctionParms
Label_0x2B:
     $5A: .. wire debug site ..
Label_0x2C:
     $6: Jump to offset 0x38
Label_0x31:
     $5E: .. debug site ..
Label_0x32:
     $5A: .. wire debug site ..
Label_0x33:
     $6: Jump to offset 0xA
Label_0x38:
     $4: Return expression
       $B: EX_Nothing
Label_0x3A:
     $53: EX_EndOfScript
```
{: file="ExecuteUbergraph_BPA_ByteCode" }

在`ExecuteUbergraph_BPA_ByteCode: Label_0xB`处，该指令调用名为`CustomPrintString`的本地虚拟脚本函数，并尝试将`StringToPrint`实例变量作为参数传入。`EX_EndFunctionParms`表示函数传参结束。

$1: `StringToPrint` — `FString`类型的实例变量，存储要打印的字符串

$0: `CallFunc_CustomPrintString_NewString` — `FString`类型的局部变量，存储`StringToPrint`的结果（类似于汇编调用函数时，外部值被捕获并复制到局部作用域*）

$16: `EX_EndFunctionParms` — 表示函数传参结束

```bash
Label_0xB:
     $45: Local Virtual Script Function named CustomPrintString
       $1: Instance variable of type FString named StringToPrint.
       $0: Local variable of type FString named CallFunc_CustomPrintString_NewString.
       $16: EX_EndFunctionParms
```
{: file="Call CustomPrintString" }

> 从技术上讲，汇编代码会将参数值压入堆栈，然后调用函数。函数随后会从堆栈中弹出该值并使用。本例中，该值被复制到一个局部变量——这是一种更高层次的抽象。另外请注意，如果我们使用编译器优化来编译汇编代码，该值可能会直接传递给函数而无需任何复制操作。不过在 `Blueprint VM` 中并非如此。
{: .prompt-info }

## CustomPrintString
`CustomPrintString` 的执行逻辑非常简单：它只是调用 `KismetSystemLibrary` 中的 `PrintString` 函数，然后返回值。

- 0x0:
  - 调试站点，不影响执行，用于断点映射。
- 0x1:
  - 调试站点，不影响执行，用于断点映射。
- 0x2:
  - 调试站点，不影响执行，用于断点映射。
- 0x3:
  - Let (Variable = Expression)
    - Variable:
      - 名为 `LocPrintString` 的 `FString` 类型局部变量。
    - Expression:
      - 名为 `InString` 的 `FString` 类型局部变量。参数标记：(`Parameter`)。
  - 此处将输入参数复制到局部变量 `LocPrintString`
- 0x1E:
  - 连线调试站点，不影响执行，用于断点映射。
- 0x1F:
  - 连线调试站点，不影响执行，用于断点映射。
- 0x20:
  - Call Math (栈节点 `KismetSystemLibrary::PrintString`)
    - `EX_Self`
    - 名为 `LocPrintString` 的 `FString` 类型局部变量。
    - `EX_True`
    - `EX_True`
    - 字面量结构体 `LinearColor` (序列化大小：16字节)
      - 字面量浮点数 0.000000
      - 字面量浮点数 0.660000
      - 字面量浮点数 1.000000
      - 字面量浮点数 1.000000
      - `EX_EndStructConst`
    - 字面量浮点数 2.000000
    - 字面量名称  `None`
    - `EX_EndFunctionParms`
  - 此处调用 `PrintString` 函数，按照函数签名传入所有参数。
- 0x6A:
  - 连线调试站点，不影响执行，用于断点映射。
- 0x6B:
  - 调试站点，不影响执行，用于断点映射。
- 0x6C:
  - Let (Variable = Expression)
    - Variable:
      - 名为 `NewString` 的 `FString` 类型局部输出变量。参数标记：(`Parameter`,`Out`)。
    - Expression:
      - 名为 `LocPrintString` 的 `FString` 类型局部变量。
  - 此处将输出参数复制到局部变量 `NewString`
- 0x87:
  - 连线调试站点，不影响执行，用于断点映射。
- 0x88:
  - Return expression
    - `EX_Nothing`
- 0x8A:
  - 脚本结束，函数终止。

![Add Function](bytecode_customfunc.png)
_Bytecode agrees with implementation_

```bash
LogK2Compiler:
[function CustomPrintString]:
Label_0x0:
     $5E: .. debug site ..
Label_0x1:
     $5A: .. wire debug site ..
Label_0x2:
     $5E: .. debug site ..
Label_0x3:
     $F: Let (Variable = Expression)
       Variable:
         $0: Local variable of type FString named LocPrintString.
       Expression:
         $0: Local variable of type FString named InString. Parameter flags: (Parameter).
Label_0x1E:
     $5A: .. wire debug site ..
Label_0x1F:
     $5E: .. debug site ..
Label_0x20:
     $68: Call Math (stack node KismetSystemLibrary::PrintString)
       $17: EX_Self
       $0: Local variable of type FString named LocPrintString.
       $27: EX_True
       $27: EX_True
       $2F: literal struct LinearColor (serialized size: 16)
         $1E: literal float 0.000000
         $1E: literal float 0.660000
         $1E: literal float 1.000000
         $1E: literal float 1.000000
         $30: EX_EndStructConst
       $1E: literal float 2.000000
       $21: literal name None
       $16: EX_EndFunctionParms
Label_0x6A:
     $5A: .. wire debug site ..
Label_0x6B:
     $5E: .. debug site ..
Label_0x6C:
     $F: Let (Variable = Expression)
       Variable:
         $48: Local out variable of type FString named NewString. Parameter flags: (Parameter,Out).
       Expression:
         $0: Local variable of type FString named LocPrintString.
Label_0x87:
     $5A: .. wire debug site ..
Label_0x88:
     $4: Return expression
       $B: EX_Nothing
Label_0x8A:
     $53: EX_EndOfScript
```
{: file="CustomPrintString" }

## One more thing
最后一个细节仍有些蹊跷：似乎末尾的 `EX_Return` 指令总是以 `EX_Nothing` 作为返回值，但我们明明为自定义函数创建了输出参数！我个人不清楚为何这样设计，但从代码层面可以解释这个行为。

### 函数的返回表达式
观察 `EX_Return` 的来源，它通过 `EmitReturn()` 函数写入字节流。当 `FBlueprintCompiledStatement` 的类型为 `KCST_Return` 时会调用该函数，而这个类型是在 `ConstructFunction()` 过程中分配的。

```cpp
void FKismetCompilerVMBackend::ConstructFunction(FKismetFunctionContext& FunctionContext, bool bIsUbergraph, bool bGenerateStubOnly)
{
    // ... Other code

    // Return statement, to push on FlowStack or to use with _GotoReturn
    FBlueprintCompiledStatement ReturnStatement;
    ReturnStatement.Type = KCST_Return;

    // ... Process function body

    // Handle the function return value
    ScriptWriter.GenerateCodeForStatement(CompilerContext, FunctionContext, ReturnStatement, nullptr);    
}
```

如你所见，这个"`Return`"似乎仅用于跳转到某个地址，并非我们在函数中定义的实际返回节点，因为它不像 `UEdGraphNode`。接着我们查看图表中实际的 `Return` 节点——它必然是派生自 `UK2Node` 的类，因此我们可以在代码库中搜索名为"`Return Node`"的 `UK2Node` 类。

### Return 节点
很快我们找到了候选者 `UK2Node_FunctionResult`，在其 `GetNodeTitle()` 函数中，节点名称被重写为"`Return Node`"。就是它了！

```cpp
FText UK2Node_FunctionResult::GetNodeTitle(ENodeTitleType::Type TitleType) const
{
    if (ENodeTitleType::MenuTitle == TitleType)
    {
        return NSLOCTEXT("K2Node", "ReturnNodeMenuTitle", "Add Return Node...");
    }
    return NSLOCTEXT("K2Node", "ReturnNode", "Return Node");
}
```

### Return 节点字节码
我们知道该节点必须有对应的 `FNodeHandlingFunctor` 来处理字节码生成，因此查看其 `CreateNodeHandler()` 函数。

```cpp
FNodeHandlingFunctor* UK2Node_FunctionResult::CreateNodeHandler(FKismetCompilerContext& CompilerContext) const
{
    return new FKCHandler_FunctionResult(CompilerContext);
}
```

找到了：`FKCHandler_FunctionResult`。现在观察其 `Compile()` 函数，可以清晰地看到：对于普通函数，会为所有输出引脚调用 `GenerateAssignment()`，然后最后一个 `FBlueprintCompiledStatement` 的类型是 `KCST_GotoReturn` 并被添加到列表中。

```cpp
virtual void Compile(FKismetFunctionContext& Context, UEdGraphNode* Node) override
{
    static const FBoolConfigValueHelper ExecutionAfterReturn(TEXT("Kismet"), TEXT("bExecutionAfterReturn"), GEngineIni);

    if (ExecutionAfterReturn)
    {
        // for backward compatibility only
        FKCHandler_VariableSet::Compile(Context, Node);
    }
    else
    {
        GenerateAssigments(Context, Node);

        if (Context.IsDebuggingOrInstrumentationRequired() && Node)
        {
            FBlueprintCompiledStatement& TraceStatement = Context.AppendStatementForNode(Node);
            TraceStatement.Type = Context.GetWireTraceType();
            TraceStatement.Comment = Node->NodeComment.IsEmpty() ? Node->GetName() : Node->NodeComment;
        }

        // always go to return
        FBlueprintCompiledStatement& GotoStatement = Context.AppendStatementForNode(Node);
        GotoStatement.Type = KCST_GotoReturn;
    }
}
```

### GenerateAssigments()
该函数本质上为每个输出引脚调用 `FKCHandler_VariableSet::InnerAssignment()`，继而调用 `FKismetCompilerUtilities::CreateObjectAssignmentStatement()` 创建类型为 `KCST_Assignment` 的语句。

```cpp
FBlueprintCompiledStatement& Statement = Context.AppendStatementForNode(Node);
Statement.Type = KCST_Assignment;
Statement.LHS = DstTerm;
Statement.RHS.Add(RHSTerm);
```

### EmitAssignmentStatement()
该函数根据属性类型生成对应的字节码，核心逻辑在 `EmitDestinationExpression()` 中。

```cpp
void EmitAssignmentStatment(FBlueprintCompiledStatement& Statement)
{
    FBPTerminal* DestinationExpression = Statement.LHS;
    FBPTerminal* SourceExpression = Statement.RHS[0];

    EmitDestinationExpression(DestinationExpression);

    EmitTerm(SourceExpression, DestinationExpression->AssociatedVarProperty);
}
```

### EmitDestinationExpression()
该函数将赋值操作转换为实际的 `EX_Let` 指令（可能是 `EX_LetBool`、`EX_LetObject` 或普通 `EX_Let`），然后调用我们已经熟悉的 `EmitTermExpr()`。

### EmitReturn()
如前所述，处理 `KCST_Return` 语句时会调用 `EmitReturn()`。技术上它可以携带返回值，但代码库中并未找到使用该参数的函数——或许这是为非蓝图节点准备的。若未传入返回参数，则使用无操作表达式 `EX_Nothing`。由于进入函数时总会压入新堆栈，因此函数结束时需要这个"`Return`"来弹出堆栈并继续流程。

### Fact Check
如果假设正确，在 `CustomPrintString()` 的字节码末尾，我们应该会看到：一个将 `FString` 变量值写入输出参数 `NewString` 的 `EX_Let` 操作，接着是 `EX_GotoReturn` 操作，然后是以 `EX_Nothing` 为参数的 `EX_Return` 操作（即函数实际返回语句），最后以 `EX_EndOfScript` 结束函数。实际情况如何？

```bash
Label_0x6C:
     $F: Let (Variable = Expression)
       Variable:
         $48: Local out variable of type FString named NewString. Parameter flags: (Parameter,Out).
       Expression:
         $0: Local variable of type FString named LocPrintString.
Label_0x87:
     $5A: .. wire debug site ..
Label_0x88:
     $4: Return expression
       $B: EX_Nothing
Label_0x8A:
     $53: EX_EndOfScript
```


`EX_Let`...存在，`EX_Return`...存在...`EX_EndOfScript`...存在...`EX_Nothing`...存在...等等！`EX_GotoReturn` 消失了！肯定有问题！

### 最后一块拼图
别慌，这其实是正确的。记得上篇文章提到的特殊步骤"[MergeAdjacentStates]"吗？第二种情况表明：如果 `EX_GotoReturn` 是函数最后一个节点生成的最后一条语句，它会被移除——因为 `EX_Return` 会处理这个跳转。（我们可以在 `CurStatementList->RemoveAt(CurStatementList->Num() - 1);` 处设置断点验证）

完美！我们成功分析了一个简单蓝图的字节码生成。整个过程虽简单，但让我们深入理解了蓝图的编译和执行机制。

## 关键收获
几个明显结论：
- 事件图中定义的任何函数或自定义事件都会生成独立的函数图，作为包装器，字节码最终会跳转到 `Ubergraph` 中对应的函数存根标签偏移位置。
- 由此理解为何蓝图比 `C++` 代码慢：`BPVM` 需要大量复制和堆栈管理操作，以及不必要的逻辑跳转，这些都增加了开销。
  - 本例中所有字面值都被复制，我们可以指定蓝图通过引用传值，或在 `C++` 函数签名中使用 `UPARAM(ref)` 避免不必要的复制。
- `FKismetCompilerContext` 在编译时会进行少量优化，但远不如 `C++` 编译器的优化能力。字节码优化主要在 `EExprToken` 和 `FBlueprintCompiledStatement` 层面，而完整的 `C++` 编译器可以在汇编层面优化。
- 从 `C++` 调用蓝图定义的函数成本高昂，但从蓝图调用 `C++` 定义的函数则快得多——因为它几乎只涉及一个跳回 `C++` 的 `EX_CallFunction` 指令，而 `C++` 能以无可比拟的速度处理剩余工作。
  - 这也解释了最佳实践为何是将繁重工作放在 C++ 端，仅用蓝图处理高层逻辑和游戏设计。

> 这里的"慢"是相对概念，衡量的是蓝图相比 `C++` 需要更多指令（最终是 `CPU` 周期）来完成相同任务。但通过多线程和异步任务，实际性能差异可能并不显著。（虽然我暂无基准测试数据支持）
{: .prompt-info } 

## 下一站
这段史诗级探索（字面意思 XD）结束后，我们可能仍会疑惑：为什么要了解这些？整个系列只是为了证明 `C++` 比蓝图快这个人尽皆知的事实吗？并非如此。除了探索乐趣之外，还有大量可扩展空间：
- 我们可以创建特定类型的蓝图（如 `Animation Blueprint` 或 `Behavior Tree`），为其开发全新编辑器，构建便于设计师使用的游戏系统。
  - 典型用例是 `RPG` 框架：开发自定义 `Dialogue` 和 `Quest` 编辑器，让设计师无需接触代码即可创建对话和任务。通过定制流程实现专属 FSM，并重写编译过程确保正确执行。
- 我们可以创建继承自 `FKismetCompilerContext` 的自定义类，重写 `Compile` 函数来实现自定义优化、添加新指令，甚至为过时玩家数据做向后兼容清理。
- 这帮助我们更好地理解编译过程（特别是顺序），当我们将代码集成到引擎时，不会在源码海洋中迷失方向（当然还是会迷失的 :D）。
- 让我们更深入理解自定义脚本语言的实现方式，为自研引擎的脚本系统提供顶级参考。
- 抽象实现细节并让编译器为我们编写完整代码的理念非常强大——`UHT（Unreal Header Tool）`也在做同样的事。想知道为什么 `C++` 头文件总是包含 `xx.generated.h`，而 `Intermediate` 文件夹总有一堆 `xx.gen.cpp` 吗？这就是 `UHT` 替我们完成繁重工作的魔法。
  - 未来我们将探讨 `UHT`。理解 `UHT` 行为能让我们为函数创建 `CustomThunk`，告诉 `UHT` 休息一下，由我们手动编写编译代码。这将彻底释放引擎的全部潜能。

系列到此结束，希望你喜欢。如有疑问、错误或讨论建议，欢迎留言帮助未来的读者 :D。下次见，编码愉快！

[section in previous post]: https://jaydengames.com/posts/bpvm-bytecode-IV/#generate-debug-bytecode
[MergeAdjacentStates]: https://jaydengames.com/posts/bpvm-bytecode-IV/#mergeadjacentstates