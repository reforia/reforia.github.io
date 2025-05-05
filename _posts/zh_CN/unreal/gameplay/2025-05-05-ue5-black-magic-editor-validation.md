---
layout: post
title: "Lyra技术解析 - 编辑器验证"
description:
  这是一系列关于我从Epic的Lyra项目中学到的知识笔记。该项目声称展示了当前虚幻引擎框架下的最佳实践。其中有些内容是我之前不了解的，有些则已经知晓，但认为仍然值得记录。
date: 2025-05-05 12:05 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor/
lang: zh-CN
---

{% include ue_version_disclaimer.html version="5.5.4" %}

## 验证函数
在上一篇文章中，我们讨论了如何在编辑器中添加触发特定操作的新按钮（"检查内容"的示例）。该按钮调用了定义在`EditorValidator.cpp`中的`UEditorValidator::ValidateCheckedOutContent`函数，该函数负责验证从源代码控制系统中检出的内容。我们将逐步分析这个函数的具体实现。

### 提前返回
函数首先检查资源注册表是否仍在加载资源。如果是，函数会提前返回并向用户显示消息对话框。这一点很重要，因为如果资源注册表仍在加载过程中，验证结果可能不准确。

```cpp
void UEditorValidator::ValidateCheckedOutContent(bool bInteractive, const EDataValidationUsecase InValidationUsecase)
{
	if (FStudioTelemetry::IsAvailable())
	{
		FStudioTelemetry::Get().RecordEvent(TEXT("ValidateContent"));
	}

	FAssetRegistryModule& AssetRegistryModule = FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry");
	if (AssetRegistryModule.Get().IsLoadingAssets())
	{
		if (bInteractive)
		{
			FMessageDialog::Open(EAppMsgType::Ok, LOCTEXT("DiscoveringAssets", "Still discovering assets. Try again once it is complete."));
		}
		else
		{
			UE_LOG(LogLyraEditor, Display, TEXT("Could not run ValidateCheckedOutContent because asset discovery was still being done."));
		}
		return;
	}
	// ...
}
```

### 获取已检出文件
接下来，我们通过调用带有修改谓词（Checked Out/Add/Delete）的`GetCachedStateByPredicate`函数，尝试获取所有已检出的文件。该函数将返回一个包含`FSourceControlStateRef`对象的数组，这些对象代表已检出的文件。随后我们可以遍历这个数组并检查每个文件的状态。

```cpp
	// ...
	TArray<FString> ChangedPackageNames;
	TArray<FString> DeletedPackageNames;

	ISourceControlProvider& SourceControlProvider = ISourceControlModule::Get().GetProvider();
	if (ISourceControlModule::Get().IsEnabled())
	{
		// Request the opened files at filter construction time to make sure checked out files have the correct state for the filter
		TSharedRef<FUpdateStatus, ESPMode::ThreadSafe> UpdateStatusOperation = ISourceControlOperation::Create<FUpdateStatus>();
		UpdateStatusOperation->SetGetOpenedOnly(true);

		TArray<FSourceControlStateRef> CheckedOutFiles = SourceControlProvider.GetCachedStateByPredicate(
			[](const FSourceControlStateRef& State) { return State->IsCheckedOut() || State->IsAdded() || State->IsDeleted(); }
		);
		// ...
	}
```

### 过滤已检出文件
将检出文件转换为长包名后，我们可以根据其状态进行过滤。如果是包文件，则检查该文件是否被删除或修改。

如果是头文件，则需要检查它是否属于可能导致基于这些类的资产出现问题的源代码头文件变更。我们可以通过调用`UEditorValidator::GetChangedAssetsForCode`函数来实现，该函数将返回已更改的包名数组。由于这是个非常庞大的函数，我们稍后再做详细解释。

```cpp
		// ...
		for (const FSourceControlStateRef& FileState : CheckedOutFiles)
		{
			FString Filename = FileState->GetFilename();
			if (FPackageName::IsPackageFilename(Filename))
			{
				// Assets
				FString PackageName;
				if (FPackageName::TryConvertFilenameToLongPackageName(Filename, PackageName))
				{
					if (FileState->IsDeleted())
					{
						DeletedPackageNames.Add(PackageName);
					}
					else
					{
						ChangedPackageNames.Add(PackageName);
					}
				}
			}
			else if (Filename.EndsWith(TEXT(".h")))
			{
				// Source code header changes for classes may cause issues in assets based on those classes
				UEditorValidator::GetChangedAssetsForCode(AssetRegistryModule.Get(), Filename, ChangedPackageNames);
			}
		}
		// ...
```

