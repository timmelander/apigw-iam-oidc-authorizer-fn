# Troubleshooting Guide

This guide helps diagnose and resolve common issues with the OCI API Gateway + OIDC Authentication solution.

## Quick Diagnostic Checklist

1. [ ] Health endpoint returns 200: `curl https://<gateway>/health`
2. [ ] Functions are deployed: `fn list functions apigw-oidc-app`
3. [ ] API Gateway deployment is ACTIVE
4. [ ] Cache cluster is ACTIVE
5. [ ] Secrets are accessible (check IAM policies)
6. [ ] Identity Domain app is activated

---

## Common Issues

### 502 Bad Gateway

**Symptoms:** API Gateway returns 502 for function routes.

**Causes:**

1. **Function not deployed**
   ```bash
   # Check function exists
   fn list functions apigw-oidc-app
   ```

2. **Function naming issue** - Certain names cause issues
   - Avoid: `authorizer`, `login`, `session_authorizer`
   - Use: `apigw_authzr`, `oidc_authn`

3. **Function timeout**
   - Check function logs for timeout errors
   - Increase timeout in `func.yaml`

4. **Missing dependencies**
   ```bash
   # Check requirements.txt has all dependencies
   cat functions/<name>/requirements.txt
   ```

**Solution:**
```bash
# Redeploy function
cd functions/<name>
fn deploy --app apigw-oidc-app --verbose
```

### Slow Initial Response / Cold Start Latency

**Symptoms:** First request after idle period takes 60-180+ seconds. Subsequent requests are fast.

**Cause:** OCI Functions cold start. When functions are idle for 5-15 minutes, containers are stopped. On next invocation, OCI must:

1. Pull the container image (if not cached)
2. Start a new container
3. Initialize the Python runtime
4. Load all dependencies (cryptography, PyJWT, redis, etc.)
5. Execute the function code

**Why It's Compounded:** A single request to `/welcome` can trigger multiple cold starts in sequence:

```
Request: /welcome
    │
    ▼
┌─────────────────┐
│ apigw_authzr    │ ◄── Cold Start #1 (30-60s)
│ (authorizer)    │     Validates session cookie
└────────┬────────┘
         │ No session → 302 redirect
         ▼
┌─────────────────┐
│ oidc_authn      │ ◄── Cold Start #2 (30-60s)
│ (/auth/login)   │     Generates PKCE, redirects to IdP
└────────┬────────┘
         │ User authenticates at IdP
         ▼
┌─────────────────┐
│ oidc_callback   │ ◄── Cold Start #3 (30-60s)
│ (/auth/callback)│     Token exchange, session creation
└────────┬────────┘
         │ Redirect back to /welcome
         ▼
┌─────────────────┐
│ apigw_authzr    │ ◄── Now warm, fast response
└─────────────────┘

Total potential cold start time: 90-180+ seconds
```

**Contributing Factors:**

| Factor | Impact |
|--------|--------|
| Python runtime | Slower startup than Go/Java GraalVM |
| Heavy dependencies | `cryptography` library is particularly slow to load |
| Image size | Larger images = longer pull times |
| Sequential execution | Each function waits for previous to complete |
| Redis TLS handshake | First connection adds latency |

**What's NOT Causing the Delay:**
- API Gateway (always running)
- Apache backend (compute instance, always running)
- OCI Cache/Redis (managed service, always available)
- OCI Vault (managed service, always available)

**Solutions:**

1. **Manual Warming (Quick Fix)**
   ```bash
   # Run after idle period or starting compute instance
   curl -s https://<gateway>/health > /dev/null
   curl -sI https://<gateway>/auth/login > /dev/null
   # Wait ~60s for containers to warm, then use normally
   ```

