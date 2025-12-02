# Security Guide

This document describes the security architecture, threat model, and production hardening recommendations.

## Security Architecture

### Defense in Depth

```
Layer 1: Network Security
├── VCN isolation
├── Security Lists / NSGs
└── Private subnets for backend

Layer 2: API Gateway
├── TLS termination
├── Custom authorizer
└── Route-level authorization

Layer 3: Session Security
├── Encrypted sessions (AES-256-GCM)
├── HKDF key derivation
├── Session binding (User-Agent)
└── Server-side storage only

Layer 4: Authentication
├── OIDC with PKCE
├── State parameter (CSRF)
├── MFA enforcement
└── Secure cookies

Layer 5: Secret Management
├── OCI Vault
├── Dynamic credentials
└── No secrets in code
```

---

## Implemented Security Controls

### Authentication

| Control | Implementation |
|---------|----------------|
| **OIDC Authorization Code** | Secure server-side flow |
| **PKCE** | Prevents code interception attacks |
| **State Parameter** | Prevents CSRF on login |
| **MFA** | FIDO2/WebAuthn via Identity Domain |

### Session Management

| Control | Implementation |
|---------|----------------|
| **Server-side sessions** | No sensitive data in cookies |
| **Opaque session IDs** | UUID, no information leakage |
| **AES-256-GCM encryption** | Sessions encrypted at rest |
| **HKDF key derivation** | Unique key per session |
| **Session binding** | Tied to User-Agent |
| **TTL enforcement** | 8-hour default expiration |

### Cookie Security

| Attribute | Value | Protection |
|-----------|-------|------------|
| `HttpOnly` | `true` | XSS mitigation |
| `Secure` | `true` | HTTPS only |
| `SameSite` | `Lax` | CSRF mitigation |

### Secret Management

| Control | Implementation |
|---------|----------------|
| **OCI Vault** | Centralized secret storage |
| **IAM policies** | Least privilege access |
| **No hardcoded secrets** | All secrets from Vault |
| **Secret rotation** | New version support |

---

## Threat Model

### Threats Addressed

| Threat | Mitigation |
|--------|------------|
| **Session hijacking** | HttpOnly cookies, User-Agent binding |
| **XSS** | HttpOnly cookies, no sensitive data client-side |
| **CSRF** | SameSite cookies, state parameter |
| **Token theft** | Server-side storage, encrypted sessions |
| **Code interception** | PKCE |
| **Replay attacks** | One-time state, nonce validation |
| **Brute force** | Rate limiting (IdP), MFA |

### Residual Risks

| Risk | Status | Notes |
|------|--------|-------|
| DDoS | Partial | Rate limiting at API Gateway |
| Malicious insider | Partial | IAM policies, audit logging |
| Zero-day vulnerabilities | Accepted | Regular patching required |

---

## Production Hardening

### Recommended Production Architecture

