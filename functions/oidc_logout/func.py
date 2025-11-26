"""
Logout Function

Handles user-initiated logout with proper session cleanup.
Clears session from OCI Cache and redirects to IdP logout with id_token_hint.
"""

import io
import os
import json
import base64
import logging
import redis
import oci
import requests

from fdk import response
from urllib.parse import urlencode
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
OCI_IAM_BASE_URL = os.environ.get('OCI_IAM_BASE_URL')
OCI_CACHE_ENDPOINT = os.environ.get('OCI_CACHE_ENDPOINT')
OCI_VAULT_PEPPER_OCID = os.environ.get('OCI_VAULT_PEPPER_OCID')
POST_LOGOUT_REDIRECT_URI = os.environ.get('POST_LOGOUT_REDIRECT_URI', '/')
SESSION_COOKIE_NAME = os.environ.get('SESSION_COOKIE_NAME', 'session_id')
COOKIE_DOMAIN = os.environ.get('COOKIE_DOMAIN', '')

# In-memory cache for secrets
_secrets_cache = {}

def get_redis_client():
    """Get Redis client with TLS."""
    return redis.Redis(
        host=OCI_CACHE_ENDPOINT,
        port=6379,
        ssl=True,
        ssl_cert_reqs="required",
        decode_responses=False
    )

def get_pepper() -> bytes:
    """Retrieve HKDF pepper from Vault."""
    if OCI_VAULT_PEPPER_OCID in _secrets_cache:
        return base64.b64decode(_secrets_cache[OCI_VAULT_PEPPER_OCID])

    signer = oci.auth.signers.get_resource_principals_signer()
    client = oci.secrets.SecretsClient({}, signer=signer)

    resp = client.get_secret_bundle(OCI_VAULT_PEPPER_OCID)
    content = resp.data.secret_bundle_content.content
    decoded = base64.b64decode(content).decode('utf-8')

    _secrets_cache[OCI_VAULT_PEPPER_OCID] = decoded
    return base64.b64decode(decoded)

def decrypt_session(encrypted_data: bytes, session_id: str, pepper: bytes) -> dict:
    """Decrypt session data using AES-256-GCM."""
    # Derive key using HKDF
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=pepper,
        info=b"session_encryption"
    )
    key = hkdf.derive(session_id.encode('utf-8'))

    # Decrypt with AES-GCM
    nonce = encrypted_data[:12]
    ciphertext = encrypted_data[12:]
    aesgcm = AESGCM(key)
    plaintext = aesgcm.decrypt(nonce, ciphertext, None)

    return json.loads(plaintext.decode('utf-8'))

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

def build_clear_cookie() -> str:
    """Build clear cookie header."""
    clear_cookie_parts = [
        f"{SESSION_COOKIE_NAME}=",
        "Expires=Thu, 01 Jan 1970 00:00:00 GMT",
        "Max-Age=0",
        "Path=/",
        "HttpOnly",
        "Secure",
        "SameSite=Lax"
    ]
    if COOKIE_DOMAIN:
        clear_cookie_parts.append(f"Domain={COOKIE_DOMAIN}")
    return "; ".join(clear_cookie_parts)

def handler(ctx, data: io.BytesIO = None):
    """
    Handle logout request.

    1. Extract session_id from cookie
    2. Retrieve and decrypt session to get id_token
    3. Delete session from OCI Cache
    4. Clear session cookie
    5. Redirect to IdP logout endpoint with id_token_hint
    """
    id_token = None

    try:
        # Get Cookie header
        cookie_header = ctx.Headers().get("Cookie", ctx.Headers().get("cookie", ""))

        # Parse cookies and get session_id
        cookies = parse_cookies(cookie_header)
        session_id = cookies.get(SESSION_COOKIE_NAME)

        # Try to get id_token from session before deleting
        if session_id:
            try:
                r = get_redis_client()
                encrypted_session = r.get(f"session:{session_id}")

                if encrypted_session:
                    # Decrypt to get id_token
                    try:
                        pepper = get_pepper()
                        session_data = decrypt_session(encrypted_session, session_id, pepper)
                        id_token = session_data.get('id_token')
                        logger.info(f"Retrieved id_token for logout: {id_token[:20] if id_token else 'None'}...")
                    except Exception as e:
                        logger.warning(f"Failed to decrypt session for id_token: {str(e)}")

                    # Delete session from cache
                    deleted = r.delete(f"session:{session_id}")
                    if deleted:
                        logger.info(f"Session deleted: {session_id[:8]}...")
                    else:
                        logger.info(f"Session not found in cache: {session_id[:8]}...")

                r.close()
            except Exception as e:
                logger.warning(f"Failed to process session from cache: {str(e)}")
                # Continue with logout even if cache operations fail

        # Build redirect URL
        redirect_url = POST_LOGOUT_REDIRECT_URI
        try:
            config_url = f"{OCI_IAM_BASE_URL}/.well-known/openid-configuration"
            config_resp = requests.get(config_url, timeout=10)
            config_resp.raise_for_status()
            openid_config = config_resp.json()

            end_session_endpoint = openid_config.get('end_session_endpoint')
            if end_session_endpoint:
                logout_params = {
                    'post_logout_redirect_uri': POST_LOGOUT_REDIRECT_URI
                }
                # Include id_token_hint if available (required by OCI Identity Domain)
                if id_token:
                    logout_params['id_token_hint'] = id_token
                    logger.info("Including id_token_hint in logout request")
                else:
                    logger.warning("No id_token available for logout - logout may fail")

                redirect_url = f"{end_session_endpoint}?{urlencode(logout_params)}"

        except Exception as e:
            logger.warning(f"Failed to get end_session_endpoint: {str(e)}")
            # Continue with local logout redirect

        logger.info("Logout completed, redirecting to IdP")

        return response.Response(
            ctx,
            response_data="",
            status_code=302,
            headers={
                "Location": redirect_url,
                "Set-Cookie": build_clear_cookie(),
                "Cache-Control": "no-store"
            }
        )

    except Exception as e:
        logger.error(f"Error in logout: {str(e)}")
        # Even on error, try to clear cookie and redirect
        return response.Response(
            ctx,
            response_data="",
            status_code=302,
            headers={
                "Location": POST_LOGOUT_REDIRECT_URI,
                "Set-Cookie": build_clear_cookie(),
                "Cache-Control": "no-store"
            }
        )
