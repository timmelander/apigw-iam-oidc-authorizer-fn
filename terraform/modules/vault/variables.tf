# apigw-iam-oidc-authorizer/terraform/modules/vault/variables.tf

variable "compartment_ocid" {
  description = "The OCID of the compartment where the Vault and secrets will be created."
  type        = string
}

variable "label_prefix" {
  description = "A prefix for resource names to ensure uniqueness."
  type        = string
}

variable "vault_type" {
  description = "The type of Vault to create (e.g., 'VIRTUAL_PRIVATE' or 'SHARED')."
  type        = string
  default     = "VIRTUAL_PRIVATE"
}

variable "key_protection_mode" {
  description = "The protection mode for the master encryption key (e.g., 'HSM' or 'SOFTWARE')."
  type        = string
  default     = "HSM"
}

variable "apache_mtls_client_cert_pem" {
  description = "The PEM content of the Apache mTLS client certificate."
  type        = string
  sensitive   = true
}

variable "apache_mtls_client_key_pem" {
  description = "The PEM content of the Apache mTLS client key."
  type        = string
  sensitive   = true
}

variable "apigw_mtls_client_cert_pem" {
  description = "The PEM content of the API Gateway mTLS client certificate."
  type        = string
  sensitive   = true
}

variable "apigw_mtls_client_key_pem" {
  description = "The PEM content of the API Gateway mTLS client key."
  type        = string
  sensitive   = true
}

variable "apache_server_cert_pem" {
  description = "The PEM content of the Apache server certificate (localhost.crt), used by API GW for mTLS trust store."
  type        = string
  sensitive   = true
}
