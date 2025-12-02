# Production Deployment Guide

Enterprise-grade deployment with private API Gateway, Load Balancer, mTLS, and full network security.

## Architecture

```
┌──────────┐
│ Browser  │
└────┬─────┘
     │ HTTPS
     ▼
┌─────────────────┐
│  Load Balancer  │  ◄── Public IP, TLS termination
│  (Flexible LB)  │
└────────┬────────┘
         │ HTTPS
         ▼
┌─────────────────┐
│  API Gateway    │  ◄── Private endpoint
│  (Private)      │
│  + NSGs         │
└────────┬────────┘
         │ mTLS
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐  ┌────────────┐
│ OCI   │  │  Compute   │  ◄── Apache with mTLS
│ Funcs │  │  (Private) │
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
| Compartment | Optional - can use existing |
| Network references | VCN, public/private subnets |
| Identity Domain | Optional - can use existing |
| Confidential App | OIDC client (creates or updates existing) |
| OCI Vault + Key | Master encryption key |
| 6+ Vault Secrets | Client secret, mTLS certs/keys, server cert |
| Functions App | 3+ functions (health, callback, logout) |
| Compute Instance | Apache HTTP server with mTLS |
| API Gateway | Private endpoint with NSGs |
| Load Balancer | Flexible LB with public IP |
| NSGs | Network Security Groups for all tiers |

## Prerequisites

### 1. OCI CLI and Terraform

```bash
# Verify OCI CLI
oci iam region list --output table

# Verify Terraform
terraform version  # Requires >= 1.0.0
```

### 2. Existing Network Infrastructure

- VCN with public and private subnets
- Internet Gateway for public subnet
- NAT Gateway for private subnet (Functions need outbound access)
- Service Gateway for OCI services

### 3. Identity Domain

An existing OCI IAM Identity Domain with a Confidential Application, or allow Terraform to create one.

### 4. mTLS Certificates

Generate certificates for mTLS communication:

```bash
# Create CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -key ca.key -out ca.crt -subj "/CN=Internal CA"

# API Gateway client cert (for connecting to Apache)
openssl genrsa -out apigw_client.key 2048
openssl req -new -key apigw_client.key -out apigw_client.csr -subj "/CN=apigw-client"
openssl x509 -req -days 365 -in apigw_client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out apigw_client.crt

# Apache server cert
openssl genrsa -out apache_localhost.key 2048
openssl req -new -key apache_localhost.key -out apache_localhost.csr -subj "/CN=localhost"
openssl x509 -req -days 365 -in apache_localhost.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out apache_localhost.crt

# Apache mTLS client cert (for verifying API Gateway)
openssl genrsa -out apache_mtls_client.key 2048
openssl req -new -key apache_mtls_client.key -out apache_mtls_client.csr -subj "/CN=apache-mtls-client"
openssl x509 -req -days 365 -in apache_mtls_client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out apache_mtls_client.crt
```

### 5. Functions Built and Pushed

```bash
cd functions/
podman login <region>.ocir.io -u '<namespace>/oracleidentitycloudservice/<email>'
fn deploy --app apigw-oidc-app --all
```

### 6. SSH Key Pair

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/oci_compute_key
```

## Deployment Steps

### Step 1: Configure Variables

