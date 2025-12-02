# Frequently Asked Questions

This document answers common questions about the OCI API Gateway + OIDC Authentication solution.

## Contents

- [What is HKDF Pepper and how does Mass Logout work?](#what-is-hkdf-pepper-and-how-does-mass-logout-work)
- [What is an Authorizer Function?](#what-is-an-authorizer-function-and-how-is-apigw_authzr-different-from-other-functions)
- [What is the Dockerfile in each function folder?](#what-is-the-dockerfile-in-each-function-folder)
- [Why Podman is required and how does OCIR work?](#why-podman-is-required-and-how-does-ocir-work)
- [What is OCI Cache and why is it used for session storage?](#what-is-oci-cache-and-why-is-it-used-for-session-storage)
- [What are Custom Claims and why does this solution need them?](#what-are-custom-claims-and-why-does-this-solution-need-them)
- [What are OIDC Scopes and why do they matter?](#what-are-oidc-scopes-and-why-do-they-matter)
- [What is the OAuth2 Authorization Code flow and why use it?](#what-is-the-oauth2-authorization-code-flow-and-why-use-it)
- [What is PKCE and why does this solution use it?](#what-is-pkce-and-why-does-this-solution-use-it)

---

## Security

### What is HKDF Pepper and how does Mass Logout work?

**HKDF** (HMAC-based Key Derivation Function) combined with a **Pepper** (a 32-byte secret stored in OCI Vault) provides both session encryption and an emergency mass logout capability.

#### How it works:

```
                    ┌─────────────┐
                    │   Pepper    │  (from OCI Vault)
                    │  (32 bytes) │
                    └──────┬──────┘
                           │
                           ▼
┌──────────────┐    ┌─────────────┐    ┌──────────────────┐
│  Session ID  │───▶│    HKDF     │───▶│  Encryption Key  │
│   (UUID)     │    │  (derive)   │    │  (unique/session)│
└──────────────┘    └─────────────┘    └──────────────────┘
                                                │
                                                ▼
                                       ┌──────────────────┐
                                       │  AES-256-GCM     │
                                       │  Encrypt Session │
                                       └──────────────────┘
```

Each session gets a **unique encryption key** derived from:
- The session ID (public, in cookie)
- The pepper (secret, in Vault)

#### Why does rotating the pepper cause Mass Logout?

If you **rotate the pepper**:
1. New pepper → different HKDF output
2. Old sessions can't be decrypted (wrong key)
3. **All sessions instantly invalidated**
4. Users must re-authenticate

#### When to use Mass Logout:

| Scenario | Action |
|----------|--------|
| Security breach suspected | Rotate pepper |
| Compromised session keys | Rotate pepper |
| Force all users to re-login | Rotate pepper |
| Single user logout | Delete session from Redis (normal logout) |

The pepper rotation is an **emergency kill switch** for invalidating all sessions at once without needing to clear the Redis cache.

---

## Architecture

### What is an Authorizer Function and how is apigw_authzr different from other functions?

In OCI API Gateway, an **Authorizer Function** is a special type of function that validates requests *before* they reach any backend. It's fundamentally different from regular backend functions.

#### Authorizer vs Backend Functions

```
                                    ┌─────────────────────────────┐
                                    │      API Gateway            │
                                    │                             │
Browser ──▶ Request ──────────────▶ │  ┌───────────────────────┐  │
                                    │  │  AUTHORIZER FUNCTION  │  │
                                    │  │     (apigw_authzr)    │  │
                                    │  │                       │  │
                                    │  │  Called FIRST on      │  │
                                    │  │  every protected      │  │
                                    │  │  request              │  │
                                    │  └───────────┬───────────┘  │
                                    │              │              │
                                    │       active: true/false    │
                                    │              │              │
                                    │              ▼              │
                                    │  ┌───────────────────────┐  │
                                    │  │   BACKEND FUNCTIONS   │  │
                                    │  │                       │  │
                                    │  │  • oidc_authn         │  │
                                    │  │  • oidc_callback      │  │
                                    │  │  • oidc_logout        │  │
                                    │  │  • health             │  │
                                    │  │                       │  │
                                    │  │  Only called if       │  │
                                    │  │  authorizer approves  │  │
                                    │  │  (or route is anon)   │  │
                                    │  └───────────────────────┘  │
                                    └─────────────────────────────┘
```

#### Key Differences

| Aspect | Authorizer Function | Backend Function |
|--------|--------------------|--------------------|
| **When called** | Before routing decision | After routing decision |
| **Purpose** | Validate credentials/session | Handle business logic |
| **Response format** | `{active: true/false, context: {...}}` | Any HTTP response |
| **Can reject requests** | Yes (returns 401/302) | No (already authorized) |
| **Called on** | Every protected request | Only matching routes |

#### What apigw_authzr does:

1. **Extracts** the `session_id` cookie from the request
2. **Looks up** the session in OCI Cache (Redis)
3. **Decrypts** the session data using HKDF-derived key
4. **Validates** session hasn't expired and User-Agent matches
5. **Returns** either:
   - `{active: true, context: {user claims}}` → Request proceeds, claims available to backend
   - `{active: false}` → API Gateway triggers `validationFailurePolicy` (302 to login)

#### Why this matters:

- **Centralized auth**: One function protects ALL routes - backends don't need auth logic
- **Consistent security**: Every protected request goes through the same validation
- **Clean separation**: Backend functions only handle business logic, not authentication

---

### What is the Dockerfile in each function folder?

A **Dockerfile** is a build recipe that tells Podman (or Docker) how to create a container image for each OCI Function. Every function in this project has one for consistent, reproducible builds.

#### How it works:

```
┌─────────────────────────────────────────────────────────────────┐
│                         Dockerfile                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Stage 1: BUILD                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ FROM fnproject/python:3.11-dev    ← Start with Python     │  │
│  │ ADD requirements.txt              ← Copy dependencies     │  │
│  │ RUN pip3 install ...              ← Install packages      │  │
│  │ ADD . /function/                  ← Copy your code        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  Stage 2: RUN                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ FROM fnproject/python:3.11        ← Smaller runtime image │  │
│  │ COPY --from=build-stage ...       ← Copy built artifacts  │  │
│  │ ENTRYPOINT [... func.py handler]  ← Run your function     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Why use a Dockerfile?

| Without Dockerfile | With Dockerfile |
|-------------------|-----------------|
| Fn uses defaults from func.yaml | Explicit, reproducible builds |
| Less control over build process | Full control over dependencies |
| May vary across environments | Consistent everywhere |

#### Multi-stage build benefits:

- **Stage 1 (build)**: Uses larger image with build tools to install dependencies
- **Stage 2 (run)**: Uses smaller runtime image for faster cold starts
- **Result**: Smaller final image, faster deployments

Each function folder contains:
```
├── func.py           # Function code
├── func.yaml         # Function metadata (name, memory, timeout)
├── requirements.txt  # Python dependencies
└── Dockerfile        # Build instructions
```

---

### Why Podman is required and how does OCIR work?

This project uses **Podman** - a daemonless, rootless container runtime that is the default on Oracle Linux 8+. Podman is used by the Fn CLI to build function container images locally, which are then stored in Oracle Container Image Registry (OCIR).

#### Why Podman over Docker?

| Aspect | Podman | Docker |
|--------|--------|--------|
| **Default on Oracle Linux 8+** | Yes | No |
| **Daemonless** | Yes (no background service) | No (requires dockerd) |
| **Rootless by default** | Yes (more secure) | No |
| **OCI-compliant images** | Yes | Yes |
| **Dockerfile compatible** | Yes | Yes |

#### The Build and Deploy Flow

```
┌───────────────────────────────────────────────────────────────────┐
│                         Your Local Machine                        │
│                                                                   │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐   │
│  │  Dockerfile  │────▶│    Podman    │────▶│  Function Image  │   │
│  │   (recipe)   │     │  (builds it) │     │   (container)    │   │
│  └──────────────┘     └──────────────┘     └─────────┬────────┘   │
│                                                      │            │
└──────────────────────────────────────────────────────┼────────────┘
                                                       │
                                                       │ podman push
                                                       ▼
┌───────────────────────────────────────────────────────────────────┐
│                Oracle Container Image Registry (OCIR)             │
│                    (Your OCI Tenancy's Registry)                  │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ oidc_authn   │  │oidc_callback │  │ apigw_authzr │  ...        │
│  │   image      │  │    image     │  │    image     │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                   │
└─────────────────────────────────────────────────────┬─────────────┘
                                                      │
                                                      │ (OCI pulls)
                                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         OCI Functions                               │
│                    (Runs your functions)                            │
│                                                                     │
│  Functions pull images from OCIR when invoked                       │
└─────────────────────────────────────────────────────────────────────┘
```

#### Key Points

| Component | Description | Documentation |
|-----------|-------------|---------------|
| **Podman** | Daemonless container runtime, default on Oracle Linux 8+ | [Podman](https://podman.io/) |
| **Fn CLI** | Oracle's CLI tool for deploying functions (uses Podman via docker alias) | [Fn Project](https://fnproject.io/) |
| **OCIR** | Oracle Container Image Registry - stores function images | [OCIR Documentation](https://docs.oracle.com/en-us/iaas/Content/Registry/home.htm) |
| **OCI Functions** | Serverless platform that pulls images from OCIR | [Functions Documentation](https://docs.oracle.com/en-us/iaas/Content/Functions/home.htm) |

#### What happens when you run `fn deploy`?

1. **Fn CLI reads** `Dockerfile` and `func.yaml`
2. **Podman builds** the function image locally
3. **Podman tags** the image: `<region>.ocir.io/<namespace>/<repo>/<function>:<version>`
4. **Podman pushes** the image to OCIR (requires authentication)
5. **Fn CLI updates** the OCI Function to reference the new image in OCIR
6. **OCI Functions** pulls the image from OCIR when the function is invoked

#### Fn CLI Compatibility

Fn CLI expects a `docker` command. Install `podman-docker` to create a compatibility alias:

```bash
# Oracle Linux / RHEL
sudo dnf install podman-docker
```

#### Authentication to OCIR

```bash
# Login format
podman login <region>.ocir.io \
  -u '<namespace>/oracleidentitycloudservice/<email>' \
  -p '<auth-token>'

# Example
podman login us-chicago-1.ocir.io \
  -u 'mytenancy/oracleidentitycloudservice/user@example.com' \
  -p 'my-auth-token'
```

#### Why OCIR?

- **Required**: OCI Functions can only pull images from OCIR (not Docker Hub)
- **Private**: Images stored in your tenancy, not publicly accessible
- **Regional**: Images stored in the same region as your functions (low latency)
- **Integrated**: Uses OCI IAM for authentication and access control

#### Common Confusion

| ❌ Incorrect Assumption | ✅ Reality |
|------------------------|-----------|
| "I need Docker for OCI Functions" | Podman works and is preferred on Oracle Linux |
| "Podman can't read Dockerfiles" | Podman fully supports Dockerfiles |
| "Functions pull from Docker Hub" | Functions pull from OCIR only |
| "OCIR is optional" | OCIR is required for OCI Functions |

---

### What is OCI Cache and why is it used for session storage?

**OCI Cache** is Oracle Cloud Infrastructure's managed Redis-compatible caching service. In this solution, it serves as the **server-side session store** - a critical component for secure session management.

#### Why Redis for Sessions?

| Requirement | Why OCI Cache (Redis) |
|-------------|----------------------|
| **Speed** | Sub-millisecond latency for session lookups on every request |
| **TTL Support** | Built-in key expiration for automatic session cleanup |
| **Scalability** | Handles thousands of concurrent sessions |
| **Persistence** | Sessions survive function cold starts |
| **Security** | TLS encryption in transit, private subnet deployment |

#### What's stored in OCI Cache?

```
┌─────────────────────────────────────────────────────────────────┐
│                        OCI Cache (Redis)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Session Data (TTL: 8 hours)                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Key: "session:{uuid}"                                   │    │
│  │ Value: AES-256-GCM encrypted blob containing:           │    │
│  │   • User claims (sub, email, name, groups)              │    │
│  │   • ID token                                            │    │
│  │   • Session metadata (created_at, user_agent)           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  PKCE State (TTL: 5 minutes)                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Key: "state:{random-state}"                             │    │
│  │ Value: {code_verifier, return_to, nonce}                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Why not store sessions in cookies?

| Cookie-based | Server-side (OCI Cache) |
|--------------|------------------------|
| Data visible to client | Data hidden on server |
| Size limited (~4KB) | Unlimited session size |
| Can't revoke instantly | Instant revocation (delete key) |
| Vulnerable to theft | Only opaque UUID exposed |

#### Key Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| `REDIS_HOST` | Cache FQDN | Connection endpoint |
| `REDIS_PORT` | 6379 | Redis port (TLS) |
| `REDIS_TLS` | true | Encrypt in transit |
| `SESSION_TTL_SECONDS` | 28800 | 8-hour session lifetime |

---

### What are Custom Claims and why does this solution need them?

**Custom Claims** are additional pieces of user information that you can include in OIDC tokens (ID token or access token) beyond the standard claims like `sub`, `name`, and `email`.

#### The Problem

By default, OCI Identity Domain tokens include only basic claims:

```
Standard ID Token Claims:
┌─────────────────────────────────────┐
│  sub: "user-unique-id"              │  ← Always included
│  name: "John Doe"                   │  ← Basic profile
│  email: "john@example.com"          │  ← If 'email' scope requested
│  iat: 1699900000                    │  ← Issued at timestamp
│  exp: 1699903600                    │  ← Expiration timestamp
└─────────────────────────────────────┘

What's MISSING:
  ✗ Group memberships
  ✗ Department
  ✗ Custom attributes
  ✗ Application-specific data
```

#### The Solution: Custom Claims

Custom Claims let you add user attributes to the token:

```
ID Token WITH Custom Claims:
┌─────────────────────────────────────┐
│  sub: "user-unique-id"              │
│  name: "John Doe"                   │
│  email: "john@example.com"          │
│  ─────────────────────────────────  │
│  user_groups: ["Admins", "DevOps"]  │  ← Custom claim!
│  user_department: "Engineering"     │  ← Custom claim!
│  user_employee_id: "EMP-12345"      │  ← Custom claim!
└─────────────────────────────────────┘
```

#### How this solution uses Custom Claims

| Custom Claim | Expression | Purpose |
|--------------|------------|---------|
| `user_groups` | `$(user.groups[*].display)` | Authorization decisions, role-based access |
| `user_email` | `$(user.email)` | Display in UI, audit logging |
| `user_given_name` | `$(user.givenName)` | Personalization |
| `user_family_name` | `$(user.familyName)` | Personalization |

#### Flow: Custom Claims → Session → Backend Headers

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Identity   │    │   oidc_      │    │   OCI Cache  │    │   Backend    │
│   Domain     │───▶│   callback   │───▶│   (Redis)    │───▶│   receives   │
│              │    │              │    │              │    │   headers    │
│  ID Token    │    │  Extracts    │    │  Stores in   │    │              │
│  with custom │    │  claims      │    │  session     │    │  X-User-     │
│  claims      │    │              │    │              │    │  Groups: ... │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

1. **Login**: User authenticates with Identity Domain
2. **Token**: ID token contains custom claims (e.g., `user_groups`)
3. **Session**: `oidc_callback` extracts claims and stores in Redis session
4. **Authorizer**: `apigw_authzr` reads session and returns claims in `context`
5. **Backend**: API Gateway transforms claims into `X-User-*` headers

#### How to configure Custom Claims

> **Important:** Custom Claims in OCI Identity Domains must be configured via the REST API - there is no UI option in the OCI Console.

See the official Oracle documentation: [Managing Custom Claims](https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/custom-claims-token.htm)

This project includes a helper script: `scripts/create_groups_claim.py`

---

### What are OIDC Scopes and why do they matter?

**Scopes** are permission strings that define what information your application can access about a user. When a user logs in, they're granting your application permission to access specific data based on the scopes you request.

#### How Scopes Work

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         LOGIN REQUEST                                   │
│                                                                         │
│  Your App requests:  scope=openid profile email groups                  │
│                             │      │       │      │                     │
│                             ▼      ▼       ▼      ▼                     │
│                         ┌──────────────────────────────┐                │
│                         │      Identity Provider       │                │
│                         │                              │                │
│                         │  "App wants access to:"      │                │
│                         │   ✓ Your identity (openid)   │                │
│                         │   ✓ Your profile (profile)   │                │
│                         │   ✓ Your email (email)       │                │
│                         │   ✓ Your groups (groups)     │                │
│                         │                              │                │
│                         │  [Consent Screen if needed]  │                │
│                         └──────────────────────────────┘                │
│                                       │                                 │
│                                       ▼                                 │
│                         ┌──────────────────────────────┐                │
│                         │  ID Token contains claims    │                │
│                         │  based on granted scopes     │                │
│                         └──────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Standard OIDC Scopes

| Scope | Required | Claims Returned | Description |
|-------|----------|-----------------|-------------|
| `openid` | **Yes** | `sub`, `iss`, `aud`, `exp`, `iat` | Required for OIDC. Returns user's unique identifier |
| `profile` | No | `name`, `family_name`, `given_name`, `preferred_username` | Basic profile information |
| `email` | No | `email`, `email_verified` | User's email address |
| `groups` | No | `groups` | Group memberships (OCI-specific) |

#### What happens without each scope?

```
Scope Requested    │ What You Get                │ What You DON'T Get
───────────────────┼─────────────────────────────┼─────────────────────────
openid only        │ sub (user ID)               │ name, email, groups
                   │ iss, aud, exp, iat          │
───────────────────┼─────────────────────────────┼─────────────────────────
openid profile     │ sub, name, given_name       │ email, groups
                   │ family_name, username       │
───────────────────┼─────────────────────────────┼─────────────────────────
openid email       │ sub, email                  │ name, groups
───────────────────┼─────────────────────────────┼─────────────────────────
openid profile     │ sub, name, email            │ groups
email              │ given_name, family_name     │
───────────────────┼─────────────────────────────┼─────────────────────────
openid profile     │ ALL: sub, name, email,      │ Nothing missing!
email groups       │ given_name, family_name,    │
                   │ groups                      │
```

#### Scopes used in this solution

This solution requests all four scopes:

```
scope=openid profile email groups
```

| Scope | Why we need it |
|-------|----------------|
| `openid` | Required - identifies the user (`sub` claim) |
| `profile` | Display name, personalization |
| `email` | Contact info, audit logging |
| `groups` | Authorization decisions, role-based access |

#### Where scopes are configured

1. **Identity Domain App** - Must allow the scopes your app requests
2. **Login Function** - Requests scopes in the authorization URL (`oidc_authn/func.py`)
3. **Token Response** - Only includes claims for granted scopes

#### Common Scope Mistakes

| Mistake | Result | Fix |
|---------|--------|-----|
| Forgot `openid` | OIDC won't work at all | Always include `openid` |
| Forgot `groups` | No group info in token | Add `groups` scope |
| App doesn't allow scope | Scope silently ignored | Configure in Identity Domain |
| Requesting non-existent scope | Error or ignored | Use only valid scopes |

#### Scopes vs Custom Claims

| Aspect | Scopes | Custom Claims |
|--------|--------|---------------|
| **What they are** | Permission categories | Specific data fields |
| **Who defines them** | OIDC standard + IdP | You define them |
| **How to enable** | Request in auth URL | Configure via REST API |
| **Example** | `email` scope | `user_department` claim |

Think of **scopes** as "which doors to open" and **custom claims** as "what specific items to bring back through those doors."

---

### What is the OAuth2 Authorization Code flow and why use it?

The **Authorization Code flow** is an OAuth2/OIDC grant type designed for server-side applications. It's the most secure way to authenticate users because sensitive tokens never pass through the browser.

#### OAuth2 Grant Types Comparison

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        OAuth2 GRANT TYPES                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Authorization Code  ◄── This solution uses this                        │
│  ───────────────────                                                    │
│  • Tokens exchanged server-to-server (secure)                           │
│  • Browser only sees authorization code                                 │
│  • Best for web apps with backend                                       │
│                                                                         │
│  Implicit (DEPRECATED)                                                  │
│  ─────────────────────                                                  │
│  • Tokens returned directly to browser (insecure)                       │
│  • No client secret needed                                              │
│  • Vulnerable to token leakage                                          │
│                                                                         │
│  Client Credentials                                                     │
│  ──────────────────                                                     │
│  • Machine-to-machine only                                              │
│  • No user involved                                                     │
│  • Service accounts                                                     │
│                                                                         │
│  Resource Owner Password (DEPRECATED)                                   │
│  ────────────────────────────────────                                   │
│  • User gives password to your app directly                             │
│  • Never use this                                                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### How Authorization Code Flow Works

```
┌──────────┐                                              ┌──────────────┐
│  Browser │                                              │   Identity   │
│          │                                              │   Provider   │
└────┬─────┘                                              └──────┬───────┘
     │                                                           │
     │  1. User clicks "Login"                                   │
     │  ─────────────────────►  /auth/login                      │
     │                              │                            │
     │  2. Redirect to IdP          │                            │
     │  ◄───────────────────────────                             │
     │       302 Location: idp.com/authorize?                    │
     │           client_id=xxx                                   │
     │           redirect_uri=.../callback                       │
     │           response_type=code  ◄── Request CODE, not token │
     │           code_challenge=xxx  ◄── PKCE challenge          │
     │                                                           │
     │  3. User authenticates at IdP                             │
     │  ────────────────────────────────────────────────────────►│
     │       (username, password, MFA)                           │
     │                                                           │
     │  4. IdP redirects back with CODE (not token!)             │
     │  ◄────────────────────────────────────────────────────────│
     │       302 Location: .../callback?code=ABC123              │
     │                                      │                    │
     │                    ┌─────────────────┘                    │
     │                    │                                      │
     │                    ▼                                      │
     │            ┌───────────────┐                              │
     │            │  oidc_callback│                              │
     │            │   (server)    │                              │
     │            └───────┬───────┘                              │
     │                    │                                      │
     │                    │  5. Server exchanges code for tokens │
     │                    │     (secure server-to-server call)   │
     │                    │  ────────────────────────────────────►
     │                    │     POST /oauth2/v1/token            │
     │                    │       code=ABC123                    │
     │                    │       client_secret=xxx ◄── Secret!  │
     │                    │       code_verifier=xxx ◄── PKCE     │
     │                    │                                      │
     │                    │  6. IdP returns tokens               │
     │                    │  ◄────────────────────────────────────
     │                    │     {                                │
     │                    │       id_token: "...",               │
     │                    │       access_token: "..."            │
     │                    │     }                                │
     │                    │                                      │
     │  7. Session created, cookie set                           │
     │  ◄─────────────────┘                                      │
     │     302 + Set-Cookie: session_id=xxx                      │
     │                                                           │
```

#### Why Authorization Code is More Secure

| Aspect | Authorization Code | Implicit (deprecated) |
|--------|-------------------|----------------------|
| **Tokens in browser URL** | No - only short-lived code | Yes - tokens exposed |
| **Client secret** | Used server-side | Cannot use (would be exposed) |
| **Token exchange** | Server-to-server (TLS) | Through browser redirect |
| **Token in browser history** | No | Yes |
| **Vulnerable to interception** | Code useless without secret | Tokens can be stolen |

This solution also uses **PKCE** (Proof Key for Code Exchange) for additional security. See [What is PKCE?](#what-is-pkce-and-why-does-this-solution-use-it) for details.

#### Where this is configured in the solution

| Component | Configuration |
|-----------|---------------|
| **Identity Domain** | Grant Type: `authorization_code` |
| **oidc_authn** | Generates PKCE, requests `response_type=code` |
| **oidc_callback** | Exchanges code for tokens with `code_verifier` |
| **OCI Cache** | Stores PKCE state during login |

#### Summary

| Question | Answer |
|----------|--------|
| Why Authorization Code? | Tokens never touch the browser |
| Why not Implicit? | Deprecated, insecure, tokens exposed |
| Why PKCE? | Prevents code interception attacks ([details](#what-is-pkce-and-why-does-this-solution-use-it)) |
| Why Confidential Client? | Can securely store client_secret |

---

### What is PKCE and why does this solution use it?

**PKCE** (Proof Key for Code Exchange, pronounced "pixie") is a security extension to OAuth2 that prevents authorization code interception attacks. It's especially important for public clients but adds security even for confidential clients like this solution.

#### The Problem PKCE Solves

Without PKCE, if an attacker intercepts the authorization code (e.g., through a malicious browser extension, network interception, or log files), they could potentially exchange it for tokens.

```
WITHOUT PKCE:
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  1. Your app redirects to IdP with client_id                   │
│  2. User logs in, IdP redirects back with code=ABC123          │
│  3. ⚠️  Attacker intercepts code                               │
│  4. ⚠️  Attacker exchanges code for tokens (if no secret)      │
│                                                                │
└────────────────────────────────────────────────────────────────┘

WITH PKCE:
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  1. Your app generates secret code_verifier                    │
│  2. Your app sends SHA256(code_verifier) as code_challenge     │
│  3. User logs in, IdP redirects back with code=ABC123          │
│  4. ⚠️  Attacker intercepts code                               │
│  5. ✓  Attacker cannot exchange code (doesn't have verifier)   │
│  6. ✓  Your app exchanges code + code_verifier → tokens        │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

#### How PKCE Works

```
STEP 1: Login Initiation (oidc_authn)
──────────────────────────────────────

   Generate random code_verifier (43-128 characters)
   │
   ▼
   code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
   │
   ▼
   code_challenge = BASE64URL(SHA256(code_verifier))
                  = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
   │
   ▼
   Store code_verifier in Redis (keyed by state)
   │
   ▼
   Redirect to IdP: /authorize?code_challenge=E9Mel...&code_challenge_method=S256


STEP 2: Token Exchange (oidc_callback)
──────────────────────────────────────

   Receive code from IdP callback
   │
   ▼
   Retrieve code_verifier from Redis (using state)
   │
   ▼
   POST to IdP /token endpoint:
   {
     code: "ABC123",
     code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
   }
   │
   ▼
   IdP verifies: SHA256(code_verifier) == stored code_challenge
   │
   ▼
   If match → IdP issues tokens
   If no match → Request rejected
```

#### PKCE in This Solution

| Component | PKCE Role |
|-----------|-----------|
| **oidc_authn** | Generates `code_verifier` and `code_challenge` |
| **OCI Cache** | Stores `code_verifier` temporarily (5 min TTL) |
| **oidc_callback** | Retrieves `code_verifier` and sends to IdP |
| **Identity Domain** | Validates `code_verifier` matches `code_challenge` |

#### Code Example

```python
# oidc_authn - Generate PKCE
import secrets
import hashlib
import base64

# Generate random verifier (43 chars from 32 bytes)
code_verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b'=').decode()

# Calculate challenge
code_challenge = base64.urlsafe_b64encode(
    hashlib.sha256(code_verifier.encode()).digest()
).rstrip(b'=').decode()

# Store verifier in Redis, send challenge to IdP
```

#### Why Use PKCE Even with Client Secret?

This solution is a **confidential client** (has a client secret), so why use PKCE too?

| Defense | Protects Against |
|---------|------------------|
| Client Secret | Unauthorized token requests |
| PKCE | Authorization code interception |
| Both together | Defense in depth |

Using both provides **defense in depth** - even if one mechanism is compromised, the other still protects you.

---

## Troubleshooting

*More questions coming soon...*
