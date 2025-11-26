# Architecture Overview

This document describes the architecture of the OCI API Gateway + OIDC Authentication solution.

## System Diagram

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      OCI API Gateway (Public)                       │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │              Custom Authorizer: apigw_authzr                  │  │
│  │  • Validates session cookie against OCI Cache                 │  │
│  │  • Returns user claims on success (sub, email, name, groups)  │  │
│  │  • validationFailurePolicy: 302 redirect to /auth/login       │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Routes:                                                            │
│  ┌─────────────┐ ┌───────────────┐ ┌────────────┐ ┌─────────────┐   │
│  │ /auth/login │ │/auth/callback │ │/auth/logout│ │  /health    │   │
│  │  Anonymous  │ │   Anonymous   │ │  Anonymous │ │  Anonymous  │   │
│  │ →oidc_authn │ │→oidc_callback │ │→oidc_logout│ │  →health    │   │
│  └─────────────┘ └───────────────┘ └────────────┘ └─────────────┘   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              /welcome, /debug, /* (Protected)                │   │
│  │              Requires valid session (AUTHENTICATION_ONLY)    │   │
│  │              → HTTP Backend (Apache)                         │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
       │                    │                    │
       ▼                    ▼                    ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│    OCI      │      │    OCI      │      │  OCI IAM    │
│   Cache     │      │   Vault     │      │  Identity   │
│   (Redis)   │      │             │      │   Domain    │
│             │      │ • Client    │      │             │
│ • Sessions  │      │   Creds     │      │ • OIDC IdP  │
│ • State     │      │ • HKDF      │      │ • MFA       │
│   (PKCE)    │      │   Pepper    │      │ • Users     │
└─────────────┘      └─────────────┘      └─────────────┘
```

## Components

### OCI API Gateway

The central entry point for all requests. Handles:

- **TLS Termination**: Public HTTPS endpoint
- **Routing**: Directs requests to appropriate backends (functions or HTTP)
- **Authentication**: Custom authorizer validates sessions before protected routes
- **Header Injection**: Passes user claims to backend applications

### OCI Functions (5 total)

| Function | Purpose | Route |
|----------|---------|-------|
| `apigw_authzr` | Session validation authorizer | N/A (called by API Gateway) |
| `oidc_authn` | Initiates OIDC login flow | `/auth/login` |
| `oidc_callback` | Handles OAuth2 callback | `/auth/callback` |
| `oidc_logout` | Session termination | `/auth/logout` |
| `health` | Health check | `/health` |

### OCI Cache (Redis)

Stores all session-related data:

- **Session Data**: Encrypted user claims, tokens, metadata
- **PKCE State**: Temporary storage during OAuth flow (5-minute TTL)
- **Session TTL**: 8 hours (configurable)

> For more details on why Redis is used and what's stored, see [FAQ: What is OCI Cache and why is it used for session storage?](./FAQ.md#what-is-oci-cache-and-why-is-it-used-for-session-storage)

### OCI Vault

Secure storage for sensitive configuration:

| Secret | Purpose |
|--------|---------|
| `oidc_client_credentials` | OAuth2 client_id and client_secret |
| `hkdf_pepper` | 32-byte key for session encryption key derivation |

### OCI IAM Identity Domain

The OpenID Connect Identity Provider:

- User authentication (username/password)
- Multi-factor authentication (FIDO2/WebAuthn)
- Authorization code issuance
- Token endpoint for code exchange
- UserInfo endpoint (optional)
- Custom Claims for user profile data

### Backend (Apache HTTP Server)

A simple HTTP server hosting protected content:

- Receives requests only after successful authentication
- Gets user information via HTTP headers (X-User-*)
- Stateless - no session handling required

## Routing Strategy

### Anonymous Routes (No Authentication Required)

| Route | Handler | Purpose |
|-------|---------|---------|
| `/` | HTTP Backend | Landing page |
| `/health` | health function | Health check |
| `/auth/login` | oidc_authn function | Start login |
| `/auth/callback` | oidc_callback function | OAuth callback |
| `/auth/logout` | oidc_logout function | End session |
| `/logged-out` | HTTP Backend | Post-logout page |

### Protected Routes (Authentication Required)

| Route | Handler | Auth Failure |
|-------|---------|--------------|
| `/welcome` | HTTP Backend | 302 → `/auth/login` |
| `/debug` | HTTP Backend | 302 → `/auth/login` |

Protected routes use `AUTHENTICATION_ONLY` authorization policy. When the authorizer returns `active: false`, the `validationFailurePolicy` triggers a 302 redirect to `/auth/login`.

## Data Flow

### Session Cookie Flow

```
Browser                 API Gateway           apigw_authzr         Vault            Cache
   │                         │                      │                 │                │
   │──Cookie: session_id=X──▶│                      │                 │                │
   │                         │──Call authorizer────▶│                 │                │
   │                         │  (Cookie, User-Agent)│                 │                │
   │                         │                      │                 │                │
   │                         │                      │──GET session:X─────────────────▶│
   │                         │                      │◀─encrypted data─────────────────│
   │                         │                      │                 │                │
   │                         │                      │──Get pepper────▶│                │
   │                         │                      │◀────────────────│                │
   │                         │                      │                 │                │
   │                         │                      │ Derive key (HKDF + pepper)       │
   │                         │                      │ Decrypt session                  │
   │                         │                      │ Validate User-Agent              │
   │                         │                      │ Check expiry                     │
   │                         │                      │                 │                │
   │                         │◀─{active:true,claims}│                 │                │
   │                         │                      │                 │                │
   │                         │──Forward to backend─▶│                 │                │
   │                         │  + X-User-* headers  │                 │                │
```

### Secrets Access Flow

```
Functions                              Vault
    │                                    │
    │──Read secret bundle───────────────▶│
    │   (client_credentials)             │
    │◀──{client_id, client_secret}───────│
    │                                    │
    │──Read secret bundle───────────────▶│
    │   (hkdf_pepper)                    │
    │◀──{pepper: base64...}──────────────│
```

## Network Architecture

### Current (POC/Validation)

- **API Gateway**: Public subnet with public IP
- **Functions**: Private subnet (VCN-native)
- **Cache**: Private subnet
- **Backend**: Private subnet

### Production Architecture (Recommended)

For production deployments, see the [Production Hardening section in SECURITY.md](./SECURITY.md#production-hardening) which includes:

- Full production architecture diagram
- WAF and Load Balancer configuration
- Private subnet deployment
- mTLS between components
- Network Security Groups
- Security checklist

## Scalability

| Component | Scaling Model |
|-----------|---------------|
| API Gateway | Managed (auto-scales) |
| Functions | Managed (auto-scales, cold starts possible) |
| Cache | Manual (cluster size) |
| Backend | Manual (compute instances) |

## High Availability

| Component | HA Strategy |
|-----------|-------------|
| API Gateway | Multi-AD by default |
| Functions | Multi-AD by default |
| Cache | Single node (POC), HA cluster available |
| Backend | Single instance (POC), load balanced available |
