# Advanced Transformations

This reference provides complex before/after examples for multi-component prompts that require sophisticated improvement strategies.

## Example 1: Multi-Step Analysis

### Before (Original Prompt)

```text
Analyze this customer feedback and tell me what we should do.

Feedback: {{feedback}}
```

### After (Improved Prompt)

```xml
<instructions>
You are a customer experience analyst. Analyze customer feedback to extract actionable insights.

Your analysis must include:
1. Sentiment classification (positive, negative, mixed, neutral)
2. Key issues or praise points identified
3. Priority level (high, medium, low)
4. Recommended actions

Consider both explicit statements and implicit concerns. Prioritize issues that affect customer retention or satisfaction.
</instructions>

<context>
This analysis supports our product improvement process. High-priority issues should be immediately actionable. Recommendations should be specific and feasible.
</context>

<examples>
  <example>
    <input>
      "Your app is mostly good but the checkout keeps crashing on my iPhone. Lost my cart twice this week. Really frustrating when I'm trying to buy something. Love the product selection though."
    </input>
    <thinking>
      Breaking down the feedback:

      1. Sentiment Analysis:
         - Negative: checkout crashes, lost cart, frustrating
         - Positive: app mostly good, love product selection
         - Overall: Mixed, leaning negative due to functional issue

      2. Key Issues:
         - Primary: Checkout crash on iPhone (functional bug)
         - Impact: Cart abandonment (revenue loss)
         - Frequency: Multiple times ("twice this week")

      3. Key Praise:
         - Product selection appreciated
         - General app quality acknowledged

      4. Priority Assessment:
         - Checkout = purchase completion = revenue
         - Recurring issue = systematic problem
         - Platform-specific (iPhone) = reproducible
         - Priority: HIGH

      5. Recommended Actions:
         - Investigate iOS checkout flow
         - Add cart persistence/recovery
         - Reach out to customer
    </thinking>
    <output>
      **Sentiment:** Mixed (negative-leaning due to functional issue)

      **Key Issues:**
      - Checkout crash on iPhone (recurring, cart loss)

      **Key Praise:**
      - Product selection quality
      - Overall app experience

      **Priority:** HIGH
      - Affects purchase completion (revenue impact)
      - Recurring issue (multiple instances)
      - Specific platform (iPhone) allows targeted debugging

      **Recommended Actions:**
      1. [Immediate] Investigate iOS checkout flow for crash causes
      2. [Short-term] Implement cart persistence to prevent data loss
      3. [Customer Care] Reach out with apology and update on fix timeline
    </output>
  </example>
</examples>

<feedback>
{{feedback}}
</feedback>

<formatting>
Structure your response with:
1. <thinking> tags for your analysis process
2. <output> tags with clearly labeled sections:
   - Sentiment
   - Key Issues
   - Key Praise
   - Priority
   - Recommended Actions (numbered, with timeframe)
</formatting>
```

### Transformation Notes

- **Task decomposition:** Broke "analyze and tell me what to do" into 5 specific subtasks
- **Context added:** Explained purpose (product improvement process)
- **Structured output:** Clear sections with specific formats
- **Actionable recommendations:** Timeframe tags (Immediate, Short-term, etc.)

---

## Example 2: Multi-Document Comparison

### Before (Original Prompt)

```text
Compare these two proposals and recommend one.

Proposal A: {{proposal_a}}
Proposal B: {{proposal_b}}
```

### After (Improved Prompt)

