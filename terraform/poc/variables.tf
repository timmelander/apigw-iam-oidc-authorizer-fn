# POC Terraform Variables

variable "tenancy_ocid" {
  description = "The OCID of your OCI tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "The OCID of the compartment for resources"
  type        = string
}

variable "region" {
  description = "The OCI region (e.g., us-chicago-1)"
  type        = string
}

variable "label_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "oidc-poc"
}

# Network
variable "public_subnet_ocid" {
  description = "The OCID of the public subnet for API Gateway"
  type        = string
}

variable "private_subnet_ocid" {
  description = "The OCID of the private subnet for Functions and Cache"
  type        = string
}

# Identity Domain
variable "oci_iam_base_url" {
  description = "OCI IAM Identity Domain base URL (e.g., https://idcs-xxx.identity.oraclecloud.com)"
  type        = string
}

variable "oidc_client_id" {
  description = "The Client ID from your Confidential Application"
  type        = string
}

variable "oidc_client_secret" {
  description = "The Client Secret from your Confidential Application"
  type        = string
  sensitive   = true
}

# Functions
variable "container_repo" {
  description = "OCIR repository URL (e.g., iad.ocir.io/namespace/oidc-fn-repo)"
  type        = string
}

variable "function_version" {
  description = "Version tag for function images"
  type        = string
  default     = "0.0.1"
}

# Backend
variable "backend_url" {
  description = "Backend HTTP server URL (e.g., http://10.0.1.100)"
  type        = string
}
