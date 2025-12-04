"""
OIDC Login Function

Initiates the OIDC Authorization Code flow with PKCE.
Generates state, code_verifier, nonce, stores them in OCI Cache,
and redirects the user to the Identity Provider.
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

from fdk import response
from urllib.parse import urlencode

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
OCI_IAM_BASE_URL = os.environ.get('OCI_IAM_BASE_URL')
OIDC_REDIRECT_URI = os.environ.get('OIDC_REDIRECT_URI')
OCI_VAULT_CLIENT_CREDS_OCID = os.environ.get('OCI_VAULT_CLIENT_CREDS_OCID')
OCI_CACHE_ENDPOINT = os.environ.get('OCI_CACHE_ENDPOINT')
STATE_TTL_SECONDS = int(os.environ.get('STATE_TTL_SECONDS', '300'))
DEFAULT_RETURN_TO = os.environ.get('DEFAULT_RETURN_TO', '/')

# In-memory cache for secrets (never written to disk)
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


def get_client_id() -> str:
    """Retrieve OAuth2 client_id from Vault."""
    secret_json = get_vault_secret(OCI_VAULT_CLIENT_CREDS_OCID)
    creds = json.loads(secret_json)
    return creds['client_id']


def get_redis_client():
    """Get Redis client with TLS (OCI Cache requires TLS)."""
    return redis.Redis(
        host=OCI_CACHE_ENDPOINT,
        port=6379,
        ssl=True,
        ssl_cert_reqs="required",
        decode_responses=True
    )


def generate_pkce():
    """Generate PKCE code_verifier and code_challenge."""
    code_verifier = secrets.token_urlsafe(32)
    digest = hashlib.sha256(code_verifier.encode('ascii')).digest()
    code_challenge = base64.urlsafe_b64encode(digest).rstrip(b'=').decode('ascii')
    return code_verifier, code_challenge


def handler(ctx, data: io.BytesIO = None):
    """Handle OIDC login initiation."""
    try:
        # Parse incoming request for return_to
        try:
            body = json.loads(data.getvalue()) if data else {}
        except Exception:
            body = {}

        return_to = body.get('return_to', DEFAULT_RETURN_TO)

        # Generate PKCE
        code_verifier, code_challenge = generate_pkce()

        # Generate state (used as cache key) and nonce
        state = secrets.token_urlsafe(32)
        nonce = secrets.token_urlsafe(32)

        # Store state data in OCI Cache
        r = get_redis_client()
        state_data = json.dumps({
            'code_verifier': code_verifier,
            'nonce': nonce,
            'return_to': return_to
        })
        r.set(f"state:{state}", state_data, ex=STATE_TTL_SECONDS)
        r.close()

        # Get client_id from Vault
        client_id = get_client_id()

        # Build authorization URL
        authorize_url = f"{OCI_IAM_BASE_URL}/oauth2/v1/authorize"
        params = {
            'response_type': 'code',
            'client_id': client_id,
            'redirect_uri': OIDC_REDIRECT_URI,
            'scope': 'openid profile email groups',
            'state': state,
            'nonce': nonce,
            'code_challenge': code_challenge,
            'code_challenge_method': 'S256'
        }
        redirect_url = f"{authorize_url}?{urlencode(params)}"

        logger.info(f"Redirecting to IdP for authentication, state={state[:8]}...")

        return response.Response(
            ctx,
            response_data="",
            status_code=302,
            headers={
                "Location": redirect_url,
                "Cache-Control": "no-store"
            }
        )

    except Exception as e:
        logger.error(f"Error in oidc_login: {str(e)}")
        return response.Response(
            ctx,
            response_data=json.dumps({"error": "internal_error", "message": str(e)}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )
