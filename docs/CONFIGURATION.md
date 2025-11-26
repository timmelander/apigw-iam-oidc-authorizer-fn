# Configuration Reference

This document describes all configuration options for the OCI API Gateway + OIDC Authentication solution.

## Environment Variables

### oidc_authn Function

Initiates the OIDC login flow.

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `OCI_IAM_BASE_URL` | Yes | Identity Domain base URL | `https://idcs-xxx.identity.oraclecloud.com` |
| `OIDC_REDIRECT_URI` | Yes | OAuth2 callback URL | `https://<gateway>/auth/callback` |
| `OCI_VAULT_CLIENT_CREDS_OCID` | Yes | Secret OCID for client credentials | `ocid1.vaultsecret.oc1...` |
| `OCI_CACHE_ENDPOINT` | Yes | Redis FQDN | `xxx.redis.region.oci.oraclecloud.com` |
| `STATE_TTL_SECONDS` | No | PKCE state expiration | `300` (default) |

### oidc_callback Function

Handles OAuth2 callback and session creation.

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `OCI_IAM_BASE_URL` | Yes | Identity Domain base URL | `https://idcs-xxx.identity.oraclecloud.com` |
| `OIDC_REDIRECT_URI` | Yes | OAuth2 callback URL (must match login) | `https://<gateway>/auth/callback` |
| `OCI_VAULT_CLIENT_CREDS_OCID` | Yes | Secret OCID for client credentials | `ocid1.vaultsecret.oc1...` |
| `OCI_VAULT_PEPPER_OCID` | Yes | Secret OCID for HKDF pepper | `ocid1.vaultsecret.oc1...` |
| `OCI_CACHE_ENDPOINT` | Yes | Redis FQDN | `xxx.redis.region.oci.oraclecloud.com` |
| `SESSION_TTL_SECONDS` | No | Session duration | `28800` (8 hours, default) |
| `SESSION_COOKIE_NAME` | No | Cookie name | `session_id` (default) |
| `DEFAULT_RETURN_TO` | No | Default redirect after login | `/` (default) |
| `COOKIE_DOMAIN` | No | Cookie domain attribute | `.example.com` |

### apigw_authzr Function

Validates sessions for protected routes.

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `OCI_VAULT_PEPPER_OCID` | Yes | Secret OCID for HKDF pepper | `ocid1.vaultsecret.oc1...` |
| `OCI_CACHE_ENDPOINT` | Yes | Redis FQDN | `xxx.redis.region.oci.oraclecloud.com` |
| `SESSION_COOKIE_NAME` | No | Cookie name to read | `session_id` (default) |

### oidc_logout Function

Handles session termination.

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `OCI_IAM_BASE_URL` | Yes | Identity Domain base URL | `https://idcs-xxx.identity.oraclecloud.com` |
| `OCI_CACHE_ENDPOINT` | Yes | Redis FQDN | `xxx.redis.region.oci.oraclecloud.com` |
| `POST_LOGOUT_REDIRECT_URI` | Yes | URL after IdP logout | `https://<gateway>/logged-out` |
| `SESSION_COOKIE_NAME` | No | Cookie name to clear | `session_id` (default) |
| `COOKIE_DOMAIN` | No | Cookie domain attribute | `.example.com` |

### health Function

Health check endpoint (no configuration required).

---

## OCI Vault Secrets

### oidc_client_credentials

OAuth2 client credentials from Identity Domain.

**Format:** JSON
```json
{
  "client_id": "ec366479cf1f49b99261a2d94291f724",
  "client_secret": "idcscs-174422b2-8ede-4de1-8342-0c2e05a40ac9"
}
```

**Used by:** `oidc_authn`, `oidc_callback`

### hkdf_pepper

Random 32-byte key for session encryption key derivation.

**Format:** Base64-encoded binary
```
k9Hd3+Xt...base64...==
```

**Generation:**
```bash
openssl rand -base64 32
```

**Used by:** `oidc_callback`, `apigw_authzr`

---

## Identity Domain Configuration

### Confidential Application Settings

| Setting | Value | Notes |
|---------|-------|-------|
| **Application Type** | Confidential | Server-side OAuth client |
| **Grant Types** | Authorization Code | Required |
| **PKCE** | Enabled (Required) | S256 challenge method |
| **Redirect URI** | `https://<gateway>/auth/callback` | Must match exactly |
| **Post-logout URI** | `https://<gateway>/logged-out` | Optional |
| **Allowed Scopes** | `openid`, `profile`, `email`, `groups` | Required for full functionality |

### Custom Claims

Custom claims allow user attributes to be included in the ID token.

| Claim Name | Expression | Description |
|------------|------------|-------------|
| `user_email` | `user.email` | User's email address |
| `user_given_name` | `user.givenName` | First name |
| `user_family_name` | `user.familyName` | Last name |
| `user_groups` | `user.groups[*].display` | Group membership |

