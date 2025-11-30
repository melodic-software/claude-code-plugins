<!-- Source: https://docs.claude.com/en/docs/about-claude/use-case-guides/ticket-routing -->

# Ticket routing

This guide walks through how to harness Claude's advanced natural language understanding capabilities to classify customer support tickets at scale based on customer intent, urgency, prioritization, customer profile, and more.

## Define whether to use Claude for ticket routing

Here are some key indicators that you should use an LLM like Claude  instead of traditional ML approaches for your classification task:

<AccordionGroup>
  <Accordion title="You have limited labeled training data available">
    Traditional ML processes require massive labeled datasets. Claude's pre-trained model can effectively classify tickets with just a few dozen labeled examples, significantly reducing data preparation time and costs.
  </Accordion>

  <Accordion title="Your classification categories are likely to change or evolve over time">
    Once a traditional ML approach has been established, changing it is a laborious and data-intensive undertaking. On the other hand, as your product or customer needs evolve, Claude can easily adapt to changes in class definitions or new classes without extensive relabeling of training data.
  </Accordion>

  <Accordion title="You need to handle complex, unstructured text inputs">
    Traditional ML models often struggle with unstructured data and require extensive feature engineering. Claude's advanced language understanding allows for accurate classification based on content and context, rather than relying on strict ontological structures.
  </Accordion>

  <Accordion title="Your classification rules are based on semantic understanding">
    Traditional ML approaches often rely on bag-of-words models or simple pattern matching. Claude excels at understanding and applying underlying rules when classes are defined by conditions rather than examples.
  </Accordion>

  <Accordion title="You require interpretable reasoning for classification decisions">
    Many traditional ML models provide little insight into their decision-making process. Claude can provide human-readable explanations for its classification decisions, building trust in the automation system and facilitating easy adaptation if needed.
  </Accordion>

  <Accordion title="You want to handle edge cases and ambiguous tickets more effectively">
    Traditional ML systems often struggle with outliers and ambiguous inputs, frequently misclassifying them or defaulting to a catch-all category. Claude's natural language processing capabilities allow it to better interpret context and nuance in support tickets, potentially reducing the number of misrouted or unclassified tickets that require manual intervention.
  </Accordion>

  <Accordion title="You need multilingual support without maintaining separate models">
    Traditional ML approaches typically require separate models or extensive translation processes for each supported language. Claude's multilingual capabilities allow it to classify tickets in various languages without the need for separate models or extensive translation processes, streamlining support for global customer bases.
  </Accordion>
</AccordionGroup>

***

## Build and deploy your LLM support workflow

### Understand your current support approach

Before diving into automation, it's crucial to understand your existing ticketing system. Start by investigating how your support team currently handles ticket routing.

Consider questions like:

* What criteria are used to determine what SLA/service offering is applied?
* Is ticket routing used to determine which tier of support or product specialist a ticket goes to?
* Are there any automated rules or workflows already in place? In what cases do they fail?
* How are edge cases or ambiguous tickets handled?
* How does the team prioritize tickets?

The more you know about how humans handle certain cases, the better you will be able to work with Claude to do the task.

### Define user intent categories

A well-defined list of user intent categories is crucial for accurate support ticket classification with Claude. Claude’s ability to route tickets effectively within your system is directly proportional to how well-defined your system’s categories are.

Here are some example user intent categories and subcategories.

<AccordionGroup>
  <Accordion title="Technical issue">
    * Hardware problem
    * Software bug
    * Compatibility issue
    * Performance problem
  </Accordion>

  <Accordion title="Account management">
    * Password reset
    * Account access issues
    * Billing inquiries
    * Subscription changes
  </Accordion>

  <Accordion title="Product information">
    * Feature inquiries
    * Product compatibility questions
    * Pricing information
    * Availability inquiries
  </Accordion>

  <Accordion title="User guidance">
    * How-to questions
    * Feature usage assistance
    * Best practices advice
    * Troubleshooting guidance
  </Accordion>

  <Accordion title="Feedback">
    * Bug reports
    * Feature requests
    * General feedback or suggestions
    * Complaints
  </Accordion>

  <Accordion title="Order-related">
    * Order status inquiries
    * Shipping information
    * Returns and exchanges
    * Order modifications
  </Accordion>

  <Accordion title="Service request">
    * Installation assistance
    * Upgrade requests
    * Maintenance scheduling
    * Service cancellation
  </Accordion>

  <Accordion title="Security concerns">
    * Data privacy inquiries
    * Suspicious activity reports
    * Security feature assistance
  </Accordion>

  <Accordion title="Compliance and legal">
    * Regulatory compliance questions
    * Terms of service inquiries
    * Legal documentation requests
  </Accordion>

  <Accordion title="Emergency support">
    * Critical system failures
    * Urgent security issues
    * Time-sensitive problems
  </Accordion>

  <Accordion title="Training and education">
    * Product training requests
    * Documentation inquiries
    * Webinar or workshop information
  </Accordion>

  <Accordion title="Integration and API">
    * Integration assistance
    * API usage questions
    * Third-party compatibility inquiries
  </Accordion>
</AccordionGroup>

