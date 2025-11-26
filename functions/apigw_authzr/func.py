"""
Session Authorizer Function

Validates session cookies for API Gateway authorizer.
Returns allow/deny decision based on session validity.
"""

import io
import os
import json
import logging

from fdk import response
from datetime import datetime, timezone

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables - read at module load
OCI_VAULT_PEPPER_OCID = os.environ.get('OCI_VAULT_PEPPER_OCID')
OCI_CACHE_ENDPOINT = os.environ.get('OCI_CACHE_ENDPOINT')
SESSION_COOKIE_NAME = os.environ.get('SESSION_COOKIE_NAME', 'session_id')

# In-memory cache for secrets
_secrets_cache = {}


def parse_cookies(cookie_header: str) -> dict:
    """Parse Cookie header into dict."""
    cookies = {}
    if cookie_header:
        for item in cookie_header.split(';'):
            item = item.strip()
            if '=' in item:
                key, value = item.split('=', 1)
                cookies[key.strip()] = value.strip()
    return cookies


def authorize_success(session_data: dict, session_id: str) -> dict:
    """Return successful authorization response."""
    # Build groups as comma-separated string for header compatibility
    groups = session_data.get("groups", [])
    if isinstance(groups, list):
        groups_str = ",".join(groups)
    else:
        groups_str = str(groups) if groups else ""

    # Build raw_claims string safely
    raw_claims = session_data.get("raw_claims", [])
    if isinstance(raw_claims, list):
        raw_claims_str = ",".join(str(c) for c in raw_claims)
    else:
        raw_claims_str = str(raw_claims) if raw_claims else ""

    return {
        "active": True,
        "principal": session_data.get("email") or session_data.get("sub"),
        "scope": ["openid", "profile", "email"],
        "expiresAt": session_data.get("exp", ""),
        "context": {
            "sub": session_data.get("sub") or "",
            "email": session_data.get("email") or "",
            "name": session_data.get("name") or "",
            "preferred_username": session_data.get("preferred_username") or "",
            "given_name": session_data.get("given_name") or "",
            "family_name": session_data.get("family_name") or "",
            "groups": groups_str,
            "session_id": session_id,
            "session_iat": session_data.get("iat") or "",
            "raw_claims": raw_claims_str,
            "userinfo_claims": ",".join(str(c) for c in session_data.get("userinfo_claims", [])) if isinstance(session_data.get("userinfo_claims"), list) else ""
        }
    }


def authorize_failure(reason: str = "invalid_token") -> dict:
    """Return authorization failure response."""
    return {
        "active": False,
        "wwwAuthenticate": f'Bearer realm="app", error="{reason}"'
    }


