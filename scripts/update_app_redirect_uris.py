#!/usr/bin/env python3
"""
Update Confidential App redirect URIs with actual API Gateway URL
"""

import oci
from oci.identity_domains import IdentityDomainsClient

# Configuration
APP_OCID = "ocid1.domainapp.oc1.us-chicago-1.amaaaaaajdavfoqai6zmmb2uzliwo6xwovetdcikabf56j3sleo23rgjspra"
IDENTITY_DOMAIN_URL = "https://idcs-b7ad140e95da45789be287098edc90f5.identity.oraclecloud.com:443"
APIGW_URL = "https://f7jbkv5vctt4wzy3jku4755vi4.apigateway.us-chicago-1.oci.customer-oci.com"

# New URIs
REDIRECT_URI = f"{APIGW_URL}/auth/callback"
POST_LOGOUT_REDIRECT_URI = f"{APIGW_URL}/logged-out"

def main():
    # Use default config for authentication
    config = oci.config.from_file()

    # Create client
    client = IdentityDomainsClient(config, IDENTITY_DOMAIN_URL)

    # Get current app
    print(f"Getting app: {APP_OCID}")
    app = client.get_app(app_id=APP_OCID)
    print(f"Current redirect URIs: {app.data.redirect_uris}")
    print(f"Current post logout redirect URIs: {app.data.post_logout_redirect_uris}")

    # Update with PATCH
    from oci.identity_domains.models import PatchOp, Operations

    patch_body = PatchOp(
        schemas=["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
        operations=[
            Operations(
                op="REPLACE",
                path="redirectUris",
                value=[REDIRECT_URI]
            ),
            Operations(
                op="REPLACE",
                path="postLogoutRedirectUris",
                value=[POST_LOGOUT_REDIRECT_URI]
            )
        ]
    )

    print(f"\nUpdating app with:")
    print(f"  redirect_uri: {REDIRECT_URI}")
    print(f"  post_logout_redirect_uri: {POST_LOGOUT_REDIRECT_URI}")

    result = client.patch_app(app_id=APP_OCID, patch_op=patch_body)

    print(f"\nUpdate successful!")
    print(f"New redirect URIs: {result.data.redirect_uris}")
    print(f"New post logout redirect URIs: {result.data.post_logout_redirect_uris}")

if __name__ == "__main__":
    main()
