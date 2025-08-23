---
layout: post
title: "Fluent FSM - Building State Machines with Style"
description:
  A deep dive into creating a fluent-style state machine framework for Unreal Engine with powerful macro-based syntax that handles nested replication and provides elegant builder patterns.
date: 2025-08-23 15:30 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/fluent-fsm/
lang: en
---

{% include ue_version_disclaimer.html version="5.4.0" %}

{% include ue_engine_post_disclaimer.html %}

## Preface
State machines are fundamental to game logic, handling everything from AI behaviors to game flow management. While Unreal provides various tools for state management, building a clean, reusable, and network-friendly state machine system often requires custom solutions. This post explores a fluent-style state machine framework that combines the power of macros with builder patterns to create an elegant and maintainable system.

The framework we'll examine demonstrates several key concepts:
- **Fluent Syntax**: Chainable method calls that read like natural language
- **Macro-based State Definition**: Automatic generation of boilerplate code
- **Nested Subobject Handling**: Proper management of complex state hierarchies

## The Architecture

### Core Components

The system is built around four main components:

**`UVFStateBase`**: The base class for all states, providing virtual methods for state lifecycle:
- `EnterState()`: Called when transitioning into this state
- `ExitState()`: Called when leaving this state  
- `UpdateState()`: Called every tick while active

**`UVFStateMachineBase`**: The state machine controller that:
- Manages current state and transitions
- Handles automatic tick updates
- Provides network replication support
- Implements transition validation and conditions

**`FStateMachineBuilder`**: A fluent builder class that allows readable state machine definitions:
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

**Macro System**: Provides declarative syntax for state machine integration.

## StateMachineBase and StateBase
The state machine inherit from a `FTickableGameObject` so we can share the ticking thread, rather than create our own ticking delegate. This decouples the need to call tick manually from owner or external systems. The SM will handle update for underlying states automatically.

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

A state is a simple `UObject` with virtual methods for lifecycle management:

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

The State Machine is the class, while the fluent syntax is essentially creating a descriptor of the underlying state machine class, so we need a "meta" class for it

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

### The Macro Magic

The framework uses several macros to eliminate boilerplate and provide clean integration:

#### Declaration Macros

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

This macro generates:
- A static factory method for the state machine definition
- Lazy-loaded caching of the definition
- Type-safe accessors for the state machine instance

#### Implementation and Lifecycle Macros

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

These handle the complete lifecycle from definition to cleanup.

#### Type Helper Macros

```cpp
#define STATE_TYPE(StateName) \
UVF##StateName##State::StaticClass()

#define STATEMACHINE_TYPE(StateMachineName) \
UVF##StateMachineName##StateMachine::StaticClass()
```

These provide type-safe references to state and state machine classes.

### Why Manual UPROPERTY Declaration?
In the implementation of the `UVFStateMachineBase` we marked the `CurrentState` as `UPROPERTY(Replicated)`

```cpp
private:
	UPROPERTY(Replicated)
	TObjectPtr<UVFStateBase> CurrentState;
```

You might wonder why the `DECLARE_STATE_MACHINE` macro doesn't automatically create the member variable since it already has the type info and name? The reason is a limitation with UHT (Unreal Header Tool) macro expansion:

```cpp
// This would be problematic:
#define DECLARE_STATE_MACHINE(MachineName) \
UPROPERTY(Replicated) \
TObjectPtr<UVF##MachineName##StateMachine> MachineName##StateMachine;
```

IDEs often don't properly expand macros before UHT parsing, causing UHT to fail at generating correct reflection code. When `DOREPLIFETIME()` is used for replication, `FindField()` assertions will fail because the macro-expanded property name wasn't properly recognized during reflection generation.

> This is a common pitfall when working with UHT - always ensure property names are explicitly visible to the header tool.
{: .prompt-warning }

## Fluent Builder Pattern

The builder pattern allows for natural language-like state machine definitions:

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

### Builder Implementation

The builder maintains state between method calls and validates the configuration:

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

## Advanced Features

