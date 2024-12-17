---
layout: post
title: Create a simple custom GPT with YouTrack Rest API
description: 
  A simple custom GPT with YouTrack Rest API, which can be used to generate a list of issues in a specific project
date: 2023-11-10 12:00 +0800
categories: [Machine Learning, GenAI]
tags: [OpenAI, GPT, YouTrack, API, OpenAPI, Rest, Machine Learning, GenAI, AI]
media_subpath: /assets/img/post-data/ai/custom-gpt-youtrack/
---

## Introduction
OpenAI has recently unveiled the groundbreaking Custom GPTs feature [GPT Introduction], enabling users to fine-tune and personalize their own GPTs. After several trials and experiments, I successfully set up a simple GPTs agent, tailored as a Project Management guru, to assist me in my workflow. As part of this endeavor, I needed a digital copilot to help me efficiently track issues using YouTrack, a popular project management tool. [YouTrack]

## The Need for API Integration
Working in project management often involves juggling multiple tasks and keeping track of numerous issues. To streamline this process, I sought to integrate YouTrack's capabilities directly into my workflow. This required a clear understanding and utilization of YouTrack’s API, a task that appeared daunting at first. The solution? Leveraging the OpenAPI Specification (OAS) to create a structured and efficient way to interact with the YouTrack API.

## Create a custom GPT
My goal is simple, play around and do some test flight experiments to get familiar with this new tool, so the first thing come into my mind is a indie game development assistant, user can create GPTs at [Custom GPT Creation] Once logged in, we can do some configurations with natural language, until we got something like this:

```
[YourGPTName], tailored for independent game developers, assists in all aspects of game development, from ideation to distribution. It provides advice, generates assets, and understands game development terminology.
```

## Add Actions
While at this moment the GPT agent seems to be finished, it's really just a more focused normal GPT, so just as shown in the announcement event by OpenAI, I thought I should jam in some Actions. (Scroll down at the bottom of configuration tab of GPTs)

![Actions](gpt_youtrack_1.webp)
_Actions_

Here we can then define the Schema, following a certain format, following OpenAPI Specification

![Schema](gpt_youtrack_2.webp)
_Schema_

## Crafting the OpenAPI Specification
### Initial Setup
My journey began with defining the basics in the OAS document - specifying the OpenAPI version, providing information about the API (like title and description), and setting the server URL
- The OSA standard can be found at [OpenAI-Specification]

Basically it will look like this:
```
"openapi": "3.1.0","info": { ... },"servers": [ ... ]
```

![OSA](gpt_youtrack_3.webp)
_OSA_

### Define Server
Since we're working with YouTrack, we need to access YouTrack Rust API, luckily, we already got covered [YouTrack Reset API]

```
"servers": [
    {
      "url": "https://[yourproject].myjetbrains.com/youtrack/api"
    }
  ]
```

![Server](gpt_youtrack_4.webp)
_Server_

### Defining Paths and Operations
The core of my interaction with YouTrack revolved around fetching issues. Therefore, I defined a /issues endpoint and detailed a GET operation to retrieve issue data. This included specifying query parameters (fields and query) to filter and customize the data returned by the API
- Here from YouTrack Document, we know that we can have a query parameter, and fields parameter to retrieve issues for us, so we can configure them here
- [Fields Syntax]
- [Query Syntax]

### Parameters and Flexibility
The power of OAS shone through in its ability to define versatile parameters. This allowed me to tailor requests to my specific needs, fetching precisely what was required from YouTrack

```
"/issues": { "get": { ... } }
```

![Issues](gpt_youtrack_5.webp)
_Issues_

![Issues](gpt_youtrack_6.webp)
_Issues_

## Action Authentication
Next, we need to provide API key for GPT to properly communicate with YouTrack server, which can be obtained via the backend of YouTrack

![API Key](gpt_youtrack_7.webp)
_API Key_

YouTrack api token is of type API Token - Bearer

![API Token](gpt_youtrack_8.webp)
_API Token_

![API Token](gpt_youtrack_9.webp)
_API Token_

## Ask GPT to send out proper Methods
While we've been very closed to the end of this journey, here's one final problem, GPT doesn't necessarily know what's the proper parameter syntax to send out, while performing tasks, so let's give it a few more instructions. Go back to the Instructions tab of this agent, add add things like:

```
Specifically, [YourGPTName] recognizes terms like 'unresolved' or 'in progress' as queries for the 'Develop' stage in YouTrack. Moreover, when interacting with the YouTrack API, [YourGPTName] automatically constructs a default field parameter of 'id,summary,project(name),description' to ensure meaningful and comprehensive issue information is returned, rather than just the Issue ID. This enhanced functionality aids in more effective project management and tracking in game development.
```

![Instructions](gpt_youtrack_10.webp)
_Instructions_

## Showcase
After save and publish this Agent, we can then do something like:

![Showcase](gpt_youtrack_11.webp)
_Showcase_

## Challenges and Insights
I've never write a single line of Rest API before, nor do I know anything about Rest API, so prior to this fun trip, I've also created another Tutor to quick give me a crash course of what is Rest API and how to use it. After about 30 mins to 1 hr learning, I can then tackle the basic operations and syntaxs very quickly. Which demonstrated an incredible potential of AI tutoring capabilities.

![Tutor](gpt_youtrack_12.webp)
_Tutor_

## Further Exploration
For those interested in exploring OpenAPI and GPTs further, I recommend delving into OpenAI's documentation and experimenting with various API integrations. The journey may be challenging, but the rewards in efficiency and understanding are well worth the effort. Currently, a GPT agent can only have one OAS formatted Json file, which means that we can't have one config for YouTrack, and another one for Github, and let the GPT to freely call corresponding APIs when needed, I would be very excited to see when Actions can be configured as Arrays of Json Objects.



[GPT Introduction]: https://openai.com/blog/introducing-gpts
[YouTrack]: https://www.jetbrains.com/youtrack/
[Custom GPT Creation]: https://chat.openai.com/create
[OpenAI-Specification]: https://github.com/OAI/OpenAPI-Specification
[YouTrack Reset API]: https://www.jetbrains.com/help/youtrack/devportal/youtrack-rest-api.html
[Fields Syntax]: https://www.jetbrains.com/help/youtrack/devportal/api-fields-syntax.html
[Query Syntax]: https://www.jetbrains.com/help/youtrack/devportal/api-query-syntax.html