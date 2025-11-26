# apigw-iam-oidc-authorizer/terraform/modules/identity_domain/main.tf

# This module either provides an existing OCI IAM Identity Domain OCID and URL,
# or creates a new Identity Domain (though not typical for this reference architecture,
# as it often assumes an existing Identity Domain).

resource "oci_identity_domain" "this" {
  count = var.create_identity_domain ? 1 : 0

  compartment_id = var.compartment_ocid
  display_name   = var.domain_display_name
  description    = var.domain_description
  home_region    = var.region # Identity Domains are regional
  license_type   = var.domain_license_type
}

output "identity_domain_ocid" {
  description = "The OCID of the Identity Domain used."
  value       = var.create_identity_domain ? oci_identity_domain.this[0].id : var.existing_identity_domain_ocid
}

output "identity_domain_url" {
  description = "The base URL of the Identity Domain used."
  value       = var.create_identity_domain ? oci_identity_domain.this[0].url : var.existing_identity_domain_url
}