### Automatic Transitions

The system supports both manual and automatic state transitions:

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

### Transition Validation and Error handling

Force transitions include comprehensive validation for debugging:

```cpp
bool UVFStateMachineBase::TryForceSetState(const TSubclassOf<UVFStateBase>& TargetStateClass, TArray<FGameplayTag>& OutFailReasons)
{
    OutFailReasons.Empty();
    
    if (!TargetStateClass)
    {
        OutFailReasons.Add(VF_STATE_TAGS::TAG_TRANSITION_FAILURE_STATE_INVALID);
        return false;
    }
    
    // Verify state exists in definition
    bool bStateExists = TransitionMap.Contains(TargetStateClass);
    if (!bStateExists)
    {
        // Check if it's a valid target state
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

### Debug Support

Non-shipping builds include extensive debug capabilities for each state, so a show debug info call can get the state machine, and get current state, then just call the polymorphic debug info method on the current state:

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

## Usage Patterns

The framework follows a 3-step usage pattern that ensures proper UHT compatibility and network support:

### Step-by-Step Integration

**Step 1: Declare the State Machine**

Use the `DECLARE_STATE_MACHINE` macro and manually create a `UPROPERTY()` member:
```cpp
class GAME_API AMyGameMode : public AGameModeBase
{
    GENERATED_BODY()
    
    DECLARE_STATE_MACHINE(MyGame)
    
private:
    // Manual UPROPERTY declaration required for UHT compatibility
    // In our macro we expect the property to be have type exactly of UVF + MachineName + StateMachine, and the property name to be exactly MachineName + StateMachine, but you can of course name the property whatever you want, just adjust the accessors accordingly
    // Replicated is also unnecessary if you don't need network support
    UPROPERTY(Replicated)
    TObjectPtr<UVFMyGameStateMachine> MyGameStateMachine;
};
```

**Step 2: Define the State Machine Skeleton**

Use `IMPLEMENT_STATE_MACHINE` with fluent syntax to define the state machine structure:
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

**Step 3: Initialize the State Machine Instance**

Call `INITIALIZE_STATE_MACHINE` to create an instance based on the skeleton definition at proper lifecycle events, in our case we want a state machine to control the match flow, so we initialize it in `BeginPlay` and clean up in `EndPlay`:
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

## Network Support (Optional)

The system uses Unreal's built-in replication with custom extensions:

1. **State Machine Replication**: The current state is marked as `UPROPERTY(Replicated)` and utilizing Subobject replication
2. **State Data Replication**: Individual states handle their own replication needs, and is routed back to owner actor replication channel via state machine nested subobject replication

### Nested Subobject Replication
Just in case the reader might be confused about what nested subobject replication is, here is a brief explanation:

In Unreal Engine, nested subobject replication refers to the ability to replicate UObject properties that are themselves UObjects (subobjects) within another UObject or Actor. This is particularly important for complex data structures where a state machine might contain multiple states, each with its own data that needs to be synchronized across the network. By default, unreal replicates only POD type or USTRUCTs, but USTRUCT doesn't support proper polymorphism. So if we want proper polymorphism (Like for our states) but we also want to replicate them, we need to use nested subobject replication.

One of the framework's key features is proper handling of nested subobject replication. State machines often contain complex data that needs to be synchronized across clients.

> For detailed information about UObject replication in Unreal Engine, see the [official documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicating-uobjects-in-unreal-engine).
{: .prompt-warning }

The replication basically contains 3 steps:
- Mark the subobject as replicated prop
- Register in the GetLifetimeReplicatedProps of the owning actor
- Add to the replication list of the owning actor

We already marked the state machine as `UPROPERTY(Replicated)` in previous section. Next, we need to register it in the owning actor's `GetLifetimeReplicatedProps`:
```cpp
public:
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

