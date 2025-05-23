---
layout: post
title: "Lyra Breakdown - Editor Validation"
description:
  A feature has been finished beautifully, and let's submit it and call it a day. Oh wait...
date: 2025-05-05 12:05 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/ue5-black-magic-editor/
lang: en
---

{% include ue_version_disclaimer.html version="5.5.4" %}

{% include ue_engine_post_disclaimer.html %}

> This is a series of notes about what I've learned from Epic's Lyra project. Which claim to be the best practices under current unreal engine framework. Some I don't know about, some I already know but I thought it would still be good noting down.
{: .prompt-info }

## Validation Functions
In the last post, we talked about how to add a new button in editor that would trigger some actions (The Check Content example). The button is calling `UEditorValidator::ValidateCheckedOutContent` function, which is defined in `EditorValidator.cpp`. This function is responsible for validating the content that has been checked out from source control. We will go through the function step by step to understand what it does.

### Early Returns
The function starts by checking if the asset registry is still loading assets. If it is, the function will return early and display a message dialog to the user. This is important because if the asset registry is still loading, the validation may not be accurate.

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

### Get Checked Out Files
Then we try to get all the checked out files, by calling `GetCachedStateByPredicate` function with the modified predicate (Checked Out, Add, Delete). This function will return an array of `FSourceControlStateRef` objects that represent the checked out files. We can then iterate through this array and check the state of each file.

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

### Filter Checked Out Files
After converting the checked out files to their long package names, we can filter them based on their state. If it is a package file, we check if it is deleted or changed. 

If the file is a header file, we need to check if it is a source code header change for classes that may cause issues in assets based on those classes. We can do this by calling `UEditorValidator::GetChangedAssetsForCode` function, which will return an array of changed package names. This is a huge function, so we will explain it later.

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

### Validate Packages
After filtering the checked out files, we can now validate the packages. We will call `ValidatePackages` function with the changed package names and deleted package names. This function will check if the packages are valid and return a boolean value indicating if there were any issues found.

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

### Validate Project Settings
Similarly, the next step is to validate the project settings. We will call `ValidateProjectSettings` function, which will check if the project settings are valid and return a boolean value indicating if there were any issues found.

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

### Report Result
Finally, we will report the result of the validation. If there were any issues found, we will display a message dialog to the user indicating that there were issues with the checked out content. If there were no issues found, we will display a message indicating that everything is fine.

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

## FMessageDialog
`FMessageDialog` is a class that provides a way to display message dialogs to the user. It is used to show messages, warnings, and errors in the editor. The class really just have a variety of `Open` functions to use. Which is used to display a simple message dialog with an OK button. For testing purposes, we can use `Debugf` to show a message dialog with a custom title and message as well.

```cpp
/** 
 * FMessageDialog
 * These functions open a message dialog and display the specified informations
 * there.
 **/
struct FMessageDialog
{
    /** Pops up a message dialog box containing the input string.
     * @param Message Text of message to show
     * @param Title Optional title to use (defaults to "Message")
    */
    static CORE_API void Debugf( const FText& Message );
    static CORE_API void Debugf( const FText& Message, const FText& Title );

    /** Pops up a message dialog box containing the last system error code in string form. */
    static CORE_API void ShowLastError();

    /**
     * Open a modal message box dialog
     * @param MessageCategory Controls the icon used for the dialog
     * @param MessageType Controls buttons dialog should have
     * @param Message Text of message to show
     * @param Title Optional title to use (defaults to "Message")
    */
    static CORE_API EAppReturnType::Type Open( EAppMsgType::Type MessageType, const FText& Message);
    static CORE_API EAppReturnType::Type Open( EAppMsgType::Type MessageType, const FText& Message, const FText& Title);
    static CORE_API EAppReturnType::Type Open( EAppMsgCategory MessageCategory, EAppMsgType::Type MessageType, const FText& Message);
    static CORE_API EAppReturnType::Type Open( EAppMsgCategory MessageCategory, EAppMsgType::Type MessageType, const FText& Message, const FText& Title);

    /**
     * Open a modal message box dialog
     * @param MessageCategory Controls the icon used for the dialog
     * @param MessageType Controls buttons dialog should have
     * @param DefaultValue If the application is Unattended, the function will log and return DefaultValue
     * @param Message Text of message to show
     * @param Title Optional title to use (defaults to "Message")
    */
    static CORE_API EAppReturnType::Type Open(EAppMsgType::Type MessageType, EAppReturnType::Type DefaultValue, const FText& Message);
    static CORE_API EAppReturnType::Type Open(EAppMsgType::Type MessageType, EAppReturnType::Type DefaultValue, const FText& Message, const FText& Title);
    static CORE_API EAppReturnType::Type Open(EAppMsgCategory MessageCategory, EAppMsgType::Type MessageType, EAppReturnType::Type DefaultValue, const FText& Message);
    static CORE_API EAppReturnType::Type Open(EAppMsgCategory MessageCategory, EAppMsgType::Type MessageType, EAppReturnType::Type DefaultValue, const FText& Message, const FText& Title);
};
```

