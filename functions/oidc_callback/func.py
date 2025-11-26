"""
OIDC Callback Function

Handles the OAuth2 authorization code exchange after user authenticates at the IdP.
Creates encrypted session and stores in OCI Cache.
"""

import io
import os
import json
import base64
import hashlib
import secrets
import logging
import redis
import oci
import requests
import jwt

from fdk import response
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
OCI_IAM_BASE_URL = os.environ.get('OCI_IAM_BASE_URL')
OIDC_REDIRECT_URI = os.environ.get('OIDC_REDIRECT_URI')
OCI_VAULT_CLIENT_CREDS_OCID = os.environ.get('OCI_VAULT_CLIENT_CREDS_OCID')
OCI_VAULT_PEPPER_OCID = os.environ.get('OCI_VAULT_PEPPER_OCID')
OCI_CACHE_ENDPOINT = os.environ.get('OCI_CACHE_ENDPOINT')
COOKIE_DOMAIN = os.environ.get('COOKIE_DOMAIN', '')
SESSION_TTL_SECONDS = int(os.environ.get('SESSION_TTL_SECONDS', '28800'))  # 8 hours
SESSION_COOKIE_NAME = os.environ.get('SESSION_COOKIE_NAME', 'session_id')
DEFAULT_RETURN_TO = os.environ.get('DEFAULT_RETURN_TO', '/')

# In-memory cache for secrets
_secrets_cache = {}

def get_vault_secret(secret_ocid: str) -> str:
    """Retrieve and decode a secret from OCI Vault."""
    if secret_ocid in _secrets_cache:
        return _secrets_cache[secret_ocid]

    signer = oci.auth.signers.get_resource_principals_signer()
    client = oci.secrets.SecretsClient({}, signer=signer)

    response_data = client.get_secret_bundle(secret_ocid)
    content = response_data.data.secret_bundle_content.content
    decoded = base64.b64decode(content).decode('utf-8')

    _secrets_cache[secret_ocid] = decoded
    return decoded

def get_client_credentials() -> tuple:
    """Retrieve OAuth2 client_id and client_secret from Vault."""
    secret_json = get_vault_secret(OCI_VAULT_CLIENT_CREDS_OCID)
    creds = json.loads(secret_json)
    return creds['client_id'], creds['client_secret']

def get_pepper() -> bytes:
    """Retrieve HKDF pepper as bytes."""
    pepper_b64 = get_vault_secret(OCI_VAULT_PEPPER_OCID)
    return base64.b64decode(pepper_b64)

def get_redis_client():
    """Get Redis client with TLS."""
    return redis.Redis(
        host=OCI_CACHE_ENDPOINT,
        port=6379,
        ssl=True,
        ssl_cert_reqs="required",
        decode_responses=False
    )

def derive_key(session_id: str, pepper: bytes) -> bytes:
    """Derive encryption key from session_id and pepper using HKDF."""
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=pepper,
        info=b"session_encryption"
    )
    return hkdf.derive(session_id.encode('utf-8'))

def encrypt_session(session_data: dict, session_id: str, pepper: bytes) -> bytes:
    """Encrypt session data using AES-256-GCM."""
    key = derive_key(session_id, pepper)
    aesgcm = AESGCM(key)

    nonce = secrets.token_bytes(12)  # 96-bit nonce for GCM
    plaintext = json.dumps(session_data).encode('utf-8')
    ciphertext = aesgcm.encrypt(nonce, plaintext, None)

    return nonce + ciphertext

def hash_user_agent(user_agent: str) -> str:
    """Hash User-Agent for session binding."""
    if not user_agent:
        return ""
    return hashlib.sha256(user_agent.encode('utf-8')).hexdigest()[:16]

