# Deployment Guide

This guide walks you through deploying the OCI API Gateway + OIDC Authentication solution in a fresh OCI tenancy.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Phase 1: Compartment and Networking](#phase-1-compartment-and-networking)
- [Phase 2: OCI Vault and Secrets](#phase-2-oci-vault-and-secrets)
- [Phase 3: OCI Cache (Redis)](#phase-3-oci-cache-redis)
- [Phase 4: OCI Functions Application](#phase-4-oci-functions-application)
- [Phase 5: API Gateway](#phase-5-api-gateway)
- [Phase 6: Identity Domain Configuration](#phase-6-identity-domain-configuration)
- [Phase 7: IAM Policies](#phase-7-iam-policies)
- [Phase 8: Configure Functions](#phase-8-configure-functions)
- [Phase 9: Backend Setup (Optional)](#phase-9-backend-setup-optional)
- [Phase 10: Verification](#phase-10-verification)
- [Phase 11: Function Warmup (Optional)](#phase-11-function-warmup-optional)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

---

## Prerequisites

### Required Tools

- **OCI CLI** - Configured with API keys for your tenancy
  - Installation and setup instructions: [OCI CLI Configuration](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm)
  - Verify installation: `oci --version`
  - Verify configuration: `oci iam region list`
  - Default config location: `~/.oci/config`
- **Fn CLI** - For deploying OCI Functions
  - Installation guide: [Installing the Fn Project CLI](https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsinstallfncli.htm)
- **Podman** - Container runtime for building and pushing function images
  - **Why needed**: OCI Functions run as container images. Podman builds these images from Dockerfiles before deployment. Without Podman, you cannot package and deploy the functions.
  - **How it's used**: Fn CLI uses Podman to build function container images locally, then pushes them to Oracle Container Image Registry (OCIR)
  - **Why Podman**: Podman is the default container runtime on Oracle Linux 8+, is daemonless, and runs rootless by default
  - Installation:
    - **Oracle Linux / RHEL**: `sudo dnf install podman` (usually pre-installed)
    - **macOS**: `brew install podman && podman machine init && podman machine start`
    - **Ubuntu/Debian**: `sudo apt-get install podman`
  - Verify installation: `podman --version`
  - **For Fn CLI compatibility**: Install `podman-docker` to create a `docker` symlink: `sudo dnf install podman-docker`
  - **See also**: [FAQ: Why Podman is required and how does OCIR work?](./FAQ.md#why-podman-is-required-and-how-does-ocir-work)
  - **Docker alternative**: If you prefer Docker, you can substitute `docker` for `podman` in all commands throughout this guide. Install Docker from [docs.docker.com/get-docker](https://docs.docker.com/get-docker/)
- **Git** - For cloning the repository and accessing the function code
  - **Why needed**: The function source code, Dockerfiles, and deployment scripts are hosted on GitHub. Git is required to download (clone) the repository.
  - Installation:
    - **Linux**: `sudo apt-get install git` (Debian/Ubuntu) or `sudo yum install git` (RHEL/CentOS)
    - **macOS**: `brew install git` or [Git for macOS](https://git-scm.com/download/mac)
    - **Windows**: [Git for Windows](https://git-scm.com/download/win)
  - Official documentation: [Getting Started - Installing Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - Verify installation: `git --version`
- **jq** - For JSON parsing (optional but helpful)
  - Installation: [Download jq](https://jqlang.github.io/jq/download/)

### Required OCI Permissions

Your user needs permissions to create/manage the following resources. If you're new to OCI IAM (Identity and Access Management), policies control who can access which resources in your tenancy.

**Getting Started with IAM Policies:**
- OCI uses policy statements to grant permissions (e.g., `Allow group Developers to manage functions-family in compartment ProjectA`)
- You need to be a tenancy administrator or have sufficient permissions to create these resources
- Official guide: [Getting Started with Policies](https://docs.oracle.com/en-us/iaas/Content/Identity/Concepts/policygetstarted.htm#Getting_Started_with_Policies)

**Resources requiring permissions:**

- Compartments
- Virtual Cloud Networks (VCN)
- Subnets and Security Lists
- API Gateway
- Functions Application and Functions
- OCI Cache (Redis)
- Vault and Secrets
- Identity Domain and Confidential Applications (can be the Default Identity Domain or a secondary Identity Domain)
- Dynamic Groups and Policies

**Recommended approach for non-administrators:**
If you don't have full tenancy administrator access, work with your OCI administrator to create a policy that grants the necessary permissions for these resources in a specific compartment.

### Time Estimate

Full deployment: 60-90 minutes (includes resource provisioning wait times)

### Important: Cold Start Latency

> **Note:** OCI Functions experience "cold starts" when idle for 5-15 minutes. The first request after idle may take 30-60+ seconds per function. Since the authentication flow involves multiple functions, initial requests can take 90-180+ seconds. See [Phase 11: Function Warmup](#phase-11-function-warmup-optional) for solutions to keep functions warm.

---

## Phase 1: Compartment and Networking

### 1.0 Set Global Variables

**Step 1: Get your tenancy OCID using OCI CLI**

Use OCI CLI to retrieve your tenancy OCID:
```bash
oci iam compartment list \
  --all \
  --compartment-id-in-subtree true \
  --access-level ACCESSIBLE \
  --include-root \
  --raw-output \
  --query "data[?contains(\"id\",'tenancy')].id | [0]"
```

This command will output your tenancy OCID (e.g., `ocid1.tenancy.oc1..aaaaaaaa...`)

**Step 2: Set environment variables**

Set your tenancy OCID (paste the output from Step 1) and region (change to your target region):
```bash
export TENANCY_OCID=<tenancy-ocid>
export REGION="us-chicago-1"
```

**Step 3: Verify (optional)**

Verify tenancy OCID is set:
```bash
echo "Tenancy OCID: $TENANCY_OCID"
echo "Region: $REGION"
```

### 1.1 Create Compartment

Create compartment for this project, then copy the compartment OCID from the output and set it:

```bash
oci iam compartment create \
  --compartment-id $TENANCY_OCID \
  --name "apigw-oidc" \
  --description "API Gateway OIDC Authentication POC"

export COMPARTMENT_OCID=<compartment-ocid>
```

### 1.2 Create VCN

```bash
oci network vcn create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-vcn" \
  --cidr-blocks '["10.0.0.0/16"]'

export VCN_OCID=<vcn-ocid>
```

### 1.3 Create Internet Gateway

```bash
oci network internet-gateway create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "apigw-oidc-igw" \
  --is-enabled true

export IGW_OCID=<internet-gateway-ocid>
```

### 1.4 Create NAT Gateway

```bash
oci network nat-gateway create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "apigw-oidc-nat"

export NAT_OCID=<nat-gateway-ocid>
```

### 1.5 Create Service Gateway

Get the service OCID, create the service gateway, then set the OCID:

```bash
export SERVICE_OCID=$(oci network service list --all | jq -r '.data[] | select(.name | contains("All")) | .id')

oci network service-gateway create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "apigw-oidc-sgw" \
  --services "[{\"serviceId\": \"$SERVICE_OCID\"}]"

export SGW_OCID=<service-gateway-ocid>
```

### 1.6 Create Route Tables

**Public route table** (for API Gateway):

```bash
oci network route-table create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "public-rt" \
  --route-rules "[{\"destination\": \"0.0.0.0/0\", \"destinationType\": \"CIDR_BLOCK\", \"networkEntityId\": \"$IGW_OCID\"}]"

export PUBLIC_RT_OCID=<public-route-table-ocid>
```

**Private route table** (for Functions, Cache, Backend):

```bash
oci network route-table create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "private-rt" \
  --route-rules "[{\"destination\": \"0.0.0.0/0\", \"destinationType\": \"CIDR_BLOCK\", \"networkEntityId\": \"$NAT_OCID\"}]"

export PRIVATE_RT_OCID=<private-route-table-ocid>
```

### 1.7 Create Security Lists

**Public security list:**

```bash
oci network security-list create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "public-sl" \
  --ingress-security-rules '[{"source": "0.0.0.0/0", "protocol": "6", "tcpOptions": {"destinationPortRange": {"min": 443, "max": 443}}}]' \
  --egress-security-rules '[{"destination": "0.0.0.0/0", "protocol": "all"}]'

export PUBLIC_SL_OCID=<public-security-list-ocid>
```

**Private security list:**

```bash
oci network security-list create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "private-sl" \
  --ingress-security-rules '[{"source": "10.0.0.0/16", "protocol": "all"}]' \
  --egress-security-rules '[{"destination": "0.0.0.0/0", "protocol": "all"}]'

export PRIVATE_SL_OCID=<private-security-list-ocid>
```

### 1.8 Create Subnets

**Public subnet** (for API Gateway):

```bash
oci network subnet create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "public-subnet" \
  --cidr-block "10.0.0.0/24" \
  --route-table-id $PUBLIC_RT_OCID \
  --security-list-ids "[\"$PUBLIC_SL_OCID\"]"

export PUBLIC_SUBNET_OCID=<public-subnet-ocid>
```

**Private subnet** (for Functions, Cache, Backend):

```bash
oci network subnet create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "private-subnet" \
  --cidr-block "10.0.1.0/24" \
  --prohibit-public-ip-on-vnic true \
  --route-table-id $PRIVATE_RT_OCID \
  --security-list-ids "[\"$PRIVATE_SL_OCID\"]"

export PRIVATE_SUBNET_OCID=<private-subnet-ocid>
```

---

## Phase 2: OCI Vault and Secrets

### 2.1 Create Vault

Create the vault and get the OCID:

```bash
oci kms management vault create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-vault" \
  --vault-type DEFAULT

export VAULT_OCID=$(oci kms management vault list \
  --compartment-id $COMPARTMENT_OCID \
  --all \
  --query 'data[?"display-name"==`apigw-oidc-vault`].id | [0]' \
  --raw-output)

echo "Vault OCID: $VAULT_OCID"
```

Wait for vault to become ACTIVE (2-3 minutes). Check vault status - repeat until lifecycle-state shows "ACTIVE":

```bash
oci kms management vault get --vault-id $VAULT_OCID --query 'data."lifecycle-state"'
```

Once ACTIVE, extract vault management endpoint:

```bash
export VAULT_MGMT_ENDPOINT=$(oci kms management vault get --vault-id $VAULT_OCID --query 'data."management-endpoint"' --raw-output)

echo "Vault Management Endpoint: $VAULT_MGMT_ENDPOINT"
```

### 2.2 Create Master Key

```bash
oci kms management key create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-master-key" \
  --key-shape '{"algorithm": "AES", "length": 32}' \
  --endpoint $VAULT_MGMT_ENDPOINT

export KEY_OCID=<key-ocid>
```

### 2.3 Create HKDF Pepper Secret

Generate a 32-byte random pepper and create the secret:

```bash
PEPPER=$(openssl rand -base64 32)

oci vault secret create-base64 \
  --compartment-id $COMPARTMENT_OCID \
  --vault-id $VAULT_OCID \
  --key-id $KEY_OCID \
  --secret-name "hkdf_pepper" \
  --secret-content-content "$PEPPER"

export PEPPER_SECRET_OCID=<pepper-secret-ocid>
```

### 2.4 Create Client Credentials Secret (Placeholder)

Create a placeholder secret (we'll update this after creating the Identity Domain app):

```bash
oci vault secret create-base64 \
  --compartment-id $COMPARTMENT_OCID \
  --vault-id $VAULT_OCID \
  --key-id $KEY_OCID \
  --secret-name "oidc_client_credentials" \
  --secret-content-content "$(echo -n '{"client_id":"placeholder","client_secret":"placeholder"}' | base64)"

export CLIENT_CREDS_SECRET_OCID=<client-creds-secret-ocid>
```

---

## Phase 3: OCI Cache (Redis)

### 3.1 Create OCI Cache Cluster

Create the Redis cache cluster. Wait for cluster to be ACTIVE (10-15 minutes), then set the OCID:

```bash
oci redis redis-cluster create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-cache" \
  --node-count 1 \
  --node-memory-in-gbs 2 \
  --software-version "REDIS_7_0" \
  --subnet-id $PRIVATE_SUBNET_OCID

export CACHE_OCID=<cache-cluster-ocid>
```

### 3.2 Get Cache Endpoint

Extract the cache endpoint:
```bash
export CACHE_ENDPOINT=$(oci redis redis-cluster redis-cluster get --redis-cluster-id $CACHE_OCID | jq -r '.data["primary-fqdn"]')
```

---

## Phase 4: OCI Functions Application

### 4.1 Get Registry Namespace

The Fn CLI will create repositories automatically. Get your registry namespace (usually the tenancy namespace):

```bash
export REGISTRY_NAMESPACE=$(oci artifacts container configuration get --compartment-id $COMPARTMENT_OCID | jq -r '.data.namespace')
```

### 4.2 Create Functions Application

```bash
oci fn application create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-app" \
  --subnet-ids "[\"$PRIVATE_SUBNET_OCID\"]"

export FN_APP_OCID=<functions-app-ocid>
```

### 4.3 Configure Fn CLI Context

Set your email for OCIR login:

```bash
export OCIR_USER_EMAIL="your.email@example.com"
```

**Create an Auth Token for OCIR Access**

An auth token is required to authenticate with Oracle Cloud Infrastructure Registry (OCIR). You can create one via the OCI Console or CLI.

**Reference Documentation:**
- [CLI: oci iam auth-token](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.71.0/oci_cli_docs/cmdref/iam/auth-token.htm)
- [Console: Getting an Auth Token](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrygettingauthtoken.htm)

**Option 1: Create via CLI (Recommended)**

Get your user OCID, create the auth token, and save it. **IMPORTANT:** Save this token immediately - it cannot be retrieved again after creation:

```bash
export USER_OCID=$(oci iam user list --compartment-id $TENANCY_OCID \
  --query "data[?name=='$OCIR_USER_EMAIL'].id | [0]" --raw-output)

export OCIR_AUTH_TOKEN=$(oci iam auth-token create \
  --user-id $USER_OCID \
  --description "OCIR access for Fn CLI" | jq -r '.data.token')

echo "Auth token created. Save this value securely: $OCIR_AUTH_TOKEN"
```

Example output from `oci iam auth-token create`:

```json
{
  "data": {
    "description": "OCIR access for Fn CLI",
    "id": "ocid1.credential.oc1..<unique_id>",
    "lifecycle-state": "ACTIVE",
    "time-created": "2025-01-15T12:00:00.000000+00:00",
    "token": "<your-auth-token>",
    "user-id": "ocid1.user.oc1..<unique_id>"
  }
}
```

**Option 2: Create via OCI Console**

1. Navigate to **Identity & Security** → **Users** → Your User
2. Under **Resources**, click **Auth Tokens**
3. Click **Generate Token**
4. Enter a description (e.g., "OCIR access for Fn CLI")
5. Click **Generate Token**
6. **Copy the token immediately** - it will not be shown again

Set the auth token from console:
```bash
export OCIR_AUTH_TOKEN="your-auth-token"
```

**Configure Fn CLI**

List existing contexts, create and configure a new context for this region, then login to container registry:

```bash
fn list context

fn create context oci-$REGION --provider oracle
fn use context oci-$REGION
fn update context oracle.compartment-id $COMPARTMENT_OCID
fn update context oracle.profile DEFAULT
fn update context api-url https://functions.$REGION.oraclecloud.com
fn update context registry $REGION.ocir.io/$REGISTRY_NAMESPACE/oidc-fn-repo

podman login $REGION.ocir.io -u "$REGISTRY_NAMESPACE/oracleidentitycloudservice/$OCIR_USER_EMAIL" -p "$OCIR_AUTH_TOKEN"
```

> **Note:** Auth tokens are valid for 90 days by default and each user can have a maximum of 2 auth tokens. If you need to rotate or manage tokens, use `oci iam auth-token list` and `oci iam auth-token delete`. For federated users (IDCS/Identity Domain), the username format for OCIR login is `<namespace>/oracleidentitycloudservice/<email>`. For local OCI users, use `<namespace>/<username>`. See the [Auth Token CLI Reference](https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.71.0/oci_cli_docs/cmdref/iam/auth-token.htm) and [OCIR Authentication Guide](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrygettingauthtoken.htm) for more details.

### 4.4 Deploy Functions

Clone repository and deploy each function:

```bash
git clone https://github.com/timmelander/apigw-iam-oidc-authorizer-fn.git
cd apigw-iam-oidc-authorizer

for func in health oidc_authn oidc_callback oidc_logout apigw_authzr; do
  echo "Deploying $func..."
  cd functions/$func
  fn deploy --app apigw-oidc-app
  cd ../..
done
```

### 4.5 Get Function OCIDs

Extract and verify function OCIDs:

```bash
export HEALTH_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "health") | .id')
export OIDC_AUTHN_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_authn") | .id')
export OIDC_CALLBACK_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_callback") | .id')
export OIDC_LOGOUT_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_logout") | .id')
export AUTHZR_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "apigw_authzr") | .id')

echo "Health Function: $HEALTH_FN_OCID"
echo "OIDC Authn Function: $OIDC_AUTHN_FN_OCID"
echo "OIDC Callback Function: $OIDC_CALLBACK_FN_OCID"
echo "OIDC Logout Function: $OIDC_LOGOUT_FN_OCID"
echo "Authorizer Function: $AUTHZR_FN_OCID"
```

---

## Phase 5: API Gateway

### 5.1 Create API Gateway

Create the API Gateway. Wait for gateway to be ACTIVE (5-10 minutes), then set the OCID:

```bash
oci api-gateway gateway create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-gateway" \
  --endpoint-type PUBLIC \
  --subnet-id $PUBLIC_SUBNET_OCID

export GATEWAY_OCID=<api-gateway-ocid>
```

### 5.2 Get Gateway Hostname

```bash
GATEWAY_HOSTNAME=$(oci api-gateway gateway get --gateway-id $GATEWAY_OCID | jq -r '.data.hostname')

export GATEWAY_URL="https://$GATEWAY_HOSTNAME"
```

### 5.3 Create API Deployment

> **Dependency Note:** This section requires `BACKEND_IP` which is created in [Phase 9: Backend Setup](#phase-9-backend-setup-optional). You have two options:
> 1. **Complete Phase 9 first** (recommended) - Jump to Phase 9, create the backend, then return here
> 2. **Use a placeholder** - Set `export BACKEND_IP="10.0.1.100"` now and update the deployment after Phase 9

The deployment specification template (`scripts/api_deployment.template.json`) contains placeholders that must be replaced with your actual OCIDs before creating the deployment.

**Step 1: Verify required environment variables are set**

The function OCIDs should already be set from [Section 4.5](#45-get-function-ocids). The backend IP requires completing [Phase 9: Backend Setup](#phase-9-backend-setup-optional) first, or you can use a placeholder and update the deployment later.

Verify function OCIDs from Section 4.5 and backend IP from Section 9.3 (or set placeholder if backend not yet deployed - `export BACKEND_IP="10.0.1.x"`):

```bash
echo "Authorizer Function: $AUTHZR_FN_OCID"
echo "Health Function: $HEALTH_FN_OCID"
echo "OIDC Authn Function: $OIDC_AUTHN_FN_OCID"
echo "OIDC Callback Function: $OIDC_CALLBACK_FN_OCID"
echo "OIDC Logout Function: $OIDC_LOGOUT_FN_OCID"
echo "Backend IP: $BACKEND_IP"
```

<details>
<summary><strong>If variables are not set (new shell session)</strong></summary>

Re-fetch all required variables using OCI CLI. First, set COMPARTMENT_OCID then get all function OCIDs:

```bash
export COMPARTMENT_OCID="<your-compartment-ocid>"

export FN_APP_OCID=$(oci fn application list \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-app" \
  --query 'data[0].id' --raw-output)

export HEALTH_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "health") | .id')
export OIDC_AUTHN_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_authn") | .id')
export OIDC_CALLBACK_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_callback") | .id')
export OIDC_LOGOUT_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_logout") | .id')
export AUTHZR_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "apigw_authzr") | .id')

echo "Functions App: $FN_APP_OCID"
echo "Authorizer: $AUTHZR_FN_OCID"
echo "Health: $HEALTH_FN_OCID"
echo "OIDC Authn: $OIDC_AUTHN_FN_OCID"
echo "OIDC Callback: $OIDC_CALLBACK_FN_OCID"
echo "OIDC Logout: $OIDC_LOGOUT_FN_OCID"
```

**Backend IP:** The backend is created in [Phase 9](#phase-9-backend-setup-optional). If the backend is not yet deployed, use a placeholder IP and update the deployment later:

**Option 1:** Use placeholder (update deployment later after Phase 9):

```bash
export BACKEND_IP="10.0.1.100"
```

**Option 2:** If backend already exists (Phase 9 completed):

```bash
export BACKEND_INSTANCE_OCID=$(oci compute instance list \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-backend" \
  --lifecycle-state RUNNING \
  --query 'data[0].id' --raw-output)

export BACKEND_IP=$(oci compute instance list-vnics \
  --instance-id $BACKEND_INSTANCE_OCID \
  | jq -r '.data[0]["private-ip"]')

echo "Backend IP: $BACKEND_IP"
```

</details>

**Step 2: Generate api_deployment.json from template**

Generate api_deployment.json from template (check template exists, replace placeholders, verify):
```bash
[ -f scripts/api_deployment.template.json ] || { echo "ERROR: Template file not found at scripts/api_deployment.template.json"; exit 1; } && \
sed -e "s|<apigw-authzr-fn-ocid>|$AUTHZR_FN_OCID|g" \
    -e "s|<health-fn-ocid>|$HEALTH_FN_OCID|g" \
    -e "s|<oidc-authn-fn-ocid>|$OIDC_AUTHN_FN_OCID|g" \
    -e "s|<oidc-callback-fn-ocid>|$OIDC_CALLBACK_FN_OCID|g" \
    -e "s|<oidc-logout-fn-ocid>|$OIDC_LOGOUT_FN_OCID|g" \
    -e "s|<backend-ip>|$BACKEND_IP|g" \
    scripts/api_deployment.template.json > scripts/api_deployment.json && \
grep -E "<[a-z-]+-ocid>|<backend-ip>" scripts/api_deployment.json && echo "ERROR: Placeholders not replaced!" || echo "OK: All placeholders replaced"
```

**Step 3: Create or update the API Gateway deployment**

Check if deployment already exists, then create or update:
```bash
export DEPLOYMENT_OCID=$(oci api-gateway deployment list \
  --compartment-id $COMPARTMENT_OCID \
  --gateway-id $GATEWAY_OCID \
  --all \
  --query "data.items[?\"display-name\"=='apigw-oidc-deployment'].id | [0]" --raw-output)

if [ -n "$DEPLOYMENT_OCID" ] && [ "$DEPLOYMENT_OCID" != "null" ]; then
  echo "Deployment exists ($DEPLOYMENT_OCID). Updating..."
  oci api-gateway deployment update \
    --deployment-id $DEPLOYMENT_OCID \
    --specification file://scripts/api_deployment.json \
    --force
else
  echo "Creating new deployment..."
  oci api-gateway deployment create \
    --compartment-id $COMPARTMENT_OCID \
    --gateway-id $GATEWAY_OCID \
    --display-name "apigw-oidc-deployment" \
    --path-prefix "/" \
    --specification file://scripts/api_deployment.json

  export DEPLOYMENT_OCID=$(oci api-gateway deployment list \
    --compartment-id $COMPARTMENT_OCID \
    --gateway-id $GATEWAY_OCID \
    --all \
    --query "data.items[?\"display-name\"=='apigw-oidc-deployment'].id | [0]" --raw-output)
fi

echo "Deployment OCID: $DEPLOYMENT_OCID"
```

> **Note:** The template file `api_deployment.template.json` should be committed to version control. The generated `api_deployment.json` (with actual OCIDs) should be in `.gitignore` to avoid committing sensitive OCIDs.

**Step 4: Verify deployment routes**

List all routes configured in the deployment:
```bash
oci api-gateway deployment get --deployment-id $DEPLOYMENT_OCID | jq -r '.data.specification.routes[].path'
```

---

## Phase 6: Identity Domain Configuration

This phase configures the OCI IAM Identity Domain you'll use for authentication. This can be:
- **Default Identity Domain**: Every OCI tenancy has one, suitable for most deployments
- **Secondary Identity Domain**: A separate domain you've created for isolation or testing

Use the Identity Domain associated with the compartment you've been working in throughout this guide.

### 6.1 Create Confidential Application

In OCI Console:

1. Navigate to **Identity & Security** → **Domains** → Select your Identity Domain
2. Click **Integrated applications** → **Add application**
3. Select **Confidential Application**
4. Click **Launch workflow**
5. Configure:
   - **Name**: `apigw-oidc-client`
   - **Description**: API Gateway OIDC Client
6. Click **Submit**

### 6.2 Configure OAuth Settings

1. Select **OAuth configuration** tab
2. Click **Edit OAuth configuration**
3. **Resource server configuration**:
   - Select **No resource server configuration**
4. **Client configuration**:
   - Select **Configure this application as a client now**
5. **Allowed grant types**:
   - Enable **Authorization Code** grant
   - Enable **Refresh token**
6. **Redirect URLs**:
   - **Redirect URL**: `$GATEWAY_URL/auth/callback` (use your gateway URL)
   - **Post-logout redirect URL**: `$GATEWAY_URL/logged-out`
7. Click **Submit**
8. **Activate** the application

### 6.3 Get Client Credentials

1. Click on your application
2. Go to **OAuth configuration**
3. Copy **Client ID** and **Client Secret**

### 6.4 Create Custom Claims

To include user profile data in tokens:

> **Important:** Custom Claims in OCI Identity Domains must be configured via the REST API - there is no UI option in the OCI Console. See the official Oracle documentation: [Managing Custom Claims](https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/custom-claims-token.htm)

1. Use the helper script provided in this project. Set your Identity Domain URL (from OCI Console → Identity → Domains → Domain URL), then run the script:
   ```bash
   export OCI_IAM_BASE_URL="https://idcs-xxxx.identity.oraclecloud.com"

   python scripts/create_groups_claim.py
   ```

2. Or create claims manually via the Identity Domains REST API with the following configuration:

| Claim Name | Value | Include in ID Token |
|------------|-------|---------------------|
| `user_email` | `user.email` | Yes |
| `user_given_name` | `user.givenName` | Yes |
| `user_family_name` | `user.familyName` | Yes |
| `user_groups` | `user.groups[*].name` | Yes |

For more details on Custom Claims and why they are needed, see [FAQ: What are Custom Claims?](./FAQ.md#what-are-custom-claims-and-why-does-this-solution-need-them)

### 6.5 Update Client Credentials Secret

Set the client credentials from step 6.3, then update the secret with actual credentials:

```bash
export CLIENT_ID=<your-client-id>
export CLIENT_SECRET=<your-client-secret>

oci vault secret update-base64 \
  --secret-id $CLIENT_CREDS_SECRET_OCID \
  --secret-content-content "$(echo -n "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\"}" | base64)"
```

### 6.6 Session Settings (Optional)

Configure global session timeout settings for the Identity Domain:

1. Navigate to **Identity & Security** → **Domains** → Your Domain
2. Go to **Settings** → **Session settings**
3. Click **Edit session settings**
4. Configure **Session duration**:
   - **Session duration (in minutes)**: 60
   - **My Apps idle timeout (in minutes)**: 60
5. Click **Save changes**

**Note**: These are global session settings that apply to all applications in the Identity Domain.

---

## Phase 7: IAM Policies

### 7.1 Create Dynamic Group

```bash
oci iam dynamic-group create \
  --compartment-id $TENANCY_OCID \
  --name "oidc-functions-dg" \
  --description "Dynamic group for OIDC functions" \
  --matching-rule "Any {ALL {resource.type = 'fnfunc', resource.compartment.id = '$COMPARTMENT_OCID'}}"

export DG_OCID=<dynamic-group-ocid>
```

### 7.2 Create Policies

Create policy for functions to read secrets, and policy for API Gateway to invoke functions:

```bash
oci iam policy create \
  --compartment-id $COMPARTMENT_OCID \
  --name "oidc-functions-vault-access" \
  --description "Allow OIDC functions to read secrets" \
  --statements '["Allow dynamic-group oidc-functions-dg to read secret-bundles in compartment id '$COMPARTMENT_OCID'"]'

oci iam policy create \
  --compartment-id $COMPARTMENT_OCID \
  --name "apigw-functions-invoke" \
  --description "Allow API Gateway to invoke functions" \
  --statements '["Allow any-user to use functions-family in compartment id '$COMPARTMENT_OCID' where ALL {request.principal.type='"'"'ApiGateway'"'"'}"]'
```

---

## Phase 8: Configure Functions

<details>
<summary><strong>Pre-fetch variables if starting a new shell session</strong></summary>

Set your compartment and tenancy OCIDs, auto-fetch all variables, then verify:

```bash
export COMPARTMENT_OCID="<your-compartment-ocid>"
export TENANCY_OCID="<your-tenancy-ocid>"
export APIGW_DEPLOYMENT_NAME="apigw-oidc-deployment"
export SUPPRESS_LABEL_WARNING=True

export OCI_IAM_BASE_URL=$(oci iam domain list --compartment-id $TENANCY_OCID --all --query 'data[0].url' --raw-output)
export FN_APP_OCID=$(oci fn application list --compartment-id $COMPARTMENT_OCID --all --display-name "apigw-oidc-app" --query 'data[0].id' --raw-output)
export OIDC_AUTHN_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all --query 'data[?"display-name"==`oidc_authn`].id | [0]' --raw-output)
export OIDC_CALLBACK_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all --query 'data[?"display-name"==`oidc_callback`].id | [0]' --raw-output)
export OIDC_LOGOUT_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all --query 'data[?"display-name"==`oidc_logout`].id | [0]' --raw-output)
export AUTHZR_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all --query 'data[?"display-name"==`apigw_authzr`].id | [0]' --raw-output)
export GATEWAY_URL=$(oci api-gateway deployment list --compartment-id $COMPARTMENT_OCID --all --query "data.items[?\"display-name\"=='${APIGW_DEPLOYMENT_NAME}'].endpoint | [0]" --raw-output | sed 's:/$::')
export VAULT_OCID=$(oci kms management vault list --compartment-id $COMPARTMENT_OCID --all --query 'data[?contains("display-name", `apigw-oidc`)].id | [0]' --raw-output)
export CLIENT_CREDS_SECRET_OCID=$(oci vault secret list --compartment-id $COMPARTMENT_OCID --vault-id $VAULT_OCID --all --name "oidc_client_credentials" --query 'data[0].id' --raw-output)
export PEPPER_SECRET_OCID=$(oci vault secret list --compartment-id $COMPARTMENT_OCID --vault-id $VAULT_OCID --all --name "hkdf_pepper" --query 'data[0].id' --raw-output)
export CACHE_OCID=${CACHE_OCID:-$(oci redis redis-cluster redis-cluster-summary list-redis-clusters --compartment-id $COMPARTMENT_OCID --all | jq -r '.data.items[] | select(."display-name" == "apigw-oidc-cache") | .id')}
export CACHE_ENDPOINT=$(oci redis redis-cluster redis-cluster get --redis-cluster-id $CACHE_OCID | jq -r '.data["primary-fqdn"]')

echo "Identity Domain: $OCI_IAM_BASE_URL"
echo "Gateway URL: $GATEWAY_URL"
echo "Cache Endpoint: $CACHE_ENDPOINT"
echo "Client Creds Secret: $CLIENT_CREDS_SECRET_OCID"
echo "Pepper Secret: $PEPPER_SECRET_OCID"
echo "OIDC Authn: $OIDC_AUTHN_FN_OCID"
echo "OIDC Callback: $OIDC_CALLBACK_FN_OCID"
echo "OIDC Logout: $OIDC_LOGOUT_FN_OCID"
echo "Authorizer: $AUTHZR_FN_OCID"
```

</details>

### 8.0 Set Identity Domain URL

Set your Identity Domain base URL (from OCI Console → Identity → Domains), or use the CLI command from the collapsible section above:
```bash
export OCI_IAM_BASE_URL=<iam-domain-url>
```

### 8.1 Configure oidc_authn

```bash
oci fn function update --function-id $OIDC_AUTHN_FN_OCID \
  --config '{
    "OCI_IAM_BASE_URL": "'$OCI_IAM_BASE_URL'",
    "OIDC_REDIRECT_URI": "'$GATEWAY_URL'/auth/callback",
    "OCI_VAULT_CLIENT_CREDS_OCID": "'$CLIENT_CREDS_SECRET_OCID'",
    "OCI_CACHE_ENDPOINT": "'$CACHE_ENDPOINT'",
    "STATE_TTL_SECONDS": "300"
  }' --force
```

### 8.2 Configure oidc_callback

```bash
oci fn function update --function-id $OIDC_CALLBACK_FN_OCID \
  --config '{
    "OCI_IAM_BASE_URL": "'$OCI_IAM_BASE_URL'",
    "OIDC_REDIRECT_URI": "'$GATEWAY_URL'/auth/callback",
    "OCI_VAULT_CLIENT_CREDS_OCID": "'$CLIENT_CREDS_SECRET_OCID'",
    "OCI_VAULT_PEPPER_OCID": "'$PEPPER_SECRET_OCID'",
    "OCI_CACHE_ENDPOINT": "'$CACHE_ENDPOINT'",
    "SESSION_TTL_SECONDS": "28800",
    "SESSION_COOKIE_NAME": "session_id"
  }' --force
```

### 8.3 Configure apigw_authzr

```bash
oci fn function update --function-id $AUTHZR_FN_OCID \
  --config '{
    "OCI_VAULT_PEPPER_OCID": "'$PEPPER_SECRET_OCID'",
    "OCI_CACHE_ENDPOINT": "'$CACHE_ENDPOINT'",
    "SESSION_COOKIE_NAME": "session_id"
  }' --force
```

### 8.4 Configure oidc_logout

```bash
oci fn function update --function-id $OIDC_LOGOUT_FN_OCID \
  --config '{
    "OCI_IAM_BASE_URL": "'$OCI_IAM_BASE_URL'",
    "OCI_CACHE_ENDPOINT": "'$CACHE_ENDPOINT'",
    "POST_LOGOUT_REDIRECT_URI": "'$GATEWAY_URL'/logged-out",
    "SESSION_COOKIE_NAME": "session_id"
  }' --force
```

---

## Phase 9: Backend Setup (Optional)

For testing, deploy a simple backend:

### 9.1 Create Compute Instance

Get the availability domain and Oracle Linux 10 image OCID, launch the instance, then set the instance OCID:

```bash
export AVAILABILITY_DOMAIN=$(oci iam availability-domain list --compartment-id $COMPARTMENT_OCID --all | jq -r '.data[0].name')

export BACKEND_IMAGE_OCID=$(oci compute image list \
  --compartment-id $TENANCY_OCID \
  --all \
  --operating-system "Oracle Linux" \
  --operating-system-version "10" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  | jq -r '.data[0].id')

oci compute instance launch \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-backend" \
  --availability-domain "$AVAILABILITY_DOMAIN" \
  --shape "VM.Standard.E4.Flex" \
  --shape-config '{"ocpus": 1, "memoryInGBs": 8}' \
  --subnet-id $PRIVATE_SUBNET_OCID \
  --image-id "$BACKEND_IMAGE_OCID" \
  --assign-public-ip false \
  --ssh-authorized-keys-file ~/.ssh/id_rsa.pub

export BACKEND_INSTANCE_OCID=<backend-instance-ocid>
```

### 9.2 Install Apache

SSH into the instance and run the following to install Apache, start it, and create test pages:

```bash
sudo dnf install -y httpd
sudo systemctl enable --now httpd

echo "<h1>Welcome</h1>" | sudo tee /var/www/html/index.html
echo "<h1>Logged Out</h1>" | sudo tee /var/www/html/logged-out.html
```

### 9.3 Get Backend IP Address

Get the private IP of the backend instance:
```bash
export BACKEND_IP=$(oci compute instance list-vnics \
  --instance-id $BACKEND_INSTANCE_OCID \
  | jq -r '.data[0]["private-ip"]')

echo "Backend IP: $BACKEND_IP"
```

### 9.4 Update API Deployment

Now that the backend is deployed, regenerate the deployment JSON and update the API Gateway:

```bash
sed -e "s|<apigw-authzr-fn-ocid>|$AUTHZR_FN_OCID|g" \
    -e "s|<health-fn-ocid>|$HEALTH_FN_OCID|g" \
    -e "s|<oidc-authn-fn-ocid>|$OIDC_AUTHN_FN_OCID|g" \
    -e "s|<oidc-callback-fn-ocid>|$OIDC_CALLBACK_FN_OCID|g" \
    -e "s|<oidc-logout-fn-ocid>|$OIDC_LOGOUT_FN_OCID|g" \
    -e "s|<backend-ip>|$BACKEND_IP|g" \
    scripts/api_deployment.template.json > scripts/api_deployment.json

oci api-gateway deployment update \
  --deployment-id $DEPLOYMENT_OCID \
  --specification file://scripts/api_deployment.json \
  --force
```

---

## Phase 10: Verification

### 10.1 Health Check

```bash
curl -s $GATEWAY_URL/health | jq
```

Expected: `{"status": "healthy", ...}`

### 10.2 Login Flow

Check login redirect:
```bash
curl -sI $GATEWAY_URL/auth/login | grep Location
```

Expected: `Location: https://idcs-....identity.oraclecloud.com/oauth2/v1/authorize?...`

### 10.3 Protected Route (Unauthenticated)

```bash
curl -sI $GATEWAY_URL/welcome | grep -E "HTTP|Location"
```

Expected: `HTTP/2 302` and `Location: /auth/login`

### 10.4 Full Flow Test

Open `$GATEWAY_URL/welcome` in browser:

1. Should redirect to Identity Domain login
2. Enter credentials + MFA
3. Should redirect back to `/welcome`
4. Should see user information

---

## Phase 11: Function Warmup (Optional)

OCI Functions experience "cold starts" when containers are stopped after idle periods (5-15 minutes). To ensure fast response times, configure periodic warmup using one of these OCI-native solutions.

### Option 1: OCI Resource Scheduler (Recommended)

Use OCI Resource Scheduler to invoke functions on a schedule. See [Appendix A in TROUBLESHOOTING.md](./TROUBLESHOOTING.md#appendix-a-setting-up-oci-resource-scheduler) for detailed setup instructions.

**Summary:** Create a schedule that invokes health and oidc_authn every 5-10 minutes. This keeps the most critical functions warm.

### Option 2: Cron Job on Compute Instance

If you have a compute instance (e.g., the Apache backend), add a cron job.

Edit crontab:
```bash
crontab -e
```

Add warmup calls every 5 minutes:
```
*/5 * * * * curl -s https://<gateway-url>/health > /dev/null 2>&1
*/5 * * * * curl -s -o /dev/null -w '' https://<gateway-url>/auth/login > /dev/null 2>&1
```

### Option 3: OCI Health Checks

Create OCI Health Checks to periodically ping the health endpoint:

1. Navigate to **Observability & Management** → **Health Checks**
2. Click **Create Health Check**
3. Configure:
   - **Name:** `apigw-oidc-warmup`
   - **Protocol:** HTTPS
   - **Target:** `<gateway-hostname>`
   - **Path:** `/health`
   - **Interval:** 5 minutes
4. Click **Create**

> **Note:** OCI Health Checks only support GET requests, so this warms the `health` function. For full warmup, combine with another option.

### Option 4: Load Balancer Health Check

If using an OCI Load Balancer in front of API Gateway, configure the backend health check:

1. Navigate to **Networking** → **Load Balancers** → Your LB
2. Edit the backend set health check:
   - **URL Path:** `/health`
   - **Interval:** 10000 ms (10 seconds)
3. This naturally keeps the health function warm

### Option 5: Post-Deployment Warmup Script

Add a warmup step to your CI/CD pipeline after deploying functions. Create a script like `warmup.sh`:

```bash
#!/bin/bash
GATEWAY_URL="https://<gateway-url>"

echo "Warming up functions..."
curl -s "$GATEWAY_URL/health" > /dev/null
curl -s -o /dev/null "$GATEWAY_URL/auth/login" 2>&1
echo "Warmup complete"
```

### Recommended Approach

For production deployments, use **Option 1 (OCI Resource Scheduler)** or **Option 2 (Cron Job)** to ensure all authentication functions stay warm. The health endpoint alone won't warm the `apigw_authzr` or `oidc_authn` functions.

---

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues and solutions.

## Next Steps

- [CONFIGURATION.md](./CONFIGURATION.md) - Customize settings
- [SECURITY.md](./SECURITY.md) - Production hardening
- [DEV_GUIDE.md](./DEV_GUIDE.md) - Extend the solution