### 验证数据包
过滤完已检出的文件后，现在可以验证数据包了。我们将调用`ValidatePackages`函数，传入已更改的包名和已删除的包名。该函数会检查数据包是否有效，并返回布尔值表示是否发现问题。

```cpp
	bool bAnyIssuesFound = false;
	TArray<FString> AllWarningsAndErrors;
	{
		if (bInteractive)
		{
			bAllowFullValidationInEditor = true;

			// We will be flushing shader compile as we load materials, so dont let other shader warnings be attributed incorrectly to the package that is loading.
			if (GShaderCompilingManager)
			{
				FScopedSlowTask SlowTask(0.f, LOCTEXT("CompilingShadersBeforeCheckingContentTask", "Finishing shader compiles before checking content..."));
				SlowTask.MakeDialog();
				GShaderCompilingManager->FinishAllCompilation();
			}
		}
		{
			FScopedSlowTask SlowTask(0.f, LOCTEXT("CheckingContentTask", "Checking content..."));
			SlowTask.MakeDialog();
			if (!ValidatePackages(ChangedPackageNames, DeletedPackageNames, 2000, AllWarningsAndErrors, InValidationUsecase))
			{
				bAnyIssuesFound = true;
			}
		}
		if (bInteractive)
		{
			bAllowFullValidationInEditor = false;
		}
	}
	// ...
```

### 验证项目设置
同样地，下一步是验证项目设置。我们将调用`ValidateProjectSettings`函数，该函数会检查项目设置是否有效，并返回布尔值表示是否发现问题。

```cpp
	{
		FLyraValidationMessageGatherer ScopedMessageGatherer;
		if (!ValidateProjectSettings())
		{
			bAnyIssuesFound = true;
		}
		AllWarningsAndErrors.Append(ScopedMessageGatherer.GetAllWarningsAndErrors());
	}
	// ...
```

### 报告结果
最后，我们将报告验证结果。如果发现任何问题，将向用户显示消息对话框提示检出内容存在问题；如果未发现问题，则显示一切正常的消息。

```cpp
	// ...
	if (bInteractive)
	{
		const bool bAtLeastOneMessage = (AllWarningsAndErrors.Num() != 0);
		if (bAtLeastOneMessage)
		{
			FMessageDialog::Open(EAppMsgType::Ok, LOCTEXT("ContentValidationFailed", "!!!!!!! Your checked out content has issues. Don't submit until they are fixed !!!!!!!\r\n\r\nSee the MessageLog and OutputLog for details"));
		}
		else if (bAnyIssuesFound)
		{
			FMessageDialog::Open(EAppMsgType::Ok, LOCTEXT("ContentValidationFailedWithNoMessages", "No errors or warnings were found, but there was an error return code. Look in the OutputLog and log file for details. You may need engineering help."));
		}
		else
		{
			FMessageDialog::Open(EAppMsgType::Ok, LOCTEXT("ContentValidationPassed", "All checked out content passed. Nice job."));
		}
	}
	// ...
```

## FScopedSlowTask
`FScopedSlowTask` 是虚幻引擎中用于管理耗时任务进度的类，它继承自`FSlowTask`。如示例所示，当`GShaderCompilingManager`编译着色器或我们验证数据包时，会通过这个类显示进度条。

当该对象超出作用域时，它会自动销毁进度条并清理任务占用的所有资源。

> 我们还可以嵌套使用`FScopedSlowTask`来显示包含多个子任务的进度情况。这对于需要分解为多个步骤的长时间运行任务特别有用。
{: .prompt-tip }