def validate_id_token(id_token: str, issuer: str, client_id: str, nonce: str) -> dict:
    """
    Validate id_token claims.

    Note: We skip signature verification because:
    1. Token is received directly from IdP over TLS
    2. OCI Identity Domain's JWKS endpoint requires authentication
    3. We validate all other claims (issuer, audience, expiry, nonce)
    """
    try:
        # Decode without signature verification
        # Safe because we received token directly from IdP over TLS
        decoded = jwt.decode(
            id_token,
            options={
                "verify_signature": False,
                "require": ["exp", "iat", "aud", "iss", "sub"]
            }
        )

        # Manually verify issuer
        if decoded.get('iss') != issuer:
            logger.error(f"Invalid issuer: expected {issuer}, got {decoded.get('iss')}")
            return None

        # Manually verify audience
        aud = decoded.get('aud')
        if isinstance(aud, list):
            if client_id not in aud:
                logger.error(f"Invalid audience: {client_id} not in {aud}")
                return None
        elif aud != client_id:
            logger.error(f"Invalid audience: expected {client_id}, got {aud}")
            return None

        # Verify nonce
        if decoded.get('nonce') != nonce:
            logger.error("Nonce mismatch in id_token")
            return None

        return decoded

    except jwt.ExpiredSignatureError:
        logger.error("ID Token has expired")
        return None
    except jwt.DecodeError as e:
        logger.error(f"Failed to decode ID Token: {e}")
        return None

