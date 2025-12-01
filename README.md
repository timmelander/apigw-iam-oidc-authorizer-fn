# OCI API Gateway + IAM + OIDC Authentication

A reference implementation for securing web applications using OCI API Gateway with OCI IAM Identity Domains for OpenID Connect (OIDC) authentication.

## Overview

This solution provides session-based authentication for protecting web applications behind OCI API Gateway. It implements:

- **OCI IAM Identity Domain** for secure Identity Provider
- **OCI API Gateway** to protect backend applications
- **OIDC Authorization Code Flow with PKCE** for secure authentication
- **OCI Cache (Redis)** for secure session storage
- **OCI Vault** for secrets management
- **Custom Authorizer Function** for session validation
- **Automatic login redirect** for unauthenticated requests

## Demo

![Login Demo](./assets/demo-login.gif)

## Architecture

```
     ┌──────────┐      ┌───────────────────────────────────────────────────────────┐
     │ Browser  │      │                OCI API Gateway (Public)                   │
     │          │      │  ┌─────────────────────────────────────────────────────┐  │
     │          │─────►│  │          Custom Authorizer (apigw_authzr)           │  │
     │          │      │  │   • Validates session cookie (via OCI Cache)        │  │
     │          │      │  │   • Decrypts session (pepper from OCI Vault)        │  │
     │          │      │  │   • Returns user claims or triggers login redirect  │  │
     │          │      │  └─────────────────────────────────────────────────────┘  │
     │          │      │                           │                               │
     │          │      │        ┌──────────────────┼───────────────────┐           │
     │          │      │        ▼                  ▼                   ▼           │
     │          │      │    ┌─────────┐        ┌──────────┐        ┌──────────┐    │
     │          │      │    │/auth/*  │        │/welcome  │        │/health   │    │
     │          │      │    │Anonymous│        │Protected │        │Anonymous │    │
     │          │      │    └────┬────┘        └─────┬────┘        └─────┬────┘    │
     └──────────┘      └─────────┼───────────────────┼───────────────────┼─────────┘
          ▲                      │                   │                   │
          │                      │                   │                   │
          │                      │                   │                   │         
          │                      ▼                   ▼                   ▼                  
          │  ┌───────────────────────────────┐   ┌─────────────┐     ┌─────────────┐
          │  │       OIDC Functions          │   │   Backend   │     │   health    │
          │  │                               │   │   (HTTP)    │     │  function   │
          │  │ ┌──────────┐  ┌─────────────┐ │   │             │     │             │
          │  │ │oidc_authn│  │oidc_callback│ │   │ • Apache    │     │ • Returns   │
          │  │ │          │  │             │ │   │ • Static    │     │   status    │
          │  │ │• PKCE    │  │• Token      │ │   │   content   │     │             │
          │  │ │• State   │  │  exchange   │ │   │ • CGI       │     │ (standalone │
          │  │ │• Redirect│  │• Session    │ │   │             │     │  no deps)   │
          │  │ └──────────┘  └─────────────┘ │   └─────────────┘     └─────────────┘
          │  │ ┌───────────────────────────┐ │
          │  │ │       oidc_logout         │ │
          │  │ │  • Session cleanup        │ │
          │  │ │  • IdP logout             │ │
          │  │ └───────────────────────────┘ │
          │  └───────────────┬───────────────┘
    OIDC Redirect            │
          │   ┌──────────────┼──────────┐
          │   ▼              ▼          ▼
     ┌─────────────┐   ┌─────────┐  ┌─────────┐
     │   OCI IAM   │   │   OCI   │  │   OCI   │
     │  Identity   │   │  Cache  │  │  Vault  │
     │   Domain    │   │ (Redis) │  │         │
     │             │   │         │  │• Client │
     │  • Auth URL │   │• Session│  │  secret │
     │  • Tokens   │   │  store  │  │• Pepper │
     └─────────────┘   └─────────┘  └─────────┘
                            ▲            ▲
                            └──────┬─────┘
                                   │
                          apigw_authzr also uses
                          Cache + Vault for session
                          validation on every request
             
             
           
```