In addition to intent, ticket routing and prioritization may also be influenced by other factors such as urgency, customer type, SLAs, or language. Be sure to consider other routing criteria when building your automated routing system.

### Establish success criteria

Work with your support team to [define clear success criteria](/en/docs/test-and-evaluate/define-success) with measurable benchmarks, thresholds, and goals.

Here are some standard criteria and benchmarks when using LLMs for support ticket routing:

<AccordionGroup>
  <Accordion title="Classification consistency">
    This metric assesses how consistently Claude classifies similar tickets over time. It's crucial for maintaining routing reliability. Measure this by periodically testing the model with a set of standardized inputs and aiming for a consistency rate of 95% or higher.
  </Accordion>

  <Accordion title="Adaptation speed">
    This measures how quickly Claude can adapt to new categories or changing ticket patterns. Test this by introducing new ticket types and measuring the time it takes for the model to achieve satisfactory accuracy (e.g., >90%) on these new categories. Aim for adaptation within 50-100 sample tickets.
  </Accordion>

  <Accordion title="Multilingual handling">
    This assesses Claude's ability to accurately route tickets in multiple languages. Measure the routing accuracy across different languages, aiming for no more than a 5-10% drop in accuracy for non-primary languages.
  </Accordion>

  <Accordion title="Edge case handling">
    This evaluates Claude's performance on unusual or complex tickets. Create a test set of edge cases and measure the routing accuracy, aiming for at least 80% accuracy on these challenging inputs.
  </Accordion>

  <Accordion title="Bias mitigation">
    This measures Claude's fairness in routing across different customer demographics. Regularly audit routing decisions for potential biases, aiming for consistent routing accuracy (within 2-3%) across all customer groups.
  </Accordion>

  <Accordion title="Prompt efficiency">
    In situations where minimizing token count is crucial, this criteria assesses how well Claude performs with minimal context. Measure routing accuracy with varying amounts of context provided, aiming for 90%+ accuracy with just the ticket title and a brief description.
  </Accordion>

  <Accordion title="Explainability score">
    This evaluates the quality and relevance of Claude's explanations for its routing decisions. Human raters can score explanations on a scale (e.g., 1-5), with the goal of achieving an average score of 4 or higher.
  </Accordion>
</AccordionGroup>

Here are some common success criteria that may be useful regardless of whether an LLM is used:

<AccordionGroup>
  <Accordion title="Routing accuracy">
    Routing accuracy measures how often tickets are correctly assigned to the appropriate team or individual on the first try. This is typically measured as a percentage of correctly routed tickets out of total tickets. Industry benchmarks often aim for 90-95% accuracy, though this can vary based on the complexity of the support structure.
  </Accordion>

  <Accordion title="Time-to-assignment">
    This metric tracks how quickly tickets are assigned after being submitted. Faster assignment times generally lead to quicker resolutions and improved customer satisfaction. Best-in-class systems often achieve average assignment times of under 5 minutes, with many aiming for near-instantaneous routing (which is possible with LLM implementations).
  </Accordion>

  <Accordion title="Rerouting rate">
    The rerouting rate indicates how often tickets need to be reassigned after initial routing. A lower rate suggests more accurate initial routing. Aim for a rerouting rate below 10%, with top-performing systems achieving rates as low as 5% or less.
  </Accordion>

  <Accordion title="First-contact resolution rate">
    This measures the percentage of tickets resolved during the first interaction with the customer. Higher rates indicate efficient routing and well-prepared support teams. Industry benchmarks typically range from 70-75%, with top performers achieving rates of 80% or higher.
  </Accordion>

  <Accordion title="Average handling time">
    Average handling time measures how long it takes to resolve a ticket from start to finish. Efficient routing can significantly reduce this time. Benchmarks vary widely by industry and complexity, but many organizations aim to keep average handling time under 24 hours for non-critical issues.
  </Accordion>

  <Accordion title="Customer satisfaction scores">
    Often measured through post-interaction surveys, these scores reflect overall customer happiness with the support process. Effective routing contributes to higher satisfaction. Aim for CSAT scores of 90% or higher, with top performers often achieving 95%+ satisfaction rates.
  </Accordion>

  <Accordion title="Escalation rate">
    This measures how often tickets need to be escalated to higher tiers of support. Lower escalation rates often indicate more accurate initial routing. Strive for an escalation rate below 20%, with best-in-class systems achieving rates of 10% or less.
  </Accordion>

  <Accordion title="Agent productivity">
    This metric looks at how many tickets agents can handle effectively after implementing the routing solution. Improved routing should increase productivity. Measure this by tracking tickets resolved per agent per day or hour, aiming for a 10-20% improvement after implementing a new routing system.
  </Accordion>

  <Accordion title="Self-service deflection rate">
    This measures the percentage of potential tickets resolved through self-service options before entering the routing system. Higher rates indicate effective pre-routing triage. Aim for a deflection rate of 20-30%, with top performers achieving rates of 40% or higher.
  </Accordion>

  <Accordion title="Cost per ticket">
    This metric calculates the average cost to resolve each support ticket. Efficient routing should help reduce this cost over time. While benchmarks vary widely, many organizations aim to reduce cost per ticket by 10-15% after implementing an improved routing system.
  </Accordion>
