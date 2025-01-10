---
layout: post
title: Embedding DeepSeek-v3 into JetBrains Rider and VS Code
description: 
  A quick walkthrough on embedding deepseek-v3 into JetBrain Rider and VS Code
date: 2025-01-10 12:00 +0800
categories: [Machine Learning, GenAI]
tags: [OpenAI, DeepSeek, API, Machine Learning, GenAI, AI]
media_subpath: /assets/img/post-data/ai/deepseek-ide/
---

## Disclaimer
I am not associated with `DeepSeek` or `JetBrains` in any way, this post is just an experience share

While `DeepSeek` performs incredibly good at code and math criteria. it fell short for some general non-programming tasks, `ChatGPT` still has it's cut, however, `DeepSeek` has become my daily driver for programming instead of `GitHub Copilot`

> [DeepSeek] fundamentally is a Chinese enterprise, so the privacy policy, data collection policy and EULA might operate differently than Non-Chinese companies
{: .prompt-warning}

## Introduction
[High-flyer], a chinese AI company has released the latest model of [deepseek] - `DeepSeek-V3`  a few days ago that quickly became popular among developers. It provides SOTA performance on coding and math tasks, with extremely cheap pricing. The model is available on [HuggingFace] with it's benchmark, as well as general web access through [deepseek chat]. But for developers, the most convenient way to use it is embedding it into our IDEs, such as JetBrains Rider and VS Code, just like `GitHub Copilot`. In this post we will cover the API accessing and embedding process.

> Based on the methods of registering, there might be a one-time 10 CNY granted to your account, which is enough for around 5 million tokens.
{: .prompt-tip }

## API Acquiring
1. Head over to [deepseek developer], and register an account
2. Create a new API
   - ![API Creation](deepseek_ide_api_1.png)
3. Give it a name
   - ![API Naming](deepseek_ide_api_2.png){: width="500"}
4. Copy the API now! (We can't copy it later after the window closed)
   - ![API Key](deepseek_ide_api_3.png){: width="500"}

## Plugin Installation
There are various plugins available for JetBrains Rider and VS Code that can be used for code auto completion and chat. The most popular options are `CodeGPT` and `Continue` plugin. However, `Continue` doesn't have a very high rating on Rider, and `CodeGPT` doesn't have a very easy to use interface for VS Code, so we are going to use `CodeGPT` for Rider and `Continue` for VS Code.

### JetBrains Rider (CodeGPT)
1. Open Rider and go to `File` -> `Settings` -> `Plugins` -> `Marketplace`.
2. Search for `CodeGPT` and install it.
   - ![CodeGPT](deepseek_ide_codegpt_1.png)
3. Restart Rider, then let's go to settings of the plugin, there're two things we need to change, the setting is located `CodeGPT - Provider - Custom OpenAI`
   1. Make sure the API key is set to the one we copied earlier.
   2. Set corresponding post url for chat
      1. `https://api.deepseek.com/chat/completions`
      2. In `Body` config, we need to set model to `deepseek-chat`
         - ![CodeGPT](deepseek_ide_codegpt_2.png)
   3. Set corresponding post url for code completion
      1. `https://api.deepseek.com/beta/completions`
      2. In `Body` config, we need to set model to `deepseek-chat`
         - ![CodeGPT](deepseek_ide_codegpt_3.png)
4. Code completion should work right away, for chat, make sure the provider at the bottom is set to `Custom OpenAI`
      - ![CodeGPT](deepseek_ide_codegpt_4.png){: width="300"}

### VS Code (Continue)
1. Open VS Code and go to `Extensions` tab.
2. Search for `Continue` and install it.
   - ![Continue](deepseek_ide_vsc_continue_1.png)
3. Restart VS Code and you will see a new tab on the left side of the IDE.
4. Click on the `Continue` tab and you will see a chat interface.
   - ![Continue](deepseek_ide_vsc_continue_2.png){: width="300"}
5. We will need to select a custom provider, in this case, deepseek. So we click the "Best" tab, and "Click Here"
   - ![Continue](deepseek_ide_vsc_continue_3.png){: width="300"}
6. Fill in DeepSeek as provider, and DeepSeek API key as the API key.
   - ![Continue](deepseek_ide_vsc_continue_4.png){: width="300"}
7. Finally, we can confirm our settings, by clicking the small "Gear" icon at the chat bar
   - ![Continue](deepseek_ide_vsc_continue_5.png){: width="300"}
8. This will open a `config.json` file, and it should look like the following:

```json
{
  "completionOptions": {
    "BaseCompletionOptions": {
      "temperature": 0,
      "maxTokens": 256
    }
  },
  "models": [
    {
      "title": "DeepSeek",
      "model": "deepseek-chat",
      "contextLength": 128000,
      "apiKey": "YOUR API KEY HERE",
      "provider": "openai",
      "apiBase": "https://api.deepseek.com/beta"
    },
    {
      "title": "DeepSeek Coder",
      "model": "deepseek-coder",
      "contextLength": 128000,
      "provider": "deepseek",
      "apiKey": "YOUR API KEY HERE"
    },
    {
      "title": "DeepSeek Chat",
      "model": "deepseek-chat",
      "contextLength": 128000,
      "apiKey": "YOUR API KEY HERE",
      "provider": "deepseek"
    }
  ],
  "tabAutocompleteModel": {
    "title": "DeepSeek",
    "model": "deepseek-chat",
    "apiKey": "YOUR API KEY HERE",
    "provider": "openai",
    "apiBase": "https://api.deepseek.com/beta"
  },
  "slashCommands": [
    {
      "name": "edit",
      "description": "Edit highlighted code"
    },
    {
      "name": "comment",
      "description": "Write comments for the highlighted code"
    },
    {
      "name": "share",
      "description": "Export the current chat session to markdown"
    },
    {
      "name": "cmd",
      "description": "Generate a shell command"
    }
  ],
  "customCommands": [
    {
      "name": "test",
      "prompt": "{{{ input }}}\n\nWrite a comprehensive set of unit tests for the selected code. It should setup, run tests that check for correctness including important edge cases, and teardown. Ensure that the tests are complete and sophisticated. Give the tests just as chat output, don't edit any file.",
      "description": "Write unit tests for highlighted code"
    }
  ],
  "contextProviders": [
    {
      "name": "diff",
      "params": {}
    },
    {
      "name": "open",
      "params": {}
    },
    {
      "name": "terminal",
      "params": {}
    }
  ]
}
```

## Pricing
Now we can enjoy the `DeepSeek`'s power with extremely cheat quota, this post itself is largely written by auto-completion feature as well. It took about 380,000 tokens, and costs 0.25 CNY (0.034 USD). Which is about 0.65 CNY (or 0.089 USD)/Million Tokens, in comparison, as the time of writing, OpenAI 4O API charges 2.5 USD/Million Tokens.


[High-flyer]: https://www.high-flyer.cn/
[deepseek]: https://www.deepseek.com/
[HuggingFace]: https://huggingface.co/deepseek-ai/DeepSeek-V3
[deepseek chat]: https://chat.deepseek.com/
[deepseek developer]: https://developer.deepseek.com/