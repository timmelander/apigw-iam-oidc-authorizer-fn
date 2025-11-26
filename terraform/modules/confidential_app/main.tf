# apigw-iam-oidc-authorizer/terraform/modules/confidential_app/main.tf

# This module either provides an existing OCI IAM Identity Domain Confidential Application
# or creates a new one and configures its properties, such as redirect URIs.

resource "oci_identity_domains_app" "this" {
  count = var.create_confidential_app ? 1 : 0

  # Required attributes for creating an application
  display_name       = var.app_display_name
  compartment_id     = var.compartment_ocid # Resource Compartment is the Identity Domain's compartment
  idcs_endpoint      = var.iam_domain_idcs_endpoint
  name               = var.app_display_name
  description        = var.app_description
  is_oauth_client    = true
  is_web_tier_client = false
  is_enabled         = true

  # OAuth client configuration
  oauth_client_grant_types = var.oauth_client_grant_types
  oauth_client_redirect_uris = var.oauth_client_redirect_uris
  oauth_client_post_logout_redirect_uris = var.oauth_client_post_logout_redirect_uris
  
  # Ensure PKCE is enforced for browser safety
  oauth_client_pkce_enforced = true
  
  # Set the scopes that the client is allowed to request
  oauth_client_allowed_scopes {
    fqs                                      = "urn:opc:idm:__myscopes__" # Placeholder for dynamic scopes
    # We will assume a default set of scopes as per requirement: openid, profile, offline_access
    # More dynamic scope handling can be implemented if needed.
  }
}

resource "oci_identity_domains_app" "existing" {
  count = var.create_confidential_app ? 0 : 1

  # When using an existing app, we primarily update its redirect URIs.
  # The app ID is required for update.
  id                 = var.existing_app_id
  compartment_id     = var.compartment_ocid
  idcs_endpoint      = var.iam_domain_idcs_endpoint
  
  oauth_client_redirect_uris = var.oauth_client_redirect_uris
  oauth_client_post_logout_redirect_uris = var.oauth_client_post_logout_redirect_uris

  # Preserve existing grant types if not explicitly set
  # Need to fetch current values if not provided.
  # For now, assuming direct update of redirect URIs.
}

output "confidential_app_id" {
  description = "The OCID of the Confidential Application."
  value       = var.create_confidential_app ? oci_identity_domains_app.this[0].id : oci_identity_domains_app.existing[0].id
}

output "confidential_client_id" {
  description = "The Client ID of the Confidential Application."
  value       = var.create_confidential_app ? oci_identity_domains_app.this[0].oauth_client_id : var.existing_client_id
}

output "confidential_client_secret" {
  description = "The Client Secret of the Confidential Application. Store this in Vault."
  value       = var.create_confidential_app ? oci_identity_domains_app.this[0].oauth_client_secret : "N/A - Use existing or retrieve manually if updating" # Should not expose existing secret
  sensitive   = true
}