## Scoped Class FLyraValidationMessageGatherer
Let's revisit the `ValidateProjectSettings` part. We can see that it is using a scoped class `FLyraValidationMessageGatherer` to gather all the warnings and errors during the validation process. This class is derived from `FOutputDevice`, which is a base class for output devices in Unreal Engine. It overrides the `Serialize` function to capture all the warnings and errors generated during the validation process.

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

It's a common approach to guard certain info in a scoped class to make the code more readable and maintainable, it also allows us to do more operations in an encapsulated object. The word "Scoped" here essentially just means the object will take care of it's own life cycle during construct and destructor and we should declare it on Stack. The `FLyraValidationMessageGatherer` class is used to gather all the warnings and errors generated during the validation process. It captures the messages and stores them in an array for later use.

For example, we have a `Serialize` function to process the messages which will take care of ignored cases and verbosity. Though I feel it's a bit wierd to call it `Serialize`, since it doesn't really serialize the strings to anything like an `FArchive`, but rather just processes the messages.

```cpp
class FLyraValidationMessageGatherer : public FOutputDevice
{
public:
    FLyraValidationMessageGatherer()
        : FOutputDevice()
    {
        GLog->AddOutputDevice(this);
    }

    virtual ~FLyraValidationMessageGatherer() override
    {
        GLog->RemoveOutputDevice(this);
    }

    virtual void Serialize(const TCHAR* V, ELogVerbosity::Type Verbosity, const class FName& Category) override
    {
        if (Verbosity <= ELogVerbosity::Warning)
        {
            FString MessageString(V);
            bool bIgnored = false;
            for (const FString& IgnorePattern : IgnorePatterns)
            {
                if (MessageString.Contains(IgnorePattern))
                {
                    bIgnored = true;
                    break;
                }
            }

            if (!bIgnored)
            {
                AllWarningsAndErrors.Add(MessageString);
                if (Verbosity == ELogVerbosity::Warning)
                {
                    AllWarnings.Add(MessageString);
                }
            }
        }
    }

    const TArray<FString>& GetAllWarningsAndErrors() const
    {
        return AllWarningsAndErrors;
    }

    const TArray<FString>& GetAllWarnings() const
    {
        return AllWarnings;
    }

    static void AddIgnorePatterns(const TArray<FString>& NewPatterns)
    {
        IgnorePatterns.Append(NewPatterns);
    }

    static void RemoveIgnorePatterns(const TArray<FString>& PatternsToRemove)
    {
        for (const FString& PatternToRemove : PatternsToRemove)
        {
            IgnorePatterns.RemoveSingleSwap(PatternToRemove);
        }
    }

private:
    TArray<FString> AllWarningsAndErrors;
    TArray<FString> AllWarnings;
    static TArray<FString> IgnorePatterns;
};
```

## FScopedSlowTask
A `FScopedSlowTask` is a class that helps to manage the progress of a slow task in Unreal Engine. It provides a way to display a progress bar and update it as the task progresses. The class is derived from `FSlowTask`. As can be seen in the example above, we are showing a progress bar when `GShaderCompilingManager` is compiling shaders and when we are validating packages.

