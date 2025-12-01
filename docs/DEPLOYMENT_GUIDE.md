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
- **Docker** - Standard Docker Engine or Docker Desktop (NOT Oracle-specific)
  - **Why needed**: OCI Functions run as container images. Docker builds these images from Dockerfiles before deployment. Without Docker, you cannot package and deploy the functions.
  - **How it's used**: Fn CLI uses Docker to build function container images locally, then pushes them to Oracle Container Image Registry (OCIR)
  - **How to install**: [Installing and Configuring Docker](https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsinstalldocker.htm)
  - Download: [Get Docker](https://docs.docker.com/get-docker/)
  - Verify installation: `docker --version`
  - **Note**: This is standard Docker from Docker Inc., not an Oracle product
  - **See also**: [FAQ: Why Docker is required and how does OCIR work?](./FAQ.md#why-docker-is-required-and-how-does-ocir-work)
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
- Identity Domain and Confidential Applications
- Dynamic Groups and Policies

**Recommended approach for non-administrators:**
If you don't have full tenancy administrator access, work with your OCI administrator to create a policy that grants the necessary permissions for these resources in a specific compartment.

### Time Estimate

Full deployment: 60-90 minutes (includes resource provisioning wait times)

---

## Phase 1: Compartment and Networking

### 1.0 Set Global Variables

**Step 1: Get your tenancy OCID using OCI CLI**

```bash
# Use OCI CLI to retrieve your tenancy OCID
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

```bash
# Set your tenancy OCID (paste the output from Step 1)
export TENANCY_OCID=<tenancy-ocid>

# Set your region (change to your target region)
export REGION="us-chicago-1"
```

**Step 3: Verify (optional)**

```bash
# Verify tenancy OCID is set
echo "Tenancy OCID: $TENANCY_OCID"
echo "Region: $REGION"
```

### 1.1 Create Compartment

```bash
# Create compartment for this project
oci iam compartment create \
  --compartment-id $TENANCY_OCID \
  --name "apigw-oidc" \
  --description "API Gateway OIDC Authentication POC"

# Copy the compartment OCID from output
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

```bash
# Get service OCID for "All <region> Services in Oracle Services Network"
export SERVICE_OCID=$(oci network service list --all | jq -r '.data[] | select(.name | contains("All")) | .id')

# Create service gateway
oci network service-gateway create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "apigw-oidc-sgw" \
  --services "[{\"serviceId\": \"$SERVICE_OCID\"}]"

export SGW_OCID=<service-gateway-ocid>
```

### 1.6 Create Route Tables

```bash
# Public route table (for API Gateway)
oci network route-table create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "public-rt" \
  --route-rules "[{\"destination\": \"0.0.0.0/0\", \"destinationType\": \"CIDR_BLOCK\", \"networkEntityId\": \"$IGW_OCID\"}]"

export PUBLIC_RT_OCID=<public-route-table-ocid>

# Private route table (for Functions, Cache, Backend)
oci network route-table create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "private-rt" \
  --route-rules "[{\"destination\": \"0.0.0.0/0\", \"destinationType\": \"CIDR_BLOCK\", \"networkEntityId\": \"$NAT_OCID\"}]"

export PRIVATE_RT_OCID=<private-route-table-ocid>
```

### 1.7 Create Security Lists

```bash
# Public security list
oci network security-list create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "public-sl" \
  --ingress-security-rules '[{"source": "0.0.0.0/0", "protocol": "6", "tcpOptions": {"destinationPortRange": {"min": 443, "max": 443}}}]' \
  --egress-security-rules '[{"destination": "0.0.0.0/0", "protocol": "all"}]'

export PUBLIC_SL_OCID=<public-security-list-ocid>

# Private security list
oci network security-list create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "private-sl" \
  --ingress-security-rules '[{"source": "10.0.0.0/16", "protocol": "all"}]' \
  --egress-security-rules '[{"destination": "0.0.0.0/0", "protocol": "all"}]'

export PRIVATE_SL_OCID=<private-security-list-ocid>
```

### 1.8 Create Subnets

```bash
# Public subnet (for API Gateway)
oci network subnet create \
  --compartment-id $COMPARTMENT_OCID \
  --vcn-id $VCN_OCID \
  --display-name "public-subnet" \
  --cidr-block "10.0.0.0/24" \
  --route-table-id $PUBLIC_RT_OCID \
  --security-list-ids "[\"$PUBLIC_SL_OCID\"]"

export PUBLIC_SUBNET_OCID=<public-subnet-ocid>

# Private subnet (for Functions, Cache, Backend)
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

```bash
# Create vault
oci kms management vault create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-vault" \
  --vault-type DEFAULT

# Get and export vault OCID automatically
export VAULT_OCID=$(oci kms management vault list \
  --compartment-id $COMPARTMENT_OCID \
  --all \
  --query 'data[?"display-name"==`apigw-oidc-vault`].id | [0]' \
  --raw-output)

echo "Vault OCID: $VAULT_OCID"

# Wait for vault to become ACTIVE (2-3 minutes)
# Check vault status - repeat until lifecycle-state shows "ACTIVE"
oci kms management vault get --vault-id $VAULT_OCID --query 'data."lifecycle-state"'

# Once ACTIVE, extract vault management endpoint
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

```bash
# Generate 32-byte random pepper
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

```bash
# We'll update this after creating the Identity Domain app
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

```bash
oci redis redis-cluster create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-cache" \
  --node-count 1 \
  --node-memory-in-gbs 2 \
  --software-version "REDIS_7_0" \
  --subnet-id $PRIVATE_SUBNET_OCID

# Wait for cluster to be ACTIVE (10-15 minutes)
export CACHE_OCID=<cache-cluster-ocid>
```

### 3.2 Get Cache Endpoint

```bash
# Extract cache endpoint
export CACHE_ENDPOINT=$(oci redis redis-cluster redis-cluster \
get --redis-cluster-id $CACHE_OCID | jq -r '.data["primary-fqdn"]')
```

---

## Phase 4: OCI Functions Application

### 4.1 Get Registry Namespace

The Fn CLI will create repositories automatically. Get your registry namespace:

```bash
# Get registry namespace (usually tenancy namespace)
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

```bash
# Set your email for OCIR login
export OCIR_USER_EMAIL="your.email@example.com"

# Create auth token in OCI Console (Identity → Users → Your User → Auth Tokens)
export OCIR_AUTH_TOKEN="your-auth-token"

# List existing contexts
fn list context

# Create new context for this region
fn create context oci-$REGION --provider oracle

# Configure context
fn use context oci-$REGION
fn update context oracle.compartment-id $COMPARTMENT_OCID
fn update context oracle.profile DEFAULT
fn update context api-url https://functions.$REGION.oraclecloud.com
fn update context registry $REGION.ocir.io/$REGISTRY_NAMESPACE/oidc-fn-repo

# Login to container registry
docker login $REGION.ocir.io -u "$REGISTRY_NAMESPACE/oracleidentitycloudservice/$OCIR_USER_EMAIL" -p "$OCIR_AUTH_TOKEN"
```

### 4.4 Deploy Functions

```bash
# Clone repository
git clone https://github.com/timmelander/apigw-iam-oidc-authorizer.git
cd apigw-iam-oidc-authorizer

# Deploy each function
for func in health oidc_authn oidc_callback oidc_logout apigw_authzr; do
  echo "Deploying $func..."
  cd functions/$func
  fn deploy --app apigw-oidc-app
  cd ../..
done
```

### 4.5 Get Function OCIDs

```bash
# Extract function OCIDs automatically
export HEALTH_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "health") | .id')
export OIDC_AUTHN_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_authn") | .id')
export OIDC_CALLBACK_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_callback") | .id')
export OIDC_LOGOUT_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "oidc_logout") | .id')
export AUTHZR_FN_OCID=$(oci fn function list --application-id $FN_APP_OCID --all | jq -r '.data[] | select(.["display-name"] == "apigw_authzr") | .id')

