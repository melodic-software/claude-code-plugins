# AWS Well-Architected Framework

The Well-Architected Framework provides guidance for building secure, high-performing, resilient, and efficient infrastructure through 6 pillars.

## Well-Architected Pillars

| Pillar | Focus | Key Questions |
| --- | --- | --- |
| **Operational Excellence** | Run and monitor systems | How do you manage workload and events? |
| **Security** | Protect data and systems | How do you manage identities and permissions? |
| **Reliability** | Recover from failures | How do you manage service failures? |
| **Performance Efficiency** | Use resources efficiently | How do you select appropriate resources? |
| **Cost Optimization** | Avoid unnecessary costs | How do you manage usage and cost? |
| **Sustainability** | Minimize environmental impact | How do you reduce carbon footprint? |

## Detailed Pillar Guidance

### 1. Operational Excellence

**Focus:** Run and monitor systems to deliver business value and improve processes.

**Design Principles:**

- Perform operations as code
- Make frequent, small, reversible changes
- Refine operations procedures frequently
- Anticipate failure
- Learn from all operational failures

**Key Areas:**

- Organization (team structure, operating model)
- Prepare (design telemetry, improve flow)
- Operate (understand health, respond to events)
- Evolve (learn and improve)

**Checklist:**

- [ ] Operations as code implemented
- [ ] Documentation maintained
- [ ] Small, frequent changes practiced
- [ ] Failure procedures tested
- [ ] Lessons learned captured

### 2. Security

**Focus:** Protect information, systems, and assets while delivering business value.

**Design Principles:**

- Implement a strong identity foundation
- Enable traceability
- Apply security at all layers
- Automate security best practices
- Protect data in transit and at rest
- Keep people away from data
- Prepare for security events

**Key Areas:**

- Identity and access management
- Detection
- Infrastructure protection
- Data protection
- Incident response

**Checklist:**

- [ ] Strong identity foundation
- [ ] Traceability enabled
- [ ] Security at all layers
- [ ] Risk assessment automated
- [ ] Data protected in transit and at rest

### 3. Reliability

**Focus:** Perform intended function correctly and consistently.

**Design Principles:**

- Automatically recover from failure
- Test recovery procedures
- Scale horizontally
- Stop guessing capacity
- Manage change in automation

**Key Areas:**

- Foundations (service quotas, network topology)
- Workload architecture (distributed design)
- Change management (monitoring, adaptation)
- Failure management (backup, recovery)

**Checklist:**

- [ ] Automatic recovery configured
- [ ] Recovery procedures tested
- [ ] Horizontal scaling enabled
- [ ] Capacity planning in place
- [ ] Change management automated

### 4. Performance Efficiency

**Focus:** Use computing resources efficiently to meet requirements.

**Design Principles:**

- Democratize advanced technologies
- Go global in minutes
- Use serverless architectures
- Experiment more often
- Consider mechanical sympathy

**Key Areas:**

- Selection (compute, storage, database, network)
- Review (performance testing)
- Monitoring (alarms, metrics)
- Trade-offs (caching, read replicas)

**Checklist:**

- [ ] Right-sized resources
- [ ] Global reach where needed
- [ ] Serverless where appropriate
- [ ] Performance monitoring active
- [ ] Experimentation enabled

### 5. Cost Optimization

**Focus:** Run systems at lowest price point while meeting requirements.

**Design Principles:**

- Implement cloud financial management
- Adopt a consumption model
- Measure overall efficiency
- Stop spending money on undifferentiated heavy lifting
- Analyze and attribute expenditure

**Key Areas:**

- Practice cloud financial management
- Expenditure and usage awareness
- Cost-effective resources
- Manage demand and supply
- Optimize over time

**Checklist:**

- [ ] Cloud financial management
- [ ] Expenditure awareness
- [ ] Cost-effective resources
- [ ] Demand management
- [ ] Optimization over time

### 6. Sustainability

**Focus:** Minimize environmental impact of running cloud workloads.

**Design Principles:**

- Understand your impact
- Establish sustainability goals
- Maximize utilization
- Anticipate and adopt new offerings
- Use managed services
- Reduce downstream impact

**Key Areas:**

- Region selection
- User behavior patterns
- Software and architecture patterns
- Data patterns
- Hardware patterns
- Development and deployment process

**Checklist:**

- [ ] Region selection for carbon
- [ ] Resource efficiency
- [ ] Data management practices
- [ ] Software efficiency patterns
- [ ] Hardware lifecycle management

## Well-Architected Alignment Checklist

### Overall Assessment

For each pillar, assess:

- [ ] Design principles understood
- [ ] Best practices implemented
- [ ] Gaps identified
- [ ] Improvement plan created

### Cross-Pillar Considerations

Some decisions affect multiple pillars:

- **Security vs Performance:** Encryption adds latency
- **Reliability vs Cost:** Redundancy costs money
- **Performance vs Cost:** Right-sizing vs over-provisioning
- **Sustainability vs Performance:** Efficiency trade-offs

## Framework Comparison: CAF vs Well-Architected

| Aspect | Microsoft CAF | AWS Well-Architected |
| --- | --- | --- |
| Scope | End-to-end adoption | Workload design |
| Structure | 7 methodologies | 6 pillars |
| Focus | Journey/transformation | Design principles |
| Governance | Strong emphasis | Part of security |
| Sustainability | Part of manage | Dedicated pillar |

### When to Use Which

- **Starting cloud journey:** Microsoft CAF (comprehensive adoption guidance)
- **Designing workloads:** AWS Well-Architected (design review)
- **Both:** Use CAF for strategy/planning, Well-Architected for implementation

## Related Resources

- cloud-alignment skill for framework analysis
- caf-pillars.md for Microsoft CAF
- AWS Well-Architected Tool (console-based review)

---

**Last Updated:** 2025-12-05