```xml
<instructions>
You are a strategic analyst comparing business proposals. Provide a structured comparison and clear recommendation.

Evaluation criteria (in order of importance):
1. Cost-effectiveness (budget alignment and ROI)
2. Feasibility (timeline, resources, technical requirements)
3. Risk profile (potential issues and mitigation)
4. Strategic alignment (fits organization goals)

Your recommendation must be definitive (choose one) with clear justification.
</instructions>

<context>
Decision context: {{context}}
Budget constraints: {{budget}}
Timeline requirements: {{timeline}}
</context>

<examples>
  <example>
    <proposal_a>
      Cloud migration with vendor X. Cost: $500K over 2 years. Timeline: 18 months. Requires hiring 2 specialists. Vendor has 95% uptime SLA.
    </proposal_a>
    <proposal_b>
      Cloud migration with vendor Y. Cost: $400K over 2 years. Timeline: 12 months. Uses existing team with training. Vendor has 99.9% uptime SLA.
    </proposal_b>
    <context>Digital transformation initiative. Minimize disruption. Reliability is critical.</context>

    <thinking>
      Comparing on each criterion:

      1. Cost-effectiveness:
         - A: $500K, no training costs, but hiring costs
         - B: $400K + training costs (~$50K estimated)
         - B slightly better on direct costs

      2. Feasibility:
         - A: 18 months, requires hiring (risk of delays)
         - B: 12 months, existing team (faster start)
         - B significantly better (6 months faster, no hiring risk)

      3. Risk Profile:
         - A: 95% uptime = ~18 days downtime/year
         - B: 99.9% uptime = ~9 hours downtime/year
         - B dramatically better for reliability-critical context

      4. Strategic Alignment:
         - "Minimize disruption": B's faster timeline wins
         - "Reliability critical": B's SLA wins
         - B aligns better on both stated priorities

      Scoring: B wins on 3 of 4 criteria, ties on 1
    </thinking>
    <output>
      ## Comparison Matrix

      | Criterion | Proposal A | Proposal B | Winner |
      |-----------|------------|------------|--------|
      | Cost | $500K + hiring | $400K + training | B |
      | Timeline | 18 months | 12 months | B |
      | Reliability | 95% SLA | 99.9% SLA | B |
      | Strategic Fit | Partial | Strong | B |

      ## Recommendation: Proposal B

      **Justification:**
      Proposal B outperforms on all criteria. The 6-month faster timeline reduces transformation risk, the 99.9% SLA addresses the stated reliability priority, and using the existing team with training builds internal capability. The $100K cost savings can fund comprehensive training and contingency.

      **Key Risk with B:**
      Training timeline must be front-loaded to avoid delays. Recommend starting training 2 months before migration begins.
    </output>
  </example>
</examples>

<proposals>
  <proposal_a>
    {{proposal_a}}
  </proposal_a>
  <proposal_b>
    {{proposal_b}}
  </proposal_b>
</proposals>

<formatting>
1. Analyze in <thinking> tags using each criterion
2. Provide <output> with:
   - Comparison matrix (table format)
   - Clear recommendation with "Recommendation: [A or B]"
   - Justification paragraph
   - Key risk acknowledgment for chosen option
</formatting>
```

### Transformation Notes

- **Evaluation framework:** Added explicit, ranked criteria
- **Context variables:** Budget, timeline, decision context
- **Comparison structure:** Matrix format for clarity
- **Balanced analysis:** Acknowledge risks even in recommended option
- **Definitive output:** "Must be definitive (choose one)"

---

## Example 3: Complex Extraction with Validation

### Before (Original Prompt)

```text
Extract the key information from this contract.

Contract: {{contract}}
```

### After (Improved Prompt)

```xml
<instructions>
You are a contract analyst extracting structured information from legal documents.

Extract the following fields:
1. Parties (all named parties with their roles)
2. Effective Date (when contract begins)
3. Term/Duration (length of agreement)
4. Financial Terms (amounts, payment schedules, conditions)
5. Key Obligations (what each party must do)
6. Termination Conditions (how contract can end)
7. Special Clauses (anything unusual or noteworthy)

For each field:
- Extract verbatim quotes where possible
- Note section/paragraph reference if available
- Mark as "NOT FOUND" if information is absent
- Flag ambiguities with [AMBIGUOUS: explanation]
</instructions>

<examples>
  <example>
    <input>
      SERVICE AGREEMENT

      This Agreement is entered into as of January 15, 2024 between ABC Corp ("Client") and XYZ Services LLC ("Provider").

      1. Term: This agreement shall be effective for a period of 24 months from the Effective Date.

      2. Compensation: Client shall pay Provider $10,000 per month, due on the first of each month. Late payments incur 1.5% monthly interest.

      3. Services: Provider shall deliver monthly analytics reports and quarterly strategy recommendations.

      4. Termination: Either party may terminate with 30 days written notice. Immediate termination permitted for material breach.
    </input>
    <thinking>
      Extracting each required field:

      1. Parties:
         - "ABC Corp" - role: Client
         - "XYZ Services LLC" - role: Provider
         - Source: Preamble

      2. Effective Date:
         - "January 15, 2024"
         - Source: "as of January 15, 2024"

      3. Term/Duration:
         - 24 months
         - Source: Section 1

      4. Financial Terms:
         - Base: $10,000/month
         - Due: First of each month
         - Late fee: 1.5% monthly interest
         - Source: Section 2

      5. Key Obligations:
         - Provider: Monthly analytics reports, quarterly strategy
         - Client: Monthly payment on time
         - Source: Sections 2, 3

      6. Termination:
         - Standard: 30 days written notice
         - Immediate: Material breach
         - Source: Section 4

      7. Special Clauses:
         - Late payment interest clause is above typical (1.5% monthly = 18% annually)
         - Note: No mention of IP ownership, liability caps, or dispute resolution
    </thinking>
    <output>
      ## Contract Extraction Results

      | Field | Value | Source |
      |-------|-------|--------|
      | **Parties** | ABC Corp (Client), XYZ Services LLC (Provider) | Preamble |
      | **Effective Date** | January 15, 2024 | Preamble |
      | **Term** | 24 months | Section 1 |

      ### Financial Terms (Section 2)
      - Monthly fee: $10,000
      - Payment due: 1st of each month
      - Late fee: 1.5% monthly interest

      ### Key Obligations
      - **Provider:** Monthly analytics reports; quarterly strategy recommendations
      - **Client:** Timely monthly payments

      ### Termination Conditions (Section 4)
      - 30 days written notice (either party)
      - Immediate termination for material breach

      ### Special Notes
      - [FLAG] Late payment interest (18% annual) is above market standard
      - [NOT FOUND] Intellectual property ownership
      - [NOT FOUND] Liability limitations
      - [NOT FOUND] Dispute resolution mechanism
    </output>
  </example>
</examples>

<contract>
{{contract}}
</contract>

<formatting>
1. Analyze document in <thinking> tags
2. Provide <output> with:
   - Summary table for simple fields
   - Detailed sections for complex fields
   - Clear [NOT FOUND] markers for missing information
   - [FLAG] markers for unusual or noteworthy clauses
   - [AMBIGUOUS] markers with explanation where needed
</formatting>
```

### Transformation Notes

- **Field specification:** Explicit list of what to extract
- **Handling missing data:** "NOT FOUND" markers
- **Ambiguity handling:** [AMBIGUOUS: explanation] pattern
- **Source tracking:** Paragraph/section references
- **Quality flags:** [FLAG] for unusual clauses

---

## Example 4: Multi-Stage Reasoning

### Before (Original Prompt)

```text
Should we expand into this new market?

Market data: {{market_data}}
Company profile: {{company_profile}}
```

### After (Improved Prompt)

