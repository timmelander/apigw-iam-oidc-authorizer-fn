# apigw-iam-oidc-authorizer/terraform/modules/vault/outputs.tf

output "vault_ocid" {
  description = "The OCID of the created OCI Vault."
  value       = oci_kms_vault.this.id
}

output "master_key_ocid" {
  description = "The OCID of the created Master Encryption Key."
  value       = oci_kms_key.this.id
}

output "oidc_client_secret_ocid" {
  description = "The OCID of the OIDC client secret stored in Vault."
  value       = oci_vault_secret.oidc_client_secret.id
}

output "apache_mtls_cert_secret_ocid" {
  description = "The OCID of the Apache mTLS client certificate secret in Vault."
  value       = oci_vault_secret.apache_mtls_client_cert.id
}

output "apache_mtls_key_secret_ocid" {
  description = "The OCID of the Apache mTLS client key secret in Vault."
  value       = oci_vault_secret.apache_mtls_client_key.id
}

output "apigw_mtls_client_cert_secret_ocid" {
  description = "The OCID of the API Gateway mTLS client certificate secret in Vault."
  value       = oci_vault_secret.apigw_mtls_client_cert.id
}

output "apigw_mtls_client_key_secret_ocid" {
  description = "The OCID of the API Gateway mTLS client key secret in Vault."
  value       = oci_vault_secret.apigw_mtls_client_key.id
}

output "apache_server_cert_secret_ocid" {
  description = "The OCID of the Apache server certificate (localhost.crt) secret in Vault."
  value       = oci_vault_secret.apache_server_cert.id
}
