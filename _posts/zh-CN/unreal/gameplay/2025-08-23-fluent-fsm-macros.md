---
layout: post
title: "流式状态机 - 优雅的状态管理框架"
description:
  深入探讨如何为虚幻引擎创建一个流式风格的状态机框架，使用强大的宏语法处理嵌套同步并提供优雅的建造者模式。
date: 2025-08-23 15:30 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/fluent-fsm/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.6.0" %}

{% include ue_engine_post_disclaimer.html %}

## 前言
状态机是游戏逻辑的基础，处理从AI行为到游戏流程管理的各个方面。虽然虚幻引擎提供了各种状态管理工具，但构建一个干净、可复用且网络友好的状态机系统通常需要自定义解决方案。本文探讨了一个流式风格的状态机框架，该框架结合了宏的力量与建造者模式，创建了一个优雅且易维护的系统。

我们将要研究的框架演示了几个关键概念：
- **流式语法**：可链接的方法调用，读起来像自然语言
- **基于宏的状态定义**：自动生成样板代码
- **嵌套子对象处理**：复杂状态层次结构的适当管理

## 架构设计

### 核心组件

该系统围绕四个主要组件构建：

**`UVFStateBase`**：所有状态的基类，提供状态生命周期的虚方法：
- `EnterState()`：转换到此状态时调用
- `ExitState()`：离开此状态时调用
- `UpdateState()`：在活动时每帧调用

**`UVFStateMachineBase`**：状态机控制器，负责：
- 管理当前状态和转换
- 处理自动时钟更新
- 提供网络同步支持
- 实现转换验证和条件

**`FStateMachineBuilder`**：允许可读性状态机定义的流式建造者类：
```cpp
auto SetupComplete = [](const UVFStateMachineBase* StateMachine) -> bool { return true; /* Simplified for brevity */ };
auto IdentitiesSelected = [](const UVFStateMachineBase* StateMachine) -> bool { return true; /* Simplified for brevity */ };

return FStateMachineBuilder(STATEMACHINE_TYPE(GamePhase))
    .Initial(STATE_TYPE(SetupShopAndEvents))
    .From(STATE_TYPE(SetupShopAndEvents))
        .To(STATE_TYPE(SelectIdentities))
            .When(SetupComplete)
    .From(STATE_TYPE(SelectIdentities))
        .To(STATE_TYPE(SelectCharacters))
            .When(IdentitiesSelected);
    .Build();
```

**宏系统**：为状态机集成提供声明式语法。

## StateMachineBase and StateBase
状态机是一个`FTickableGameObject`，这样我们可以共享一个全局的`Ticking`线程(`UWorld:Tick()` in `LevelTick.cpp`)，而不是创建我们自己的`Update`委托。这解耦了从所有者或外部系统手动调用tick的需要。SM将自动处理底层状态的更新。

```cpp
UCLASS()
class GAME_API UVFStateMachineBase : public UObject, public FTickableGameObject
{
	GENERATED_BODY()

private:
	TMap<UClass*, TArray<FVFStateTransition>> TransitionLookup;
	
	// Tick control
	bool bIsTickEnabled;
	TWeakObjectPtr<UWorld> CachedWorld;
    
public:
	UVFStateMachineBase();
	
	// FTickableGameObject interface
	virtual void Tick(float DeltaTime) override;
	virtual bool IsTickable() const override;
	virtual TStatId GetStatId() const override;
	virtual UWorld* GetTickableGameObjectWorld() const override;
	
	// State machine interface
	void Initialize(const FVFStateMachineDefinition& Definition);
	void Update(float DeltaTime);
	bool TryForceSetState(const TSubclassOf<UVFStateBase>& TargetStateClass, TArray<FGameplayTag>& OutFailReasons);
	void TransitionToState(TSubclassOf<UVFStateBase> StateClass);
	void Shutdown();
	void SetTickEnabled(bool bEnabled);
	virtual void RegisterReplicatedSubObjects(AActor* Owner) { };
	virtual void UnregisterReplicatedSubObjects(AActor* Owner) { };

	UFUNCTION(BlueprintPure, Category = "State Machine")
	const UVFStateBase* GetCurrentState() const { return CurrentState; }
	UVFStateBase* GetMutableCurrentState() { return CurrentState; }
	
private:
	void BuildTransitionLookup();
	bool TryAutoTransition();

public:
    // Network Support, by default all FSM support replication automatically, but can of course remove it if your game doesn't need it
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
	virtual bool IsSupportedForNetworking() const override { return true; };

private:
	UPROPERTY(Replicated)
	TObjectPtr<UVFStateBase> CurrentState;
	
	FVFStateMachineDefinition StateMachineDefinition;

	TMap<TSubclassOf<UVFStateBase>, TArray<FVFStateTransition>> TransitionMap;
};
```