2. **OCI Resource Scheduler (Recommended)** - See [Appendix A](#appendix-a-setting-up-oci-resource-scheduler) for full setup guide.

   As of September 2024, OCI Resource Scheduler natively supports scheduled function invocation - no external compute or cron needed.

   **Setup:**
   1. Go to: OCI Console → Governance & Administration → Resource Scheduler → Schedules
   2. Create schedule with cron expression (e.g., `*/5 * * * *` for every 5 min)
   3. Select "Static - apply schedule to specific resources"
   4. Choose your function (`health` or `oidc_authn`)
   5. Set Action to "Start"

   **Required IAM:**
   ```
   # Dynamic group for the schedule
   ALL {resource.type='resourceschedule', resource.id='<schedule-ocid>'}

   # Policy
   Allow dynamic-group <schedule-dg> to manage functions-family in compartment <name>
   ```

   **Benefits:**
   - No compute instance needed ($0 vs $6-30/month for external cron)
   - Managed by OCI - no maintenance
   - Native IAM integration

   **Timing:** OCI Functions stay warm for ~5-15 minutes after last invocation (varies).
   - **5-minute intervals** - Conservative, guarantees warm functions
   - **10-minute intervals** - Good balance, occasional cold start possible
   - **15-minute intervals** - Cost optimized, may see cold starts during low traffic

   **Cost Analysis:**
   | Interval | Invocations/month | Function Cost | Notes |
   |----------|-------------------|---------------|-------|
   | 5 min | ~17,280 | Free (under 2M) | Most reliable |
   | 10 min | ~8,640 | Free | Good balance |
   | 15 min | ~5,760 | Free | May have gaps |

   Resource Scheduler itself is free. Function invocations are within free tier.

   **Reference:** [Scheduling a Function - Oracle Docs](https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsscheduling.htm)

3. **External Cron (Alternative)**

   If Resource Scheduler isn't available, use an external cron:
   ```bash
   # Add to crontab on any always-on server (e.g., bastion host)
   */5 * * * * curl -s https://<gateway>/health > /dev/null
   */5 * * * * curl -sI https://<gateway>/auth/login > /dev/null
   ```

   Note: Requires a running compute instance (~$6-30/month) or external service
   (cron-job.org, GitHub Actions scheduled workflow).

4. **Provisioned Concurrency** (Production)
   - Configure minimum instances in OCI Console
   - Keeps containers warm but incurs additional cost

5. **Optimize Dependencies**
   - Use multi-stage Docker builds
   - Lazy-load heavy modules
   - Consider lighter alternatives to `cryptography`

6. **Use Faster Runtime**
   - Go has ~10x faster cold start than Python
   - GraalVM native images are also fast

7. **Increase Function Memory**
   - More memory = more CPU allocation = faster startup
   - Try 512MB or 1024MB instead of default 256MB

---

### 401 Unauthorized (Expected 302 Redirect)

**Symptoms:** Protected routes return 401 instead of redirecting to login.

**Cause:** `validationFailurePolicy` not configured or authorizer not returning correct response.

**Solution:** Verify API deployment specification:
```json
"validationFailurePolicy": {
  "type": "MODIFY_RESPONSE",
  "responseCode": "302",
  "responseHeaderTransformations": {
    "setHeaders": {
      "items": [{"name": "Location", "values": ["/auth/login"]}]
    }
  }
}
```

### Invalid State Parameter

**Symptoms:** Callback fails with "Invalid state" error.

**Causes:**

1. **State expired** (TTL is 5 minutes)
2. **State already used** (replay attempt)
3. **Cache connectivity issue**

**Diagnostic:**
```bash
# Check if function can reach cache
fn invoke apigw-oidc-app health
```

**Solution:**
- Retry login flow
- Check cache cluster is ACTIVE
- Verify function has network access to cache subnet

### Token Exchange Failure

**Symptoms:** Callback fails at token exchange step.

**Causes:**

1. **Invalid client credentials**
   ```bash
   # Verify secret content
   oci secrets secret-bundle get --secret-id <secret-ocid> \
     | jq -r '.data."secret-bundle-content".content' | base64 -d
   ```

2. **Redirect URI mismatch**
   - Check Identity Domain app configuration
   - Ensure exact match including trailing slashes

3. **IdP connectivity issue**
   - Check function can reach Identity Domain URL
   - Verify NAT Gateway configured for private subnet

**Diagnostic - Enable verbose logging:**
```python
# In func.py, add logging
import logging
logging.basicConfig(level=logging.DEBUG)
```

### Session Not Found

**Symptoms:** User authenticated but next request fails.

**Causes:**

1. **Cookie not being set**
   - Check browser dev tools for Set-Cookie header
   - Verify `Secure` flag matches HTTPS

2. **Cookie not being sent**
   - Check `SameSite` attribute
   - Verify domain matches

3. **Session expired or deleted from cache**
   ```bash
   # Check session TTL in function config
   oci fn function get --function-id <callback-fn-id> \
     | jq '.data.config.SESSION_TTL_SECONDS'
   ```

4. **User-Agent mismatch** (session binding)
   - Session bound to original browser's User-Agent
   - Different browser/device will fail

### Function Can't Read Secrets

**Symptoms:** Functions fail with vault access errors.

**Cause:** Missing IAM policy for dynamic group.

**Diagnostic:**
```bash
# Check dynamic group membership
oci iam dynamic-group get --dynamic-group-id <dg-ocid>

# Check policies
oci iam policy list --compartment-id <compartment-ocid> --all
```

**Solution:**
```bash
# Create/fix policy
oci iam policy create \
  --compartment-id <compartment-ocid> \
  --name "oidc-functions-vault-access" \
  --statements '["Allow dynamic-group oidc-functions-dg to read secret-bundles in compartment id <compartment-ocid>"]'
```

### Function Can't Connect to Cache

**Symptoms:** Redis connection errors in function logs.

**Causes:**

1. **Network configuration**
   - Function and cache must be in same VCN or peered
   - Check security list allows port 6379

2. **Wrong endpoint**
   ```bash
   # Get correct FQDN
   oci redis cluster get --cluster-id <cache-ocid> \
     | jq -r '.data["primary-fqdn"]'
   ```

3. **TLS requirement**
   - OCI Cache requires TLS
   - Ensure `ssl=True` in Redis connection

---

## Viewing Logs

### Function Invocation Logs

```bash
# Enable logging for function app (OCI Console)
# Navigate to: Functions > Application > Logs > Enable

# Or via CLI
oci logging log create \
  --display-name "apigw-oidc-fn-logs" \
  --log-group-id <log-group-ocid> \
  --log-type SERVICE \
  --configuration '{
    "source": {
      "category": "invoke",
      "resource": "<fn-app-ocid>",
      "service": "functions",
      "sourceType": "OCISERVICE"
    }
  }'
```

### API Gateway Access Logs

```bash
# Enable in deployment specification
"loggingPolicies": {
  "executionLog": {
    "isEnabled": true,
    "logLevel": "INFO"
  }
}
```

### Searching Logs

```bash
# OCI Console: Observability > Logging > Logs
# Search query examples:

# Find all errors
data.message = '*error*'

# Find specific function invocations
data.functionName = 'oidc_callback'

# Find by request ID
data.requestId = '<request-id>'
```

---

## Testing Individual Components

### Test Health Function

```bash
curl -s https://<gateway>/health | jq
# Expected: {"status": "healthy", "timestamp": "..."}
```

### Test Login Redirect

```bash
curl -sI https://<gateway>/auth/login | grep -E "HTTP|Location"
# Expected: HTTP/2 302, Location: https://idcs-...
```

### Test Authorizer (No Session)

```bash
curl -sI https://<gateway>/welcome | grep -E "HTTP|Location"
# Expected: HTTP/2 302, Location: /auth/login
```

### Test Cache Connectivity

```bash
# Invoke health with cache check
fn invoke apigw-oidc-app health
```

### Test Vault Access

```bash
# From a function, try reading secret
# Add debug endpoint or check logs
```

---

## Debug Mode

### Enable Function Debug Logging

Add to function code:
```python
import logging
import json

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

def handler(ctx, data):
    logger.debug(f"Context: {json.dumps(ctx.__dict__, default=str)}")
    logger.debug(f"Data: {data.getvalue()}")
    # ... rest of handler
```

### Capture Full Request/Response

Use browser developer tools:
1. Open Network tab
2. Navigate to protected route
3. Check redirect chain
4. Examine cookies and headers

---

## Recovery Procedures

### Force Session Logout (All Users)

Rotate the HKDF pepper to invalidate all sessions:

```bash
# Generate new pepper
NEW_PEPPER=$(openssl rand -base64 32)

# Update secret
oci vault secret update-base64 \
  --secret-id <pepper-secret-ocid> \
  --secret-content-content "$NEW_PEPPER"

# Redeploy functions to pick up new pepper
for fn in oidc_callback apigw_authzr; do
  cd functions/$fn && fn deploy --app apigw-oidc-app && cd ../..
done
```

### Clear Cache

```bash
# Connect to cache (requires bastion or VPN)
redis-cli -h <cache-endpoint> --tls -p 6379

# Clear all sessions
KEYS session:* | xargs DEL
```

### Redeploy All Functions

```bash
for func in health oidc_authn oidc_callback oidc_logout apigw_authzr; do
  echo "Redeploying $func..."
  cd functions/$func
  fn deploy --app apigw-oidc-app
  cd ../..
done
```

### Update API Gateway Deployment

First regenerate `api_deployment.json` from the template (see [Deployment Guide Section 5.3](./DEPLOYMENT_GUIDE.md#53-create-api-deployment)), then:

```bash
oci api-gateway deployment update \
  --deployment-id <deployment-ocid> \
  --specification file://scripts/api_deployment.json \
  --force
```

---

## Getting Help

1. **Check logs** - Most issues are visible in function or API Gateway logs
2. **Enable debug logging** - Add verbose logging to functions
3. **Test components individually** - Isolate which component is failing
4. **Review configuration** - Compare against [CONFIGURATION.md](./CONFIGURATION.md)
5. **Report issues** - https://github.com/timmelander/apigw-iam-oidc-authorizer/issues

---

# Appendices

## Appendix A: Setting Up OCI Resource Scheduler

This appendix provides a complete walkthrough for configuring OCI Resource Scheduler to keep your authentication functions warm and eliminate cold start latency.

### Overview

OCI Resource Scheduler (released September 2024) can invoke functions on a schedule without requiring external compute instances or cron jobs. This is the recommended approach for keeping functions warm.

### Which Functions to Warm

For this OIDC authentication solution, warm these functions:

| Function | Why | Route |
|----------|-----|-------|
| `health` | Warms shared dependencies, fast to invoke | `/health` |
| `oidc_authn` | Login flow entry point, critical path | `/auth/login` |

**Note:** `oidc_callback` and `apigw_authzr` will warm naturally when users authenticate. Warming `health` and `oidc_authn` covers the most common cold start scenarios.

### Prerequisites

- OCI Console access with permissions to create Resource Schedules
- Functions already deployed to `apigw-oidc-app`
- Permissions to create Dynamic Groups and Policies (or request from admin)

### Step 1: Get Function OCIDs

```bash
# List functions in your application
oci fn function list \
  --application-id <app-ocid> \
  --query "data[].{name:\"display-name\", id:id}" \
  --output table
```

Note the OCIDs for `health` and `oidc_authn`.

### Step 2: Create the Resource Schedule

1. **Navigate to Resource Scheduler:**
   - OCI Console → Governance & Administration → Resource Scheduler → Schedules

2. **Click "Create schedule"**

3. **Basic Information:**
   - **Name:** `oidc-function-warmer`
   - **Description:** `Keeps OIDC authentication functions warm to prevent cold start latency`
   - **Compartment:** Select your compartment

4. **Schedule Configuration:**
   - **Schedule type:** Cron expression
   - **Cron expression:** `0 */10 * * *` (every 10 minutes)

   Recommended intervals:
   | Interval | Cron Expression | Use Case |
   |----------|-----------------|----------|
   | 5 min | `0 */5 * * *` | High traffic, guaranteed warm |
   | 10 min | `0 */10 * * *` | Balanced (recommended) |
   | 15 min | `0 */15 * * *` | Low traffic, cost optimized |

5. **Resources:**
   - **Resource type:** Function
   - **Selection type:** Static - apply schedule to specific resources
   - Click "Select resources" and choose:
     - `health`
     - `oidc_authn`

6. **Action:** Select "Start"

7. **Review and Create**

### Step 3: Create Dynamic Group for Scheduler

The Resource Scheduler needs IAM permissions to invoke your functions.

1. **Navigate to:** Identity & Security → Dynamic Groups

2. **Create Dynamic Group:**
   - **Name:** `oidc-scheduler-dg`
   - **Description:** `Dynamic group for OIDC function warming scheduler`
   - **Matching Rule:**
     ```
     ALL {resource.type='resourceschedule', resource.compartment.id='<your-compartment-ocid>'}
     ```

   Or for a specific schedule only:
     ```
     ALL {resource.type='resourceschedule', resource.id='<schedule-ocid>'}
     ```

### Step 4: Create IAM Policy

1. **Navigate to:** Identity & Security → Policies

2. **Create Policy:**
   - **Name:** `oidc-scheduler-policy`
   - **Description:** `Allow Resource Scheduler to invoke OIDC functions`
   - **Compartment:** Select your compartment (or root for tenancy-wide)
   - **Policy Statements:**
     ```
     Allow dynamic-group oidc-scheduler-dg to manage functions-family in compartment <compartment-name>
     ```

   Or more restrictive (specific functions only):
     ```
     Allow dynamic-group oidc-scheduler-dg to use fn-function in compartment <compartment-name> where target.function.id in ('<health-fn-ocid>', '<oidc_authn-fn-ocid>')
     Allow dynamic-group oidc-scheduler-dg to use fn-invocation in compartment <compartment-name>
     ```

### Step 5: Verify the Schedule

1. **Check Schedule Status:**
   - Go to Resource Scheduler → Schedules → `oidc-function-warmer`
   - Status should be "Active"

2. **Monitor Invocations:**
   - Go to: Observability & Management → Logging → Logs
   - Search for function invocations from the scheduler

3. **Test Manually:**
   - In the schedule details, click "Run now" to trigger an immediate invocation
   - Check function logs to confirm execution

### Step 6: Verify Functions Stay Warm

After the schedule has run at least once:

```bash
# These should respond in <1 second (warm)
time curl -s https://<gateway>/health
time curl -sI https://<gateway>/auth/login

# Compare to cold start (wait 20+ minutes with schedule disabled)
# Cold start typically takes 30-60+ seconds
```

### Troubleshooting the Scheduler

#### Schedule Not Running

1. **Check schedule status** - Must be "Active"
2. **Verify cron expression** - Use [crontab.guru](https://crontab.guru) to validate
3. **Check time zone** - OCI uses UTC by default

#### Permission Denied Errors

1. **Verify dynamic group rule** matches the schedule
2. **Check policy** grants `functions-family` or specific function permissions
3. **Ensure policy** is in the correct compartment

#### Functions Not Warming

1. **Check function logs** for invocation records
2. **Verify function OCIDs** in the schedule match deployed functions
3. **Try "Run now"** to test immediate invocation

### Cost Summary

| Component | Cost |
|-----------|------|
| Resource Scheduler | Free |
| Function invocations (10-min interval) | ~8,640/month = Free tier |
| **Total** | **$0** |

### CLI Alternative

You can also create schedules via OCI CLI:

```bash
# Create schedule (requires JSON definition file)
oci resource-scheduler schedule create \
  --compartment-id <compartment-ocid> \
  --display-name "oidc-function-warmer" \
  --action "START_RESOURCE" \
  --recurrence-type "CRON" \
  --recurrence-details '{"cronExpression": "0 */10 * * *"}' \
  --resources '[{"id": "<health-fn-ocid>"}, {"id": "<oidc_authn-fn-ocid>"}]'
```

### References

- [Scheduling a Function - Oracle Docs](https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsscheduling.htm)
- [Resource Scheduler Overview](https://docs.oracle.com/en-us/iaas/Content/ResourceScheduler/Concepts/resourcescheduler_topic-overview.htm)
- [Cron Expression Reference](https://crontab.guru/)