When it goes out of scope, it will automatically destroy the progress bar and clean up any resources used by the task.

> We can also nest `FScopedSlowTask` to show progress of a task that is divided into multiple sub-tasks. This is useful when we have a long-running task that can be broken down into smaller steps.
{: .prompt-tip }

```cpp
/**
 * A scope block representing an amount of work divided up into sections.
 * Use one scope at the top of each function to give accurate feedback to the user of a slow operation's progress.
 *
 * Example Usage:
 *    void DoSlowWork()
 *    {
 *        FScopedSlowTask Progress(2.f, LOCTEXT("DoingSlowWork", "Doing Slow Work..."));
 *        // Optionally make this show a dialog if not already shown
 *        Progress.MakeDialog();
 *
 *        // Indicate that we are entering a frame representing 1 unit of work
 *        Progress.EnterProgressFrame(1.f);
 *        
 *        // DoFirstThing() can follow a similar pattern of creating a scope divided into frames. These contribute to their parent's progress frame proportionately.
 *        DoFirstThing();
 *        
 *        Progress.EnterProgressFrame(1.f);
 *        DoSecondThing();
 *    }
 *
 */
struct FScopedSlowTask : FSlowTask
{

    /**
     * Construct this scope from an amount of work to do, and a message to display
     * @param        InAmountOfWork            Arbitrary number of work units to perform (can be a percentage or number of steps).
     *                                        0 indicates that no progress frames are to be entered in this scope (automatically enters a frame encompassing the entire scope)
     * @param        InDefaultMessage        A message to display to the user to describe the purpose of the scope
     * @param        bInEnabled                When false, this scope will have no effect. Allows for proper scoped objects that are conditionally disabled.
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

## Static Struct Inside Function
As mentioned before, the `GetChangedAssetsForCode` function is used to get all potentially changed blueprints if we have modified a related header file, but that's not what makes it cool, what really shines is it's using a static struct `FCachedNativeClasses` to cache all the native classes in the project. This is a clever way to avoid having to search for the classes every time we need to find them. The `FCachedNativeClasses` struct is defined inside the `GetChangedAssetsForCode` function, so it will only be created once and reused for all calls to `GetChangedAssetsForCode`.

The `GetChangedAssetsForCode` function is responsible for finding all the native classes inside the header that changed. It does this by first finding the correct module that the header belongs to. It uses `FSourceCodeNavigation::GetSourceFileDatabase().GetModuleNames()` to get a list of all module names and then checks if the changed header file starts with any of those module paths.

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

## Custom Editor Validator Class
To create a new custom editor validator class is simple, we just need to inherit from `UEditorValidator` and implement the `CanValidateAsset_Implementation` and `ValidateLoadedAsset_Implementation` functions.

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

## Suppress -Woverloaded-virtual
From the above code, we can see a strange line in header, `// -Woverloaded-virtual`. While is not a mystery that `-Woverloaded-virtual` is a warning for some compiler (Clang for example) indicating that there's a signature mismatch between a derived function and a base function, hence the derived version "hides" the base function, in this case, `CanValidateAsset_Implementation`.

Reading from the source code we know that this is due to the `CanValidateAsset_Implementation` that took in `UObject* InAsset` as parameter has been deprecated already, the up to date signature is now `CanValidateAsset_Implementation(UObject* InObject, FDataValidationContext& InContext)`. Implmenetations of this signature in child without touch the base version would cause a `-Woverloaded-virtual` warning. This essentially just brings the base class function to the current scope to suppress the warning.

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

### Why not update the base class?
The reason for not updating the base class is that it would break all the existing implementations of `CanValidateAsset_Implementation` in child classes. This would require all developers to update their code to match the new signature, which may not be feasible in a large codebase. By keeping the old signature and suppressing the warning, it allows developers to gradually update their code without breaking existing functionality.

This is a good example of how Unreal Engine manages to keep backward compatibility while still allowing for improvements and changes in the codebase.

