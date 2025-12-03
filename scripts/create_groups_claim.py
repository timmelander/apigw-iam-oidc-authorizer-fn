#!/usr/bin/env python3
"""
Create Custom Claim to include user groups in OIDC tokens.

OCI Identity Domain doesn't include groups in tokens by default.
This script creates a Custom Claim that adds groups to the ID token.

Reference: https://docs.oracle.com/en-us/iaas/Content/Identity/api-getstarted/custom-claims-token.htm

Usage:
    # Set environment variable first (recommended)
    export OCI_IAM_BASE_URL="https://idcs-xxxx.identity.oraclecloud.com"
    python scripts/create_groups_claim.py

    # Or pass as command line argument
    python scripts/create_groups_claim.py --domain-url https://idcs-xxxx.identity.oraclecloud.com

    # List existing claims
    python scripts/create_groups_claim.py list
"""

import oci
import requests
import json
import os
import argparse

def get_identity_domain_url():
    """Get Identity Domain URL from environment or raise error."""
    url = os.environ.get("OCI_IAM_BASE_URL")
    if url:
        return url.rstrip("/")
    return None

def get_access_token():
    """Get access token using OCI config for Identity Domain admin API."""
    config = oci.config.from_file()

    # Use the Identity Domains client to get an access token
    # We need client credentials from our Confidential App
    print("Note: You need to use client credentials to get an admin access token.")
    print("Using OCI SDK signer for authentication...")

    return config

def create_groups_claim(identity_domain_url):
    """Create custom claim for groups in ID token."""

    config = oci.config.from_file()

    # Create a signer for the Identity Domains API
    signer = oci.Signer(
        tenancy=config["tenancy"],
        user=config["user"],
        fingerprint=config["fingerprint"],
        private_key_file_location=config["key_file"],
        pass_phrase=config.get("pass_phrase")
    )

    # Custom Claims endpoint
    endpoint = f"{identity_domain_url}/admin/v1/CustomClaims"

    # Custom claim payload to include groups in ID token
    # Expression $(user.groups[*].display) returns all group display names
    # Note: "groups" is a reserved name, so we use "user_groups"
    payload = {
        "schemas": [
            "urn:ietf:params:scim:schemas:oracle:idcs:CustomClaim"
        ],
        "name": "user_groups",
        "value": "$(user.groups[*].display)",
        "expression": True,
        "mode": "always",
        "tokenType": "BOTH",  # Include in both ID token and Access token
        "allScopes": True     # Apply to all scopes
    }

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    print(f"Creating custom claim at: {endpoint}")
    print(f"Payload: {json.dumps(payload, indent=2)}")

    # Make the request with OCI signature
    response = requests.post(
        endpoint,
        json=payload,
        headers=headers,
        auth=signer
    )

    print(f"\nResponse Status: {response.status_code}")
    print(f"Response Body: {json.dumps(response.json(), indent=2) if response.text else 'Empty'}")

    if response.status_code in [200, 201]:
        print("\n✓ Custom claim created successfully!")
        print("Users will now have 'groups' claim in their tokens after re-authentication.")
    else:
        print(f"\n✗ Failed to create custom claim: {response.status_code}")
        if response.status_code == 401:
            print("\nNote: You may need to use OAuth2 client credentials instead of OCI API signature.")
            print("Try using the OCI Console: Identity & Security > Domains > [Your Domain] > Settings")

def list_custom_claims(identity_domain_url):
    """List existing custom claims."""
    config = oci.config.from_file()

    signer = oci.Signer(
        tenancy=config["tenancy"],
        user=config["user"],
        fingerprint=config["fingerprint"],
        private_key_file_location=config["key_file"],
        pass_phrase=config.get("pass_phrase")
    )

    endpoint = f"{identity_domain_url}/admin/v1/CustomClaims"

    headers = {
        "Accept": "application/json"
    }

    print(f"Listing custom claims from: {endpoint}")

    response = requests.get(
        endpoint,
        headers=headers,
        auth=signer
    )

    print(f"\nResponse Status: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        claims = data.get("Resources", [])
        if claims:
            print(f"\nFound {len(claims)} custom claim(s):")
            for claim in claims:
                print(f"  - {claim.get('name')}: {claim.get('value')} (tokenType: {claim.get('tokenType')})")
        else:
            print("\nNo custom claims configured.")
    else:
        print(f"Response: {response.text}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Create Custom Claims for OCI Identity Domain"
    )
    parser.add_argument(
        "action",
        nargs="?",
        default="create",
        choices=["create", "list"],
        help="Action to perform (default: create)"
    )
    parser.add_argument(
        "--domain-url",
        help="Identity Domain URL (or set OCI_IAM_BASE_URL env var)"
    )

    args = parser.parse_args()

    # Get Identity Domain URL from args or environment
    identity_domain_url = args.domain_url or get_identity_domain_url()

    if not identity_domain_url:
        print("ERROR: Identity Domain URL not provided.")
        print()
        print("Set the OCI_IAM_BASE_URL environment variable:")
        print("  export OCI_IAM_BASE_URL=\"https://idcs-xxxx.identity.oraclecloud.com\"")
        print()
        print("Or pass it as an argument:")
        print("  python scripts/create_groups_claim.py --domain-url https://idcs-xxxx.identity.oraclecloud.com")
        print()
        print("You can find your Identity Domain URL in OCI Console:")
        print("  Identity & Security → Domains → [Your Domain] → Domain URL")
        exit(1)

    print(f"Using Identity Domain: {identity_domain_url}")
    print()

    if args.action == "list":
        list_custom_claims(identity_domain_url)
    else:
        print("=" * 60)
        print("OCI Identity Domain - Create Groups Custom Claim")
        print("=" * 60)
        print()

        # First list existing claims
        print("Checking existing custom claims...")
        list_custom_claims(identity_domain_url)

        print()
        print("-" * 60)
        print("Creating groups custom claim...")
        print("-" * 60)
        create_groups_claim(identity_domain_url)
