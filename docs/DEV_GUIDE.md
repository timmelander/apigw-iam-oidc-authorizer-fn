# Development Guide

This guide is for developers who want to understand, modify, or extend the OCI API Gateway + OIDC Authentication solution. It covers the project structure, function architecture, local development setup, testing strategies, and how to add new features like custom claims or protected routes.

## Project Structure

```
.
├── functions/
│   ├── apigw_authzr/           # Session validation authorizer
│   │   ├── Dockerfile          # Build configuration
│   │   ├── func.py             # Main handler
│   │   ├── func.yaml           # Function metadata
│   │   └── requirements.txt    # Python dependencies
│   ├── health/                 # Health check endpoint
│   │   ├── Dockerfile
│   │   ├── func.py
│   │   ├── func.yaml
│   │   └── requirements.txt
│   ├── oidc_authn/             # Login initiation
│   │   ├── Dockerfile
│   │   ├── func.py
│   │   ├── func.yaml
│   │   └── requirements.txt
│   ├── oidc_callback/          # OAuth callback handler
│   │   ├── Dockerfile
│   │   ├── func.py
│   │   ├── func.yaml
│   │   └── requirements.txt
│   └── oidc_logout/            # Session termination
│       ├── Dockerfile
│       ├── func.py
│       ├── func.yaml
│       └── requirements.txt
├── scripts/
│   ├── api_deployment.template.json  # API Gateway spec template (with placeholders)
│   ├── api_deployment.json           # Generated spec (gitignored, contains actual OCIDs)
│   ├── api_deployment_simple.json    # Minimal API Gateway spec (no auth)
│   ├── create_confidential_app.py    # Create OAuth2 app in Identity Domain
│   ├── create_groups_claim.py        # Add groups claim to OIDC tokens
│   ├── update_app_redirect_uris.py   # Update OAuth2 redirect URIs
│   └── verify-deployment.sh          # End-to-end OIDC flow test
├── policies/
│   └── oci-policies.txt              # IAM policy templates for deployment
├── docs/                       # Documentation
└── README.md
```