**Configuration Steps:**

> **Note:** Adding custom claims in OCI IAM Identity Domains is done through the Identity Domains REST API - there is no direct configuration option in the OCI Console UI for this task.

See the official Oracle documentation: [Managing Custom Claims](https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/custom-claims-token.htm)

The REST API allows you to:
1. Create custom claim definitions
2. Map user attributes to token claims
3. Configure which tokens include the claims (ID token, access token)

---

## API Gateway Configuration

### Deployment Specification

The API Gateway deployment is configured via JSON specification (`scripts/api_deployment.json`).

#### Authentication Policy

```json
{
  "requestPolicies": {
    "authentication": {
      "type": "CUSTOM_AUTHENTICATION",
      "functionId": "<apigw_authzr-ocid>",
      "isAnonymousAccessAllowed": true,
      "parameters": {
        "Cookie": "request.headers[Cookie]",
        "User-Agent": "request.headers[User-Agent]"
      },
      "validationFailurePolicy": {
        "type": "MODIFY_RESPONSE",
        "responseCode": "302",
        "responseHeaderTransformations": {
          "setHeaders": {
            "items": [
              {
                "name": "Location",
                "values": ["/auth/login"],
                "ifExists": "OVERWRITE"
              }
            ]
          }
        }
      }
    }
  }
}
```

#### Route Authorization Types

| Type | Behavior |
|------|----------|
| `ANONYMOUS` | No authentication required |
| `AUTHENTICATION_ONLY` | Requires valid session (302 on failure) |

#### Header Transformations

Pass user claims to backend:

```json
{
  "headerTransformations": {
    "setHeaders": {
      "items": [
        {"name": "X-User-Sub", "values": ["${request.auth[sub]}"]},
        {"name": "X-User-Email", "values": ["${request.auth[email]}"]},
        {"name": "X-User-Name", "values": ["${request.auth[name]}"]},
        {"name": "X-User-Groups", "values": ["${request.auth[groups]}"]}
      ]
    }
  }
}
```

---

## Session Configuration

### Session Data

| Field | Description | Source |
|-------|-------------|--------|
| `session_id` | Unique session identifier | Generated (UUID) |
| `user_sub` | User's unique identifier | ID token `sub` claim |
| `email` | User's email | Custom claim |
| `name` | Display name | ID token `name` claim |
| `given_name` | First name | Custom claim |
| `family_name` | Last name | Custom claim |
| `preferred_username` | Username | ID token |
| `groups` | Group membership | Custom claim |
| `id_token` | Original ID token | IdP response |
| `access_token` | Original access token | IdP response |
| `ua_hash` | User-Agent hash | Request header |
| `created_at` | Session creation time | Epoch seconds |
| `expires_at` | Session expiration time | Epoch seconds |

### Session Cookie

| Attribute | Value | Purpose |
|-----------|-------|---------|
| `Name` | `session_id` | Configurable |
| `Value` | `<uuid>` | Opaque identifier |
| `HttpOnly` | `true` | Prevent XSS access |
| `Secure` | `true` | HTTPS only |
| `SameSite` | `Lax` | CSRF protection |
| `Path` | `/` | All routes |
| `Max-Age` | `28800` | 8 hours (matches session TTL) |

---

## Cache Configuration

### Key Patterns

| Pattern | TTL | Content |
|---------|-----|---------|
| `session:<id>` | 8 hours | Encrypted session data |
| `state:<state>` | 5 minutes | PKCE code_verifier + return_to |

### Connection Settings

| Setting | Value |
|---------|-------|
| **Port** | 6379 |
| **TLS** | Required |
| **Auth** | None (VCN-based access control) |

---

## Timeouts and Limits

### Function Timeouts

| Function | Timeout | Memory |
|----------|---------|--------|
| `oidc_authn` | 60s | 256MB |
| `oidc_callback` | 60s | 256MB |
| `apigw_authzr` | 60s | 256MB |
| `oidc_logout` | 60s | 256MB |
| `health` | 30s | 128MB |

### API Gateway Timeouts

| Setting | Value |
|---------|-------|
| Connect timeout | 10-30s |
| Read timeout | 10-30s |
| Send timeout | 10-30s |

---

## Updating Configuration

### Function Environment Variables

```bash
oci fn function update --function-id <function-ocid> \
  --config '{"KEY": "value"}' --force
```

### Secrets Rotation

```bash
# Create new secret version
oci vault secret update-base64 \
  --secret-id <secret-ocid> \
  --secret-content-content "<base64-content>"

# Functions pick up new version on next cold start
# Force immediate rotation by redeploying:
cd functions/<name> && fn deploy --app apigw-oidc-app
```

### API Gateway Deployment

```bash
oci api-gateway deployment update \
  --deployment-id <deployment-ocid> \
  --specification file://scripts/api_deployment.json --force
```