```cpp
/**
 * A scope block representing an amount of work divided up into sections.
 * Use one scope at the top of each function to give accurate feedback to the user of a slow operation's progress.
 *
 * Example Usage:
 *	void DoSlowWork()
 *	{
 *		FScopedSlowTask Progress(2.f, LOCTEXT("DoingSlowWork", "Doing Slow Work..."));
 *		// Optionally make this show a dialog if not already shown
 *		Progress.MakeDialog();
 *
 *		// Indicate that we are entering a frame representing 1 unit of work
 *		Progress.EnterProgressFrame(1.f);
 *		
 *		// DoFirstThing() can follow a similar pattern of creating a scope divided into frames. These contribute to their parent's progress frame proportionately.
 *		DoFirstThing();
 *		
 *		Progress.EnterProgressFrame(1.f);
 *		DoSecondThing();
 *	}
 *
 */
struct FScopedSlowTask : FSlowTask
{

	/**
	 * Construct this scope from an amount of work to do, and a message to display
	 * @param		InAmountOfWork			Arbitrary number of work units to perform (can be a percentage or number of steps).
	 *										0 indicates that no progress frames are to be entered in this scope (automatically enters a frame encompassing the entire scope)
	 * @param		InDefaultMessage		A message to display to the user to describe the purpose of the scope
	 * @param		bInEnabled				When false, this scope will have no effect. Allows for proper scoped objects that are conditionally disabled.
	 */
	FORCEINLINE FScopedSlowTask(float InAmountOfWork, const FText& InDefaultMessage = FText(), bool bInEnabled = true, FFeedbackContext& InContext = *GWarn)
		: FSlowTask(InAmountOfWork, InDefaultMessage, bInEnabled, InContext)
	{
		Initialize();
	}

	FORCEINLINE ~FScopedSlowTask()
	{
		Destroy();
	}
};
```

## 函数内的静态结构体
如前所述，`GetChangedAssetsForCode`函数用于在修改相关头文件时获取所有可能受影响的蓝图，但真正精妙之处在于它使用了一个静态结构体`FCachedNativeClasses`来缓存项目中所有的原生类。这种设计巧妙地避免了每次需要查找类时都要重新搜索的开销。`FCachedNativeClasses`结构体被定义在`GetChangedAssetsForCode`函数内部，因此它只会被创建一次，并在所有对该函数的调用中重复使用。

该函数的工作原理是首先定位变更头文件所属的模块。它通过调用`FSourceCodeNavigation::GetSourceFileDatabase().GetModuleNames()`获取所有模块名称列表，然后检查变更的头文件路径是否以这些模块路径开头。

```cpp
// --------------------------------------------------------
void UEditorValidator::GetChangedAssetsForCode(IAssetRegistry& AssetRegistry, const FString& ChangedHeaderLocalFilename, TArray<FString>& OutChangedPackageNames)
{
	static struct FCachedNativeClasses{...} NativeClassCache;

	const TArray<FString>& ModuleNames = FSourceCodeNavigation::GetSourceFileDatabase().GetModuleNames();
	const FString* Module = ModuleNames.FindByPredicate([ChangedHeaderLocalFilename](const FString& ModuleBuildPath) {
		const FString ModuleFullPath = FPaths::ConvertRelativePathToFull(FPaths::GetPath(ModuleBuildPath));
		if (ChangedHeaderLocalFilename.StartsWith(ModuleFullPath))
		{
			return true;
		}
		return false;
		});

	if (Module)
	{
		// ...
	}
}

struct FCachedNativeClasses
{
	public:
		FCachedNativeClasses()
		{
			static const FName ModuleNameFName = "ModuleName";
			static const FName ModuleRelativePathFName = "ModuleRelativePath";

			for (TObjectIterator<UClass> ClassIt; ClassIt; ++ClassIt)
			{
				UClass* TestClass = *ClassIt;
				if (TestClass->HasAnyClassFlags(CLASS_Native))
				{
					FAssetData ClassAssetData(TestClass);

					FString ModuleName, ModuleRelativePath;
					ClassAssetData.GetTagValue(ModuleNameFName, ModuleName);
					ClassAssetData.GetTagValue(ModuleRelativePathFName, ModuleRelativePath);

					Classes.Add(ModuleName + TEXT("+") + ModuleRelativePath, TestClass);
				}
			}
		}

		TArray<TWeakObjectPtr<UClass>> GetClassesInHeader(const FString& ModuleName, const FString& ModuleRelativePath)
		{
			TArray<TWeakObjectPtr<UClass>> ClassesInHeader;
			Classes.MultiFind(ModuleName + TEXT("+") + ModuleRelativePath, ClassesInHeader);

			return ClassesInHeader;
		}

	private:
		TMultiMap<FString, TWeakObjectPtr<UClass>> Classes;
}
```