void AMyGameMode::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(AMyGameMode, MyGameStateMachine);
}
```

Next, we will add the property to a replicated subobject list. The only functions we care about here is `AddReplicatedSubObject` and `RemoveReplicatedSubObject`, which are provided by `AActor` base class. We will call these in `BeginPlay` and `EndPlay` respectively:
```cpp
void AVFGameState::BeginPlay()
{
	Super::BeginPlay();
	
	// Initialize game state only on authority
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

Note that in the above implementation we commented out the calls to `GamePhaseStateMachine->RegisterReplicatedSubObjects(this);` and `GamePhaseStateMachine->UnregisterReplicatedSubObjects(this);` for better readability. These functions are essential for nested subobject replication, especially when the state machine contains complex data structures that also need to be replicated.

```cpp
virtual void RegisterReplicatedSubObjects(AActor* Owner) { };
virtual void UnregisterReplicatedSubObjects(AActor* Owner) { };
```

Override these methods effectively cascades down the replication list registration (and un-registration) to the current state, ensuring that all nested subobjects are properly accounted for in the replication process:

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

Don't forget to also override `GetLifetimeReplicatedProps` in your state machine to replicate the state as well:

```cpp
void UVFStateMachineBase::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
    UObject::GetLifetimeReplicatedProps(OutLifetimeProps);
    DOREPLIFETIME(UVFStateMachineBase, CurrentState);
}
```

> For more complex scenarios involving nested replication, refer to the [UObject replication documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicating-uobjects-in-unreal-engine) for advanced patterns.
{: .prompt-info }

With, we can now automatically replicate the state machine and the state it contains. It's a once and for all setup.

### Complex Game State Example

The framework shines in complex scenarios like game phase management:

```cpp
UCLASS()
class GAME_API UVFGamePhaseStateMachine : public UVFStateMachineBase
{
    GENERATED_BODY()

public:
    // Complex replicated data
    UPROPERTY(BlueprintReadOnly, EditAnywhere, Replicated)
    TArray<FVFPlayerSelectionData> PlayerSelections;

    UPROPERTY(BlueprintReadOnly, EditAnywhere, Replicated)
    TArray<TSoftObjectPtr<UVFEventDataAsset>> SelectedEventCards;

    // Game logic methods
    bool AreAllSelectionsComplete() const;
    FVFPlayerSelectionData* FindPlayerSelection(const int32& VFPlayerIndex);
    
    // Network support
    virtual void RegisterReplicatedSubObjects(AActor* Owner) override;
    virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;
};
```

## Benefits and Trade-offs

### Advantages

**Readability**: The fluent syntax makes state machine definitions self-documenting:
```cpp
.From(STATE_TYPE(Setup)).To(STATE_TYPE(Playing)).When(AllPlayersReady)
```

**Type Safety**: Macros generate type-safe accessors and prevent common errors.

**Network Ready**: Built-in replication support handles multiplayer scenarios seamlessly.

**Maintainability**: Centralized state logic reduces duplication and bugs.

**Performance**: Lazy initialization and efficient transition lookups minimize overhead.

### Considerations

**Macro Complexity**: Heavy macro usage can complicate debugging and IDE support.

**Compile-time Dependencies**: Template-heavy code may increase compile times.

**Learning Curve**: The fluent API requires understanding of the builder pattern.

**Memory Footprint**: Caching and lookup structures consume additional memory.

## Take Aways

This fluent state machine framework demonstrates several important concepts:

- **Domain-Specific Languages**: Macros can create readable, domain-specific syntax within C++
- **Builder Patterns**: Method chaining creates intuitive configuration APIs
- **Network Architecture**: Proper replication handling is crucial for multiplayer systems
- **Code Generation**: Macros can eliminate boilerplate while maintaining type safety
- **UHT Awareness**: Understanding tool limitations is crucial for robust macro design

The framework successfully balances flexibility with ease of use, providing a robust foundation for complex game state management. While the macro-heavy approach may not suit all projects, it offers significant benefits for teams that value clean, maintainable code.

The key insight is that well-designed abstractions can make complex systems both more powerful and more approachable—turning what could be hundreds of lines of boilerplate into elegant, readable declarations that clearly express intent.