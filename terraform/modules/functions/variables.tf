# OCI Functions Module - Variables

variable "compartment_ocid" {
  description = "The OCID of the compartment"
  type        = string
}

variable "tenancy_ocid" {
  description = "The OCID of the tenancy (for dynamic group)"
  type        = string
}

variable "label_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "subnet_ocid" {
  description = "The OCID of the subnet for functions"
  type        = string
}

variable "container_repo" {
  description = "OCI Container Registry repo URL (e.g., iad.ocir.io/namespace/repo)"
  type        = string
}

variable "function_version" {
  description = "Version tag for function images"
  type        = string
  default     = "0.0.1"
}

variable "cache_endpoint" {
  description = "OCI Cache (Redis) endpoint FQDN"
  type        = string
}

variable "oci_iam_base_url" {
  description = "OCI IAM Identity Domain base URL"
  type        = string
}

variable "gateway_hostname" {
  description = "Public hostname for the API Gateway (for redirect URIs)"
  type        = string
}

variable "client_creds_secret_ocid" {
  description = "OCID of the Vault secret containing client credentials"
  type        = string
}

variable "pepper_secret_ocid" {
  description = "OCID of the Vault secret containing HKDF pepper"
  type        = string
}

variable "cookie_domain" {
  description = "Domain for session cookies (optional, leave empty for default)"
  type        = string
  default     = ""
}