```
                    Oracle Cloud Infrastructure
              Production OIDC Authentication Architecture

                        ┌─────────────────┐
                        │                 │
                        │     Browser     │◄─────────────────────────────────────────┐
                        │                 │                                          │
                        └──────────┬──────┘                                          │
                                   │ HTTPS                                           │
                                   ▼                                                 │
┌────────────────────────────────────────────────────────────────────────────────┐   │
│                              PUBLIC SUBNET                                     │   │
│                                                                                │   │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │                     OCI Web Application Firewall                         │  │   │
│  │               • OWASP rules  • Rate limiting  • Bot protection           │  │   │
│  └──────────────────────────────────────────────────────────────────────────┘  │   │
│                                    │                                           │   │
│                                    ▼                                           │   │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │                     OCI Flexible Load Balancer                           │  │   │
│  │           • TLS termination  • Health checks  • Custom domain            │  │   │
│  └──────────────────────────────────────────────────────────────────────────┘  │   │
│                                                                                │   │
│  Layer 1: Network Security                                                     │   │
└────────────────────────────────────────────────────────────────────────────────┘   │
                                     │                                               │
                                     ▼                                               │
┌────────────────────────────────────────────────────────────────────────────────┐   │
│                              PRIVATE SUBNET                                    │   │
│                                                                                │   │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │   │
│  │                     OCI API Gateway (Private)                            │  │   │
│  │                                                                          │  │   │
│  │   ┌────────────────────────────────────────────────────────────────────┐ │  │   │
│  │   │                Custom Authorizer: apigw_authzr                     │ │  │   │
│  │   │     • Session validation  • User claims  • Login redirect          │ │  │   │
│  │   └────────────────────────────────────────────────────────────────────┘ │  │   │
│  │                                                                          │  │   │
│  │          Routes: /auth/* (Anonymous) | /welcome, /* (Protected)          │  │   │
│  └──────────────────────────────────────────────────────────────────────────┘  │   │
│           │                      │                       │                     │   │
│  Layer 2: API Gateway            │                       │                     │   │
│           │                      │                       │                     │   │
│           │                      │                       │                     │   │
│           ▼                      ▼                       ▼                     │   │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐           │   │
│  │  OCI Functions  │     │    OCI Cache    │     │ Backend (Apache)│           │   │
│  │    (Private)    │     │    (Private)    │     │    (Private)    │           │   │
│  │                 │     │                 │     │                 │           │   │
│  │  • oidc_authn   │     │  • Sessions     │     │  • Protected    │           │   │
│  │  • callback     │     │  • PKCE state   │     │    content      │           │   │
│  │  • logout       │     │  • TLS 1.2+     │     │  • mTLS         │           │   │
│  │  • authzr       │     │                 │     │                 │           │   │
│  └────────┬────────┘     └─────────────────┘     └─────────────────┘           │   │
│           │                                                                    │   │
│  Layer 3: Session Security                                                     │   │
└───────────┼────────────────────────────────────────────────────────────────────┘   │
            │                                                                        │
            │                                                                        │
            │                                                                        │
            ▼                                                                        │
┌────────────────────────────────────────────────────────────────────────────────┐   │
│                          OSN (Oracle Services Network)                         │   │
│                                                                                │   │
│       ┌──────────────────┐           ┌──────────────────────┐                  │   │
│       │     OCI Vault    │           │      OCI IAM         │                  │   │
│       │                  │           │   Identity Domain    │──────────────────┼───┘
│       │   • Secrets      │           │                      │  OIDC Redirect   │
│       │   • Keys         │           │   • OIDC IdP         │                  │
│       │   • mTLS certs   │           │                      │                  │
│       └──────────────────┘           └──────────────────────┘                  │
│                                                                                │
│  Layer 4: Authentication                                                       │
└────────────────────────────────────────────────────────────────────────────────┘
```

#### POC vs Production Comparison

| Component | POC | Production |
|-----------|-----|------------|
| Entry Point | API Gateway (public) | Load Balancer + WAF |
| API Gateway | Public subnet | Private subnet |
| Domain | OCI default URL | Custom domain + SSL |
| Backend | HTTP | mTLS |
| Cache | TLS | TLS + encryption at rest |
| Monitoring | Basic logs | APM + alerts |

### Network Hardening

#### Private API Gateway

1. Move API Gateway to private subnet
2. Add public Load Balancer
3. Configure backend set to API Gateway

#### WAF Integration

```bash
# Enable WAF policy on Load Balancer
oci waf web-app-firewall create \
  --compartment-id <compartment-ocid> \
  --backend-type LOAD_BALANCER \
  --load-balancer-id <lb-ocid> \
  --web-app-firewall-policy-id <policy-ocid>
```

#### Network Security Groups

```bash
# Create NSG for functions
oci network nsg create \
  --compartment-id <compartment-ocid> \
  --vcn-id <vcn-ocid> \
  --display-name "fn-nsg"

# Add rules: only allow from API Gateway
oci network nsg rules add \
  --nsg-id <nsg-ocid> \
  --security-rules '[{
    "direction": "INGRESS",
    "protocol": "6",
    "source": "<api-gw-subnet-cidr>",
    "sourceType": "CIDR_BLOCK"
  }]'
```

### mTLS Between Components

#### API Gateway to Backend

