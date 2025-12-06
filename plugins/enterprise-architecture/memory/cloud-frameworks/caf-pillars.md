# Microsoft Cloud Adoption Framework (CAF)

The Cloud Adoption Framework provides comprehensive guidance for Azure cloud adoption through 7 methodologies.

## CAF Methodologies

| # | Methodology | Purpose | Key Activities |
| --- | --- | --- | --- |
| 1 | **Strategy** | Define business justification | Motivations, outcomes, business case |
| 2 | **Plan** | Create adoption plan | Digital estate, skills, timeline |
| 3 | **Ready** | Prepare environment | Landing zones, governance baseline |
| 4 | **Adopt** | Migrate/innovate workloads | Migration waves, modernization |
| 5 | **Govern** | Manage cloud governance | Policies, compliance, cost management |
| 6 | **Secure** | Implement security | Zero trust, identity, data protection |
| 7 | **Manage** | Operate cloud estate | Monitoring, optimization, resilience |

## Methodology Flow

```text
Foundational (Sequential):
Strategy → Plan → Ready → Adopt

Operational (Parallel/Ongoing):
├── Govern
├── Secure
└── Manage
```

## Detailed Methodology Guidance

### 1. Strategy

**Purpose:** Align cloud adoption to business goals.

**Key Activities:**

- Document cloud motivations
- Define business outcomes
- Build business justification
- Identify cloud journey team

**Deliverables:**

- Strategy document
- Business case
- RACI matrix

### 2. Plan

**Purpose:** Create comprehensive transformation plan.

**Key Activities:**

- Assess digital estate
- Assess organizational readiness
- Create skills readiness plan
- Build cloud adoption plan

**Deliverables:**

- Digital estate inventory
- Skills gap analysis
- Cloud adoption plan

### 3. Ready

**Purpose:** Deploy enterprise-ready Azure environments.

**Key Activities:**

- Deploy Azure landing zone
- Establish governance baseline
- Configure network topology
- Set up identity management

**Deliverables:**

- Landing zone deployment
- Governance policies
- Network architecture

### 4. Adopt

**Purpose:** Deploy production workloads.

**Key Activities:**

- Assess workloads
- Deploy/migrate workloads
- Release to production
- Iterate and improve

**Sub-disciplines:**

- **Migrate:** Move existing workloads
- **Innovate:** Build new cloud-native solutions

**Deliverables:**

- Migration waves
- Modernization roadmap
- Release documentation

### 5. Govern

**Purpose:** Maintain control, compliance, cost optimization.

**Key Activities:**

- Define governance policies
- Implement cost management
- Manage security baseline
- Ensure regulatory compliance

**Governance Disciplines:**

- Cost Management
- Security Baseline
- Identity Baseline
- Resource Consistency
- Deployment Acceleration

**Deliverables:**

- Governance policies
- Compliance reports
- Cost dashboards

### 6. Secure

**Purpose:** Protect against cyber threats.

**Key Activities:**

- Implement Zero Trust
- Configure identity and access
- Protect data and applications
- Enable threat protection

**Security Pillars:**

- Identity and access
- Infrastructure protection
- Data protection
- Application security
- Security operations

**Deliverables:**

- Security architecture
- Identity policies
- Threat protection config

### 7. Manage

**Purpose:** Ensure operational excellence.

**Key Activities:**

- Configure monitoring
- Implement backup/recovery
- Optimize performance
- Manage operations

**Management Disciplines:**

- Monitoring
- Business continuity
- Operations compliance
- Platform operations
- Workload operations

**Deliverables:**

- Monitoring dashboards
- DR procedures
- Operations runbooks

## CAF Alignment Checklist

### Strategy

- [ ] Cloud motivations documented
- [ ] Business outcomes defined
- [ ] Financial considerations addressed
- [ ] Technical considerations documented

### Plan

- [ ] Digital estate assessed
- [ ] Skills readiness evaluated
- [ ] Cloud adoption plan created
- [ ] Azure readiness confirmed

### Ready

- [ ] Landing zone deployed
- [ ] Governance baseline established
- [ ] Network topology defined
- [ ] Identity management configured

### Adopt

- [ ] Workload assessment complete
- [ ] Migration/modernization approach selected
- [ ] Testing and validation plan
- [ ] Cutover plan documented

### Govern

- [ ] Governance policies defined
- [ ] Cost management implemented
- [ ] Compliance requirements mapped
- [ ] Security baselines established

### Secure

- [ ] Identity and access management
- [ ] Network security configured
- [ ] Data protection implemented
- [ ] Threat protection enabled

### Manage

- [ ] Monitoring configured
- [ ] Backup and recovery tested
- [ ] Operations procedures documented
- [ ] Optimization practices established

## MCP Integration

For current CAF documentation, use the microsoft-learn MCP server:

```text
mcp__microsoft-learn__microsoft_docs_search: "cloud adoption framework [topic]"
mcp__microsoft-learn__microsoft_docs_fetch: [specific URL]
```

## Related Resources

- cloud-alignment skill for CAF analysis
- well-architected.md for design principles
- Azure Well-Architected Framework (separate from CAF)

---

**Last Updated:** 2025-12-05
