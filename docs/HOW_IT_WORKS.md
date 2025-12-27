# How It Works

This document explains the end-to-end authentication flows in detail.

## Table of Contents

- [Overview](#overview)
- [Authentication Flows](#authentication-flows)
- [Security Mechanisms](#security-mechanisms)
- [Session Data Structure](#session-data-structure)
- [User Claims Propagation](#user-claims-propagation)
- [Error Handling](#error-handling)

---

## Overview

The solution implements **session-based authentication** using OIDC Authorization Code Flow with PKCE. Here's how a user goes from anonymous to authenticated:

1. User visits a protected page
2. No session found → redirect to login
3. Login generates PKCE and redirects to Identity Provider
4. User authenticates (username/password + MFA)
5. IdP redirects back with authorization code
6. Callback exchanges code for tokens, creates encrypted session
7. User redirected to original page with session cookie
8. Subsequent requests validated against session in cache

> **Note:** For details on PKCE (Proof Key for Code Exchange) and why this solution uses it, see [FAQ: What is PKCE?](./FAQ.md#what-is-pkce-and-why-does-this-solution-use-it)

## Authentication Flows

### Flow 1: First Visit (No Session) → Redirect to Login

```
┌─────────┐       ┌─────────────┐       ┌──────────────┐
│ Browser │       │ API Gateway │       │ apigw_authzr │
└────┬────┘       └──────┬──────┘       └──────┬───────┘
     │                   │                     │
     │ 1. GET /welcome   │                     │
     │──────────────────▶│                     │
     │                   │                     │
     │                   │ 2. Call authorizer  │
     │                   │    (no cookie)      │
     │                   │────────────────────▶│
     │                   │                     │
     │                   │                     │ 3. No session
     │                   │                     │    cookie found
     │                   │                     │
     │                   │ 4. {active: false}  │
     │                   │◀────────────────────│
     │                   │                     │
     │ 5. 302 /auth/login│                     │
     │    ?return_to=    │                     │
     │    /welcome       │                     │
     │◀──────────────────│                     │
     │                   │                     │
```

### Flow 2: Login Initiation (OIDC Authorize)

```
┌─────────┐       ┌─────────────┐      ┌───────────┐      ┌───────┐      ┌─────┐      ┌─────┐
│ Browser │       │ API Gateway │      │ oidc_authn│      │ Vault │      │Cache│      │ IdP │
└────┬────┘       └──────┬──────┘      └─────┬─────┘      └───┬───┘      └──┬──┘      └──┬──┘
     │                   │                   │                │             │            │
     │ 1. GET /auth/login│                   │                │             │            │
     │    ?return_to=... │                   │                │             │            │
     │──────────────────▶│                   │                │             │            │
     │                   │                   │                │             │            │
     │                   │ 2. Route to       │                │             │            │
     │                   │    oidc_authn     │                │             │            │
     │                   │──────────────────▶│                │             │            │
     │                   │                   │                │             │            │
     │                   │                   │ 3. Get client_id             │            │
     │                   │                   │    from Vault  │             │            │
     │                   │                   │───────────────▶│             │            │
     │                   │                   │◀───────────────│             │            │
     │                   │                   │                │             │            │
     │                   │                   │ 4. Generate:   │             │            │
     │                   │                   │  • state       │             │            │
     │                   │                   │  • nonce       │             │            │
     │                   │                   │  • code_verifier             │            │
     │                   │                   │  • code_challenge            │            │
     │                   │                   │                │             │            │
     │                   │                   │ 5. Store state │             │            │
     │                   │                   │    {code_verifier,           │            │
     │                   │                   │     return_to} │             │            │
     │                   │                   │─────────────────────────────▶│            │
     │                   │                   │                │             │            │
     │                   │ 6. 302 to IdP     │                │             │            │
     │◀──────────────────│◀──────────────────│                │             │            │
     │                   │                   │                │             │            │
     │ 7. GET /authorize?client_id=...&code_challenge=...&state=...         │            │
     │──────────────────────────────────────────────────────────────────────────────────▶│
     │                   │                   │                │             │            │
```

### Flow 3: User Authentication at IdP

```
┌─────────┐                                                                            ┌─────┐
│ Browser │                                                                            │ IdP │
└────┬────┘                                                                            └──┬──┘
     │                                                                                    │
     │ 1. 200 Login Page (HTML served by IdP)                                             │
     │◀───────────────────────────────────────────────────────────────────────────────────│
     │                                                                                    │
     │ 2. POST credentials (username/password)                                            │
     │───────────────────────────────────────────────────────────────────────────────────▶│
     │                                                                                    │
     │ 3. 200 MFA Page (if MFA enabled)                                                   │
     │◀───────────────────────────────────────────────────────────────────────────────────│
     │                                                                                    │
     │ 4. POST MFA code (TOTP/FIDO2)                                                      │
     │───────────────────────────────────────────────────────────────────────────────────▶│
     │                                                                                    │
     │ 5. 302 /auth/callback?code=AUTH_CODE&state=STATE                                   │
     │◀───────────────────────────────────────────────────────────────────────────────────│
     │                                                                                    │
```

**Note:** During this flow, our system is not involved. The IdP handles the entire login UI, credential validation, and MFA.

### Flow 4: OAuth Callback (Token Exchange & Session Creation)

```
┌─────────┐      ┌────────────┐      ┌─────────────┐      ┌───────┐       ┌───────┐      ┌─────┐
│ Browser │      │ API Gateway│      │oidc_callback│      │ Vault │       │ Cache │      │ IdP │
└────┬────┘      └─────┬──────┘      └──────┬──────┘      └───┬───┘       └───┬───┘      └──┬──┘
     │                 │                    │                 │               │             │
     │ 1. GET /auth/callback?code=X&state=Y │                 │               │             │
     │────────────────▶│                    │                 │               │             │
     │                 │                    │                 │               │             │
     │                 │ 2. Route to        │                 │               │             │
     │                 │    oidc_callback   │                 │               │             │
     │                 │───────────────────▶│                 │               │             │
     │                 │                    │                 │               │             │
     │                 │                    │ 3. Get state:Y  │               │             │
     │                 │                    │────────────────────────────────▶│             │
     │                 │                    │◀────────────────────────────────│             │
     │                 │                    │ {code_verifier, │               │             │
     │                 │                    │  return_to}     │               │             │
     │                 │                    │                 │               │             │
     │                 │                    │ 4. Get client_id│               │             │
     │                 │                    │    & client_secret              │             │
     │                 │                    │    from Vault   │               │             │
     │                 │                    │────────────────▶│               │             │
     │                 │                    │◀────────────────│               │             │
     │                 │                    │                 │               │             │
     │                 │                    │ 5. POST /token  │               │             │
     │                 │                    │    (code, verifier,             │             │
     │                 │                    │     client_id,  │               │             │
     │                 │                    │     client_secret)              │             │
     │                 │                    │──────────────────────────────────────────────▶│
     │                 │                    │                 │               │             │
     │                 │                    │◀──────────────────────────────────────────────│
     │                 │                    │ {id_token,      │               │             │
     │                 │                    │  access_token}  │               │             │
     │                 │                    │                 │               │             │
     │                 │                    │ 6. Validate tokens              │             │
     │                 │                    │    Extract claims               │             │
     │                 │                    │                 │               │             │
     │                 │                    │ 7. Get pepper   │               │             │
     │                 │                    │    from Vault   │               │             │
     │                 │                    │────────────────▶│               │             │
     │                 │                    │◀────────────────│               │             │
     │                 │                    │                 │               │             │
     │                 │                    │ 8. Generate session_id          │             │
     │                 │                    │    Derive key (HKDF + pepper)   │             │
     │                 │                    │    Encrypt session (AES-256-GCM)│             │
     │                 │                    │                 │               │             │
     │                 │                    │ 9. Store encrypted              │             │
     │                 │                    │    session      │               │             │
     │                 │                    │────────────────────────────────▶│             │
     │                 │                    │                 │               │             │
     │                 │                    │ 10. Delete state:Y              │             │
     │                 │                    │────────────────────────────────▶│             │
     │                 │                    │                 │               │             │
     │ 11. 302 to return_to (e.g., /welcome)│                 │               │             │
     │     Set-Cookie: session_id=...       │                 │               │             │
     │◀────────────────│◀───────────────────│                 │               │             │
     │                 │                    │                 │               │             │
```

### Flow 5: Authenticated Request (Session Validation)

```
┌─────────┐      ┌────────────┐      ┌────────────┐      ┌───────┐       ┌───────┐      ┌─────────┐
│ Browser │      │ API Gateway│      │apigw_authzr│      │ Vault │       │ Cache │      │ Backend │
└────┬────┘      └─────┬──────┘      └──────┬─────┘      └───┬───┘       └───┬───┘      └────┬────┘
     │                 │                    │                │               │               │
     │ 1. GET /welcome │                    │                │               │               │
     │    Cookie:      │                    │                │               │               │
     │    session_id=X │                    │                │               │               │
     │────────────────▶│                    │                │               │               │
     │                 │                    │                │               │               │
     │                 │ 2. Call authorizer │                │               │               │
     │                 │    (Cookie, UA)    │                │               │               │
     │                 │───────────────────▶│                │               │               │
     │                 │                    │                │               │               │
     │                 │                    │ 3. Get encrypted               │               │
     │                 │                    │    session:X   │               │               │
     │                 │                    │───────────────────────────────▶│               │
     │                 │                    │◀───────────────────────────────│               │
     │                 │                    │ {ciphertext,   │               │               │
     │                 │                    │  tag, nonce}   │               │               │
     │                 │                    │                │               │               │
     │                 │                    │ 4. Get pepper  │               │               │
     │                 │                    │    from Vault  │               │               │
     │                 │                    │───────────────▶│               │               │
     │                 │                    │◀───────────────│               │               │
     │                 │                    │                │               │               │
     │                 │                    │ 5. Derive key (HKDF + pepper)  │               │
     │                 │                    │    Decrypt session             │               │
     │                 │                    │    Validate User-Agent         │               │
     │                 │                    │    Check expiry                │               │
     │                 │                    │                │               │               │
     │                 │ 6. {active: true,  │                │               │               │
     │                 │     context: {     │                │               │               │
     │                 │       sub, email,  │                │               │               │
     │                 │       name, groups │                │               │               │
     │                 │     }}             │                │               │               │
     │                 │◀───────────────────│                │               │               │
     │                 │                    │                │               │               │
     │                 │ 7. Forward to backend               │               │               │
     │                 │    + X-User-Sub: ...                │               │               │
     │                 │    + X-User-Email: ...              │               │               │
     │                 │    + X-User-Name: ...               │               │               │
     │                 │    + X-User-Groups: ...             │               │               │
     │                 │────────────────────────────────────────────────────────────────────▶│
     │                 │                    │                │               │               │
     │                 │◀────────────────────────────────────────────────────────────────────│
     │ 8. 200 OK + HTML│                    │                │               │               │
     │◀────────────────│                    │                │               │               │
     │                 │                    │                │               │               │
```

### Flow 6: Logout

```
┌─────────┐      ┌────────────┐      ┌───────────┐      ┌───────┐       ┌─────┐
│ Browser │      │ API Gateway│      │oidc_logout│      │ Cache │       │ IdP │
└────┬────┘      └─────┬──────┘      └─────┬─────┘      └───┬───┘       └──┬──┘
     │                 │                   │                │              │
     │ 1. GET /auth/logout                 │                │              │
     │    Cookie: session_id=X             │                │              │
     │────────────────▶│                   │                │              │
     │                 │                   │                │              │
     │                 │ 2. Route to       │                │              │
     │                 │    oidc_logout    │                │              │
     │                 │──────────────────▶│                │              │
     │                 │                   │                │              │
     │                 │                   │ 3. Delete      │              │
     │                 │                   │    session:X   │              │
     │                 │                   │───────────────▶│              │
     │                 │                   │                │              │
     │ 4. 302 to IdP /logout               │                │              │
     │    Set-Cookie: session_id=;         │                │              │
     │    Max-Age=0; Path=/                │                │              │
     │◀────────────────│◀──────────────────│                │              │
     │                 │                   │                │              │
     │ 5. GET IdP /logout?post_logout_redirect_uri=...      │              │
     │────────────────────────────────────────────────────────────────────▶│
     │                 │                   │                │              │
     │ 6. 302 to post_logout_redirect_uri  │                │              │
     │    (e.g., /logged-out.html)         │                │              │
     │◀────────────────────────────────────────────────────────────────────│
     │                 │                   │                │              │
```

## Security Mechanisms

### PKCE (Proof Key for Code Exchange)

Protects against authorization code interception:

1. **Login**: Generate random `code_verifier` (43-128 chars)
2. **Login**: Compute `code_challenge = BASE64URL(SHA256(code_verifier))`
3. **Login**: Send `code_challenge` to IdP in authorize request
4. **Callback**: Send `code_verifier` to IdP in token request
5. **IdP**: Verifies `SHA256(code_verifier) == code_challenge`

```python
# Generation (oidc_authn)
code_verifier = base64url(random(32))  # 43 chars
code_challenge = base64url(sha256(code_verifier))

# Verification (IdP)
assert sha256(received_verifier) == stored_challenge
```

### State Parameter (CSRF Protection)

Prevents cross-site request forgery:

1. **Login**: Generate random `state`
2. **Login**: Store `{state: {code_verifier, return_to}}` in cache (5 min TTL)
3. **Callback**: Verify `state` from IdP matches stored state
4. **Callback**: Delete state after use (one-time)

### Session Encryption

Sessions are encrypted at rest in OCI Cache:

1. **Key Derivation**: `key = HKDF(pepper, session_id, "session-encryption")`
2. **Encryption**: `AES-256-GCM(key, plaintext)` → ciphertext + tag + nonce
3. **Storage**: `session:{id}` → `{ciphertext, tag, nonce}`

```python
# Encryption
key = hkdf_sha256(pepper, salt=session_id, info="session-encryption", length=32)
ciphertext, tag, nonce = aes_gcm_encrypt(key, session_data)

# Decryption
key = hkdf_sha256(pepper, salt=session_id, info="session-encryption", length=32)
session_data = aes_gcm_decrypt(key, ciphertext, tag, nonce)
```

### Session Binding

Sessions are bound to the User-Agent to prevent cookie theft:

1. **Creation**: Store `ua_hash = SHA256(User-Agent)` in session
2. **Validation**: Compare request's `SHA256(User-Agent)` with stored hash
3. **Mismatch**: Reject session (treat as invalid)

## Session Data Structure

```json
{
  "session_id": "abc123...",
  "user_sub": "user-ocid-...",
  "email": "user@example.com",
  "name": "John Doe",
  "given_name": "John",
  "family_name": "Doe",
  "preferred_username": "johndoe",
  "groups": ["Developers", "AppUsers"],
  "id_token": "eyJ...",
  "access_token": "eyJ...",
  "ua_hash": "sha256...",
  "created_at": 1700000000,
  "expires_at": 1700028800
}
```

## User Claims Propagation

The authorizer returns claims in the `context` object, which API Gateway makes available as `request.auth[claim_name]`:

| Claim | Header | Source |
|-------|--------|--------|
| `sub` | `X-User-Sub` | ID Token |
| `email` | `X-User-Email` | Custom Claim |
| `name` | `X-User-Name` | ID Token |
| `given_name` | `X-User-Given-Name` | Custom Claim |
| `family_name` | `X-User-Family-Name` | Custom Claim |
| `preferred_username` | `X-User-Username` | ID Token |
| `groups` | `X-User-Groups` | Custom Claim |
| `session_id` | `X-User-Session` | Session |

## Error Handling

| Scenario | Response | Action |
|----------|----------|--------|
| No session cookie | 302 → /auth/login | Start login flow |
| Invalid/expired session | 302 → /auth/login | Re-authenticate |
| User-Agent mismatch | 302 → /auth/login | Possible hijacking |
| Invalid state parameter | 400 Bad Request | CSRF attempt |
| Token exchange failure | 500 + error page | IdP issue |
| Cache unavailable | 500 + error page | Infrastructure issue |