1. Generate client certificate
2. Store in OCI Vault
3. Configure API Gateway mTLS backend

```json
{
  "backend": {
    "type": "HTTP_BACKEND",
    "url": "https://backend:443/",
    "isSslVerifyDisabled": false,
    "connectTimeoutInSeconds": 30,
    "mutualTls": {
      "secretId": "<client-cert-secret-ocid>"
    }
  }
}
```

### Rate Limiting

Configure in API Gateway deployment:

```json
{
  "requestPolicies": {
    "rateLimiting": {
      "rateKey": "CLIENT_IP",
      "rateInRequestsPerSecond": 10
    }
  }
}
```

### Audit Logging

Enable OCI Audit for:

- API Gateway invocations
- Function invocations
- Vault secret access
- IAM policy changes

```bash
# Enable audit logging (automatic in OCI)
# Configure retention and export
oci audit config update \
  --compartment-id <compartment-ocid> \
  --retention-period-days 365
```

---

## Secret Rotation

### Client Credentials

1. Generate new credentials in Identity Domain
2. Update Vault secret
3. Redeploy affected functions

```bash
# Update secret
oci vault secret update-base64 \
  --secret-id <secret-ocid> \
  --secret-content-content "$(echo -n '{...}' | base64)"

# Redeploy
cd functions/oidc_authn && fn deploy --app apigw-oidc-app
cd ../oidc_callback && fn deploy --app apigw-oidc-app
```

### HKDF Pepper (Mass Logout)

> For a detailed explanation of how HKDF and the pepper work together, see [FAQ: What is HKDF Pepper and how does Mass Logout work?](./FAQ.md#what-is-hkdf-pepper-and-how-does-mass-logout-work)

Rotating the pepper invalidates ALL sessions:

```bash
# Generate new pepper
NEW_PEPPER=$(openssl rand -base64 32)

# Update secret
oci vault secret update-base64 \
  --secret-id <pepper-secret-ocid> \
  --secret-content-content "$NEW_PEPPER"

# Redeploy
cd functions/oidc_callback && fn deploy --app apigw-oidc-app
cd ../apigw_authzr && fn deploy --app apigw-oidc-app
```

---

## Compliance Considerations

### Data Residency

- All data stored in configured OCI region
- Cache, Vault, Functions in same region
- No cross-region replication (configurable)

### Data Retention

| Data | Location | Retention |
|------|----------|-----------|
| Sessions | OCI Cache | TTL (8 hours) |
| State | OCI Cache | TTL (5 minutes) |
| Secrets | OCI Vault | Until deleted |
| Logs | OCI Logging | Configurable |
| Audit | OCI Audit | 365 days default |

### Access Control

| Role | Permissions |
|------|-------------|
| Admin | Full access to all resources |
| Developer | Deploy functions, read logs |
| Operator | View status, read logs |
| Auditor | Read audit logs only |

---

## Security Checklist

### Pre-Production

- [ ] Move API Gateway to private subnet
- [ ] Add Load Balancer with WAF
- [ ] Configure Network Security Groups
- [ ] Enable mTLS to backend
- [ ] Set up audit log export
- [ ] Configure rate limiting
- [ ] Review IAM policies (least privilege)
- [ ] Test secret rotation procedures
- [ ] Document incident response

### Ongoing

- [ ] Monitor for security advisories
- [ ] Review access logs regularly
- [ ] Rotate secrets periodically
- [ ] Patch dependencies
- [ ] Conduct security assessments

---

## Incident Response

### Session Compromise

1. **Immediate**: Rotate HKDF pepper (invalidates all sessions)
2. **Investigate**: Review logs for unauthorized access
3. **Notify**: Affected users if required
4. **Remediate**: Address root cause

### Secret Exposure

1. **Immediate**: Rotate exposed secret
2. **Revoke**: Old credentials in Identity Domain
3. **Investigate**: How secret was exposed
4. **Remediate**: Fix exposure vector

### DDoS Attack

1. **Immediate**: Enable WAF protection rules
2. **Scale**: Increase rate limits if needed
3. **Block**: Offending IP ranges
4. **Investigate**: Attack patterns