```xml
<instructions>
You are a strategic advisor analyzing market expansion opportunities. Conduct a structured analysis leading to a clear recommendation.

Analysis Framework:
1. Market Opportunity Assessment
2. Competitive Landscape Analysis
3. Company Capability Fit
4. Risk Evaluation
5. Financial Viability
6. Strategic Recommendation

Recommendation must be one of:
- EXPAND: Strong opportunity, acceptable risk
- DEFER: Good opportunity, but timing or preparation issues
- DECLINE: Poor fit or unacceptable risk
</instructions>

<context>
Decision criteria:
- Minimum ROI threshold: {{roi_threshold}}
- Maximum risk tolerance: {{risk_tolerance}}
- Strategic priorities: {{strategic_priorities}}
</context>

<examples>
  <example>
    <market_data>
      Southeast Asian e-commerce market. $50B TAM, 15% annual growth. Main competitors: Lazada (40%), Shopee (35%). Remaining 25% fragmented. Key challenge: logistics infrastructure.
    </market_data>
    <company_profile>
      US-based e-commerce platform. $2B revenue. Strong logistics network in North America. No international presence. Tech platform is scalable. Cash reserves: $500M.
    </company_profile>
    <roi_threshold>15% within 3 years</roi_threshold>
    <risk_tolerance>Medium</risk_tolerance>
    <strategic_priorities>International expansion, platform growth</strategic_priorities>

    <thinking>
      STAGE 1: Market Opportunity Assessment
      - TAM: $50B (significant)
      - Growth: 15% annual (above average)
      - Opportunity score: HIGH

      STAGE 2: Competitive Landscape
      - Top 2 competitors hold 75% share
      - Both are well-funded, established
      - Entry barrier: HIGH
      - Differentiation needed: Significant

      STAGE 3: Capability Fit
      - Tech platform: Scalable (GOOD)
      - Logistics: US-only, needs building (GAP)
      - International experience: None (GAP)
      - Cash: $500M available (ADEQUATE)

      STAGE 4: Risk Evaluation
      - Logistics build-out: HIGH RISK
      - Competitive response: HIGH RISK
      - Cultural/regulatory learning: MEDIUM RISK
      - Overall: ABOVE THRESHOLD

      STAGE 5: Financial Viability
      - Investment required: ~$200-300M (logistics + marketing)
      - Time to break-even: 4-5 years (estimate)
      - ROI within 3 years: UNLIKELY
      - Meets threshold: NO

      STAGE 6: Synthesis
      - Market is attractive (HIGH opportunity)
      - But company not ready (capability GAPS)
      - Risk exceeds tolerance
      - ROI threshold not achievable
    </thinking>
    <output>
      ## Market Expansion Analysis: Southeast Asia E-Commerce

      ### Assessment Summary

      | Dimension | Rating | Notes |
      |-----------|--------|-------|
      | Market Opportunity | HIGH | $50B TAM, 15% growth |
      | Competitive Position | CHALLENGING | 75% held by 2 players |
      | Capability Fit | MODERATE | Tech ready, logistics gap |
      | Risk Level | ABOVE TOLERANCE | Logistics, competition |
      | Financial Viability | BELOW THRESHOLD | 4-5yr breakeven, <15% 3yr ROI |

      ### Recommendation: DEFER

      **Rationale:**
      The market opportunity is genuine, but current capability gaps and risk profile don't support immediate entry. The 4-5 year breakeven timeline fails the 15% 3-year ROI threshold.

      **Recommended Path Forward:**
      1. Build international operations experience in lower-risk market first
      2. Develop logistics partnerships or acquisition targets in SEA
      3. Reassess in 18-24 months with improved capabilities

      **What Would Change This to EXPAND:**
      - Strategic logistics acquisition in region
      - Relaxed ROI timeline to 5 years
      - Partnership with local player for market entry
    </output>
  </example>
</examples>

<market_data>
{{market_data}}
</market_data>

<company_profile>
{{company_profile}}
</company_profile>

<formatting>
1. Work through all 6 stages in <thinking> tags
2. Provide <output> with:
   - Assessment summary table
   - Clear recommendation (EXPAND/DEFER/DECLINE)
   - Rationale paragraph
   - Path forward recommendations
   - Conditions that would change the recommendation
</formatting>
```

### Transformation Notes

- **Structured framework:** 6 explicit analysis stages
- **Decision constraints:** ROI threshold, risk tolerance as variables
- **Definitive output:** Three clear options (EXPAND/DEFER/DECLINE)
- **Actionable path forward:** What to do regardless of decision
- **Transparency:** What would change the recommendation

---

## Advanced Pattern Summary

| Pattern | When to Use |
|---------|-------------|
| Multi-stage analysis | Complex decisions requiring step-by-step reasoning |
| Comparison framework | Evaluating multiple options against criteria |
| Extraction with validation | Structured data from unstructured documents |
| Definitive recommendation | Business decisions requiring clear direction |
| NOT FOUND/FLAG markers | Handling incomplete or unusual information |
| Context variables | Customizing analysis to specific constraints |

---

## Next Steps

- For domain-specific examples, see [domain-specific.md](domain-specific.md)
- For pattern details, see [../patterns/](../patterns/)
- For iterating on complex prompts, see [../workflows/iterative-refinement.md](../workflows/iterative-refinement.md)