状态则是一个简单的`UObject`派生类：:

```cpp
UCLASS(Abstract, BlueprintType)
class GAME_API UVFStateBase : public UObject
{
    GENERATED_BODY()

public:
    UVFStateBase() {};
    
    /** Called when entering this state */
    virtual void EnterState(UVFStateMachineBase* StateMachine) {}

    /** Called when exiting this state */
    virtual void ExitState(UVFStateMachineBase* StateMachine) {}
    
    /** Called every frame while this state is active */
    virtual void UpdateState(UVFStateMachineBase* StateMachine, const float DeltaTime) {}

    virtual bool IsSupportedForNetworking() const override { return true; }

#if !UE_BUILD_SHIPPING
    /** Return debug information for this state - available in all non-shipping builds for debugging */
    virtual FString GetDebugInfo(const UVFStateMachineBase* StateMachine) const { return FString(); }
#endif

protected:
    /** Helper to get the current game state */
    class AVFGameState* GetGameState(const UVFStateMachineBase* StateMachine) const;
};
```

状态机类实际上是真正的实例，而我们用流式语法定义的实际上是状态机的描述文件，因此我们需要创造对应的“描述类”

```cpp
// StateTransitionTable.h
struct FVFStateTransition
{
	TSubclassOf<UVFStateBase> FromState;
	TSubclassOf<UVFStateBase> ToState;
	TFunction<bool(const UVFStateMachineBase*)> Condition = nullptr;
};

struct FVFStateMachineDefinition
{
	TSubclassOf<UVFStateMachineBase> StateMachineClass;
	TSubclassOf<UVFStateBase> InitialState;
	TArray<FVFStateTransition> Transitions;
};
```

## 流式建造者模式

建造者模式允许类似自然语言的状态机定义：

```cpp
FVFStateMachineDefinition AVFGameState::CreateGamePhaseFSM()
{
	// Transition conditions - check state completion via state objects and game data
	auto SetupComplete = [](const UVFStateMachineBase* StateMachine) -> bool { return true; /* Simplified for brevity */};
	auto IdentitiesSelected = [](const UVFStateMachineBase* StateMachine) -> bool { return true; /* Simplified for brevity */};
	auto CharactersSelected = [](const UVFStateMachineBase* StateMachine) -> bool { return true; /* Simplified for brevity */ };

    return FStateMachineBuilder(STATEMACHINE_TYPE(GamePhase))
        .Initial(STATE_TYPE(SetupShopAndEvents))
        .From(STATE_TYPE(SetupShopAndEvents))
            .To(STATE_TYPE(SelectIdentities))
                .When(SetupComplete)
        .From(STATE_TYPE(SelectIdentities))
            .To(STATE_TYPE(SelectCharacters))
                .When(IdentitiesSelected)
        .From(STATE_TYPE(SelectCharacters))
            .To(STATE_TYPE(PreRound))
                .When(CharactersSelected)
        .Build();
}
```

### 建造者实现

建造者在方法调用之间维护状态并验证配置：

