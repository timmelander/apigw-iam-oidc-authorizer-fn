# POC Deployment Guide

Simplified deployment for testing, validation, and learning the OCI API Gateway + OIDC Authentication solution.

## Architecture

```
┌──────────┐
│ Browser  │
└────┬─────┘
     │ HTTPS
     ▼
┌─────────────────┐
│  API Gateway    │  ◄── Public endpoint (OCI-managed TLS)
│  (Public)       │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐  ┌────────────┐
│ OCI   │  │  Backend   │
│ Funcs │  │  (HTTP)    │
└───┬───┘  └────────────┘
    │
    ▼
┌───────────┐
│ OCI Cache │  ◄── Session storage
│ (Redis)   │
└───────────┘
```

## What Gets Created

| Resource | Description |
|----------|-------------|
| OCI Cache Cluster | Redis for session storage |
| OCI Vault + Key | Secrets encryption |
| 2 Vault Secrets | Client credentials + HKDF pepper |
| Functions App | 5 functions (health, authn, callback, authzr, logout) |
| Dynamic Group | For function Vault access |
| IAM Policy | Function → Vault read permission |
| API Gateway | Public endpoint |
| API Deployment | Routes with custom authorizer |

## Prerequisites

### 1. OCI CLI Configured

```bash
# Verify OCI CLI works
oci iam region list --output table
```

### 2. Existing Network

You need an existing VCN with:
- **Public subnet** - For API Gateway
- **Private subnet** - For Functions and OCI Cache

### 3. Identity Domain + Confidential App

Create a Confidential Application in your OCI IAM Identity Domain:
- **Application type**: Confidential Application
- **Allowed grant types**: Authorization Code
- **Redirect URL**: `https://<gateway-hostname>/auth/callback` (update after deployment)
- **Post-logout redirect**: `https://<gateway-hostname>/logged-out`
- **Scopes**: `openid`, `profile`, `email`, `groups`

### 4. Functions Built and Pushed

```bash
# From project root
cd functions/

# Login to OCIR
podman login <region>.ocir.io -u '<namespace>/oracleidentitycloudservice/<email>'

# Deploy all functions
fn deploy --app apigw-oidc-app --all
```

## Deployment Steps

### Step 1: Configure Variables

```bash
cd terraform/poc
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Required - OCI Authentication
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaaexample"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaaexample"
region           = "us-chicago-1"

# Required - Network
public_subnet_ocid  = "ocid1.subnet.oc1.us-chicago-1.aaaaaaaaexample"
private_subnet_ocid = "ocid1.subnet.oc1.us-chicago-1.aaaaaaaaexample"

# Required - Identity Domain
oci_iam_base_url   = "https://idcs-xxxxxxxx.identity.oraclecloud.com"
oidc_client_id     = "your-client-id"
oidc_client_secret = "your-client-secret"

# Required - Functions
container_repo   = "iad.ocir.io/your-namespace/oidc-fn-repo"
function_version = "0.0.1"

# Required - Backend
backend_url = "http://10.0.1.100"

# Optional
label_prefix = "oidc-poc"
```

### Step 2: Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

### Step 3: Update Identity Domain

After deployment, update your Confidential App redirect URIs:

```bash
# Get the gateway URL from outputs
terraform output gateway_url

# Update in Identity Domain Console:
# - Redirect URL: https://<gateway-url>/auth/callback
# - Post-logout redirect: https://<gateway-url>/logged-out
```

Or use the provided script:
```bash
python3 ../../scripts/update_app_redirect_uris.py \
  --app-id <app-id> \
  --redirect-uri "https://<gateway-url>/auth/callback" \
  --post-logout-uri "https://<gateway-url>/logged-out"
```

## Testing

```bash
# Set gateway URL
GATEWAY_URL=$(terraform output -raw gateway_url)

# 1. Health check (anonymous)
curl $GATEWAY_URL/health

# 2. Protected route (should redirect to login)
curl -I $GATEWAY_URL/welcome

# 3. Login flow (open in browser)
echo "Open: $GATEWAY_URL/auth/login"
```

## Outputs

| Output | Description |
|--------|-------------|
| `gateway_url` | Public API Gateway URL |
| `cache_endpoint` | OCI Cache FQDN |
| `functions_app_id` | Functions application OCID |
| `vault_id` | Vault OCID |

## Cleanup

```bash
terraform destroy
```

## Troubleshooting

### Function Invocation Errors

Check function logs:
```bash
fn invoke apigw-oidc-app health
oci logging-search search-logs --search-query 'search "<compartment-ocid>/apigw-oidc" | sort by datetime desc'
```

### Cache Connection Issues

Verify private subnet has route to OCI Cache service:
```bash
oci redis redis-cluster get --redis-cluster-id <cache-cluster-id>
```

### Gateway Returns 502

Check that backend URL is reachable from the private subnet.

## Next Steps

Once POC is validated, consider the [Production deployment](../prod/) for:
- Private API Gateway behind Load Balancer
- mTLS backend communication
- Full Network Security Groups
- Compute instance with Apache backend
