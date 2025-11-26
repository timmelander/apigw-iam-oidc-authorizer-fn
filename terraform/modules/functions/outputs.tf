# OCI Functions Module - Outputs

output "application_id" {
  description = "The OCID of the Functions application"
  value       = oci_functions_application.this.id
}

output "health_function_id" {
  description = "The OCID of the health function"
  value       = oci_functions_function.health.id
}

output "oidc_authn_function_id" {
  description = "The OCID of the oidc_authn function"
  value       = oci_functions_function.oidc_authn.id
}

output "oidc_callback_function_id" {
  description = "The OCID of the oidc_callback function"
  value       = oci_functions_function.oidc_callback.id
}

output "apigw_authzr_function_id" {
  description = "The OCID of the apigw_authzr function"
  value       = oci_functions_function.apigw_authzr.id
}

output "oidc_logout_function_id" {
  description = "The OCID of the oidc_logout function"
  value       = oci_functions_function.oidc_logout.id
}

output "dynamic_group_id" {
  description = "The OCID of the functions dynamic group"
  value       = oci_identity_dynamic_group.functions.id
}
