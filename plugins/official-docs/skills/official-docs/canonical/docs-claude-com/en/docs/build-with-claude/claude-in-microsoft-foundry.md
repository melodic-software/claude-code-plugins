<!-- Source: https://docs.claude.com/en/docs/build-with-claude/claude-in-microsoft-foundry -->

# Claude in Microsoft Foundry

Access Claude models through Microsoft Foundry with Azure-native endpoints and authentication.

This guide will walk you through the process of setting up and making API calls to Claude in Foundry in Python, TypeScript, or using direct HTTP requests. When you can access Claude in Foundry, you will be billed for Claude usage in the Microsoft Marketplace with your Azure subscription, allowing you to access Claude's latest capabilities while managing costs through your Azure subscription.

Regional availability: At launch, Claude is available as a Global Standard deployment type in Foundry resources with US DataZone coming soon. Pricing for Claude in the Microsoft Marketplace uses Anthropic's standard API pricing. Visit our [pricing page](https://claude.com/pricing#api) for details.

## Preview

In this preview platform integration, Claude models run on Anthropic's infrastructure. This is a commercial integration for billing and access through Azure. As an independent processor for Microsoft, customers using Claude through Microsoft Foundry are subject to Anthropic's data use terms. Anthropic continues to provide its industry-leading safety and data commitments, including zero data retention availability.

## Prerequisites

Before you begin, ensure you have:

* An active Azure subscription
* Access to [Foundry](https://ai.azure.com/)
* The [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed (optional, for resource management)

## Install an SDK

Anthropic's [client SDKs](/en/api/client-sdks) support Foundry through platform-specific packages.

```bash  theme={null}