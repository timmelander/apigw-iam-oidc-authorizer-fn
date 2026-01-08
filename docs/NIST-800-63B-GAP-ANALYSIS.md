# NIST 800-63B Session Management Gap Analysis

This document provides a gap analysis comparing this project's session management implementation against [NIST Special Publication 800-63B Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html), specifically the [Session Management requirements](https://pages.nist.gov/800-63-3-Implementation-Resources/63B/Session/).

## Table of Contents

- [Executive Summary](#executive-summary)
- [Scope and AAL Context](#scope-and-aal-context)
- [NIST 800-63B Requirements Summary](#nist-800-63b-requirements-summary)
- [Compliance Assessment](#compliance-assessment)
  - [Requirements Met](#requirements-met)
  - [Gaps Identified](#gaps-identified)
- [Remediation Recommendations](#remediation-recommendations)
- [OCI IAM Identity Domain Capabilities](#oci-iam-identity-domain-capabilities)
- [References](#references)

---

## Executive Summary

This POC implementation provides a solid foundation for NIST 800-63B session management compliance at **AAL1** level, with several controls already meeting **AAL2** requirements. Key strengths include cryptographically secure session tokens, encrypted session storage, and secure cookie attributes.

**Primary gaps** requiring remediation for AAL2 compliance:
1. No idle session timeout (NIST requires ≤30 minutes)
2. Session binding (User-Agent) is disabled
3. No reauthentication mechanism for extended sessions

These gaps can be addressed through application code changes and OCI IAM Identity Domain configuration.

---

## Scope and AAL Context

### Authenticator Assurance Levels

NIST 800-63B defines three Authenticator Assurance Levels with progressively stricter session requirements:

| Level | Authentication | Session Timeout (Absolute) | Idle Timeout | Reauthentication |
|-------|---------------|---------------------------|--------------|------------------|
| **AAL1** | Single factor | 30 days | No requirement | Any authenticator |
| **AAL2** | Multi-factor | 12 hours | 30 minutes | Memorized secret or biometric |
| **AAL3** | Hardware MFA | 12 hours | 15 minutes | Both factors required |

### This Project's Context

- **Current POC state**: Basic authentication via OCI IAM Identity Domain
- **Target capability**: AAL2 achievable with Identity Domain MFA policies
- **AAL3 capability**: Possible via FIDO2/WebAuthn authenticators in Identity Domain

---

## NIST 800-63B Requirements Summary

> "Strength of session management procedures is as important as authentication, since the ability to hijack a session is as damaging as an authentication failure."
> — NIST SP 800-63B, Section 7

### Core Session Management Requirements

| Requirement | Description |
|-------------|-------------|
| **Session Secret** | Random value with sufficient entropy, transmitted over authenticated protected channel |
| **Session Binding** | Tie session to subscriber characteristics (device, User-Agent) |
| **Absolute Timeout** | Maximum session lifetime based on AAL level |
| **Idle Timeout** | Terminate session after inactivity period |
| **Reauthentication** | Periodic confirmation subscriber still controls session |
| **Secure Cookies** | HttpOnly, Secure flags; inaccessible to JavaScript |
| **Federation** | RP should govern session timeout; IdP provides auth timestamp |

---

## Compliance Assessment

### Requirements Met

The following NIST 800-63B requirements are **fully or substantially met** by the current implementation:

#### 1. Cryptographically Secure Session Secrets

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| Sufficient entropy for session ID | `secrets.token_urlsafe(32)` generates 256-bit random value | **Met** |
| Approved random bit generator | Python `secrets` module uses OS CSPRNG | **Met** |
| Transmitted over protected channel | HTTPS only (API Gateway TLS termination) | **Met** |

**Code Reference:** `functions/oidc_callback/func.py:296`
```python
session_id = secrets.token_urlsafe(32)
```

#### 2. Session Data Encryption

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| Protect session data at rest | AES-256-GCM encryption | **Met** |
| Key derivation | HKDF-SHA256 with pepper from OCI Vault | **Met** |
| Unique key per session | Derived from session_id + pepper | **Met** |

**Code Reference:** `functions/oidc_callback/func.py:91-100`

#### 3. Secure Cookie Attributes

| Attribute | NIST Requirement | Implementation | Status |
|-----------|-----------------|----------------|--------|
| `HttpOnly` | Prevent JavaScript access | `HttpOnly` set | **Met** |
| `Secure` | HTTPS only transmission | `Secure` set | **Met** |
| `SameSite` | CSRF protection | `SameSite=Lax` | **Met** |
| `Path` | Scope restriction | `Path=/` | **Met** |

**Code Reference:** `functions/oidc_callback/func.py:323-330`
```python
cookie_parts = [
    f"{SESSION_COOKIE_NAME}={session_id}",
    "HttpOnly",
    "Secure",
    "SameSite=Lax"
]
```

#### 4. Absolute Session Timeout

| AAL Level | NIST Requirement | Implementation | Status |
|-----------|-----------------|----------------|--------|
| AAL1 | ≤30 days | 8 hours default | **Met** |
| AAL2 | ≤12 hours | 8 hours default | **Met** |
| AAL3 | ≤12 hours | 8 hours default | **Met** |

**Configuration:** `SESSION_TTL_SECONDS=28800` (8 hours)

#### 5. State Parameter / Replay Prevention

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| CSRF protection via state | Random state parameter with PKCE | **Met** |
| One-time state use | Atomic `GETDEL` prevents replay | **Met** |
| State TTL | 5-minute expiration | **Met** |

**Code Reference:** `functions/oidc_callback/func.py:228`
```python
state_data_raw = r.execute_command('GETDEL', f"state:{state}")
```

#### 6. Avoid Session Leakage

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| No session in URLs | Cookie-only session transport | **Met** |
| No logging of secrets | Session ID not logged in full | **Met** |
| Cache-Control headers | `no-store` on auth responses | **Met** |

---

### Gaps Identified

The following NIST 800-63B requirements are **not met or partially met**:

#### Gap 1: No Idle Session Timeout (AAL2/AAL3)

| Aspect | NIST Requirement | Current State | Impact |
|--------|-----------------|---------------|--------|
| AAL2 Idle Timeout | ≤30 minutes | **Not implemented** | High |
| AAL3 Idle Timeout | ≤15 minutes | **Not implemented** | High |

**NIST Requirement:**
> "Reauthentication of the subscriber SHALL be repeated following any period of inactivity lasting 30 minutes or longer." (AAL2)

**Current Behavior:** Sessions remain valid for the full 8-hour absolute timeout regardless of user activity. An unattended device remains authenticated.

**Risk:** If a user walks away from their device, an attacker with physical access has up to 8 hours to misuse the session.

#### Gap 2: Session Binding Disabled

| Aspect | NIST Requirement | Current State | Impact |
|--------|-----------------|---------------|--------|
| Session binding | Tie to subscriber characteristics | **Disabled in POC** | Medium |

**NIST Requirement:**
> Session binding ties the session to the subscriber through a characteristic (e.g., device identity, User-Agent) that would change if the session were hijacked.

**Current Behavior:** User-Agent binding code exists but is commented out in `apigw_authzr/func.py:235-248`:
```python
# Validate session binding (disabled for POC - UA handling differs...)
# if stored_ua_hash != current_ua_hash:
#     return authorize_failure("binding_mismatch")
```

**Risk:** Session cookies stolen via XSS or network interception can be used from any device without detection.

#### Gap 3: No Reauthentication Mechanism

| Aspect | NIST Requirement | Current State | Impact |
|--------|-----------------|---------------|--------|
| Periodic reauth | Confirm subscriber presence | **Not implemented** | Medium |
| Reauth warning | Advance notice before timeout | **Not implemented** | Low |

**NIST Requirement:**
> "Reauthentication is a periodic process during which a subscriber demonstrates that they are still in control of the valid session secret."

**Current Behavior:** No mechanism exists to:
- Require reauthentication after idle period
- Warn users before session expiration
- Allow single-factor reauth to extend session

**Risk:** No verification that the original authenticated user is still present at the device.

#### Gap 4: Federation Session Coordination

| Aspect | NIST Requirement | Current State | Impact |
|--------|-----------------|---------------|--------|
| IdP auth timestamp | Assert `auth_time` in tokens | Available but unused | Low |
| Session alignment | Coordinate RP/IdP timeouts | **Partially implemented** | Low |

**NIST Requirement:**
> "The IdP should assert the authentication timestamp and the maximum authentication age to enable the RP to make appropriate reauthentication timing decisions."

**Current Behavior:**
- OCI Identity Domain sends `auth_time` in ID token
- Application does not use `auth_time` for session timeout decisions
- IdP and RP session timeouts are configured independently

---

## Remediation Recommendations

### Priority 1: Implement Idle Timeout (AAL2 Requirement)

**Approach A: Application-Level Idle Tracking**

Add `last_activity` timestamp to session data, update on each request:

```python
session_data = {
    ...
    'last_activity': datetime.now(timezone.utc).isoformat(),
}
```

In authorizer, check idle timeout:
```python
IDLE_TIMEOUT_SECONDS = 1800  # 30 minutes for AAL2

last_activity = datetime.fromisoformat(session_data.get('last_activity'))
if datetime.now(timezone.utc) - last_activity > timedelta(seconds=IDLE_TIMEOUT_SECONDS):
    return authorize_failure("session_idle_timeout")
```

**Approach B: Sliding Window with Redis TTL**

Use a separate Redis key for activity tracking with short TTL:
```python
r.set(f"activity:{session_id}", "1", ex=IDLE_TIMEOUT_SECONDS)
```

Check existence in authorizer - if missing, session is idle-timed-out.

### Priority 2: Enable Session Binding

Uncomment and test the User-Agent binding code in `apigw_authzr/func.py`:

```python
stored_ua_hash = session_data.get('ua_hash', '')
if stored_ua_hash and user_agent:
    current_ua_hash = hashlib.sha256(user_agent.encode('utf-8')).hexdigest()[:16]
    if stored_ua_hash != current_ua_hash:
        logger.warning(f"Session binding mismatch")
        return authorize_failure("binding_mismatch")
```

**Note:** Test thoroughly as User-Agent handling may differ between API Gateway and direct requests.

### Priority 3: Implement Reauthentication

**Option A: Full Reauthentication on Idle Timeout**

When idle timeout occurs, redirect to `/auth/login` with `prompt=login` to force IdP reauthentication.

**Option B: Soft Reauthentication (AAL2 Compliant)**

Per NIST, AAL2 allows reauthentication with a single factor after idle timeout (if absolute timeout not reached):

1. Redirect to `/auth/reauth` endpoint
2. Accept password-only or biometric verification
3. Extend session if successful

This requires OCI Identity Domain support for step-up authentication or a custom password verification flow.

### Priority 4: Configure Identity Domain Session Limits

Align OCI IAM Identity Domain session settings with application requirements:

| Setting | AAL2 Recommendation | Configuration Path |
|---------|--------------------|--------------------|
| Session Duration | ≤720 minutes (12 hours) | Settings → Session settings |
| My Apps Idle Timeout | ≤30 minutes | Settings → Session settings |

---

## OCI IAM Identity Domain Capabilities

OCI IAM Identity Domains provide several features relevant to NIST 800-63B compliance:

### Authentication Assurance Levels

| OCI IAM Feature | AAL Support | Notes |
|-----------------|-------------|-------|
| Username/Password | AAL1 | Single factor |
| Password + SMS/Email OTP | AAL1* | NIST considers SMS OTP restricted |
| Password + TOTP App | AAL2 | Time-based one-time password |
| Password + Push Notification | AAL2 | Oracle Mobile Authenticator |
| FIDO2/WebAuthn | AAL2/AAL3 | Phishing-resistant, hardware option for AAL3 |
| Passkeys | AAL2 | Device-bound or synced credentials |

*SMS OTP is classified as a "restricted" authenticator by NIST due to known vulnerabilities.

### Session Configuration

| Setting | Range | Default | Documentation |
|---------|-------|---------|---------------|
| Session Duration | 1-32,767 min | 600 min | [Session Limits](https://docs.oracle.com/en-us/iaas/Content/Identity/sessionsettings/session-limits.htm) |
| My Apps Idle Timeout | 5-480 min | 480 min | [Session Settings](https://docs.oracle.com/en-us/iaas/Content/Identity/sessionsettings/change-session-settings.htm) |

### MFA Enforcement via Sign-On Policies

OCI Identity Domain Sign-On Policies can enforce MFA based on:
- User group membership
- Network conditions (IP address)
- Device posture
- Application sensitivity

**Configuration Path:** Identity Domain → Security → Sign-on policies

### FIDO2/WebAuthn for AAL3

For AAL3 compliance, configure FIDO2 authenticators:
1. Enable FIDO2 in: Identity Domain → Security → MFA
2. Require hardware security keys in Sign-On Policy
3. Users register FIDO2 devices in My Apps

---

## Compliance Summary Matrix

| NIST 800-63B Requirement | AAL1 | AAL2 | AAL3 | Current Status |
|--------------------------|------|------|------|----------------|
| Secure random session ID | Req | Req | Req | **Met** |
| Protected channel (TLS) | Req | Req | Req | **Met** |
| HttpOnly cookies | Rec | Req | Req | **Met** |
| Secure cookies | Req | Req | Req | **Met** |
| Absolute timeout | 30d | 12h | 12h | **Met** (8h) |
| Idle timeout | — | 30m | 15m | **Gap** |
| Session binding | Rec | Rec | Req | **Gap** (disabled) |
| Reauthentication | Any | MFA or PW | Both factors | **Gap** |
| Replay prevention | Req | Req | Req | **Met** (GETDEL) |
| Session encryption | Rec | Rec | Req | **Met** (AES-GCM) |

**Legend:** Req = Required, Rec = Recommended, — = Not specified

---

## References

### NIST Publications
- [NIST SP 800-63B Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)
- [NIST 800-63B Session Management Implementation Resources](https://pages.nist.gov/800-63-3-Implementation-Resources/63B/Session/)
- [NIST SP 800-63B-4 Draft (August 2024)](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-63B-4.2pd.pdf)

### OCI Documentation
- [OCI IAM Session Limits](https://docs.oracle.com/en-us/iaas/Content/Identity/sessionsettings/session-limits.htm)
- [Changing Session Settings](https://docs.oracle.com/en-us/iaas/Content/Identity/sessionsettings/change-session-settings.htm)
- [Implementing MFA in OCI IAM Identity Domains](https://blogs.oracle.com/cloudsecurity/post/implementing-mfa-oci-iam-identity-domains)

### Related Project Documentation
- [Security Guide](./SECURITY.md)
- [Configuration Reference](./CONFIGURATION.md)
- [How It Works](./HOW_IT_WORKS.md)
