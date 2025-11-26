# Terraform Deployment Guide

This directory contains Terraform configurations for deploying the OCI API Gateway + OIDC Authentication solution.

## Choose Your Deployment

| Deployment | Use Case | Guide |
|------------|----------|-------|
| **[POC](./poc/)** | Testing, validation, learning | [poc/README.md](./poc/README.md) |
| **[Production](./prod/)** | Enterprise deployment | [prod/README.md](./prod/README.md) |

## POC vs Production Comparison

```
POC (Simple)                          Production (Enterprise)
─────────────────                     ──────────────────────────

┌──────────┐                          ┌──────────┐
│ Browser  │                          │ Browser  │
└────┬─────┘                          └────┬─────┘
     │                                     │
     ▼                                     ▼
┌─────────────────┐                   ┌─────────────────┐
│  API Gateway    │                   │  Load Balancer  │  ◄── TLS termination
│  (Public)       │                   │  (Public)       │
└────────┬────────┘                   └────────┬────────┘
         │                                     │
         │                                     ▼
         │                            ┌─────────────────┐
         │                            │  API Gateway    │  ◄── Private endpoint
         │                            │  (Private)      │
         │                            │  + NSGs         │
         │                            └────────┬────────┘
         │                                     │ mTLS
         ▼                                     ▼
┌─────────────────┐                   ┌─────────────────┐
│  HTTP Backend   │                   │  HTTP Backend   │
│                 │                   │  mTLS Required  │
└─────────────────┘                   └─────────────────┘
```

| Feature | POC | Production |
|---------|-----|------------|
| API Gateway | Public endpoint | Private (behind LB) |
| Load Balancer | None | Flexible LB |
| Backend Connection | HTTP | mTLS |
| Network Security | Basic | Full NSGs |
| Vault Secrets | 2 | 6+ |
| Complexity | Simple | Enterprise-ready |
| Time to Deploy | ~15 min | ~30 min |

## Directory Structure

```
terraform/
├── README.md               # This file (overview)
├── poc/                    # POC deployment
│   ├── README.md           # POC-specific guide
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars.example
├── prod/                   # Production deployment
│   ├── README.md           # Production-specific guide
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── modules/                # Shared modules (used by both)
    ├── cache/              # OCI Cache (Redis)
    ├── functions/          # OCI Functions (all 5)
    ├── apigateway/         # API Gateway + NSGs
    ├── vault/              # OCI Vault + secrets
    ├── compute/            # Backend compute instance
    ├── loadbalancer/       # Flexible Load Balancer
    ├── network/            # VCN/Subnet references
    ├── compartment/        # Compartment management
    ├── identity_domain/    # Identity Domain references
    └── confidential_app/   # OIDC app management
```

## Prerequisites (Both Deployments)

Before deploying either configuration:

1. **OCI CLI configured** with `~/.oci/config`
2. **Terraform installed** (v1.0.0+)
3. **Existing VCN** with public and private subnets
4. **OCI IAM Identity Domain** with Confidential Application
5. **Function images built and pushed** to OCIR

### Build and Push Functions

```bash
# From project root
cd functions/

# Deploy all functions to OCIR
fn deploy --app apigw-oidc-app --all
```

## Quick Start

### Option 1: POC Deployment

```bash
cd terraform/poc
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

See [poc/README.md](./poc/README.md) for detailed instructions.

### Option 2: Production Deployment

```bash
cd terraform/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

See [prod/README.md](./prod/README.md) for detailed instructions.

## Post-Deployment

After either deployment completes:

1. **Note the outputs** (gateway URL, etc.)
2. **Update Identity Domain** redirect URIs to match
3. **Test the deployment**:
   ```bash
   curl https://<gateway-url>/health
   curl -I https://<gateway-url>/welcome  # Should redirect to login
   ```

## Cleanup

```bash
# From poc/ or prod/ directory
terraform destroy
```

## References

- [OCI Terraform Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [Project Documentation](../docs/)
- [FAQ](../docs/FAQ.md)
