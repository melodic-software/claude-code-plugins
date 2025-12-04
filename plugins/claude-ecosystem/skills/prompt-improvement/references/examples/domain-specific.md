# Domain-Specific Examples

This reference provides improved prompt examples for specific use case domains.

## Code Review Domain

### Before

```text
Review this code and tell me if there are any problems.

{{code}}
```

### After

````xml
<instructions>
You are a senior software engineer conducting a code review. Analyze the provided code for issues across multiple dimensions.

Review categories:
1. **Bugs:** Logic errors, off-by-one errors, null/undefined handling
2. **Security:** Injection vulnerabilities, authentication issues, data exposure
3. **Performance:** Inefficient algorithms, unnecessary operations, memory leaks
4. **Maintainability:** Readability, naming, complexity, documentation
5. **Best Practices:** Language idioms, design patterns, code organization

For each issue found:
- Identify the specific line(s)
- Explain why it's a problem
- Suggest a fix
- Rate severity: CRITICAL, HIGH, MEDIUM, LOW
</instructions>

<examples>
  <example>
    <input>
```python
def get_user(user_id):
    query = f"SELECT * FROM users WHERE id = {user_id}"
    result = db.execute(query)
    return result[0]
```
    </input>
    <thinking>
      Reviewing each category:

      1. Bugs:
         - Line 4: Assumes result is non-empty (IndexError if user not found)

      2. Security:
         - Line 2: SQL injection vulnerability (string interpolation in query)
         - CRITICAL: user_id is directly interpolated

      3. Performance:
         - SELECT * fetches all columns (minor)

      4. Maintainability:
         - No error handling
         - No docstring

      5. Best Practices:
         - Should use parameterized queries
         - Should handle empty results gracefully
    </thinking>
    <output>
      ## Code Review Results

      ### CRITICAL

      **SQL Injection Vulnerability** (Line 2)
      - Problem: Direct string interpolation allows SQL injection
      - Impact: Attacker could read/modify/delete database
      - Fix: Use parameterized queries
      ```python
      query = "SELECT * FROM users WHERE id = %s"
      result = db.execute(query, (user_id,))
      ```

      ### HIGH

      **Unhandled Empty Result** (Line 4)
      - Problem: `result[0]` throws IndexError if user not found
      - Fix: Check result before accessing
      ```python
      if result:
          return result[0]
      return None
      ```

      ### LOW

      **SELECT * Usage** (Line 2)
      - Problem: Fetches unnecessary columns
      - Fix: Specify only needed columns

      **Missing Documentation** (Line 1)
      - Problem: No docstring explaining function behavior
      - Fix: Add docstring with parameters and return value
    </output>
  </example>
</examples>

<code>
{{code}}
</code>

<formatting>
1. Analyze in <thinking> tags by category
2. Provide <output> grouped by severity (CRITICAL, HIGH, MEDIUM, LOW)
3. Each issue includes: location, problem, impact/reason, fix with code
</formatting>
````

---

## Data Analysis Domain

### Before

```text
Analyze this data and give me insights.

{{data}}
```

### After

