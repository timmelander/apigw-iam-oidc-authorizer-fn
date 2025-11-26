# OCI API Gateway - Multi-Argument Authorizer Functions

**Source:** [Oracle Official Documentation](https://docs.oracle.com/en-us/iaas/Content/APIGateway/Tasks/apigatewayusingauthorizerfunction_topic-Creating_an_Authorizer_Function.htm)

**Research Date:** 2025-01-22

---

## Overview

Oracle recommends the use of **multi-argument authorizer functions** rather than single-argument authorizer functions because of their additional versatility. Single-argument authorizer functions are **planned for deprecation** in a future release.

Multi-argument authorizer functions can:
- Accept multiple request elements (headers, query params, cookies, body)
- Perform finer-grained, request-based authentication
- Query decision services and policy agents with multiple attributes
- Cache results with configurable cache keys

---

## Request Format

### Multi-Argument (Recommended)

```json
{
  "type": "USER_DEFINED",
  "data": {
    "<argument-n>": "<context-variable-value>",
    "<argument-m>": "<context-variable-value>"
  }
}
```

### Single-Argument (Deprecated)

```json
{
  "type": "TOKEN",
  "token": "<token-value>"
}
```

---

## Response Format

### Valid Token (HTTP 200)

```json
{
  "active": true,
  "scope": ["<scopes>"],
  "expiresAt": "<date-time>",
  "context": {
    "<key>": "<value>"
  }
}
```

### Invalid Token (HTTP 200)

```json
{
  "active": false,
  "wwwAuthenticate": "<directive>"
}
```

### Error (HTTP 5xx)

Returns HTTP 5xx to indicate verification failure. API Gateway returns HTTP 502 to clients.

---

## Available Context Variables

| Context Table | Description |
|---------------|-------------|
| `request.headers` | Header names and values from the request |
| `request.query` | Query parameter names and values |
| `request.body` | Request body (multi-argument only) |
| `request.host` | Host name from Host header |
| `request.cert` | Base64-encoded TLS certificate (mTLS) |
| `request.path` | Path parameters from API spec |
| `request.subdomain` | Leading part of hostname |

### Accessing Headers

Use bracket notation: `request.headers[Header-Name]`

Examples:
- `request.headers[Authorization]`
- `request.headers[Cookie]`
- `request.headers[User-Agent]`
- `request.headers[X-Forwarded-For]`

**Important:** If a header is not present in the original request, that argument is **not passed** to the authorizer function (rather than being passed with null).

---

## Configuration Example

### API Gateway Deployment Spec

```json
{
  "requestPolicies": {
    "authentication": {
      "type": "CUSTOM_AUTHENTICATION",
      "functionId": "ocid1.fnfunc.oc1.phx.aaaaaaaaac2______kg6fq",
      "isAnonymousAccessAllowed": false,
      "parameters": {
        "cookie": "request.headers[Cookie]",
        "userAgent": "request.headers[User-Agent]",
        "xForwardedFor": "request.headers[X-Forwarded-For]"
      },
      "cacheKey": ["cookie"]
    }
  }
}
```

### Function Arguments Mapping (Console)

| Context | Header Name | Argument Name |
|---------|-------------|---------------|
| request.headers | Cookie | cookie |
| request.headers | User-Agent | userAgent |
| request.headers | X-Forwarded-For | xForwardedFor |

---

## Cache Key Configuration

The cache key defaults to all arguments except those from `request.body`. Customize via:

```json
"cacheKey": ["<argument-1>", "<argument-2>"]
```

For session-based auth, caching by cookie reduces function invocations for repeated requests with the same session.

---

## Testing Multi-Argument Functions

### Direct Function Invocation

```bash
echo -n '{"type": "USER_DEFINED", "data": {"cookie": "session_id=abc123", "userAgent": "Mozilla/5.0..."}}' | fn invoke <app> <function>
```

### API Gateway Test

```bash
curl -i \
  -H "Cookie: session_id=abc123" \
  -H "User-Agent: Mozilla/5.0..." \
  https://api.example.com/api/endpoint
```

---

## Key Differences from Single-Argument

| Aspect | Single-Argument | Multi-Argument |
|--------|-----------------|----------------|
| Token source | Single header/param | Multiple request elements |
| Payload type | `TOKEN` | `USER_DEFINED` |
| Deprecation | Planned | Recommended |
| Session binding | Requires manual header parsing | Direct access to headers |
| Caching | Limited | Configurable cache keys |

---

## References

> The following are official Oracle Cloud Infrastructure documentation links for API Gateway authorizer functions.

- [Creating an Authorizer Function](https://docs.oracle.com/en-us/iaas/Content/APIGateway/Tasks/apigatewayusingauthorizerfunction_topic-Creating_an_Authorizer_Function.htm)
- [Adding Authentication and Authorization Request Policies](https://docs.oracle.com/en-us/iaas/Content/APIGateway/Tasks/apigatewayusingauthorizerfunction_topic-Adding_authn_authz_request_policies.htm)
- [Adding Context Variables to Policies](https://docs.oracle.com/en-us/iaas/Content/APIGateway/Tasks/apigatewaycontextvariables.htm)
- [Tutorial: Customize API Security with Functions](https://docs.oracle.com/en/learn/apigw-authfn/index.html)