> **Note:** This diagram represents the functional POC architecture. For production deployments, see the [Production Hardening section in SECURITY.md](./docs/SECURITY.md#production-hardening) which includes Load Balancer, WAF, private subnets, and mTLS recommendations.

## Authentication Flow

1. **User visits protected route** (e.g., `/welcome`)
2. **Authorizer validates session** - `apigw_authzr` checks for valid session cookie
3. **No session → redirect to login** - `validationFailurePolicy` returns 302 to `/auth/login`
4. **Login initiates OIDC flow** - `oidc_authn` generates PKCE, stores state, redirects to IdP
5. **User authenticates** at OCI IAM Identity Domain
6. **Callback processes auth code** - `oidc_callback` exchanges code for tokens
7. **Session created** - Encrypted session stored in OCI Cache, secure cookie set
8. **User redirected to original URL** with valid session
9. **Subsequent requests** validated by authorizer, user claims passed to backend

## Functions

| Function | Route | Purpose |
|----------|-------|---------|
| `apigw_authzr` | N/A (Authorizer) | Session validation, returns user claims |
| `oidc_authn` | `/auth/login` | Initiates OIDC login flow with PKCE |
| `oidc_callback` | `/auth/callback` | Handles OAuth2 callback, creates session |
| `oidc_logout` | `/auth/logout` | Clears session, redirects to IdP logout |
| `health` | `/health` | Health check endpoint |

> **Note:** The `apigw_authzr` function is an **Authorizer Function** - a special OCI API Gateway concept that validates requests before they reach any backend. See [FAQ: What is an Authorizer Function?](./docs/FAQ.md#what-is-an-authorizer-function-and-how-is-apigw_authzr-different-from-other-functions) for details on how it differs from regular backend functions.

## API Endpoints

| Path | Method | Auth | Description |
|------|--------|------|-------------|
| `/` | GET | Anonymous | Landing page |
| `/health` | GET | Anonymous | Health check |
| `/auth/login` | GET | Anonymous | Initiates OIDC login |
| `/auth/callback` | GET | Anonymous | OAuth2 callback handler |
| `/auth/logout` | GET, POST | Anonymous | Logout and session cleanup |
| `/welcome` | GET | Protected | User info page (requires auth) |
| `/debug` | GET | Protected | Debug page with all claims |

## Security Features

- **PKCE** (Proof Key for Code Exchange) for authorization code flow
- **AES-256-GCM** encryption for session data
- **HKDF** key derivation with pepper stored in OCI Vault
- **Session binding** to User-Agent for hijacking protection
- **HttpOnly, Secure** cookies
- **TLS** for OCI Cache (Redis) connections
- **Custom Claims** in OCI Identity Domain for user profile data

## Prerequisites

- OCI CLI configured with appropriate permissions
- Fn CLI installed and configured
- Docker installed for function builds
- OCI Identity Domain with Confidential Application
- OCI Cache (Redis) cluster
- OCI Vault with secrets

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/timmelander/apigw-iam-oidc-authorizer-fn.git
   cd apigw-iam-oidc-authorizer-fn

   ```

2. **Configure Fn context**
   ```bash
   fn use context oci-chicago
   ```

3. **Deploy functions**
   ```bash
   for func in health oidc_authn oidc_callback oidc_logout apigw_authzr; do
     cd functions/$func && fn deploy --app apigw-oidc-app && cd ../..
   done
   ```

4. **Update API Gateway deployment**

   Generate the deployment JSON from template (replace placeholders with your OCIDs), then update:
   ```bash
   # See Deployment Guide Section 5.3 for full instructions on generating api_deployment.json
   oci api-gateway deployment update --deployment-id <deployment_id> \
     --specification file://scripts/api_deployment.json --force
   ```

## Documentation

### Developer Guides

| Document | Description |
|----------|-------------|
| [Architecture](./docs/ARCHITECTURE.md) | System components and how they connect |
| [How It Works](./docs/HOW_IT_WORKS.md) | End-to-end authentication flows with diagrams |
| [Deployment Guide](./docs/DEPLOYMENT_GUIDE.md) | Fresh tenancy deployment (zero to working) |
| [Terraform](./terraform/README.md) | Infrastructure as Code deployment (POC and Production) |
| [Configuration](./docs/CONFIGURATION.md) | All environment variables, secrets, and settings |
| [Development](./docs/DEVELOPMENT.md) | Code structure, local testing, extending the solution |
| [Troubleshooting](./docs/TROUBLESHOOTING.md) | Common issues and debugging |
| [Security](./docs/SECURITY.md) | Security architecture and production hardening |
| [API Reference](./docs/API_REFERENCE.md) | All endpoints with request/response examples |
| [FAQ](./docs/FAQ.md) | Frequently asked questions |

### Reference

| Document | Description |
|----------|-------------|
| [Authorizer Functions](./docs/multi-argument-authorizer-functions.md) | OCI API Gateway authorizer format reference |

## Testing

```bash
# Health check (anonymous)
curl https://<api-gateway-url>/health

# Login redirect check
curl -I https://<api-gateway-url>/auth/login

# Protected endpoint without session (expect 302 redirect)
curl -I https://<api-gateway-url>/welcome
```

## Configuration

### Function Environment Variables

See [Configuration](./docs/CONFIGURATION.md) for complete configuration details.

### OCI Identity Domain Setup

1. Create Confidential Application
2. Enable Authorization Code grant with PKCE
3. Configure redirect URI: `https://<api-gateway-url>/auth/callback`
4. Create Custom Claims for user profile data:
   - `user_email`, `user_given_name`, `user_family_name`, `user_groups`

## Known Issues

1. **Function naming restrictions** - Certain function names cause 502 errors. Workaround names are used:
   - `session_authorizer` → `apigw_authzr`
   - `oidc_login` → `oidc_authn`

2. **Cold start latency** - First invocation after idle may be slow due to container cold start.

## License

Apache 2.0

## Contributing

Contributions welcome. Please open an issue first to discuss proposed changes.