```xml
<instructions>
You are a data analyst extracting insights from provided data. Perform a comprehensive analysis that moves from observation to insight to recommendation.

Analysis structure:
1. **Data Overview:** What data is present, structure, completeness
2. **Key Metrics:** Important numbers, calculations, aggregations
3. **Patterns & Trends:** What patterns emerge from the data
4. **Anomalies:** Outliers, unexpected values, data quality issues
5. **Insights:** What the data tells us (interpretation, not just description)
6. **Recommendations:** Actions to take based on insights

Be specific with numbers. Don't just say "sales increased" - say "sales increased 23% from Q1 to Q2."
</instructions>

<context>
Analysis purpose: {{purpose}}
Key questions to answer: {{questions}}
</context>

<examples>
  <example>
    <input>
      Monthly Sales Data (2024):
      Jan: $45,000
      Feb: $48,000
      Mar: $52,000
      Apr: $47,000
      May: $55,000
      Jun: $62,000
    </input>
    <purpose>Quarterly business review</purpose>
    <questions>Are we on track? Where should we focus?</questions>

    <thinking>
      1. Data Overview:
         - 6 months of monthly sales data
         - All values present, no missing data
         - Currency: USD

      2. Key Metrics:
         - Q1 total: $145,000 (Jan+Feb+Mar)
         - Q2 total: $164,000 (Apr+May+Jun)
         - Q1 average: $48,333/month
         - Q2 average: $54,667/month
         - Overall growth: Q2 vs Q1 = +13.1%
         - Peak: June ($62,000)
         - Trough: January ($45,000)

      3. Patterns & Trends:
         - General upward trend with one dip
         - Q2 stronger than Q1
         - June shows acceleration

      4. Anomalies:
         - April dip (47K) breaks the upward trend
         - April is 10% below March
         - Worth investigating what caused April dip

      5. Insights:
         - Strong momentum into summer
         - Q2 shows recovery and acceleration
         - April may indicate seasonal or operational issue

      6. Recommendations:
         - Investigate April dip for preventable causes
         - Project Q3 based on June momentum
         - Consider what drove June success (replicate)
    </thinking>
    <output>
      ## Data Analysis: Monthly Sales (H1 2024)

      ### Key Metrics
      | Metric | Value |
      |--------|-------|
      | Q1 Total | $145,000 |
      | Q2 Total | $164,000 |
      | Q2 vs Q1 Growth | +13.1% |
      | Best Month | June ($62,000) |
      | Weakest Month | January ($45,000) |

      ### Patterns & Trends
      - **Overall trajectory:** Upward with 13.1% quarterly growth
      - **Monthly progression:** Consistent gains except April dip
      - **Momentum:** Accelerating into Q2 (June +12.7% vs May)

      ### Anomaly Alert
      - **April Dip:** $47,000 (10% below March)
      - This breaks the otherwise consistent upward trend
      - Recommend investigating: Was this seasonal? Operational? External?

      ### Insights
      1. **We're on track:** 13% quarterly growth is strong
      2. **Momentum is building:** June acceleration suggests continued growth
      3. **April risk:** Understanding the dip prevents future recurrence

      ### Recommendations
      1. **Immediate:** Investigate April dip causes
      2. **Replicate:** Identify what drove June success
      3. **Forecast:** Project Q3 using June momentum ($65K-70K monthly)
      4. **Focus area:** Whatever worked in June, double down
    </output>
  </example>
</examples>

<data>
{{data}}
</data>

<formatting>
1. Work through all 6 analysis steps in <thinking> tags
2. Provide <output> with:
   - Key Metrics table
   - Patterns & Trends section
   - Anomalies/Alerts if any
   - Numbered Insights
   - Numbered Recommendations
</formatting>
```

---

## Customer Support Domain

### Before

```text
Draft a response to this customer email.

{{email}}
```

### After

```xml
<instructions>
You are a customer support specialist crafting helpful, empathetic responses.

Response requirements:
1. **Acknowledge** the customer's situation/feelings
2. **Address** the specific issue or question
3. **Provide** clear next steps or resolution
4. **Close** with follow-up options

Tone guidelines:
- Professional but warm
- Empathetic without being overly apologetic
- Clear and actionable
- Concise (aim for 150 words or less unless complexity requires more)

Never:
- Make promises you can't keep
- Blame the customer
- Use jargon without explanation
- Leave issues unresolved without clear next steps
</instructions>

<context>
Company: {{company_name}}
Product/Service: {{product}}
Known issues: {{known_issues}}
Available actions: {{available_actions}}
</context>

<examples>
  <example>
    <input>
      Subject: WHERE IS MY ORDER???

      I ordered 5 days ago and paid for express shipping. Still nothing. This is ridiculous. I needed this for my daughter's birthday which is TOMORROW. This is the worst experience ever.
    </input>
    <company_name>TechGadgets Inc.</company_name>
    <product>Electronics retailer</product>
    <known_issues>Carrier delays in Northeast region</known_issues>
    <available_actions>Full refund, expedited replacement, store credit</available_actions>

    <thinking>
      Issue breakdown:
      - Order delayed despite express shipping
      - Time-sensitive (birthday tomorrow)
      - Customer is frustrated (caps, "ridiculous," "worst")

      Approach:
      1. Acknowledge urgency and frustration genuinely
      2. Don't make excuses but do explain
      3. Focus on solutions since birthday is tomorrow
      4. Offer concrete resolution

      Best resolution:
      - Birthday is tomorrow, shipping won't help
      - Offer: Full refund AND store credit for inconvenience
      - Alternative: Check local pickup options
    </thinking>
    <output>
      Subject: Re: WHERE IS MY ORDER???

      Hi there,

      I completely understand how frustrating this is, especially with your daughter's birthday tomorrow. This isn't the experience we want for you, and I'm sorry we've let you down.

      I've looked into your order, and it appears to be affected by carrier delays in your region. However, I know that doesn't solve your immediate need.

      Here's what I can do right now:

      1. **Immediate refund** of your full order including shipping
      2. **$25 store credit** for the inconvenience
      3. If you'd like to try again, I can check if we have the item at a local partner store for pickup today

      Please reply with which option works best, and I'll process it immediately.

      Again, I'm truly sorry about the timing. I hope we can make it up to you.

      Best,
      [Agent Name]
      TechGadgets Inc. Support
    </output>
  </example>
</examples>

<customer_email>
{{email}}
</customer_email>

<formatting>
1. Analyze the email in <thinking> tags:
   - Identify the core issue
   - Note customer's emotional state
   - Plan your approach
   - Determine best resolution
2. Provide response in <output> tags
3. Include subject line (Re: original subject)
4. Use numbered options when offering choices
</formatting>
```

