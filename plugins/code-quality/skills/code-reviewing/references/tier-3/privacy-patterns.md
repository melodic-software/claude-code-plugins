# Privacy Patterns - Data Privacy Code Review Checks

**Tier 3 Reference** - Loaded when code contains privacy-related patterns: PII*, email*, user*, customer*, personal*, gdpr*, ccpa*, consent*, privacy*, data_subject*

## PII Identification and Classification

- [ ] **PII detection** - All personally identifiable information (name, email, phone, address, SSN, etc.) is identified and classified by sensitivity level
- [ ] **Special category data** - Sensitive PII (health, biometric, genetic, racial/ethnic origin, political opinions, religious beliefs, sexual orientation) is flagged and handled with heightened controls
- [ ] **Derived PII** - Indirect identifiers (IP addresses, device IDs, behavioral patterns, location data) are recognized as PII
- [ ] **Context-specific PII** - Data that becomes PII when combined (zip code + birth date + gender) is identified and protected

## Data Minimization

- [ ] **Collection limitation** - Only PII necessary for stated purpose is collected; no "nice to have" data fields
- [ ] **Field-level justification** - Each PII field has documented business/legal justification for collection
- [ ] **Purpose limitation** - PII is only used for purposes disclosed at collection time; repurposing requires new consent
- [ ] **Storage minimization** - PII is not duplicated unnecessarily; references/IDs used instead of copying full PII across systems
- [ ] **Retention alignment** - PII is not stored longer than necessary for stated purpose

## Consent Management

- [ ] **Explicit consent** - Affirmative, unambiguous consent obtained before PII collection (no pre-checked boxes, implied consent, or bundled consent)
- [ ] **Granular consent** - Separate consent for distinct processing purposes; users can consent to some purposes and reject others
- [ ] **Consent withdrawal** - Users can withdraw consent as easily as they gave it; systems handle consent revocation gracefully
- [ ] **Consent audit trail** - What consent was given, when, how, and by whom is logged immutably
- [ ] **Parental consent** - For minors (under 13 in US, under 16 in EU), verifiable parental consent is obtained

## Data Subject Access Rights (DSAR)

- [ ] **Access endpoint** - Provides mechanism for users to request all PII held about them
- [ ] **Complete disclosure** - All PII across all systems/databases is included in access response (no partial responses)
- [ ] **Machine-readable format** - Data provided in structured, commonly used format (JSON, CSV, XML)
- [ ] **Timely response** - DSAR responses generated within legal timeframes (30 days GDPR, 45 days CCPA)
- [ ] **Identity verification** - Requestor identity is verified before disclosing PII (prevent unauthorized access)

## Right to Deletion (Erasure)

- [ ] **Deletion endpoint** - Provides mechanism for users to request PII deletion
- [ ] **Complete erasure** - PII is deleted from all systems including backups, logs, caches, analytics, and third-party systems
- [ ] **Cascading deletion** - Deletion propagates through all data stores; no orphaned PII fragments remain
- [ ] **Retention exceptions** - Legal holds, fraud prevention, or regulatory requirements for retention are documented and applied correctly
- [ ] **Deletion verification** - Deletion completion is confirmed and logged; users receive confirmation

## Data Portability

- [ ] **Export functionality** - Users can export their PII in machine-readable format
- [ ] **Interoperable format** - Export uses industry-standard formats that can be imported into competing services
- [ ] **Complete export** - All user-provided and system-generated PII is included (profile, preferences, history, etc.)
- [ ] **Direct transfer** - Where feasible, supports direct PII transfer to another controller

## Privacy by Design

- [ ] **Default privacy** - Most privacy-protective settings are enabled by default; users must opt-in to less private options
- [ ] **Privacy impact assessment** - Code changes affecting PII processing have documented privacy impact analysis
- [ ] **Least privilege** - Only code/services that need PII have access; access is role-based and minimal
- [ ] **Built-in protection** - Privacy safeguards are embedded in system architecture, not added as afterthought
- [ ] **Visibility and transparency** - Users can see what PII is held, how it's used, and who it's shared with