```cpp
class FStateMachineBuilder
{
public:
    FStateMachineBuilder(TSubclassOf<UVFStateMachineBase> StateMachineClass)
    {
        Definition.StateMachineClass = StateMachineClass;
    }

    FStateMachineBuilder& Initial(TSubclassOf<UVFStateBase> State)
    {
        Definition.InitialState = State;
        return *this;
    }
    
    FStateMachineBuilder& From(TSubclassOf<UVFStateBase> State)
    {
        CurrentFrom = State;
        return *this;
    }
    
    FStateMachineBuilder& To(TSubclassOf<UVFStateBase> State)
    {
        checkf(CurrentFrom, TEXT("Cannot add transition without a 'From' state defined"));
        Definition.Transitions.Add({CurrentFrom, State});
        return *this;
    }
    
    FStateMachineBuilder& When(const TFunction<bool(const UVFStateMachineBase*)>& Condition)
    {
        if (Definition.Transitions.Num() > 0)
        {
            Definition.Transitions.Last().Condition = Condition;
        }
        return *this;
    }
    
    FVFStateMachineDefinition Build() { return MoveTemp(Definition); }

private:
    FVFStateMachineDefinition Definition;
    TSubclassOf<UVFStateBase> CurrentFrom = nullptr;
};
```

### 宏的魔法

该框架使用几个宏来消除样板代码并提供干净的集成：

#### 声明宏

```cpp
#define DECLARE_STATE_MACHINE(MachineName) \
private: \
static FVFStateMachineDefinition Create##MachineName##FSM(); \
mutable TOptional<FVFStateMachineDefinition> Cached##MachineName##Definition; \
\
public: \
const FVFStateMachineDefinition& Get##MachineName##Definition() const \
{ \
if (!Cached##MachineName##Definition.IsSet()) \
{ \
Cached##MachineName##Definition = Create##MachineName##FSM(); \
} \
return Cached##MachineName##Definition.GetValue(); \
} \
\
const UVF##MachineName##StateMachine* Get##MachineName##StateMachine() const \
{ \
    return MachineName##StateMachine; \
} \
UVF##MachineName##StateMachine* GetMutable##MachineName##StateMachine() \
{ \
    return MachineName##StateMachine; \
}
```

此宏生成：
- 状态机定义的静态工厂方法
- 定义的延迟加载缓存
- 状态机实例的类型安全访问器

#### 实现和生命周期宏

```cpp
#define IMPLEMENT_STATE_MACHINE(ClassName, MachineName) \
FVFStateMachineDefinition ClassName::Create##MachineName##FSM()

#define INITIALIZE_STATE_MACHINE(MachineName) \
MachineName##StateMachine = NewObject<UVF##MachineName##StateMachine>(this, NAME_None, RF_Public | RF_Standalone); \
MachineName##StateMachine->Initialize(Get##MachineName##Definition());

#define SHUTDOWN_STATE_MACHINE(MachineName) \
if (IsValid(MachineName##StateMachine)) \
{ \
    MachineName##StateMachine->Shutdown(); \
}
```

这些处理从定义到清理的完整生命周期。

#### 类型辅助宏

```cpp
#define STATE_TYPE(StateName) \
UVF##StateName##State::StaticClass()

#define STATEMACHINE_TYPE(StateMachineName) \
UVF##StateMachineName##StateMachine::StaticClass()
```

这些提供对状态和状态机类的类型安全引用。

### 为什么要手动声明UPROPERTY？
在实现`UVFStateMachineBase`时，我们手动创建了`CurrentState`并标记为`UPROPERTY(Replicated)`

```cpp
private:
	UPROPERTY(Replicated)
	TObjectPtr<UVFStateBase> CurrentState;
```

你可能会想为什么`DECLARE_STATE_MACHINE`宏不自动生成`UPROPERTY(Replicated)`成员变量，而是要我们手动再次创建一次，这不是多此一举么？答案是UHT（虚幻头文件工具）宏展开的限制：

```cpp
// 这样做会有问题：
#define DECLARE_STATE_MACHINE(MachineName) \
UPROPERTY(Replicated) \
TObjectPtr<UVF##MachineName##StateMachine> MachineName##StateMachine;
```