```bash
cd terraform/prod
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# OCI Authentication
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaaexample"
compartment_ocid = "ocid1.compartment.oc1..aaaaaaaaexample"
region           = "us-chicago-1"

# Network
vcn_ocid            = "ocid1.vcn.oc1.us-chicago-1.example"
public_subnet_ocid  = "ocid1.subnet.oc1.us-chicago-1.public-example"
private_subnet_ocid = "ocid1.subnet.oc1.us-chicago-1.private-example"
load_balancer_subnet_cidr = "10.0.1.0/24"
api_gateway_subnet_cidr   = "10.0.2.0/24"

# Identity Domain
oci_iam_domain_ocid = "ocid1.domain.oc1..example"
oci_iam_base_url    = "https://idcs-xxxxxxxx.identity.oraclecloud.com"
oidc_client_id      = "your-client-id"

# Compute
ssh_public_key         = "ssh-rsa AAAAB3... your-key"
compute_instance_shape = "VM.Standard.E4.Flex"
compute_image_ocid     = "ocid1.image.oc1.us-chicago-1.example"

# Functions
oci_functions_container_repo = "iad.ocir.io/namespace/oidc-fn-repo"

# mTLS Certificates (use heredoc syntax)
apache_mtls_client_cert_pem = <<-EOT
-----BEGIN CERTIFICATE-----
... content of apache_mtls_client.crt ...
-----END CERTIFICATE-----
EOT

apache_mtls_client_key_pem = <<-EOT
-----BEGIN RSA PRIVATE KEY-----
... content of apache_mtls_client.key ...
-----END RSA PRIVATE KEY-----
EOT

apigw_mtls_client_cert_pem = <<-EOT
-----BEGIN CERTIFICATE-----
... content of apigw_client.crt ...
-----END CERTIFICATE-----
EOT

apigw_mtls_client_key_pem = <<-EOT
-----BEGIN RSA PRIVATE KEY-----
... content of apigw_client.key ...
-----END RSA PRIVATE KEY-----
EOT

apache_server_cert_pem = <<-EOT
-----BEGIN CERTIFICATE-----
... content of apache_localhost.crt ...
-----END CERTIFICATE-----
EOT

# Load Balancer
lb_domain_name = "oidc-auth.example.com"

# Naming
label_prefix = "oidc-auth-prod"
```

### Step 2: Initialize and Apply

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 3: Update Identity Domain Redirect URIs

```bash
# Get Load Balancer IP
LB_IP=$(terraform output -raw load_balancer_public_ip)

# Update Confidential App redirect URIs
python3 ../../scripts/update_app_redirect_uris.py \
  --app-id <app-id> \
  --redirect-uri "https://$LB_IP/auth/callback" \
  --post-logout-uri "https://$LB_IP/logged-out"
```

### Step 4: Configure Apache (if needed)

SSH to compute instance and verify Apache configuration:

```bash
COMPUTE_IP=$(terraform output -raw apache_compute_public_ip)
ssh -i ~/.ssh/oci_compute_key opc@$COMPUTE_IP

# Verify Apache is running with mTLS
sudo systemctl status httpd
sudo cat /etc/httpd/conf.d/ssl.conf | grep -E "(SSLVerifyClient|SSLCACertificateFile)"
```

## Testing

```bash
# Get Load Balancer URL
LB_IP=$(terraform output -raw load_balancer_public_ip)

# 1. Health check
curl -k https://$LB_IP/health

# 2. Protected route (redirects to login)
curl -kI https://$LB_IP/welcome

# 3. Full login flow (open in browser)
echo "Open: https://$LB_IP/auth/login"
```

## Outputs

| Output | Description |
|--------|-------------|
| `load_balancer_public_ip` | Public entry point |
| `api_gateway_deployment_endpoint` | Private gateway URL |
| `apache_compute_public_ip` | For SSH access |
| `apache_compute_private_ip` | Backend IP |
| `vault_ocid` | Secrets vault |
| Various secret OCIDs | Vault secret references |

## Security Considerations

### Network Security Groups

The deployment creates NSGs that restrict:
- Load Balancer: Accepts HTTPS from internet
- API Gateway: Accepts only from Load Balancer subnet
- Compute: Accepts only from API Gateway subnet
- Functions: Outbound only to OCI services

### mTLS

- API Gateway presents client certificate to Apache
- Apache verifies client certificate against CA
- Ensures only authorized API Gateway can access backend

### Secrets Management

All sensitive data stored in OCI Vault:
- OIDC client credentials
- mTLS certificates and keys
- HKDF pepper for session encryption

## Cleanup

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Warning**: This will delete all data including:
- OCI Cache sessions
- Vault secrets
- Compute instance

## Troubleshooting

### Load Balancer Health Check Failing

```bash
# Check backend set health
oci lb backend-health get --backend-set-name <name> --load-balancer-id <lb-id>
```

### API Gateway 502 Errors

1. Verify mTLS certificates are correct
2. Check NSG rules allow traffic
3. Verify Apache is listening on correct port

### Certificate Errors

```bash
# Verify certificate chain
openssl verify -CAfile ca.crt apigw_client.crt
openssl verify -CAfile ca.crt apache_localhost.crt
```

## Migration from POC

To migrate from POC to Production:

1. Export session data from POC OCI Cache (if needed)
2. Deploy Production configuration
3. Update DNS/redirect URIs to point to Load Balancer IP
4. Import session data to Production OCI Cache
5. Destroy POC deployment