## Data Retention and Disposal

- [ ] **Retention policies** - Each PII category has documented retention period based on legal/business requirements
- [ ] **Automated deletion** - PII is automatically deleted when retention period expires (no manual cleanup required)
- [ ] **Secure disposal** - Deleted PII is cryptographically erased or physically destroyed; not just marked as deleted
- [ ] **Backup retention** - Backups containing PII have retention limits and are purged when no longer needed
- [ ] **Log retention** - Logs containing PII are retained only as long as necessary; sensitive fields are redacted or hashed

## Cross-Border Data Transfers

- [ ] **Transfer legality** - PII transfers outside user's jurisdiction comply with legal mechanisms (adequacy decisions, SCCs, BCRs, Privacy Shield alternatives)
- [ ] **Transfer disclosure** - Users are informed when PII will be transferred internationally
- [ ] **Data localization** - Where required, PII is stored and processed within specific geographic boundaries
- [ ] **Transfer safeguards** - Contracts with international processors include GDPR Article 28 or equivalent requirements

## Third-Party Data Sharing

- [ ] **Processor agreements** - Contracts with third-party processors include data protection clauses, audit rights, and breach notification
- [ ] **Minimized sharing** - Only PII necessary for third-party service is shared; excessive data is not disclosed
- [ ] **Consent for sharing** - Users consent to third-party sharing when required; legitimate interest is documented when consent not required
- [ ] **Third-party vetting** - Processors are vetted for adequate security and privacy practices before PII is shared
- [ ] **Onward transfer restrictions** - Third parties are contractually prohibited from sharing PII further without authorization

## Privacy in Logs and Analytics

- [ ] **Log redaction** - PII in logs is redacted, hashed, or tokenized; raw PII is not logged
- [ ] **Analytics anonymization** - Analytics systems receive anonymized or aggregated data, not raw PII
- [ ] **Error handling** - Exception messages and stack traces do not expose PII
- [ ] **Debugging safeguards** - Debug modes do not log PII to console, files, or external services
- [ ] **Monitoring boundaries** - Application performance monitoring (APM) and error tracking tools do not capture PII

## Anonymization and Pseudonymization

- [ ] **Irreversible anonymization** - Truly anonymized data cannot be re-identified; anonymization is not reversible
- [ ] **Pseudonymization keys** - Pseudonymization keys/tokens are stored separately from pseudonymized data with access controls
- [ ] **Re-identification testing** - Anonymization techniques are tested against re-identification attacks (linkage, inference, etc.)
- [ ] **Aggregation thresholds** - Aggregated data has minimum population thresholds (k-anonymity) to prevent re-identification
- [ ] **Differential privacy** - Where appropriate, differential privacy techniques add noise to prevent individual identification

## Privacy Impact Assessments

- [ ] **High-risk processing** - New processing activities involving sensitive PII, large-scale profiling, or automated decisions trigger privacy impact assessment (PIA/DPIA)
- [ ] **Risk mitigation** - PIAs identify privacy risks and document mitigation measures
- [ ] **Stakeholder involvement** - Data protection officer (DPO) or privacy team reviews PIAs before high-risk processing begins
- [ ] **Documented outcomes** - PIA conclusions are documented and available for regulatory review

## Breach Notification

- [ ] **Breach detection** - Systems monitor for unauthorized PII access, disclosure, or loss
- [ ] **Breach logging** - Potential breaches are logged with details: what PII, how many records, when, how discovered
- [ ] **Notification triggers** - Breach notification obligations are evaluated (72-hour GDPR notification, state law variations)
- [ ] **User notification** - When breach poses high risk to users, they are notified directly with remediation guidance
- [ ] **Regulatory notification** - Breaches are reported to supervisory authorities within legal timeframes with required details

---

**Usage:** This Tier 3 reference loads when privacy-related patterns are detected. Use these checks to ensure code handling PII complies with GDPR, CCPA, and privacy best practices.

**Related:** See main SKILL.md section 1.16 Data Privacy (GDPR/CCPA) for overview-level checks.