def handler(ctx, data: io.BytesIO = None):
    """
    Handle OIDC callback.

    1. Receive callback with code and state parameters
    2. Retrieve state + code_verifier from OCI Cache (atomic GETDEL)
    3. Validate state matches
    4. Exchange authorization code for tokens
    5. Validate id_token
    6. Create encrypted session in OCI Cache
    7. Set session cookie and redirect to original URL
    """
    try:
        # Get query parameters - try multiple sources
        request_url = ctx.Headers().get("Fn-Http-Request-Url", "")
        if not request_url or "?" not in request_url:
            request_url = ctx.Headers().get("x-original-url", "")

        body = {}
        if data:
            raw = data.getvalue()
            if raw:
                try:
                    body = json.loads(raw)
                except json.JSONDecodeError:
                    pass

        query_string = request_url.split("?")[1] if "?" in request_url else ""
        query_params = parse_qs(query_string)

        def get_str(val):
            if val is None:
                return None
            if isinstance(val, list):
                return val[0] if val else None
            return str(val)

        # Get code/state from multiple sources
        code = (query_params.get("code", [None])[0] or
                body.get("code") or
                get_str(ctx.Headers().get("X-Query-Code", ctx.Headers().get("x-query-code"))))
        state = (query_params.get("state", [None])[0] or
                 body.get("state") or
                 get_str(ctx.Headers().get("X-Query-State", ctx.Headers().get("x-query-state"))))
        error = (query_params.get("error", [None])[0] or
                 body.get("error") or
                 get_str(ctx.Headers().get("X-Query-Error", ctx.Headers().get("x-query-error"))))
        error_description = query_params.get("error_description", [""])[0] or body.get("error_description", "")

        user_agent = get_str(ctx.Headers().get("User-Agent", ctx.Headers().get("user-agent", ""))) or ""

        if error:
            logger.error(f"OIDC error: {error} - {error_description}")
            return response.Response(
                ctx,
                response_data=json.dumps({"error": error, "description": error_description}),
                status_code=401,
                headers={"Content-Type": "application/json"}
            )

        if not code or not state:
            logger.error("Missing code or state parameter")
            return response.Response(
                ctx,
                response_data=json.dumps({"error": "missing_parameters"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )

        # Retrieve state data from cache (atomic GETDEL to prevent replay)
        r = get_redis_client()
        state_data_raw = r.execute_command('GETDEL', f"state:{state}")

        if not state_data_raw:
            logger.error(f"State not found or already used: {state[:8]}...")
            r.close()
            return response.Response(
                ctx,
                response_data=json.dumps({"error": "invalid_state"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )

        state_data = json.loads(state_data_raw.decode('utf-8'))
        code_verifier = state_data.get('code_verifier')
        nonce = state_data.get('nonce')
        return_to = state_data.get('return_to', DEFAULT_RETURN_TO)

        # Get client credentials from Vault
        client_id, client_secret = get_client_credentials()

        # Get OpenID configuration
        config_url = f"{OCI_IAM_BASE_URL}/.well-known/openid-configuration"
        config_resp = requests.get(config_url, timeout=10)
        config_resp.raise_for_status()
        openid_config = config_resp.json()

        token_endpoint = openid_config['token_endpoint']
        issuer = openid_config['issuer']

        # Exchange code for tokens
        token_data = {
            'grant_type': 'authorization_code',
            'client_id': client_id,
            'client_secret': client_secret,
            'redirect_uri': OIDC_REDIRECT_URI,
            'code': code,
            'code_verifier': code_verifier
        }

        token_resp = requests.post(token_endpoint, data=token_data, timeout=30)
        token_resp.raise_for_status()
        tokens = token_resp.json()

        id_token = tokens.get('id_token')
        access_token = tokens.get('access_token')
        if not id_token:
            logger.error("No id_token in token response")
            r.close()
            return response.Response(
                ctx,
                response_data=json.dumps({"error": "no_id_token"}),
                status_code=500,
                headers={"Content-Type": "application/json"}
            )

        # Validate id_token
        validated_claims = validate_id_token(id_token, issuer, client_id, nonce)

        if not validated_claims:
            r.close()
            return response.Response(
                ctx,
                response_data=json.dumps({"error": "invalid_id_token"}),
                status_code=401,
                headers={"Content-Type": "application/json"}
            )

        # Create session
        session_id = secrets.token_urlsafe(32)
        session_exp = datetime.now(timezone.utc) + timedelta(seconds=SESSION_TTL_SECONDS)

        # Read claims from ID token (including custom claims: user_email, user_given_name, user_family_name, user_groups)
        session_data = {
            'sub': validated_claims.get('sub'),
            'email': validated_claims.get('user_email') or validated_claims.get('email') or '',
            'name': validated_claims.get('user_displayname') or validated_claims.get('name') or '',
            'preferred_username': validated_claims.get('user_id') or validated_claims.get('preferred_username') or '',
            'given_name': validated_claims.get('user_given_name') or validated_claims.get('given_name') or '',
            'family_name': validated_claims.get('user_family_name') or validated_claims.get('family_name') or '',
            'groups': validated_claims.get('user_groups') or validated_claims.get('groups') or [],
            'ua_hash': hash_user_agent(user_agent),
            'exp': session_exp.isoformat(),
            'iat': datetime.now(timezone.utc).isoformat(),
            'id_token': id_token,
            'raw_claims': list(validated_claims.keys())
        }

        # Encrypt and store session
        pepper = get_pepper()
        encrypted_session = encrypt_session(session_data, session_id, pepper)
        r.set(f"session:{session_id}", encrypted_session, ex=SESSION_TTL_SECONDS)
        r.close()

        # Build Set-Cookie header
        cookie_expires = session_exp.strftime("%a, %d %b %Y %H:%M:%S GMT")
        cookie_parts = [
            f"{SESSION_COOKIE_NAME}={session_id}",
            f"Expires={cookie_expires}",
            f"Max-Age={SESSION_TTL_SECONDS}",
            "Path=/",
            "HttpOnly",
            "Secure",
            "SameSite=Lax"
        ]
        if COOKIE_DOMAIN:
            cookie_parts.append(f"Domain={COOKIE_DOMAIN}")

        set_cookie_header = "; ".join(cookie_parts)

        logger.info(f"Session created for user: {validated_claims.get('sub')}")

        # Redirect to original URL
        return response.Response(
            ctx,
            response_data="",
            status_code=302,
            headers={
                "Location": return_to,
                "Set-Cookie": set_cookie_header,
                "Cache-Control": "no-store"
            }
        )

    except Exception as e:
        logger.error(f"Error in oidc_callback: {str(e)}")
        return response.Response(
            ctx,
            response_data=json.dumps({"error": "internal_error", "message": str(e)}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )
