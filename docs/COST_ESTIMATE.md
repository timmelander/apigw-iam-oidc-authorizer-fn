# Cost Estimate

This document provides monthly cost estimates for running the OCI API Gateway + OIDC Authentication solution at different usage levels.

## Assumptions

| Assumption | Value | Notes |
|------------|-------|-------|
| Protected page views per session | 15 | Average pages a user accesses after login |
| Active logout rate | 30% | Users who click logout vs. session expiry |
| Session duration | 8 hours | Default SESSION_TTL_SECONDS |
| Warmup frequency | Every 5 minutes | Scheduler hitting `/health` endpoint |
| Function memory | 256 MB | Default allocation |
| Function execution time | 500ms avg | Typical for auth operations |

## Function Invocations Per Login Session

| Function | Invocations | When |
|----------|-------------|------|
| `oidc_authn` | 1 | User initiates login |
| `oidc_callback` | 1 | OAuth callback after IdP auth |
| `apigw_authzr` | 15 | Once per protected page view |
| `oidc_logout` | 0.3 | 30% of users actively logout |
| **Total per session** | **~17** | |

## Warmup Invocations (Fixed Cost)

To prevent cold starts, periodic health checks keep functions warm:

```
12 calls/hour × 24 hours × 30 days = 8,640 invocations/month
```

### Warmup Options and Costs

| Option | Monthly Cost | Notes |
|--------|--------------|-------|
| OCI Health Checks | ~$8.64 | $0.001/check × 8,640 checks |
| Cron on backend compute | $0 | If you already have a backend server |
| Always Free compute + cron | $0 | Use OCI's free tier VM |
| Load Balancer health check | $0 | If using LB (production setup) |

> **Recommendation**: If deploying with a backend compute instance, use a simple cron job to hit `/health` and `/auth/login` every 5 minutes at no additional cost.

## Monthly Cost Estimates

### Tier 1: 10,000 Logins/Month

Small application or internal tool.

| Component | Calculation | Monthly Cost |
|-----------|-------------|--------------|
| **OCI Functions** | 10,000 × 17 + 8,640 warmup = ~179,000 invocations | ~$6.00 |
| **OCI API Gateway** | ~179,000 API calls | ~$0.54 |
| **OCI Cache (Redis)** | 1 node, 2GB memory | $28.87 |
| **OCI IAM Identity Domain** | 1 domain | $3.47 |
| **OCI Vault** | 1 vault + 1 key + secrets | ~$1.00 |
| **Warmup (cron)** | Using backend compute | $0.00 |
| | **Total** | **~$40/month** |

### Tier 2: 50,000 Logins/Month

Medium application with regular traffic.

| Component | Calculation | Monthly Cost |
|-----------|-------------|--------------|
| **OCI Functions** | 50,000 × 17 + 8,640 warmup = ~859,000 invocations | ~$30.00 |
| **OCI API Gateway** | ~859,000 API calls | ~$2.58 |
| **OCI Cache (Redis)** | 1 node, 2GB memory | $28.87 |
| **OCI IAM Identity Domain** | 1 domain | $3.47 |
| **OCI Vault** | 1 vault + 1 key + secrets | ~$1.00 |
| **Warmup (cron)** | Using backend compute | $0.00 |
| | **Total** | **~$66/month** |

### Tier 3: 100,000 Logins/Month

Large application with high traffic.

| Component | Calculation | Monthly Cost |
|-----------|-------------|--------------|
| **OCI Functions** | 100,000 × 17 + 8,640 warmup = ~1,709,000 invocations | ~$60.00 |
| **OCI API Gateway** | ~1,709,000 API calls | ~$5.13 |
| **OCI Cache (Redis)** | 1 node, 2GB memory (consider 4GB for high traffic) | $28.87 |
| **OCI IAM Identity Domain** | 1 domain | $3.47 |
| **OCI Vault** | 1 vault + 1 key + secrets | ~$1.00 |
| **Warmup (cron)** | Using backend compute | $0.00 |
| | **Total** | **~$99/month** |

## Cost Summary Table

| Logins/Month | Function Invocations | API Calls | Est. Total Cost |
|--------------|---------------------|-----------|-----------------|
| 10,000 | ~179,000 | ~179,000 | ~$40/month |
| 50,000 | ~859,000 | ~859,000 | ~$66/month |
| 100,000 | ~1,709,000 | ~1,709,000 | ~$99/month |

## Fixed vs Variable Costs

### Fixed Costs (~$33/month baseline)

These costs remain constant regardless of traffic:

| Component | Monthly Cost |
|-----------|--------------|
| OCI Cache (Redis) 2GB | $28.87 |
| OCI IAM Identity Domain | $3.47 |
| OCI Vault | ~$1.00 |
| **Fixed Total** | **~$33/month** |

### Variable Costs

These scale with usage:

| Component | Pricing |
|-----------|---------|
| OCI Functions | ~$0.035 per 1,000 invocations |
| OCI API Gateway | ~$3.00 per 1,000,000 calls |

## Cost Optimization Tips

1. **Warmup Strategy**: Use OCI Resource Scheduler (free) instead of external cron jobs to keep functions warm.

2. **Session Duration**: Longer sessions (e.g., 24 hours vs 8 hours) reduce login frequency and function invocations.

3. **Cache Sizing**: Start with 2GB Redis node. Only upgrade to 4GB if you expect >50,000 concurrent sessions.

4. **Free Tier**: OCI offers Always Free resources that may cover some costs:
   - 2 million function invocations/month (first month)
   - Check current Always Free offerings

5. **Reserved Capacity**: For predictable workloads, OCI reserved pricing can reduce costs by 30-50%.

## Pricing References

- [OCI Functions Pricing](https://www.oracle.com/cloud/price-list/#functions)
- [OCI API Gateway Pricing](https://www.oracle.com/cloud/price-list/#api-gateway)
- [OCI Cache Pricing](https://www.oracle.com/cloud/price-list/#cache)
- [OCI IAM Pricing](https://www.oracle.com/cloud/price-list/#iam)
- [OCI Vault Pricing](https://www.oracle.com/cloud/price-list/#vault)

> **Note**: Prices are estimates based on US regions as of 2024. Actual costs may vary by region and are subject to change. Use the [OCI Cost Estimator](https://www.oracle.com/cloud/costestimator.html) for precise calculations.

## Excluded from Estimates

The following are **not included** in these estimates:

- Backend compute (Apache/application server)
- Network egress/bandwidth
- OCI Logging (if enabled)
- Load Balancer (production deployments)
- WAF (production deployments)
- DNS/domain registration
