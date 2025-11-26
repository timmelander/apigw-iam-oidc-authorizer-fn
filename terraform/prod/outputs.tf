# apigw-iam-oidc-authorizer/terraform/environments/prod/outputs.tf

# This file defines the outputs that will be displayed after a successful Terraform apply.

output "load_balancer_public_ip" {
  description = "The public IP address of the OCI Flexible Load Balancer."
  value       = module.loadbalancer.load_balancer_public_ip
}

output "api_gateway_deployment_endpoint" {
  description = "The deployment endpoint URL of the OCI API Gateway."
  value       = module.apigateway.api_gateway_deployment_endpoint
}

output "apache_compute_public_ip" {
  description = "The public IP address of the Apache Compute Instance (for SSH access)."
  value       = module.compute.compute_public_ip
}

output "apache_compute_private_ip" {
  description = "The private IP address of the Apache Compute Instance (backend for API Gateway)."
  value       = module.compute.compute_private_ip
}

output "oidc_auth_app_function_app_id" {
  description = "The OCID of the OCI Functions Application."
  value       = module.functions.function_app_id
}

output "oidc_health_function_id" {
  description = "The OCID of the OCI Health Function."
  value       = module.functions.health_function_id
}

output "oidc_callback_function_id" {
  description = "The OCID of the OCI OIDC Callback Function."
  value       = module.functions.oidc_callback_function_id
}

output "oidc_logout_function_id" {
  description = "The OCID of the OCI Logout Function."
  value       = module.functions.logout_function_id
}

output "vault_ocid" {
  description = "The OCID of the OCI Vault created."
  value       = module.vault.vault_ocid
}

output "oidc_client_secret_ocid" {
  description = "The OCID of the OIDC client secret stored in Vault."
  value       = module.vault.oidc_client_secret_ocid
}

output "apache_mtls_cert_secret_ocid" {
  description = "The OCID of the Apache mTLS client certificate secret in Vault."
  value       = module.vault.apache_mtls_cert_secret_ocid
}

output "apache_mtls_key_secret_ocid" {
  description = "The OCID of the Apache mTLS client key secret in Vault."
  value       = module.vault.apache_mtls_key_secret_ocid
}

output "apigw_mtls_client_cert_secret_ocid" {
  description = "The OCID of the API Gateway mTLS client certificate secret in Vault."
  value       = module.vault.apigw_mtls_client_cert_secret_ocid
}

output "apigw_mtls_client_key_secret_ocid" {
  description = "The OCID of the API Gateway mTLS client key secret in Vault."
  value       = module.vault.apigw_mtls_client_key_secret_ocid
}

output "apache_server_cert_secret_ocid" {
  description = "The OCID of the Apache server certificate (localhost.crt) secret in Vault, used by API GW trust store."
  value       = module.vault.apache_server_cert_secret_ocid
}
