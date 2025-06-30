---
layout: post
title: "为独立项目打造免费的本地 CI/CD：基于 TeamCity 的解决方案及其重要性"
description:
  每位独立游戏开发者都懂得打包和部署的痛苦。本篇文章将带你一步步搭建一个基于 TeamCity 的免费本地 CI/CD 流程，以优化你的项目工作流。
date: 2025-06-29 10:16 +0800
categories: [Unreal, Gameplay]
published: true
tags: [Unreal, Gameplay]
media_subpath: /assets/img/post-data/unreal/gameplay/teamcity-cicd/
lang: zh-CN
---

## 引言
有一件事在我制作独立游戏的过程中总是困扰着我——辛苦干了几个星期，一切在 `PIE` 中看起来都很完美，决定打包一下上传到设备实测一下，然后……烹饪失败、打包崩溃、`UBT` 崩、或者其他各种奇奇怪怪的问题 **每次都来**。到后面我甚至对 `Build` 有了恐惧——不仅时间长，还特别折磨调试过程。

是的我知道，“你应该永远在打包环境下测试！” “你不能相信 PIE！”。可问题是，`Cook` 是个吃资源的怪物，它会把所有能用的资源吞掉，一个不小心就要 30~40 分钟，甚至更久。意味着什么？——开发迭代严重放缓。对于独立游戏而言，失去迭代速度几乎等于慢性死亡。

但这些说法并没有错。在理想世界里，我们确实希望有持续打包、`Cook`、自动测试等完整流程。每天早上我能看到最新版本自动拉取构建成功，晚上如果有错误也能收到邮件提醒（比起一个月后才发现错误，再去翻几百个 CL 来追溯真的好太多）。但现实是，怎么实现这种理想方案？它必须**既省钱又高效**。

作为开发者，对 `CI/CD`（持续集成/持续部署）应该已经不陌生，实际上本博客就是靠 `github CI/CD `和 `vercel CI/CD` 在运行的，这并不是什么新鲜词汇。同样的理念也适用于游戏开发。一个稳定的 `CI/CD` 流程非常关键：它能确保你的代码始终处于可部署状态、自动测试、加快开发效率。本文我们将用 `TeamCity` 来搭建一个本地 `CI/CD` 环境，这是一个强大的工具，适合独立开发者使用并且免费。

## 什么是 TeamCity？
`TeamCity` 是 JetBrains 开发的 `CI/CD` 服务端软件，它可以自动执行构建、测试、部署流程，支持多种语言和平台，当然也包括 `Unreal Engine`，是游戏开发者很好的选择。我们在开始前要了解一些基本术语：

- **Build Agent**：构建代理，负责实际运行构建流程的组件，可部署在本机或其他设备上。
- **Build Configuration**：构建配置，定义项目如何构建，包括步骤、触发器、参数等。
- **Build Trigger**：构建触发器，指触发构建的事件，比如代码提交或定时。
- **Build Step**：构建步骤，指构建流程中每一个动作，比如编译、测试、打包。
- **Build Queue**：构建队列，`TeamCity` 会根据优先级和 `Agent` 空闲情况调度。
- **Build Log**：构建日志，记录每一步的输出和信息，方便诊断问题。
- **Build Artifact**：构建产物，比如打包后的游戏文件、文档、可执行文件等。
- **Build History**：构建历史，记录每次构建的状态、耗时、产物等。
- **Build Status**：构建状态，比如成功、失败、进行中等，会以图标形式显示。

所以我们的目标是，配置一个 `TeamCity` 服务端，使用本机作为 `Build Agent`，然后构建 `Unreal` 项目。

为了自动化，我们会配置 `Build Configuration`，设定编译、测试、打包等步骤，并通过版本控制系统（如 `P4V`）设置触发器，一旦有改动就启动构建流程。