# Verify
echo "Health Function: $HEALTH_FN_OCID"
echo "OIDC Authn Function: $OIDC_AUTHN_FN_OCID"
echo "OIDC Callback Function: $OIDC_CALLBACK_FN_OCID"
echo "OIDC Logout Function: $OIDC_LOGOUT_FN_OCID"
echo "Authorizer Function: $AUTHZR_FN_OCID"
```

---

## Phase 5: API Gateway

### 5.1 Create API Gateway

```bash
oci api-gateway gateway create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name "apigw-oidc-gateway" \
  --endpoint-type PUBLIC \
  --subnet-id $PUBLIC_SUBNET_OCID

# Wait for gateway to be ACTIVE (5-10 minutes)
export GATEWAY_OCID=<api-gateway-ocid>
```

### 5.2 Get Gateway Hostname

```bash
GATEWAY_HOSTNAME=$(oci api-gateway gateway get --gateway-id $GATEWAY_OCID | jq -r '.data.hostname')

export GATEWAY_URL="https://$GATEWAY_HOSTNAME"
```

### 5.3 Create API Deployment

Update `scripts/api_deployment.json` with your function OCIDs, then:

```bash
oci api-gateway deployment create \
  --compartment-id $COMPARTMENT_OCID \
  --gateway-id $GATEWAY_OCID \
  --display-name "oidc-auth-deployment" \
  --path-prefix "/" \
  --specification file://scripts/api_deployment.json