---

## Content Creation Domain

### Before

```text
Write a blog post about {{topic}}.
```

### After

```xml
<instructions>
You are a content strategist creating engaging blog content. Write a blog post optimized for readability and engagement.

Content structure:
1. **Hook:** Opening that grabs attention (question, statistic, story)
2. **Context:** Why this topic matters to the reader
3. **Main content:** Key points with supporting details
4. **Actionable takeaways:** What the reader can do
5. **Conclusion:** Summary and call to action

Style guidelines:
- Write at an 8th-grade reading level
- Use short paragraphs (2-3 sentences max)
- Include subheadings every 2-3 paragraphs
- Use bullet points for lists
- Active voice preferred
- Vary sentence length for rhythm
</instructions>

<context>
Target audience: {{audience}}
Blog tone: {{tone}}
Word count target: {{word_count}}
SEO keywords to include: {{keywords}}
</context>

<examples>
  <example>
    <input>Write about time management for remote workers</input>
    <audience>Remote professionals, 25-45</audience>
    <tone>Helpful, conversational, practical</tone>
    <word_count>600</word_count>
    <keywords>time management, remote work, productivity, work from home</keywords>

    <thinking>
      Planning the post:

      Hook options:
      - Statistic about remote work productivity
      - Question about struggling with time
      - Brief story about typical WFH chaos

      Main points (3-4):
      1. Time blocking technique
      2. Environment design
      3. Boundaries with household/family
      4. Tools and systems

      Takeaways:
      - One technique to try today
      - Simple implementation steps

      Structure:
      - Hook (stat + question)
      - Context (why remote work time management is hard)
      - Point 1: Time blocking
      - Point 2: Environment
      - Point 3: Boundaries
      - Actionable steps
      - CTA
    </thinking>
    <output>
      # 3 Time Management Secrets Remote Workers Swear By

      Did you know that remote workers report being 47% more productive than their office counterparts? Yet many still struggle to manage their time effectively at home.

      If you've ever looked up from your laptop to realize it's 3 PM and you haven't done that important task yet, you're not alone. Here's how to fix it.

      ## Why Time Management Hits Different at Home

      The office had structure built in. Meetings, lunch breaks, the commute home—all created natural boundaries. At home, work bleeds into everything.

      Without intentional systems, even the most disciplined professionals find themselves scattered. Let's fix that.

      ## 1. Time Blocking: Your New Best Friend

      Stop managing a to-do list. Start managing your calendar.

      Time blocking means assigning specific hours to specific tasks. Not "work on report" but "9-11 AM: Draft Q3 report." When the block ends, you move on.

      **Try this:** Block your most important task for the first 90 minutes of your day, before checking email.

      ## 2. Design Your Environment for Focus

      Your brain associates spaces with activities. If you answer emails on the couch, your brain thinks "couch = work."

      Create clear boundaries. Work happens at the desk. Relaxation happens elsewhere.

      Even a small change helps. One remote worker simply puts on shoes when "at work" and takes them off to signal the end of the day.

      ## 3. Boundaries Aren't Rude—They're Necessary

      Tell your household your schedule. A closed door or headphones means "do not disturb."

      This isn't about being unavailable. It's about being fully present for work AND for life—just not both at once.

      ## Start Today

      Pick one technique from this list. Just one. Try it for a week.

      Time management isn't about doing more. It's about doing what matters, when you planned to do it.

      Which technique will you try first? Let us know in the comments.
    </output>
  </example>
</examples>

<topic>
{{topic}}
</topic>

<formatting>
1. Plan content in <thinking> tags:
   - Hook approach
   - Main points (3-4)
   - Takeaways
   - Overall structure
2. Write post in <output> tags
3. Use markdown formatting (# for title, ## for subheadings)
4. Include a call to action at the end
</formatting>
```

