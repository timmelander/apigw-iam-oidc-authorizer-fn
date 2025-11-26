# apigw-iam-oidc-authorizer/terraform/modules/confidential_app/outputs.tf

output "confidential_app_id" {
  description = "The ID of the Confidential Application."
  value       = var.create_confidential_app ? oci_identity_domains_app.this[0].id : oci_identity_domains_app.existing[0].id
}

output "confidential_client_id" {
  description = "The Client ID of the Confidential Application."
  value       = var.create_confidential_app ? oci_identity_domains_app.this[0].oauth_client_id : var.existing_client_id
}

output "confidential_client_secret" {
  description = "The Client Secret of the Confidential Application. Only available if a new application was created."
  value       = var.create_confidential_app ? oci_identity_domains_app.this[0].oauth_client_secret : ""
  sensitive   = true
}