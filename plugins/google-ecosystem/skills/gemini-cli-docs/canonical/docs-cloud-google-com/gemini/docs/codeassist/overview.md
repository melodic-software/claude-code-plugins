---
source_url: https://docs.cloud.google.com/gemini/docs/codeassist/overview
source_type: llms-txt
content_hash: sha256:c56835c4ccae666b471bdd9d706c5aa72a127b58e06442759107e2321d0ff398
sitemap_url: https://geminicli.com/llms.txt
fetch_method: html
last_modified: '2025-12-05T18:42:54Z'
---

Gemini Code Assist Standard and Enterprise overview  |  Gemini for Google Cloud  |  Google Cloud Documentation

[Skip to main content](#main-content)

[![Google Cloud Documentation](https://www.gstatic.com/devrel-devsite/prod/vf25d28f8fa3eb402b276b2981491ec30329502b5e6089118cc6ebe4dff7f7eb7/clouddocs/images/lockup.svg)](/)

`/`

[Console](//console.cloud.google.com/)

* English
* Deutsch
* Español
* Español – América Latina
* Français
* Indonesia
* Italiano
* Português
* Português – Brasil
* 中文 – 简体
* 中文 – 繁體
* 日本語
* 한국어

Sign in

[![](https://docs.cloud.google.com/_static/clouddocs/images/icons/products/gemini-color.svg)](https://docs.cloud.google.com/gemini/docs)

* [Gemini for Google Cloud](https://docs.cloud.google.com/gemini/docs)

[Start free](//console.cloud.google.com/freetrial)

* [Home](https://docs.cloud.google.com/)
* [Documentation](https://docs.cloud.google.com/docs)
* [AI and ML](https://docs.cloud.google.com/docs/ai-ml)
* [Gemini for Google Cloud](https://docs.cloud.google.com/gemini/docs)
* [Guides](https://docs.cloud.google.com/gemini/docs/overview)

Send feedback

# Gemini Code Assist Standard and Enterprise overview Stay organized with collections Save and categorize content based on your preferences.

Gemini Code Assist Standard and Enterprise, which are products in the
[Gemini for Google Cloud](/gemini/docs/overview) portfolio, offer
AI-powered assistance to help your development team build, deploy, and operate
applications throughout the software development lifecycle. Note that these
products are separate from
[Gemini Code Assist for individuals](https://codeassist.google).

You can use Gemini Code Assist in
[supported IDEs](/gemini/docs/codeassist/supported-languages#supported_ides),
such as VS Code, JetBrains IDEs, or Android Studio, for AI-powered coding
assistance in [many popular languages](/gemini/docs/codeassist/supported-languages).
You can get code completions as you write your code, generate full
functions or code blocks from comments, generate unit tests, and get help with
debugging, understanding, and documenting your code.

Gemini Code Assist provides contextualized responses to your
prompts, including
[source citations](/gemini/docs/discover/works#how-when-gemini-cites-sources)
regarding which documentation and code samples
Gemini Code Assist used to generate its responses.

[Learn how and when
Gemini for Google Cloud uses your data](/gemini/docs/discover/data-governance).

As an early-stage technology, Gemini for Google Cloud products can
generate output that seems plausible but is factually incorrect. We recommend that you validate
all output from Gemini for Google Cloud products before you use it. For more
information, see
[Gemini for Google Cloud and responsible AI](/gemini/docs/discover/responsible-ai).

Gemini Code Assist provides citation information when it
directly quotes at length from another source, such as existing open source code.
For more information, see
[How and when Gemini cites sources](/gemini/docs/discover/works#how-when-gemini-cites-sources).

## Gemini Code Assist Standard and Enterprise editions overview

The following section compares the Gemini Code Assist Standard
and Enterprise editions.

The Standard edition offers AI coding assistance, with enterprise-grade
security, for building and running applications. The Enterprise edition offers
all of the [supported features](#supported-features) in the Standard edition,
but you can also customize it based on your private source code repositories,
and it's integrated with additional Google Cloud services for building
applications across a broader tech stack.

The following table helps you to decide which edition aligns best with your
organization's development goals by highlighting the intended audience and the
benefits for each edition:

|  | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| Intended audience | * Customers with basic coding needs. * Organizations with strict data security and compliance requirements. | * Large enterprises with complex software development processes. * Customers wanting to have AI response customized based on private   source code repositories to accelerate development based on   organizational best practices. * Customers needing AI-powered application development assistant   across an expanding list of Google Cloud services. |
| Benefits | * Code completion and generation for popular programming languages, and available across some Google Cloud services. * AI-powered chat support. * Simplified user interface and integration with IDEs. * Local codebase awareness in your IDE: Use the power of Gemini's large context window for in-depth local codebase understanding. * Enterprise-grade security: Robust data governance, secure infrastructure, and indemnification for code suggestions. * Extended integrations: Gemini Code Assist Standard provides AI assistance in Firebase, Colab Enterprise, BigQuery data insights, Cloud Run, and Database Studio. | * All of the benefits mentioned for Gemini Code Assist Standard, with the addition of the following:  + [Code customization](/gemini/docs/codeassist/code-customization-overview): Your organization can augment the model with your private codebases for tailored suggestions. + Extended integrations: Gemini Code Assist Enterprise provides AI assistance across Google Cloud like Apigee, Application Integration, and Gemini Cloud Assist, empowering cloud teams to build, design and operate, and optimize their applications and infrastructure more effectively on Google Cloud. |

For a comparison of each edition's features, see
[Supported features](#supported-features).

## Supported features for Gemini Code Assist Standard and Enterprise

The following sections show the types of generative AI assistance that are
available in Gemini Code Assist Standard and Enterprise.

### Code assistance and chat

The following table shows the types of generative AI assistance that are
available in
[supported IDEs](/gemini/docs/codeassist/supported-languages#supported_ides):

| AI coding assistance | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| Code completion and generation in your IDE project in the following IDEs:   * [Cloud Shell Editor](/code/docs/shell/write-code-gemini#get_inline_suggestions_while_you_code) * [Cloud Workstations](/workstations/docs/write-code-gemini#get_inline_suggestions_while_you_code) * [JetBrains IDEs (such as IntelliJ and PyCharm)](/gemini/docs/codeassist/write-code-gemini#get_code_completions) * [VS Code](/gemini/docs/codeassist/write-code-gemini#get_code_completions) * [Android Studio](https://developer.android.com/studio/gemini/overview) |  |  |
| Conversational assistant in your IDE [using your opened files' context](/gemini/docs/discover/works#gemini-code-assist) |  |  |
| Multi-IDE support (VS Code, [JetBrains IDEs such as IntelliJ and PyCharm](/gemini/docs/codeassist/supported-languages#supported_ides), Cloud Workstations) |  |  |
| Agentic chat | | |
| Prompt Gemini to complete complex, multi-step tasks that use system tools and Model Context Protocol (MCP) servers. For more information, see [Use the Gemini Code Assist agent mode](/gemini/docs/codeassist/use-agentic-chat-pair-programmer). |  |  |
| Gemini CLI quota | | |
| [Quota](/gemini/docs/quotas) for using [Gemini CLI](/gemini/docs/codeassist/gemini-cli). |  |  |
| Smart actions and commands | | |
| Initiate smart actions by right-clicking selected code ([VS Code](/gemini/docs/codeassist/write-code-gemini#use_smart_actions), [JetBrains IDEs such as IntelliJ and PyCharm](/gemini/docs/codeassist/write-code-gemini#use_smart_actions), [Cloud Shell Editor](/code/docs/shell/write-code-gemini#use_smart_actions), [Cloud Workstations](/workstations/docs/write-code-gemini#use_smart_actions), and [Android Studio](https://developer.android.com/studio/gemini/overview)). Initiate smart commands with the slash `/` on the quick pick bar either with or without selected code ([VS Code](/gemini/docs/codeassist/write-code-gemini#generate_code_with_prompts), [Cloud Shell Editor](/code/docs/shell/write-code-gemini#use_smart_commands), and [Cloud Workstations](/workstations/docs/write-code-gemini#use_smart_commands)). |  |  |
| Intellectual property and compliance | | |
| [Source citations in your IDE and the Google Cloud console](/gemini/docs/discover/works) |  |  |
| [IP indemnification](/gemini/docs/discover/works#how-gemini-protects) |  |  |
| [VPC-SC and Private Google Access](/gemini/docs/configure-vpc-service-controls) |  |  |
| Enterprise knowledge | | |
| [Customized code suggestions from your code bases in GitHub, GitLab, and Bitbucket in your IDE](/gemini/docs/codeassist/code-customization-overview) |  |  |

### Additional features outside the IDE

The following sections detail additional features available with the
Gemini Code Assist Standard and Enterprise editions that go beyond
assistance in your IDE.

#### Gemini Cloud Assist

The following table shows the types of generative AI assistance in
[Gemini Cloud Assist](https://cloud.google.com/gemini/docs/cloud-assist/overview)
in the Google Cloud console:

| Gemini Cloud Assist assistance | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| [Gemini Cloud Assist features](https://cloud.google.com/gemini/docs/cloud-assist/overview#ai-assistance) (including features available to all Google users and available to Gemini Code Assist Enterprise users) |  |  |

#### Gemini in Apigee

The following table shows the types of generative AI assistance with API
development in [Apigee](https://cloud.google.com/apigee/docs) (IDE and the
Google Cloud console):

| Gemini Code Assist for API management | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| [Create or edit OpenAPI specification](/apigee/docs/api-platform/local-development/vscode/develop-design-edit-apis#designing-apis-with-gemini-code-assist) using natural language prompts. |  |  |
| [Enterprise context](/apigee/docs/api-platform/local-development/vscode/develop-design-edit-apis#designing-apis-with-gemini-code-assist) used when creating or updating API specifications. |  |  |
| [Gemini Code Assist code explained for Apigee policies.](/apigee/docs/api-platform/develop/attaching-and-configuring-policies-management-ui#use-gemini-code-assist-code-explain) ([Preview](/products#product-launch-stages)) |  |  |

#### Gemini in Application Integration

The following table shows the types of generative AI assistance in
[Application Integration](https://cloud.google.com/application-integration/docs/overview)
in the Google Cloud console:

| Integration creation assist | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| [AI-assisted visual editor for automation flow generation](https://cloud.google.com/application-integration/docs/build-integrations-gemini#create-an-integration) |  |  |
| [Enterprise context embedded AI-assisted automation authoring](https://cloud.google.com/application-integration/docs/build-integrations-gemini#contextual-recommendations) |  |  |
| [Generative AI Automation flow documentation generation and refinement](https://cloud.google.com/application-integration/docs/build-integrations-gemini#generate-integration-description) |  |  |

#### Gemini in BigQuery features with Gemini Code Assist

The following table shows the types of generative AI assistance for BigQuery
in [BigQuery Studio](https://cloud.google.com/bigquery/docs/query-overview#bigquery-studio):

| Data insights | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| [Data insights](/bigquery/docs/data-insights#insights-bigquery-table) provides an insightful library of queries generated from the metadata of your tables. |  |  |

#### Gemini in Colab Enterprise

The following table shows the types of generative AI assistance for code in
[Colab Enterprise](https://cloud.google.com/colab/docs/introduction):

| Notebook code assist | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| [Python code generation and completion in notebook](https://cloud.google.com/colab/docs/use-code-completion) |  |  |

#### Gemini in databases

The following table shows the types of generative AI assistance for coding in
databases:

| Generate SQL queries | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| Write in natural language to generate SQL statements. |  |  |
| Get contextual code that works with your schema. |  |  |
| Optimize and explain existing queries. |  |  |

#### Gemini in Firebase

The following table shows the types of generative AI assistance for application
development provided by
[Gemini in Firebase](https://firebase.google.com/docs/gemini-in-firebase):

| Chat AI assistance in the Firebase console | Gemini Code Assist Standard | Gemini Code Assist Enterprise |
| --- | --- | --- |
| Use deep knowledge, best practices, and troubleshooting expertise for Firebase products and services. |  |  |
| Generate, refactor, and debug sample code for Firebase with natural language in chat. |  |  |
| Use natural language prompts to explain, generate, and transform code. |  |  |
| App quality analysis | | |
| Summarize app crashes and provide insights and troubleshooting steps to help developers investigate and resolve app quality issues. |  |  |
| Analyze existing code, identify potential issues, and suggest improvements. |  |  |
| Firebase Cloud Messaging and In-App Messaging campaign summarization and insights | | |
| Summarize and analyze your messaging campaigns, providing actionable recommendations to improve performance. |  |  |
| Firebase Data Connect schema generation and data exploration | | |
| Generate database schemas with natural language. |  |  |
| Generate GraphQL queries and mutations with natural language. |  |  |
| Contextual awareness | | |
| Use project and application context to guide conversational assistance, troubleshooting, and app quality analysis. |  |  |

## Set up Gemini Code Assist

For detailed setup steps, see
[Set up Gemini Code Assist](/gemini/docs/codeassist/set-up-gemini).

## Interact with Gemini Code Assist in your IDE

After you
[set up Gemini Code Assist Standard or Enterprise for a Google Cloud project](/gemini/docs/codeassist/set-up-gemini),
and install the Gemini Code Assist extension in your IDE
([VS Code](https://marketplace.visualstudio.com/items?itemName=GoogleCloudTools.cloudcode)
or [supported JetBrains IDE](https://plugins.jetbrains.com/plugin/24198-gemini-code-assist)),
you can ask for assistance in the following ways:

* Receive code completions or generate code directly in the code editor.
* Click spark **Gemini** in the IDE to
  display the conversational assistant. You can ask questions or select code in
  your editor and enter prompts such as the following:

  + `Write unit tests for my code.`
  + `Help me debug my code.`
  + `Make my code more readable.`

For more information, see
[Use Gemini Code Assist in your IDE](/gemini/docs/codeassist/use-in-ide).

## What's next

* Learn how to [use Gemini Code Assist in your IDE](/gemini/docs/codeassist/use-in-ide).
* Learn [how Gemini for Google Cloud uses your data](/gemini/docs/discover/data-governance).
* Learn about [Gemini Code Assist pricing](/products/gemini/pricing).
* Learn about the [security, privacy, and compliance of
  Gemini Code Assist](/gemini/docs/codeassist/security-privacy-compliance).

Send feedback

Except as otherwise noted, the content of this page is licensed under the [Creative Commons Attribution 4.0 License](https://creativecommons.org/licenses/by/4.0/), and code samples are licensed under the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0). For details, see the [Google Developers Site Policies](https://developers.google.com/site-policies). Java is a registered trademark of Oracle and/or its affiliates.

Last updated 2025-12-05 UTC.

Need to tell us more?

[[["Easy to understand","easyToUnderstand","thumb-up"],["Solved my problem","solvedMyProblem","thumb-up"],["Other","otherUp","thumb-up"]],[["Hard to understand","hardToUnderstand","thumb-down"],["Incorrect information or sample code","incorrectInformationOrSampleCode","thumb-down"],["Missing the information/samples I need","missingTheInformationSamplesINeed","thumb-down"],["Other","otherDown","thumb-down"]],["Last updated 2025-12-05 UTC."],[],[]]