export DEPLOYMENT_OCID=<api-deployment-ocid>
```

---

## Phase 6: Identity Domain Configuration

### 6.1 Create Confidential Application

In OCI Console:

1. Navigate to **Identity & Security** → **Domains** → Your Domain
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
   - Enable **PKCE** (required)
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

1. Use the helper script provided in this project:
   ```bash
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

```bash
# Set the client credentials from step 6.3
export CLIENT_ID=<your-client-id>
export CLIENT_SECRET=<your-client-secret>

# Update secret with actual credentials
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

```bash
# Policy for functions to read secrets
oci iam policy create \
  --compartment-id $COMPARTMENT_OCID \
  --name "oidc-functions-vault-access" \
  --description "Allow OIDC functions to read secrets" \
  --statements '["Allow dynamic-group oidc-functions-dg to read secret-bundles in compartment id '$COMPARTMENT_OCID'"]'

# Policy for API Gateway to invoke functions
oci iam policy create \
  --compartment-id $COMPARTMENT_OCID \
  --name "apigw-functions-invoke" \
  --description "Allow API Gateway to invoke functions" \
  --statements '["Allow any-user to use functions-family in compartment id '$COMPARTMENT_OCID' where ALL {request.principal.type='"'"'ApiGateway'"'"'}"]'
```

---

## Phase 8: Configure Functions

### 8.0 Set Identity Domain URL

```bash
# Set your Identity Domain base URL (from OCI Console → Identity → Domains)
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

```bash
# Get the first availability domain
export AVAILABILITY_DOMAIN=$(oci iam availability-domain list --compartment-id $COMPARTMENT_OCID | jq -r '.data[0].name')

# Get Oracle Linux 8 image OCID for your region
# Note: Images are in the tenancy root compartment
export BACKEND_IMAGE_OCID=$(oci compute image list \
  --compartment-id $TENANCY_OCID \
  --operating-system "Oracle Linux" \
  --operating-system-version "8" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --limit 1 \
  | jq -r '.data[0].id')

# Launch instance
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

SSH into the instance and run:

```bash
sudo dnf install -y httpd
sudo systemctl enable --now httpd

# Create test pages
echo "<h1>Welcome</h1>" | sudo tee /var/www/html/index.html
echo "<h1>Logged Out</h1>" | sudo tee /var/www/html/logged-out.html
```

### 9.3 Get Backend IP Address

```bash
# Get the private IP of the backend instance
export BACKEND_IP=$(oci compute instance list-vnics \
  --instance-id $BACKEND_INSTANCE_OCID \
  | jq -r '.data[0]["private-ip"]')

echo "Backend IP: $BACKEND_IP"
```

### 9.4 Update API Deployment

Update `scripts/api_deployment.json` with the backend IP address (`$BACKEND_IP`).

---

## Phase 10: Verification

### 10.1 Health Check

```bash
curl -s $GATEWAY_URL/health | jq
```

Expected: `{"status": "healthy", ...}`

### 10.2 Login Flow

```bash
# Check login redirect
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

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues and solutions.

## Next Steps

- [CONFIGURATION.md](./CONFIGURATION.md) - Customize settings
- [SECURITY.md](./SECURITY.md) - Production hardening
- [DEVELOPMENT.md](./DEVELOPMENT.md) - Extend the solution
