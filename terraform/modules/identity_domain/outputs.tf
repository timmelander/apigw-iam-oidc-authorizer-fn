# apigw-iam-oidc-authorizer/terraform/modules/identity_domain/outputs.tf

output "identity_domain_ocid" {
  description = "The OCID of the Identity Domain used."
  value       = var.create_identity_domain ? oci_identity_domain.this[0].id : var.existing_identity_domain_ocid
}

output "identity_domain_url" {
  description = "The base URL of the Identity Domain used."
  value       = var.create_identity_domain ? oci_identity_domain.this[0].url : var.existing_identity_domain_url
}