def handler(ctx, data: io.BytesIO = None):
    """Handle session authorization."""
    try:
        # Parse input
        body = {}
        if data:
            raw = data.getvalue()
            if raw:
                try:
                    body = json.loads(raw)
                except json.JSONDecodeError:
                    logger.warning("Failed to parse request body as JSON")

        auth_data = body.get('data', body)

        # Extract headers (handle both case variations)
        cookie_header = auth_data.get('Cookie', auth_data.get('cookie', ''))
        user_agent = auth_data.get('User-Agent', auth_data.get('userAgent', ''))

        # Parse cookies and get session_id
        cookies = parse_cookies(cookie_header)
        session_id = cookies.get(SESSION_COOKIE_NAME)

        if not session_id:
            logger.info("No session cookie found")
            return response.Response(
                ctx,
                response_data=json.dumps(authorize_failure("no_session")),
                status_code=200,
                headers={"Content-Type": "application/json"}
            )

        # === LAZY IMPORTS - only loaded when session exists ===
        import base64
        import hashlib
        import redis
        import oci
        from cryptography.hazmat.primitives.kdf.hkdf import HKDF
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        # Get session from cache
        try:
            r = redis.Redis(
                host=OCI_CACHE_ENDPOINT,
                port=6379,
                ssl=True,
                ssl_cert_reqs="required",
                decode_responses=False
            )
            encrypted_session = r.get(f"session:{session_id}")
            r.close()
        except Exception as e:
            logger.error(f"Redis connection failed: {str(e)}")
            return response.Response(
                ctx,
                response_data=json.dumps(authorize_failure("cache_error")),
                status_code=200,
                headers={"Content-Type": "application/json"}
            )

        if not encrypted_session:
            logger.info(f"Session not found in cache: {session_id[:8]}...")
            return response.Response(
                ctx,
                response_data=json.dumps(authorize_failure("session_not_found")),
                status_code=200,
                headers={"Content-Type": "application/json"}
            )

        # Get pepper from Vault
        try:
            if OCI_VAULT_PEPPER_OCID not in _secrets_cache:
                signer = oci.auth.signers.get_resource_principals_signer()
                client = oci.secrets.SecretsClient({}, signer=signer)
                resp = client.get_secret_bundle(OCI_VAULT_PEPPER_OCID)
                content = resp.data.secret_bundle_content.content
                _secrets_cache[OCI_VAULT_PEPPER_OCID] = base64.b64decode(content).decode('utf-8')
            pepper = base64.b64decode(_secrets_cache[OCI_VAULT_PEPPER_OCID])
        except Exception as e:
            logger.error(f"Failed to get pepper from Vault: {str(e)}")
            return response.Response(
                ctx,
                response_data=json.dumps(authorize_failure("vault_error")),
                status_code=200,
                headers={"Content-Type": "application/json"}
            )

        # Decrypt session
        try:
            # Derive key using HKDF
            hkdf = HKDF(
                algorithm=hashes.SHA256(),
                length=32,
                salt=pepper,
                info=b"session_encryption"
            )
            key = hkdf.derive(session_id.encode('utf-8'))

            # Decrypt with AES-GCM
            nonce = encrypted_session[:12]
            ciphertext = encrypted_session[12:]
            aesgcm = AESGCM(key)
            plaintext = aesgcm.decrypt(nonce, ciphertext, None)
            session_data = json.loads(plaintext.decode('utf-8'))
        except Exception as e:
            logger.error(f"Failed to decrypt session: {str(e)}")
            return response.Response(
                ctx,
                response_data=json.dumps(authorize_failure("invalid_session")),
                status_code=200,
                headers={"Content-Type": "application/json"}
            )

        # Check expiration
        exp = session_data.get('exp')
        if exp:
            exp_dt = datetime.fromisoformat(exp.replace('Z', '+00:00'))
            if datetime.now(timezone.utc) > exp_dt:
                logger.info("Session expired")
                return response.Response(
                    ctx,
                    response_data=json.dumps(authorize_failure("session_expired")),
                    status_code=200,
                    headers={"Content-Type": "application/json"}
                )

        # Validate session binding (disabled for POC - UA handling differs between callback and authorizer)
        # stored_ua_hash = session_data.get('ua_hash', '')
        # if stored_ua_hash and user_agent:
        #     current_ua_hash = hashlib.sha256(user_agent.encode('utf-8')).hexdigest()[:16]
        #     if stored_ua_hash != current_ua_hash:
        #         logger.warning(f"Session binding mismatch for session {session_id[:8]}...")
        #         logger.warning(f"Stored UA hash: {stored_ua_hash}, Current UA hash: {current_ua_hash}")
        #         logger.warning(f"Current UA: {user_agent}")
        #         return response.Response(
        #             ctx,
        #             response_data=json.dumps(authorize_failure("binding_mismatch")),
        #             status_code=200,
        #             headers={"Content-Type": "application/json"}
        #         )

        # Success
        logger.info(f"Session authorized for user: {session_data.get('sub', 'unknown')}")
        return response.Response(
            ctx,
            response_data=json.dumps(authorize_success(session_data, session_id)),
            status_code=200,
            headers={"Content-Type": "application/json"}
        )

    except Exception as e:
        logger.error(f"Error in session_authorizer: {str(e)}", exc_info=True)
        return response.Response(
            ctx,
            response_data=json.dumps(authorize_failure("internal_error")),
            status_code=200,
            headers={"Content-Type": "application/json"}
        )