## 自定义编辑器验证器类
创建自定义编辑器验证器类非常简单，我们只需要继承`UEditorValidator`并实现`CanValidateAsset_Implementation`和`ValidateLoadedAsset_Implementation`两个函数即可。

```cpp
// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "EditorValidator.h"

#include "EditorValidator_SourceControl.generated.h"

class FText;
class UObject;

UCLASS()
class UEditorValidator_SourceControl : public UEditorValidator
{
	GENERATED_BODY()

public:
	UEditorValidator_SourceControl();

protected:
	using Super::CanValidateAsset_Implementation; // -Woverloaded-virtual
	virtual bool CanValidateAsset_Implementation(const FAssetData& InAssetData, UObject* InObject, FDataValidationContext& InContext) const override;
	virtual EDataValidationResult ValidateLoadedAsset_Implementation(const FAssetData& InAssetData, UObject* InAsset, FDataValidationContext& Context) override;
};
```

```cpp
// Copyright Epic Games, Inc. All Rights Reserved.

#include "EditorValidator_SourceControl.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "ISourceControlModule.h"
#include "Misc/PackageName.h"
#include "SourceControlHelpers.h"
#include "Validation/EditorValidator.h"

#include UE_INLINE_GENERATED_CPP_BY_NAME(EditorValidator_SourceControl)

#define LOCTEXT_NAMESPACE "EditorValidator"

UEditorValidator_SourceControl::UEditorValidator_SourceControl()
	: Super()
{
	
}

bool UEditorValidator_SourceControl::CanValidateAsset_Implementation(const FAssetData& InAssetData, UObject* InAsset, FDataValidationContext& InContext) const
{
	return InAsset != nullptr;
}

EDataValidationResult UEditorValidator_SourceControl::ValidateLoadedAsset_Implementation(const FAssetData& InAssetData, UObject* InAsset, FDataValidationContext& Context)
{
	// ...

	return GetValidationResult();
}

#undef LOCTEXT_NAMESPACE
```

## 抑制-Woverloaded-virtual警告
在上面的代码中，我们可以在头文件中看到一个特殊的注释行`// -Woverloaded-virtual`。虽然`-Woverloaded-virtual`警告（在Clang等编译器中）并不神秘——它表示派生函数与基类函数存在签名不匹配，导致派生版本"隐藏"了基类函数（本例中的`CanValidateAsset_Implementation`）——但这里的处理方式值得探讨。

通过阅读源代码可以发现，这是因为接收`UObject* InAsset`参数的`CanValidateAsset_Implementation`版本已被弃用，最新的函数签名已更新为`CanValidateAsset_Implementation(UObject* InObject, FDataValidationContext& InContext)`。如果子类实现了新签名但未修改基类版本，就会触发`-Woverloaded-virtual`警告。这里的处理方式本质上是通过将基类函数引入当前作用域来抑制警告。

```cpp
UCLASS()
class UEditorValidator_Blueprints : public UEditorValidator
{
	// ...

protected:
	using Super::CanValidateAsset_Implementation; // -Woverloaded-virtual
	virtual bool CanValidateAsset_Implementation(const FAssetData& InAssetData, UObject* InAsset, FDataValidationContext& InContext) const override;
	// ...
};

// The base class is still using the old signature.
UCLASS(Abstract)
class UEditorValidator : public UEditorValidatorBase
{
	// ...
protected:
	virtual bool CanValidateAsset_Implementation(UObject* InAsset) const override;
}

// EditorValidatorBase.cpp
	UE_DEPRECATED("5.4", "CanValidateAsset_Implementation(UObject* InAsset) is deprecated, override CanValidateAsset_Implementation(UObject* InObject, FDataValidationContext& InContext) instead")
	virtual bool CanValidateAsset_Implementation(UObject* InAsset) const 
	{
		 return true; 
	}
// ...
```

### 为何不直接更新基类？
不更新基类的主要原因是这会破坏所有子类中现有的`CanValidateAsset_Implementation`实现。在大型代码库中，要求所有开发者同步更新代码以匹配新签名是不现实的。通过保留旧签名并抑制警告，开发者可以逐步更新代码而不影响现有功能。

这个案例很好地展示了虚幻引擎如何在保持向后兼容性的同时，仍能持续推进代码库的改进和更新。