UHT通常不会在IDE正确展开宏之后解析，导致UHT无法生成正确的反射代码。当使用`DOREPLIFETIME()`进行网络同步时，`FindField()`断言将失败，因为宏展开的属性名在反射生成期间没有被正确识别。

> 这是使用UHT时的常见陷阱 - 始终确保属性名对头文件工具明确可见。
{: .prompt-warning }

## 高级功能

### 自动转换

系统支持手动和自动状态转换：

```cpp
bool UVFStateMachineBase::TryAutoTransition()
{
    if (!CurrentState) return false;
    
    const TArray<FVFStateTransition>* Transitions = TransitionMap.Find(CurrentState->GetClass());
    if (!Transitions) return false;
    
    for (const FVFStateTransition& Transition : *Transitions)
    {
        if (!Transition.Condition || Transition.Condition(this))
        {
            TransitionToState(Transition.ToState);
            return true; // First valid transition wins
        }
    }
    return false;
}
```

### 转换验证和错误处理

强制转换包括全面的调试验证：

```cpp
bool UVFStateMachineBase::TryForceSetState(const TSubclassOf<UVFStateBase>& TargetStateClass, TArray<FGameplayTag>& OutFailReasons)
{
    OutFailReasons.Empty();
    
    if (!TargetStateClass)
    {
        OutFailReasons.Add(VF_STATE_TAGS::TAG_TRANSITION_FAILURE_STATE_INVALID);
        return false;
    }
    
    // 验证状态是否存在于定义中
    bool bStateExists = TransitionMap.Contains(TargetStateClass);
    if (!bStateExists)
    {
        // 检查它是否是有效的目标状态
        for (const auto& TransitionPair : TransitionMap)
        {
            for (const auto& Transition : TransitionPair.Value)
            {
                if (Transition.ToState == TargetStateClass)
                {
                    bStateExists = true;
                    break;
                }
            }
            if (bStateExists) break;
        }
    }
    
    if (!bStateExists)
    {
        OutFailReasons.Add(VF_STATE_TAGS::TAG_TRANSITION_FAILURE_STATE_DOES_NOT_IN_SM);
        return false;
    }
    
    TransitionToState(TargetStateClass);
    return true;
}
```

### 调试支持

非发布构建包含每个状态的广泛调试功能，因此显示调试信息调用可以获取状态机，获取当前状态，然后在当前状态上调用多态调试信息方法：

```cpp
#if !UE_BUILD_SHIPPING
virtual FString GetDebugInfo(const UVFStateMachineBase* StateMachine) const 
{ 
    return FString::Printf(TEXT("SetupState - Events: %s, Shop: %s"), 
        AreEventCardsInitialized() ? TEXT("Ready") : TEXT("Pending"),
        AreShopItemsInitialized() ? TEXT("Ready") : TEXT("Pending"));
}
#endif
```

## 使用模式

该框架遵循确保适当的UHT兼容性和网络支持的3步使用模式：

### 分步集成

**步骤1：声明状态机**

使用`DECLARE_STATE_MACHINE`宏并手动创建`UPROPERTY()`成员：
```cpp
class GAME_API AMyGameMode : public AGameModeBase
{
    GENERATED_BODY()
    
    DECLARE_STATE_MACHINE(MyGame)
    
private:
    // 需要手动UPROPERTY声明以实现UHT兼容性
    // 在我们的宏中，我们期望属性的类型恰好是UVF + MachineName + StateMachine，属性名恰好是MachineName + StateMachine，但你当然可以将属性命名为任何名称，只需相应调整访问器
    // 如果不需要网络支持，则Replicated也是不必要的
    UPROPERTY(Replicated)
    TObjectPtr<UVFMyGameStateMachine> MyGameStateMachine;
};
```

**步骤2：定义状态机骨架**