---

## Technical Documentation Domain

### Before

```text
Write documentation for this API endpoint.

{{endpoint_info}}
```

### After

```xml
<instructions>
You are a technical writer creating API documentation. Write clear, comprehensive documentation that developers can use effectively.

Documentation structure:
1. **Endpoint summary:** One-line description
2. **Request details:** Method, URL, headers, parameters
3. **Request body:** Schema with field descriptions
4. **Response:** Success and error response formats
5. **Examples:** Curl and language-specific examples
6. **Notes:** Rate limits, authentication, common issues

Writing guidelines:
- Be precise and unambiguous
- Include all required vs optional fields
- Show realistic example values
- Document error cases developers will encounter
- Use consistent formatting throughout
</instructions>

<examples>
  <example>
    <input>
      POST /api/users
      Creates a new user
      Requires: email (string), password (string, min 8 chars)
      Optional: name (string), role (string, default "user")
      Returns: user object with id
      Errors: 400 if validation fails, 409 if email exists
    </input>
    <thinking>
      Structuring the documentation:

      1. Summary: Create new user account
      2. Request: POST, auth required?, content-type
      3. Body schema: email, password, name, role
      4. Responses: 201 success, 400 validation, 409 conflict
      5. Examples: Curl, Python, JavaScript
      6. Notes: Password requirements, email uniqueness
    </thinking>
    <output>
      # Create User

      Creates a new user account.

      ## Request

      ```
      POST /api/users
      Content-Type: application/json
      ```

      ### Headers

      | Header | Required | Description |
      |--------|----------|-------------|
      | Content-Type | Yes | Must be `application/json` |
      | Authorization | Yes | Bearer token |

      ### Request Body

      | Field | Type | Required | Description |
      |-------|------|----------|-------------|
      | email | string | Yes | Valid email address. Must be unique. |
      | password | string | Yes | Minimum 8 characters. |
      | name | string | No | User's display name. |
      | role | string | No | User role. Default: `"user"`. Options: `"user"`, `"admin"`. |

      ## Response

      ### Success (201 Created)

      ```json
      {
        "id": "usr_abc123",
        "email": "jane@example.com",
        "name": "Jane Doe",
        "role": "user",
        "created_at": "2024-01-15T10:30:00Z"
      }
      ```

      ### Errors

      **400 Bad Request** - Validation failed
      ```json
      {
        "error": "validation_error",
        "message": "Password must be at least 8 characters",
        "field": "password"
      }
      ```

      **409 Conflict** - Email already exists
      ```json
      {
        "error": "email_exists",
        "message": "An account with this email already exists"
      }
      ```

      ## Examples

      ### Curl

      ```bash
      curl -X POST https://api.example.com/api/users \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer YOUR_TOKEN" \
        -d '{
          "email": "jane@example.com",
          "password": "securepass123",
          "name": "Jane Doe"
        }'
      ```

      ### Python

      ```python
      import requests

      response = requests.post(
          "https://api.example.com/api/users",
          headers={"Authorization": "Bearer YOUR_TOKEN"},
          json={
              "email": "jane@example.com",
              "password": "securepass123",
              "name": "Jane Doe"
          }
      )
      user = response.json()
      ```

      ## Notes

      - Passwords are hashed before storage; the plain text is never stored
      - Email addresses are case-insensitive for uniqueness checks
      - Rate limit: 10 requests per minute per IP
    </output>
  </example>
</examples>

<endpoint_info>
{{endpoint_info}}
</endpoint_info>

<formatting>
1. Plan documentation in <thinking> tags
2. Write documentation in <output> tags using markdown
3. Use tables for request/response schemas
4. Include code blocks for all examples
5. Document ALL error cases mentioned in the input
</formatting>
```

---

## Domain Selection Guide

| Domain | Key Improvement Focus |
| -------- | ---------------------- |
| Code Review | Severity ratings, specific line references, fix suggestions |
| Data Analysis | Observation → Insight → Recommendation flow, specific numbers |
| Customer Support | Empathy first, clear resolution options, professional tone |
| Content Creation | Hook + structure + CTA, readability optimization |
| Technical Docs | Completeness, examples, error documentation |

---

## Next Steps

- For basic examples, see [basic-transformations.md](basic-transformations.md)
- For advanced multi-component examples, see [advanced-transformations.md](advanced-transformations.md)
- For pattern details, see [../patterns/](../patterns/)