## Download TeamCity
## 下载 TeamCity
前往 [TeamCity 官网](https://www.jetbrains.com/teamcity/download/)，下载最新版本。`TeamCity` 提供了 `SaaS` 付费版本，但我们完全可以用它提供的**免费本地授权**来构建我们的独立开发流程。安装步骤很简单，可以在本机或者独立服务器上运行。

![Download TeamCity](download_teamcity.png){: width="800"}

## 配置 Build Agent
下载安装程序后运行，安装向导会一步步引导你完成配置。中途会弹出一个窗口来配置 `Build Agent`，我们这里直接把本机用作 `Build Agent`。

> 本文使用工作站作为 `Build Agent` 只是为了教程演示，在正式环境中，我会使用 `NAS` 存储所有数据与 `P4`，并配置一台独立 `Build` 机来运行 `TeamCity Server` 和 `Build Agent`。它们之间通过局域网通信，我的工作站可以专注开发与测试。
{: .prompt-info }

![Install TeamCity](install_teamcity_1.png){: width="800"}

## 安装 PostgreSQL
接下来 `TeamCity` 会要求设置数据库。它支持多种数据库，我们这里选择免费的 `PostgreSQL`。只要版本大于 6.0 都可以，我使用的是最新稳定版（17.5）。

![Setup Database](setup_database_1.png){: width="800"}

首先需要安装 `JDBC Driver`，点击即可。

从 [PostgreSQL 官网](https://www.postgresql.org/download/) 下载，保持默认配置，记住设置的密码，后续会用到。

![Setup Database](setup_database_2.png){: width="800"}

安装完成后，你可以使用 `pgAdmin` 管理 `PostgreSQL` 数据库。

![PGAdmin](pgadmin.png){: width="800"}


展开 `Servers` 栏，会提示输入你之前设置的密码。登录后，右键 `Databases` > `Create > Database...`，输入名称，点击保存。

同时需要创建一个用户供 `TeamCity` 访问数据库。右键 `Login/Group Roles` > `Create > Login/Group Role...`，设置账号、密码，勾选 `Can login?`。如果你像我一样懒得细配置，甚至可以直接设置为 `Superuser`。

![BM User](pgadmin_user.png){: width="800"}
![Super User](pgadmin_superuserconfig.png){: width="800"}

然后回到 `TeamCity` 安装向导，填入数据库信息。
![Setup Database](setup_database_1.png){: width="800"}

连接成功后，基本配置就完成了，`TeamCity` 的 Web 页面也会通过 `http://localhost:8111` 提供。


## 创建项目
进入网页后，它会让你登录，点击底部 `login as admin`。管理员账号登录需要一个安装时生成的认证 token，可以在 `teamcity-server.log` 里找到，复制后即可登录。

![Authentication Token](authentication_token.png){: width="800"}

第一步是创建一个新项目。点击 `Projects`，然后点击 `Create Project`，输入项目名并创建。

## 设置构建配置
接下来点击 `Build Configurations` > `Create Build Configuration`，输入名称并确认。

![Build Configuration](build_config.png){: width="800"}

## 设置触发器
我们希望构建在检测到代码变更后自动执行，所以要配置 VCS Root。

在项目中点击 `VCS Roots` > `Create VCS Root`，选择类型为 `Perforce`，填写 P4V 服务器地址和凭据，测试连接确保无误。

![Build Trigger VCS Root](build_trigger.png){: width="800"}

![Build Trigger VCS P4](build_trigger_p4.png){: width="800"}

然后回到 `Build Configuration`，点击 `Triggers` > `Add new trigger` > 选择 `VCS Trigger`，TeamCity 将在代码变化时自动触发构建。

我还设置了在构建前清空工作区，以避免之前某些后处理脚本修改文件后残留，导致下次构建失败。

![VCS Trigger](vcs_trigger.png){: width="800"}

![VCS Trigger Confirmed](vcs_trigger_2.png){: width="800"}

## 设置构建步骤
现在我们需要定义构建步骤。构建步骤是指在构建过程中执行的单个操作，例如编译代码、运行测试或打包项目。点击 `Build Steps` 标签页，然后点击 `Add build step` 添加构建步骤。

![Build Step](build_step.png){: width="800"}

目前我们可以先输入以下命令来进行测试：

```bash
echo "Triggered By New Changelist!"
```

在命令行中输入后点击 `Run`，它会在控制台中输出一条信息，表示构建步骤已成功执行。

![Test Result](test_result.png){: width="800"}

## 提交另一个 CL 进行测试
现在我们可以向 P4V 服务器提交另一个 `changelist（CL）`，`TeamCity` 会自动检测到变更并触发构建。你可以在 `Build Queue` 标签页中查看构建状态。

这里我是在 `Mac` 上通过 `P4V` 正常提交 `changelist`。然后——没错，`TeamCity` 自动检测到了变更并触发了构建。


![Pending CL](pending_cl.png){: width="800"}

![Auto Trigger](auto_trigger.png){: width="800"}

## 运行构建命令
到目前为止，我们已经设置好了一个基础的构建配置，能在版本控制系统检测到更改时自动触发构建。但我们还需要定义 `Unreal Engine` 项目的实际构建步骤。

为此，我们将添加一个运行 `Unreal Build Tool（UBT）`来编译项目的构建步骤。点击 `Build Steps` 标签页，然后点击 `Add build step`。在 `Runner` 类型中选择 `Command Line`，然后输入：

```bash
CALL "%ue_root%\Engine\Build\BatchFiles\RunUAT.bat" ^
  BuildCookRun ^
  -project="%teamcity.build.checkoutDir%\%project_name%\%project_name%.uproject" ^
  -noP4 ^
  -platform=%platform% ^
  -clientconfig=%build_config% ^
  -serverconfig=%build_config% ^
  -build ^
  -cook ^
  -pak ^
  -stage ^
  -archive ^
  -archivedirectory="%teamcity.build.checkoutDir%\%project_name%\%output_dir%"
```

![Build Script](build_script.png){: width="800"}

我们尽量避免硬编码路径，因此会使用一些 `TeamCity` 参数来提升灵活性。你可以在构建配置的 `Parameters` 标签页中定义这些参数。

> 更正：我改变了`output_dir`的值为`Artifacts`, 而在上部分的`-archivedirectory`参数中也相应修改了。这样可以确保构建产物存放在`BuildAgent`本地`Checkout`目录的 `Artifacts` 目录下，便于后续管理和访问。
{: .prompt-info }

![Parameters](parameters.png){: width="800"}

点击 `Run` 进行一次试运行，你应该能看到构建流程启动。`TeamCity` 会执行 `UBT` 命令，编译项目、`Cook` 资源并打包游戏。你可以在 `Build Log` 标签中监控整个过程。（`CPU` 直接拉满，所以建议使用一台专门的高性能构建机）

![Cooking Package](cooking_package.png){: width="800"}

最后，设置构建产物的存储路径。点击 `General Settings`（常规设置）标签页，向下滚动到 `Artifact Paths`（产物路径）部分。在这里，你可以指定构建产物的存放位置。例如，你可以设置为：

```bash
\%project_name%\%output_dir%\%platform%\
```

![Artifact Path](artifact_path.png){: width="800"}

## 自动通知机制
构建完成后，你可以在指定的输出目录中找到打包好的游戏文件。同时，`TeamCity` 也会在 `Artifacts` 标签页中保存构建产物，供你下载或部署使用。

在结束前，还有一些进阶功能可以加入。例如，使用 `Unreal` 的自动化测试框架 `Gauntlet`。它支持命令行执行，因此可以轻松集成到构建流程中，形成完整的自动构建+测试流水线。测试结果可以导出为 `XML` 格式，而 `TeamCity` 则能解析这些 `XML` 并以图形方式展示测试结果。

![Parse XML](parse_xml.png){: width="800"}

在报告设置窗口中，选择报告类型为 `Ant JUnit`，并设置报告路径，例如 `+:%output_dir%/TestReports/*.xml`

![Report Config](report_config.png){: width="800"}

接下来，我们为用户配置通知触发器。首先，创建一个用户：

![Create User](create_user.png){: width="800"}

打开 `Users` 标签页，点击 `Notification Rules`。可以看到系统已经继承了一些全局规则，例如当构建失败且包含了我的更改，或我是调查人时，会通过邮件通知我。作为独立开发者，我希望尽早发现问题，因此会为自己添加一条更频繁的通知规则。

![Existing Notification Rule](existing_notification_rule.png){: width="800"}

我希望在任何构建开始、成功或失败时都收到通知。点击 `Add new rule`，勾选所有相关字段，并关联特定构建配置。

![Create Notification Rule](create_new_notification_rule.png){: width="800"}

最后，设置 `Email Notifier`，在配置窗口填写你的 `SMTP` 邮箱服务器地址与端口，然后点击 `Test Connection` 测试连接。测试邮件应很快就能收到。一旦配置完成，你将可以即时收到构建通知。

![Email Notifier](email_notifier.png){: width="800"}

## 结果
等我把这一套流程都搭建完，已经很晚了，早前提交的测试 CL 也忘得一干二净，直接倒头就睡。第二天早上醒来，邮箱里收到了绿色构建通过的通知，这才反应过来：“哦对，我昨天刚搭了 CI/CD 流水线！”看到一切都按预期运行，真的非常有成就感。

![Final Result](final_result.png){: width="500"} 