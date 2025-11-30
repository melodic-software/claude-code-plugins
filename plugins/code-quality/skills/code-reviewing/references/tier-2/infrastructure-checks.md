# Infrastructure and IaC Code Review Checks

## Tier 2 Reference

**Loaded for:** Dockerfile, docker-compose.yml, *.tf, *.tfvars, Kubernetes manifests (*.yaml in k8s/), Helm charts, CI/CD files (.github/workflows/*, .gitlab-ci.yml, Jenkinsfile)

## 1. Cloud/Infrastructure (12-Factor)

- [ ] **Codebase** - One codebase tracked in version control, many deploys
- [ ] **Dependencies** - Explicitly declare and isolate dependencies (package.json, requirements.txt, go.mod)
- [ ] **Config** - Store config in environment variables, never hardcode secrets
- [ ] **Backing services** - Treat backing services (DB, cache, queue) as attached resources
- [ ] **Build, release, run** - Strictly separate build and run stages
- [ ] **Processes** - Execute app as stateless processes (state in backing services)
- [ ] **Port binding** - Export services via port binding (not hardcoded ports)
- [ ] **Concurrency** - Scale out via process model (horizontal scaling)
- [ ] **Disposability** - Fast startup and graceful shutdown
- [ ] **Dev/prod parity** - Keep dev, staging, prod as similar as possible
- [ ] **Logs** - Treat logs as event streams (stdout/stderr, not files)
- [ ] **Admin processes** - Run admin/maintenance tasks as one-off processes

## 2. Dockerfile Best Practices

- [ ] **Multi-stage builds** - Use multi-stage builds to reduce final image size
- [ ] **Base image pinning** - Pin base image to specific version/digest (not `latest`)
- [ ] **Non-root user** - Run container as non-root user (avoid UID 0)
- [ ] **Layer optimization** - Order layers from least to most frequently changing
- [ ] **Minimal layers** - Combine RUN commands to reduce layers
- [ ] **Build cache efficiency** - Copy dependency files before source code
- [ ] **COPY vs ADD** - Prefer COPY over ADD (ADD has implicit behavior)
- [ ] **Secrets handling** - Never embed secrets in image (use build args carefully)
- [ ] **Health checks** - Include HEALTHCHECK instruction
- [ ] **Metadata labels** - Add LABEL for version, maintainer, description
- [ ] **Minimal base images** - Use alpine/distroless when possible
- [ ] **Clean up in same layer** - Remove temp files in same RUN layer (apt clean, rm cache)
- [ ] **WORKDIR instead of cd** - Use WORKDIR for directory changes
- [ ] **Explicit EXPOSE** - Document exposed ports with EXPOSE

## 3. Container Security

- [ ] **Vulnerability scanning** - Scan images for CVEs (Trivy, Snyk, Clair)
- [ ] **Read-only filesystem** - Mount root filesystem as read-only when possible
- [ ] **Drop capabilities** - Drop unnecessary Linux capabilities
- [ ] **Resource limits** - Set CPU/memory limits (not unlimited)
- [ ] **Network policies** - Restrict container network access
- [ ] **Secret management** - Use secrets management (not env vars for sensitive data)
- [ ] **Image signing** - Sign and verify container images (Docker Content Trust)
- [ ] **Private registries** - Use private registries for production images
- [ ] **Minimal attack surface** - Remove unnecessary packages and binaries
- [ ] **Security contexts** - Configure security contexts (runAsNonRoot, allowPrivilegeEscalation: false)

## 4. Kubernetes Patterns

- [ ] **Resource requests/limits** - Set CPU/memory requests and limits
- [ ] **Liveness probes** - Configure liveness probes for crash detection
- [ ] **Readiness probes** - Configure readiness probes for traffic routing
- [ ] **Startup probes** - Use startup probes for slow-starting containers
- [ ] **ConfigMaps for config** - Externalize config with ConfigMaps (not hardcoded)
- [ ] **Secrets for sensitive data** - Use Secrets for passwords, tokens, keys
- [ ] **Labels and selectors** - Use consistent labeling strategy
- [ ] **Namespaces** - Organize resources by namespace
- [ ] **Pod security policies** - Enforce security policies (PSP/PSA)
- [ ] **Service accounts** - Use dedicated service accounts (not default)
- [ ] **Network policies** - Restrict pod-to-pod communication
- [ ] **Rolling updates** - Configure rolling update strategy
- [ ] **Pod disruption budgets** - Set PDBs for high availability
- [ ] **Affinity/anti-affinity** - Use affinity rules for placement
- [ ] **Init containers** - Use init containers for setup tasks

## 5. Terraform Patterns

- [ ] **Module composition** - Break infrastructure into reusable modules
- [ ] **State management** - Use remote state backend (S3, Azure Storage)
- [ ] **State locking** - Enable state locking (DynamoDB, Azure Blob)
- [ ] **Variable validation** - Add validation rules to variables
- [ ] **Output values** - Define outputs for cross-module references
- [ ] **Provider pinning** - Pin provider versions (avoid breaking changes)
- [ ] **Resource tagging** - Apply consistent tags (environment, owner, cost-center)
- [ ] **Naming conventions** - Use consistent naming across resources
- [ ] **Data sources** - Use data sources for existing resources
- [ ] **Lifecycle rules** - Set lifecycle rules (prevent_destroy, ignore_changes)
- [ ] **Conditional resources** - Use count/for_each for conditional creation
- [ ] **Sensitive values** - Mark sensitive outputs appropriately
- [ ] **Module versioning** - Version modules with semantic versioning
- [ ] **Plan before apply** - Always review plan output before apply
- [ ] **Workspaces** - Use workspaces for environment separation (or separate state files)

## 6. CI/CD Pipeline Security

- [ ] **Secrets management** - Store secrets in CI/CD secret stores (not code)
- [ ] **Least privilege** - Grant minimal permissions to CI/CD service accounts
- [ ] **Dependency scanning** - Scan dependencies for vulnerabilities
- [ ] **Code scanning** - Run SAST/DAST in pipeline
- [ ] **Container scanning** - Scan built images before deployment
- [ ] **Signed commits** - Enforce GPG-signed commits
- [ ] **Branch protection** - Protect main branches (required reviews, status checks)
- [ ] **Audit logging** - Log pipeline executions and changes
- [ ] **Approval gates** - Require manual approval for production deploys
- [ ] **Credential rotation** - Rotate CI/CD credentials regularly
- [ ] **Artifact verification** - Verify artifact integrity (checksums, signatures)
- [ ] **Immutable builds** - Build artifacts once, deploy everywhere (no rebuild)

## 7. Infrastructure Testing

- [ ] **Linting** - Lint IaC files (tflint, hadolint, yamllint)
- [ ] **Static analysis** - Run static analysis tools (checkov, tfsec, kube-score)
- [ ] **Unit tests** - Test Terraform modules (Terratest)
- [ ] **Integration tests** - Test infrastructure integration
- [ ] **Policy as code** - Enforce policies (Open Policy Agent, Sentinel)
- [ ] **Dry runs** - Test changes in non-prod before production
- [ ] **Rollback plan** - Document and test rollback procedures
- [ ] **Chaos engineering** - Test resilience with chaos experiments
- [ ] **Load testing** - Validate performance under load
- [ ] **Security testing** - Run security tests (penetration testing)

## 8. GitOps Patterns

- [ ] **Git as source of truth** - All infrastructure defined in Git
- [ ] **Declarative config** - Use declarative configuration (not imperative scripts)
- [ ] **Automated sync** - Use GitOps tools for automated sync (ArgoCD, Flux)
- [ ] **Pull-based deployments** - Prefer pull-based over push-based deployments
- [ ] **Immutable infrastructure** - Replace instead of modifying infrastructure
- [ ] **Version control everything** - Track all config changes in Git
- [ ] **Environment branches/directories** - Separate environments clearly
- [ ] **Automated drift detection** - Detect and reconcile drift
- [ ] **Audit trail** - Git history provides audit trail
- [ ] **Rollback via Git** - Rollback by reverting commits

## 9. Resource Management

- [ ] **Right-sizing** - Size resources appropriately (not over-provisioned)
- [ ] **Auto-scaling** - Configure horizontal/vertical auto-scaling
- [ ] **Spot/preemptible instances** - Use spot instances for fault-tolerant workloads
- [ ] **Resource quotas** - Set namespace/project resource quotas
- [ ] **Cost tagging** - Tag resources for cost allocation
- [ ] **Idle resource cleanup** - Automate cleanup of idle resources
- [ ] **Reserved instances** - Use reserved instances for predictable workloads
- [ ] **Lifecycle policies** - Configure lifecycle policies (S3, blob storage)
- [ ] **Compression** - Enable compression for data transfer
- [ ] **Caching** - Use caching layers (CDN, Redis, etc.)

## 10. Secrets Handling in IaC

- [ ] **Never commit secrets** - No secrets in version control (use .gitignore)
- [ ] **External secret stores** - Use Vault, AWS Secrets Manager, Azure Key Vault
- [ ] **Dynamic secrets** - Generate short-lived credentials when possible
- [ ] **Secret rotation** - Automate secret rotation
- [ ] **Encryption at rest** - Encrypt secrets at rest
- [ ] **Encryption in transit** - Use TLS for secret transmission
- [ ] **Secret scanning** - Scan commits for accidentally committed secrets
- [ ] **Separate secret files** - Keep secrets in separate files (not mixed with config)
- [ ] **Reference by ID** - Reference secrets by ID/ARN (not value)
- [ ] **Audit secret access** - Log and monitor secret access

## 11. Network Policies

- [ ] **Default deny** - Default to deny-all, explicitly allow needed traffic
- [ ] **Namespace isolation** - Isolate namespaces with network policies
- [ ] **Egress control** - Restrict egress traffic to known destinations
- [ ] **Ingress control** - Restrict ingress to specific sources/ports
- [ ] **Service mesh** - Use service mesh for advanced traffic control (Istio, Linkerd)
- [ ] **mTLS** - Enable mutual TLS for service-to-service communication
- [ ] **Network segmentation** - Segment networks by trust level
- [ ] **Firewall rules** - Configure cloud firewall rules
- [ ] **Private endpoints** - Use private endpoints for cloud services
- [ ] **VPN/VPC peering** - Secure cross-network communication

## 12. Observability and Monitoring

- [ ] **Logging** - Centralize logs (ELK, Splunk, CloudWatch)
- [ ] **Metrics** - Collect infrastructure metrics (Prometheus, Datadog)
- [ ] **Tracing** - Implement distributed tracing (Jaeger, Zipkin)
- [ ] **Alerts** - Configure alerts for critical conditions
- [ ] **Dashboards** - Create dashboards for key metrics
- [ ] **Health endpoints** - Expose health check endpoints
- [ ] **Synthetic monitoring** - Test external endpoints periodically
- [ ] **SLO/SLI tracking** - Track service level objectives
- [ ] **Incident response** - Document incident response procedures
- [ ] **Postmortems** - Conduct blameless postmortems after incidents

---

**Last Updated:** 2025-11-28
