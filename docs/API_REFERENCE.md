# API Reference

This document describes all API endpoints exposed by the OCI API Gateway + OIDC Authentication solution.

## Base URL

```
https://<gateway-id>.apigateway.<region>.oci.customer-oci.com
```

---

## Public Endpoints (No Authentication)

### GET /health

Health check endpoint.

**Request:**
```
GET /health HTTP/1.1
Host: <gateway-url>
```

**Response (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

---

### GET /auth/login

Initiates the OIDC authentication flow.

**Request:**
```
GET /auth/login HTTP/1.1
Host: <gateway-url>
```

**Query Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `return_to` | No | URL to redirect after successful login |

**Response (302 Redirect):**
```
HTTP/1.1 302 Found
Location: https://idcs-xxx.identity.oraclecloud.com/oauth2/v1/authorize?
  client_id=<client-id>&
  redirect_uri=https://<gateway>/auth/callback&
  response_type=code&
  scope=openid+profile+email+groups&
  state=<random-state>&
  code_challenge=<pkce-challenge>&
  code_challenge_method=S256
```

**Example:**
```bash
# Start login flow
curl -sI "https://<gateway>/auth/login?return_to=/welcome"

# Response
HTTP/2 302
location: https://idcs-xxx.identity.oraclecloud.com/oauth2/v1/authorize?...
```

---

### GET /auth/callback

OAuth2 callback endpoint. Called by the Identity Provider after authentication.

**Request:**
```
GET /auth/callback?code=<auth-code>&state=<state> HTTP/1.1
Host: <gateway-url>
```

**Query Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `code` | Yes | Authorization code from IdP |
| `state` | Yes | State parameter (must match stored state) |
| `error` | No | Error code if authentication failed |
| `error_description` | No | Human-readable error description |

**Response (302 Redirect on Success):**
```
HTTP/1.1 302 Found
Location: /welcome
Set-Cookie: session_id=<uuid>; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=28800
```

**Response (400 Bad Request on Error):**
```json
{
  "error": "invalid_state",
  "message": "State parameter does not match"
}
```

**Error Codes:**

| Code | Description |
|------|-------------|
| `invalid_state` | State parameter missing or doesn't match |
| `missing_code` | Authorization code not provided |
| `token_exchange_failed` | Failed to exchange code for tokens |
| `invalid_token` | ID token validation failed |

---

### GET/POST /auth/logout

Terminates the user session and redirects to Identity Provider logout.

**Request:**
```
GET /auth/logout HTTP/1.1
Host: <gateway-url>
Cookie: session_id=<session-id>
```

**Response (302 Redirect):**
```
HTTP/1.1 302 Found
Location: https://idcs-xxx.identity.oraclecloud.com/oauth2/v1/userlogout?
  post_logout_redirect_uri=https://<gateway>/logged-out
Set-Cookie: session_id=; Path=/; HttpOnly; Secure; Max-Age=0
```

**Example:**
```bash
curl -sI "https://<gateway>/auth/logout" -H "Cookie: session_id=abc123"

# Response
HTTP/2 302
location: https://idcs-xxx.identity.oraclecloud.com/oauth2/v1/userlogout?...
set-cookie: session_id=; Path=/; HttpOnly; Secure; Max-Age=0
```

---

### GET /

Landing page (anonymous access).

**Request:**
```
GET / HTTP/1.1
Host: <gateway-url>
```

**Response (200 OK):**
```html
<!DOCTYPE html>
<html>
<head><title>Welcome</title></head>
<body>...</body>
</html>
```

---

### GET /logged-out

Post-logout page (anonymous access).

**Request:**
```
GET /logged-out HTTP/1.1
Host: <gateway-url>
```

**Response (200 OK):**
```html
<!DOCTYPE html>
<html>
<head><title>Logged Out</title></head>
<body>You have been logged out.</body>
</html>
```

---

## Protected Endpoints (Authentication Required)

All protected endpoints require a valid session cookie. Without a valid session, the request is redirected to `/auth/login`.

### GET /welcome

User information page.

**Request:**
```
GET /welcome HTTP/1.1
Host: <gateway-url>
Cookie: session_id=<valid-session-id>
```

**Response (200 OK with Valid Session):**
```html
<!DOCTYPE html>
<html>
<body>
  <h1>Welcome, John Doe!</h1>
  <p>Email: john@example.com</p>
</body>
</html>
```

**Response (302 Redirect without Valid Session):**
```
HTTP/1.1 302 Found
Location: /auth/login
```

---

### GET /debug

Debug page showing all user claims (development only).

**Request:**
```
GET /debug HTTP/1.1
Host: <gateway-url>
Cookie: session_id=<valid-session-id>
```

**Response Headers (Added by API Gateway):**

| Header | Value |
|--------|-------|
| `X-User-Sub` | User's unique identifier |
| `X-User-Email` | User's email address |
| `X-User-Name` | User's display name |
| `X-User-Username` | User's preferred username |
| `X-User-Given-Name` | User's first name |
| `X-User-Family-Name` | User's last name |
| `X-User-Groups` | Comma-separated group list |
| `X-User-Session` | Session ID |
| `X-Session-Created` | Session creation timestamp |
| `X-Raw-Claims` | Raw claims from ID token (JSON) |
| `X-Userinfo-Claims` | Claims from userinfo endpoint (JSON) |

---

## Authentication Details

### Session Cookie

| Attribute | Value |
|-----------|-------|
| Name | `session_id` |
| Value | UUID (e.g., `550e8400-e29b-41d4-a716-446655440000`) |
| Path | `/` |
| HttpOnly | `true` |
| Secure | `true` |
| SameSite | `Lax` |
| Max-Age | `28800` (8 hours) |

### Authorizer Response

The `apigw_authzr` function returns claims in the context, which become available as `request.auth[claim]` in API Gateway:

| Claim | Description | Example |
|-------|-------------|---------|
| `sub` | User's unique identifier | `abc123...` |
| `email` | Email address | `user@example.com` |
| `name` | Display name | `John Doe` |
| `given_name` | First name | `John` |
| `family_name` | Last name | `Doe` |
| `preferred_username` | Username | `johndoe` |
| `groups` | Group membership | `Developers,AppUsers` |
| `session_id` | Session identifier | `550e8400...` |
| `session_iat` | Session creation time | `1700000000` |

---

## Error Responses

### 302 Found (Redirect to Login)

Returned when accessing a protected resource without a valid session.

```
HTTP/1.1 302 Found
Location: /auth/login
```

### 400 Bad Request

Returned for malformed requests.

```json
{
  "error": "bad_request",
  "message": "Missing required parameter: state"
}
```

### 401 Unauthorized

Returned for API routes (if configured) when session is invalid.

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="api"
```

### 500 Internal Server Error

Returned when an unexpected error occurs.

```json
{
  "error": "internal_error",
  "message": "An unexpected error occurred"
}
```

### 502 Bad Gateway

Returned when a backend function fails to respond.

```
HTTP/1.1 502 Bad Gateway
```

---

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| `/health` | 100 req/s |
| `/auth/login` | 10 req/s per IP |
| `/auth/callback` | 10 req/s per IP |
| `/auth/logout` | 10 req/s per IP |
| Protected routes | 50 req/s per session |

---

## Testing with cURL

### Health Check

```bash
curl -s https://<gateway>/health | jq
```

### Check Login Redirect

```bash
curl -sI https://<gateway>/auth/login
```

### Access Protected Route (No Session)

```bash
curl -sI https://<gateway>/welcome
# Expect: 302 redirect to /auth/login
```

### Access Protected Route (With Session)

```bash
curl -s https://<gateway>/welcome \
  -H "Cookie: session_id=<valid-session-id>"
```

### Logout

```bash
curl -sI https://<gateway>/auth/logout \
  -H "Cookie: session_id=<valid-session-id>"
```

---

## OpenAPI Specification

```yaml
openapi: 3.0.0
info:
  title: OCI API Gateway OIDC Authentication
  version: 1.0.0

paths:
  /health:
    get:
      summary: Health check
      responses:
        '200':
          description: Service is healthy

  /auth/login:
    get:
      summary: Initiate OIDC login
      parameters:
        - name: return_to
          in: query
          schema:
            type: string
      responses:
        '302':
          description: Redirect to Identity Provider

  /auth/callback:
    get:
      summary: OAuth2 callback
      parameters:
        - name: code
          in: query
          required: true
          schema:
            type: string
        - name: state
          in: query
          required: true
          schema:
            type: string
      responses:
        '302':
          description: Redirect to original URL with session cookie
        '400':
          description: Invalid request

  /auth/logout:
    get:
      summary: Logout
      responses:
        '302':
          description: Redirect to Identity Provider logout

  /welcome:
    get:
      summary: Protected welcome page
      security:
        - sessionCookie: []
      responses:
        '200':
          description: Welcome page
        '302':
          description: Redirect to login

securitySchemes:
  sessionCookie:
    type: apiKey
    in: cookie
    name: session_id
```