使用`IMPLEMENT_STATE_MACHINE`与流式语法定义状态机结构：
```cpp
IMPLEMENT_STATE_MACHINE(AMyGameMode, MyGame)
{
    return FStateMachineBuilder(STATEMACHINE_TYPE(MyGame))
        .Initial(STATE_TYPE(Startup))
        .From(STATE_TYPE(Startup))
            .To(STATE_TYPE(Playing))
                .When([](const UVFStateMachineBase* SM) { return true; })
        .Build();
}
```

**步骤3：初始化状态机实例**

在适当的生命周期事件中调用`INITIALIZE_STATE_MACHINE`基于骨架定义创建实例，在我们的情况下，我们希望状态机控制匹配流程，所以我们在`BeginPlay`中初始化它，在`EndPlay`中清理：
```cpp
void AMyGameMode::BeginPlay()
{
    Super::BeginPlay();
    INITIALIZE_STATE_MACHINE(MyGame);
}

void AMyGameMode::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    SHUTDOWN_STATE_MACHINE(MyGame);
    Super::EndPlay(EndPlayReason);
}
```

## 网络支持（可选）

系统使用虚幻的内置同步与自定义扩展：

1. **状态机同步**：当前状态被标记为`UPROPERTY(Replicated)`并利用Subobject同步
2. **状态数据同步**：各个状态处理自己的同步需求，并通过状态机嵌套子对象同步路由回所有者同步通道

### 嵌套子对象同步
如果读者可能对什么是嵌套子对象同步感到困惑，这里有一个简要说明：

在虚幻引擎中，嵌套子对象同步是指在另一个`UObject`或`Actor`中同步本身是`UObjects`（子对象）的成员的能力。这对于状态机可能包含多个状态的复杂数据结构特别重要，每个状态都有自己需要在网络上同步的数据。默认情况下，虚幻只同步POD类型或`USTRUCT`，但`USTRUCT`不支持适当的多态性。因此，如果我们想要适当的多态性（如我们的状态）但我们也想要同步它们，我们需要使用嵌套子对象同步。

该框架的一个关键特性是正确处理嵌套子对象同步。状态机通常包含需要跨客户端同步的复杂数据。

> 有关虚幻引擎中UObject同步的详细信息，请参阅[官方文档](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicating-uobjects-in-unreal-engine)。
{: .prompt-warning }

同步基本上包含3个步骤：
- 将子对象标记为同步属性
- 在拥有角色的`GetLifetimeReplicatedProps`中注册
- 添加到拥有角色的同步列表中

我们已经在前面的部分中将状态机标记为`UPROPERTY(Replicated)`。接下来，我们需要在拥有角色的`GetLifetimeReplicatedProps`中注册它：
```cpp
public:
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

void AMyGameMode::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AMyGameMode, MyGameStateMachine);
}
```

接下来，我们将属性添加到同步子对象列表中。这里我们关心的唯一函数是`AddReplicatedSubObject`和`RemoveReplicatedSubObject`，它们由`AActor`基类提供。我们将分别在`BeginPlay`和`EndPlay`中调用这些：
```cpp
void AVFGameState::BeginPlay()
{
	Super::BeginPlay();
	
	// 仅在权威端初始化游戏状态
	if (GetLocalRole() == ROLE_Authority)
	{
		INITIALIZE_STATE_MACHINE(GamePhase);

		AddReplicatedSubObject(GamePhaseStateMachine);
		// GamePhaseStateMachine->RegisterReplicatedSubObjects(this);
	}
}

void AVFGameState::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (GetLocalRole() == ROLE_Authority)
	{
		RemoveReplicatedSubObject(GamePhaseStateMachine);
		// GamePhaseStateMachine->UnregisterReplicatedSubObjects(this);
		
		SHUTDOWN_STATE_MACHINE(GamePhase);
	}
	
	Super::EndPlay(EndPlayReason);
}
```

请注意，在上述实现中，为了更好的可读性，我们注释掉了对`GamePhaseStateMachine->RegisterReplicatedSubObjects(this);`和`GamePhaseStateMachine->UnregisterReplicatedSubObjects(this);`的调用。这些函数对于嵌套子对象同步至关重要，特别是当状态机包含也需要同步的复杂数据结构时。