</AccordionGroup>

### Choose the right Claude model

The choice of model depends on the trade-offs between cost, accuracy, and response time.

Many customers have found `claude-3-5-haiku-20241022` an ideal model for ticket routing, as it is the fastest and most cost-effective model in the Claude 3 family while still delivering excellent results. If your classification problem requires deep subject matter expertise or a large volume of intent categories complex reasoning, you may opt for the [larger Sonnet model](/en/docs/about-claude/models).

### Build a strong prompt

Ticket routing is a type of classification task. Claude analyzes the content of a support ticket and classifies it into predefined categories based on the issue type, urgency, required expertise, or other relevant factors.

Let’s write a ticket classification prompt. Our initial prompt should contain the contents of the user request and return both the reasoning and the intent.

<Tip>
  Try the [prompt generator](/en/docs/prompt-generator) on the [Claude Console](https://console.anthropic.com/login) to have Claude write a first draft for you.
</Tip>

Here's an example ticket routing classification prompt:

```python  theme={null}
def classify_support_request(ticket_contents):
    # Define the prompt for the classification task
    classification_prompt = f"""You will be acting as a customer support ticket classification system. Your task is to analyze customer support requests and output the appropriate classification intent for each request, along with your reasoning. 

        Here is the customer support request you need to classify:

        <request>{ticket_contents}</request>

        Please carefully analyze the above request to determine the customer's core intent and needs. Consider what the customer is asking for has concerns about.

        First, write out your reasoning and analysis of how to classify this request inside <reasoning> tags.

        Then, output the appropriate classification label for the request inside a <intent> tag. The valid intents are:
        <intents>
        <intent>Support, Feedback, Complaint</intent>
        <intent>Order Tracking</intent>
        <intent>Refund/Exchange</intent>
        </intents>

        A request may have ONLY ONE applicable intent. Only include the intent that is most applicable to the request.

        As an example, consider the following request:
        <request>Hello! I had high-speed fiber internet installed on Saturday and my installer, Kevin, was absolutely fantastic! Where can I send my positive review? Thanks for your help!</request>

        Here is an example of how your output should be formatted (for the above example request):
        <reasoning>The user seeks information in order to leave positive feedback.</reasoning>
        <intent>Support, Feedback, Complaint</intent>

        Here are a few more examples:
        <examples>
        <example 2>
        Example 2 Input:
        <request>I wanted to write and personally thank you for the compassion you showed towards my family during my father's funeral this past weekend. Your staff was so considerate and helpful throughout this whole process; it really took a load off our shoulders. The visitation brochures were beautiful. We'll never forget the kindness you showed us and we are so appreciative of how smoothly the proceedings went. Thank you, again, Amarantha Hill on behalf of the Hill Family.</request>

        Example 2 Output:
        <reasoning>User leaves a positive review of their experience.</reasoning>
        <intent>Support, Feedback, Complaint</intent>
        </example 2>
        <example 3>

        ...

        </example 8>
        <example 9>
        Example 9 Input:
        <request>Your website keeps sending ad-popups that block the entire screen. It took me twenty minutes just to finally find the phone number to call and complain. How can I possibly access my account information with all of these popups? Can you access my account for me, since your website is broken? I need to know what the address is on file.</request>

        Example 9 Output:
        <reasoning>The user requests help accessing their web account information.</reasoning>
        <intent>Support, Feedback, Complaint</intent>
        </example 9>

        Remember to always include your classification reasoning before your actual intent output. The reasoning should be enclosed in <reasoning> tags and the intent in <intent> tags. Return only the reasoning and the intent.
        """
```

Let's break down the key components of this prompt:

* We use Python f-strings to create the prompt template, allowing the `ticket_contents` to be inserted into the `<request>` tags.
* We give  Claude a clearly defined role as a classification system that carefully analyzes the ticket content to determine the customer's core intent and needs.
* We instruct Claude on proper output formatting, in this case to provide its reasoning and analysis inside `<reasoning>` tags, followed by the appropriate classification label inside `<intent>` tags.
* We specify the valid intent categories: "Support, Feedback, Complaint", "Order Tracking", and "Refund/Exchange".
* We include a few examples (a.k.a. few-shot prompting) to illustrate how the output should be formatted, which improves accuracy and consistency.

The reason we want to have Claude split its response into various XML tag sections is so that we can use regular expressions to separately extract the reasoning and intent from the output. This allows us to create targeted next steps in the ticket routing workflow, such as using only the intent to decide which person to route the ticket to.

### Deploy your prompt

It’s hard to know how well your prompt works without deploying it in a test production setting and [running evaluations](/en/docs/test-and-evaluate/develop-tests).

Let’s build the deployment structure. Start by defining the method signature for wrapping our call to Claude. We'll take the method we’ve already begun to write, which has `ticket_contents` as input, and now return a tuple of `reasoning` and `intent` as output. If you have an existing automation using traditional ML, you'll want to follow that method signature instead.

```python  theme={null}
import anthropic
import re