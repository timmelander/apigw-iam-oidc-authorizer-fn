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

    signer = get_oci_signer()

    # Check if claim already exists
    existing_claims = get_existing_claims(identity_domain_url, signer)
    claim_name = "user_groups"

    if claim_name in existing_claims:
        existing = existing_claims[claim_name]
        print(f"\n✓ Custom claim '{claim_name}' already exists!")
        print(f"  Value: {existing.get('value')}")
        print(f"  Token Type: {existing.get('tokenType')}")
        print("\nNo action needed - claim is already configured.")
        return True

    # Custom Claims endpoint
    endpoint = f"{identity_domain_url}/admin/v1/CustomClaims"

    # Custom claim payload to include groups in ID token
    # Expression $(user.groups[*].display) returns all group display names
    # Note: "groups" is a reserved name, so we use "user_groups"
    payload = {
        "schemas": [
            "urn:ietf:params:scim:schemas:oracle:idcs:CustomClaim"
        ],
        "name": claim_name,
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
        print("Users will now have 'user_groups' claim in their tokens after re-authentication.")
        return True
    elif response.status_code == 409:
        print("\n✓ Custom claim already exists (409 conflict).")
        print("No action needed - claim is already configured.")
        return True
    else:
        print(f"\n✗ Failed to create custom claim: {response.status_code}")
        if response.status_code == 401:
            print("\nNote: You may need to use OAuth2 client credentials instead of OCI API signature.")
            print("Try using the OCI Console: Identity & Security > Domains > [Your Domain] > Settings")
        return False

def get_oci_signer():
    """Create OCI signer for API authentication."""
    config = oci.config.from_file()
    return oci.Signer(
        tenancy=config["tenancy"],
        user=config["user"],
        fingerprint=config["fingerprint"],
        private_key_file_location=config["key_file"],
        pass_phrase=config.get("pass_phrase")
    )

def get_existing_claims(identity_domain_url, signer):
    """Get existing custom claims as a dict keyed by name."""
    endpoint = f"{identity_domain_url}/admin/v1/CustomClaims"
    headers = {"Accept": "application/json"}

    response = requests.get(endpoint, headers=headers, auth=signer)

    if response.status_code == 200:
        data = response.json()
        claims = data.get("Resources", [])
        return {claim.get("name"): claim for claim in claims}
    return {}

def list_custom_claims(identity_domain_url):
    """List existing custom claims."""
    signer = get_oci_signer()
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
        return claims
    else:
        print(f"Response: {response.text}")
        return []

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

        # Create claim (will check if exists first)
        create_groups_claim(identity_domain_url)

        print()
        print("-" * 60)
        print("Current custom claims:")
        print("-" * 60)
        list_custom_claims(identity_domain_url)