```cpp
virtual void RegisterReplicatedSubObjects(AActor* Owner) { };
virtual void UnregisterReplicatedSubObjects(AActor* Owner) { };
```

重写这些方法有效地将同步列表注册（和注销）级联到当前状态，确保所有嵌套子对象在同步过程中得到适当考虑：

```cpp
void UVFGamePhaseStateMachine::RegisterReplicatedSubObjects(AActor* Owner)
{
	Super::RegisterReplicatedSubObjects(Owner);
	if (!IsValid(Owner))
		return;
	
	Owner->AddReplicatedSubObject(GetMutableCurrentState());
}

void UVFGamePhaseStateMachine::UnregisterReplicatedSubObjects(AActor* Owner)
{
	Super::UnregisterReplicatedSubObjects(Owner);

	if (!IsValid(Owner))
		return;
	
	Owner->RemoveReplicatedSubObject(GetMutableCurrentState());
}
```

不要忘记在你的状态机中重写`GetLifetimeReplicatedProps`以同步状态：

```cpp
void UVFStateMachineBase::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    UObject::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(UVFStateMachineBase, CurrentState);
}
```

> 对于涉及嵌套同步的更复杂场景，请参考[UObject同步文档](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicating-uobjects-in-unreal-engine)了解高级模式。
{: .prompt-info }

现在，我们可以自动同步状态机及其包含的状态。这是一次性设置。

### 复杂游戏状态示例

该框架在游戏阶段管理等复杂场景中表现出色：

```cpp
UCLASS()
class VESTIGESAGA_API UVFGamePhaseStateMachine : public UVFStateMachineBase
{
    GENERATED_BODY()

public:
    // 复杂的同步数据
    UPROPERTY(BlueprintReadOnly, EditAnywhere, Replicated)
    TArray<FVFPlayerSelectionData> PlayerSelections;

    UPROPERTY(BlueprintReadOnly, EditAnywhere, Replicated)
    TArray<TSoftObjectPtr<UVFEventDataAsset>> SelectedEventCards;

    // 游戏逻辑方法
    bool AreAllSelectionsComplete() const;
    FVFPlayerSelectionData* FindPlayerSelection(const int32& VFPlayerIndex);
    
    // 网络支持
    virtual void RegisterReplicatedSubObjects(AActor* Owner) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
};
```

## 优势和权衡

### 优势

**可读性**：流式语法使状态机定义自文档化：
```cpp
.From(STATE_TYPE(Setup)).To(STATE_TYPE(Playing)).When(AllPlayersReady)
```

**类型安全**：宏生成类型安全的访问器并防止常见错误。

**网络就绪**：内置同步支持无缝处理多人场景。

**可维护性**：集中化状态逻辑减少重复和错误。

**性能**：延迟初始化和高效的转换查找最小化开销。

### 考量

**宏复杂性**：大量使用宏可能会使调试和IDE支持复杂化。

**编译时依赖**：模板重度代码可能增加编译时间。

**学习曲线**：流式API需要理解建造者模式。

**内存占用**：缓存和查找结构消耗额外内存。

## 要点

这个流式状态机框架演示了几个重要概念：

- **领域特定语言**：宏可以在C++中创建可读的、领域特定的语法
- **建造者模式**：方法链接创建直观的配置API
- **网络架构**：适当的同步处理对于多人系统至关重要
- **代码生成**：宏可以在保持类型安全的同时消除样板
- **UHT意识**：理解工具限制对于健壮的宏设计至关重要

该框架成功地平衡了灵活性和易用性，为复杂的游戏状态管理提供了强大的基础。虽然宏重度方法可能不适合所有项目，但它为重视干净、可维护代码的团队提供了显著的好处。

关键见解是设计良好的抽象可以使复杂系统既更强大又更易于接近——将原本可能是数百行样板代码的内容转化为优雅、可读的声明，清晰地表达意图。