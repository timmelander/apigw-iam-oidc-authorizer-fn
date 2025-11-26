#!/usr/bin/env python3
"""
Create a Confidential Application in OCI Identity Domain for OIDC authentication.

This script uses the Identity Domain REST API to create an OAuth2 confidential client.
"""

import oci
import json
import sys

# Configuration
IDENTITY_DOMAIN_URL = "https://idcs-b7ad140e95da45789be287098edc90f5.identity.oraclecloud.com"
APP_NAME = "apigw-oidc-app"
APP_DESCRIPTION = "API Gateway OIDC Authentication Application"

# Placeholder redirect URI - will be updated after API Gateway is deployed
REDIRECT_URI = "https://placeholder.example.com/oauth2/callback"
POST_LOGOUT_REDIRECT_URI = "https://placeholder.example.com/"

def create_confidential_app():
    """Create a confidential OAuth2 application in Identity Domain."""

    # Load OCI config
    config = oci.config.from_file()

    # Create Identity Domains client
    identity_client = oci.identity_domains.IdentityDomainsClient(
        config,
        service_endpoint=IDENTITY_DOMAIN_URL
    )

    # Create the application - minimal required fields
    app_details = oci.identity_domains.models.App(
        display_name=APP_NAME,
        description=APP_DESCRIPTION,
        schemas=["urn:ietf:params:scim:schemas:oracle:idcs:App"],
        active=True,
        is_o_auth_client=True,
        client_type="confidential",
        allowed_grants=["authorization_code", "refresh_token"],
        redirect_uris=[REDIRECT_URI],
        post_logout_redirect_uris=[POST_LOGOUT_REDIRECT_URI],
        based_on_template=oci.identity_domains.models.AppBasedOnTemplate(
            value="CustomWebAppTemplateId"
        )
    )

    try:
        response = identity_client.create_app(app=app_details)
        app = response.data

        print(f"✅ Confidential Application Created Successfully!")
        print(f"")
        print(f"Application Details:")
        print(f"  Display Name: {app.display_name}")
        print(f"  App ID (name): {app.name}")
        print(f"  OCID: {app.ocid}")
        print(f"  Redirect URI: {REDIRECT_URI}")
        print(f"")

        # Client secret is typically returned in the response
        if hasattr(app, 'client_secret') and app.client_secret:
            print(f"  Client ID: {app.name}")
            print(f"  Client Secret: {app.client_secret}")

            # Output JSON for updating Vault secret
            creds = {
                "client_id": app.name,
                "client_secret": app.client_secret
            }
            print(f"")
            print(f"Vault Secret JSON (base64 encode this):")
            print(json.dumps(creds))
        else:
            print(f"  Client Secret: Not returned - check console")
            print(f"  Client ID: {app.name}")

        return app

    except oci.exceptions.ServiceError as e:
        print(f"❌ Error creating application: {e.message}")
        print(f"   Status: {e.status}")
        print(f"   Code: {e.code}")
        if hasattr(e, 'request_id'):
            print(f"   Request ID: {e.request_id}")
        sys.exit(1)

if __name__ == "__main__":
    print("Creating Confidential Application in OCI Identity Domain...")
    print(f"Identity Domain: {IDENTITY_DOMAIN_URL}")
    print(f"Application Name: {APP_NAME}")
    print("")

    create_confidential_app()