> **Note:** Each function folder contains a `Dockerfile` for building container images. See [FAQ: What is the Dockerfile in each function folder?](./FAQ.md#what-is-the-dockerfile-in-each-function-folder) for details on how multi-stage builds work.

## Function Architecture

### Common Patterns

All functions follow this pattern:

```python
import io
import json
import logging
from fdk import response

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def handler(ctx, data: io.BytesIO = None):
    try:
        # Parse input
        body = json.loads(data.getvalue()) if data else {}

        # Get configuration
        config = ctx.Config()

        # Business logic
        result = do_work(config, body)

        # Return response
        return response.Response(
            ctx,
            response_data=json.dumps(result),
            headers={"Content-Type": "application/json"}
        )
    except Exception as e:
        logger.exception("Handler error")
        return response.Response(
            ctx,
            response_data=json.dumps({"error": str(e)}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )
```

### Authorizer Response Format

The `apigw_authzr` function must return this format:

```python
# Success - allow request
{
    "active": True,
    "principal": "user-sub-value",
    "scope": ["openid", "profile"],
    "expiresAt": "2024-01-01T12:00:00Z",
    "context": {
        "sub": "user-sub",
        "email": "user@example.com",
        "name": "User Name",
        "groups": "Group1,Group2"
    }
}

# Failure - deny request
{
    "active": False,
    "wwwAuthenticate": "Bearer realm=\"api\""
}
```

### Redirect Response Format

For `oidc_authn` and `oidc_logout`:

```python
return response.Response(
    ctx,
    response_data="",
    status_code=302,
    headers={
        "Location": redirect_url,
        "Set-Cookie": cookie_string  # Optional
    }
)
```

---

## Local Development

### Prerequisites

```bash
# Python 3.11+
python3 --version

# Fn CLI
fn version

# Podman
podman --version
```

### Virtual Environment

```bash
# Create venv
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install fdk oci redis cryptography requests
```

### Local Testing (Unit Tests)

```python
# test_handler.py
import json
from unittest.mock import Mock, patch

def test_authorizer_valid_session():
    # Mock context
    ctx = Mock()
    ctx.Config.return_value = {
        "OCI_VAULT_PEPPER_OCID": "test-pepper",
        "OCI_CACHE_ENDPOINT": "localhost",
        "SESSION_COOKIE_NAME": "session_id"
    }

    # Mock data with valid session cookie
    data = json.dumps({
        "Cookie": "session_id=valid-session-id",
        "User-Agent": "Test Browser"
    })

    with patch('func.get_session') as mock_session:
        mock_session.return_value = {
            "sub": "user-123",
            "email": "test@example.com"
        }

        result = handler(ctx, io.BytesIO(data.encode()))

        assert result.status_code == 200
        body = json.loads(result.response_data)
        assert body["active"] == True
```

### Local Function Invocation

```bash
# Build and run locally (requires Podman)
cd functions/health
fn build
fn run

# In another terminal
curl -X POST http://localhost:8080 -d '{}'
```

---

## Adding New Features

### Adding a New Protected Route

1. **Update the template** (`scripts/api_deployment.template.json`) - add the new route:

```json
{
  "path": "/new-route",
  "methods": ["GET"],
  "backend": {
    "type": "HTTP_BACKEND",
    "url": "http://<backend-ip>/new-endpoint"
  },
  "requestPolicies": {
    "authorization": {
      "type": "AUTHENTICATION_ONLY"
    },
    "headerTransformations": {
      "setHeaders": {
        "items": [
          {"name": "X-User-Sub", "values": ["${request.auth[sub]}"]}
        ]
      }
    }
  }
}
```

2. **Regenerate and deploy** (see [Deployment Guide Section 5.3](./DEPLOYMENT_GUIDE.md#53-create-api-deployment)):
```bash
# Regenerate api_deployment.json from template with your OCIDs
# Then update the deployment:
oci api-gateway deployment update \
  --deployment-id <deployment-ocid> \
  --specification file://scripts/api_deployment.json --force
```

### Adding Custom Claims

1. **Configure in Identity Domain** via REST API (see [Managing Custom Claims](https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/custom-claims-token.htm))

2. **Update oidc_callback** to extract and store:
```python
# Extract from ID token
custom_claim = id_token_claims.get("custom_claim_name")

# Store in session
session_data["custom_claim"] = custom_claim
```

3. **Update apigw_authzr** to include in context:
```python
context["custom_claim"] = session_data.get("custom_claim", "")
```

4. **Update API Gateway** to pass as header:
```json
{"name": "X-Custom-Claim", "values": ["${request.auth[custom_claim]}"]}
```

### Adding New Function

1. **Create function directory**:
```bash
mkdir -p functions/new_function
cd functions/new_function
```

2. **Create func.yaml**:
```yaml
schema_version: 20180708
name: new_function
version: 0.0.1
runtime: python
build_image: fnproject/python:3.11-dev
run_image: fnproject/python:3.11
entrypoint: /python/bin/fdk /function/func.py handler
memory: 256
timeout: 60
```

3. **Create func.py**:
```python
import io
import json
from fdk import response

def handler(ctx, data: io.BytesIO = None):
    return response.Response(
        ctx,
        response_data=json.dumps({"status": "ok"}),
        headers={"Content-Type": "application/json"}
    )
```

4. **Create requirements.txt**:
```
fdk>=0.1.50
```

5. **Create Dockerfile** (optional, for custom builds):
```dockerfile
FROM fnproject/python:3.11-dev as build
WORKDIR /function
ADD requirements.txt .
RUN pip3 install --target /python -r requirements.txt
ADD . /function/

FROM fnproject/python:3.11
WORKDIR /function
COPY --from=build /python /python
COPY --from=build /function /function
ENV PYTHONPATH=/python
ENTRYPOINT ["/python/bin/fdk", "/function/func.py", "handler"]
```

6. **Deploy**:
```bash
fn deploy --app apigw-oidc-app
```

---

## Code Conventions

### Logging

```python
import logging
logger = logging.getLogger(__name__)

logger.debug("Detailed debug info")
logger.info("Normal operation")
logger.warning("Potential issue")
logger.error("Error occurred")
logger.exception("Error with stack trace")
```

### Error Handling

```python
# Specific exceptions
class SessionNotFoundError(Exception):
    pass

class SessionExpiredError(Exception):
    pass

# In handler
try:
    session = get_session(session_id)
except SessionNotFoundError:
    return deny_response("Session not found")
except SessionExpiredError:
    return deny_response("Session expired")
```

### Configuration Access

```python
def handler(ctx, data):
    config = ctx.Config()

    # Required config (raise if missing)
    cache_endpoint = config["OCI_CACHE_ENDPOINT"]

    # Optional config with default
    ttl = int(config.get("SESSION_TTL_SECONDS", "28800"))
```

---

## Testing

### Unit Tests

```bash
# Run unit tests
cd functions/apigw_authzr
python -m pytest tests/ -v
```

### Integration Tests

```bash
# Test health endpoint
curl -s https://<gateway>/health | jq

# Test login redirect
curl -sI https://<gateway>/auth/login | head -5

# Test protected route (no session)
curl -sI https://<gateway>/welcome | head -5
```

### End-to-End Tests

Use a browser automation tool (Selenium, Playwright) or manual testing:

1. Navigate to protected route
2. Complete login flow
3. Verify user info displayed
4. Test logout
5. Verify session cleared

---

## Deployment

### Development Workflow

```bash
# 1. Make changes
vim functions/<name>/func.py

# 2. Build locally
cd functions/<name>
fn build

# 3. Test locally (optional)
fn run  # In one terminal
curl -X POST http://localhost:8080 -d '{}'  # In another

# 4. Deploy
fn deploy --app apigw-oidc-app

# 5. Verify
fn invoke apigw-oidc-app <function-name>
```

### Version Bumping

Update `func.yaml` version before deploying:
```yaml
version: 0.0.2  # Increment
```

### Rollback

```bash
# List function versions (via container images)
oci artifacts container image list \
  --compartment-id <tenancy-ocid> \
  --repository-name oidc-fn-repo/<function-name>

# Update function to use previous image
oci fn function update --function-id <function-ocid> \
  --image "<region>.ocir.io/<namespace>/oidc-fn-repo/<name>:<prev-version>"
```

---

## Debugging

### Enable Debug Logging

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

### View Function Logs

```bash
# OCI Console: Functions > Application > Logs
# Or use OCI Logging service search
```

### Inspect Function Configuration

```bash
oci fn function get --function-id <function-ocid> \
  | jq '.data | {name: ."display-name", config: .config, image: .image}'
```

### Test Authorizer Directly

```bash
# Invoke authorizer with test data
echo '{"Cookie": "session_id=test", "User-Agent": "curl"}' \
  | fn invoke apigw-oidc-app apigw_authzr
```

---

## Performance Considerations

### Cold Starts

- First invocation after idle: 2-5 seconds
- Keep functions warm with periodic health checks
- Minimize dependencies to reduce startup time

> **Note:** For detailed cold start troubleshooting including multi-function latency stacking, see [Slow Initial Response / Cold Start Latency](./TROUBLESHOOTING.md#slow-initial-response--cold-start-latency).

### Connection Pooling

```python
# Reuse Redis connection across invocations
_redis_client = None

def get_redis():
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.Redis(...)
    return _redis_client
```

### Caching Secrets

```python
# Cache secrets in memory (refreshed on cold start)
_pepper = None

def get_pepper(config):
    global _pepper
    if _pepper is None:
        _pepper = fetch_from_vault(config["OCI_VAULT_PEPPER_OCID"])
    return _pepper
```
