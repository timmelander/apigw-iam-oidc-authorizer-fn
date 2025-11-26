# apigw-iam-oidc-authorizer/terraform/modules/apigateway/variables.tf

variable "compartment_ocid" {
  description = "The OCID of the compartment where the API Gateway will be created."
  type        = string
}

variable "label_prefix" {
  description = "A prefix for resource names to ensure uniqueness."
  type        = string
}

variable "private_subnet_ocid" {
  description = "The OCID of the private subnet where the API Gateway will be deployed."
  type        = string
}

variable "vcn_ocid" {
  description = "The OCID of the VCN where the API Gateway NSG will be created."
  type        = string
}

variable "load_balancer_subnet_cidr" {
  description = "The CIDR block of the public subnet where the Load Balancer is deployed."
  type        = string
}

variable "oci_iam_base_url" {
  description = "The base URL of the OCI IAM Identity Domain (used for JWKS URL and issuer)."
  type        = string
}

variable "oidc_client_id" {
  description = "The Client ID of the OIDC Confidential Application (used for JWT audience)."
  type        = string
}

variable "apache_compute_ip" {
  description = "The private IP address of the Apache Compute instance (backend for /* route)."
  type        = string
}

variable "health_function_id" {
  description = "The OCID of the 'health' OCI Function."
  type        = string
}

variable "oidc_callback_function_id" {
  description = "The OCID of the 'oidc_callback' OCI Function."
  type        = string
}

variable "logout_function_id" {
  description = "The OCID of the 'logout' OCI Function."
  type        = string
}

variable "apigw_mtls_client_cert_secret_ocid" {
  description = "The OCID of the Vault secret containing the API Gateway mTLS client certificate."
  type        = string
}

variable "apigw_mtls_client_key_secret_ocid" {
  description = "The OCID of the Vault secret containing the API Gateway mTLS client key."
  type        = string
}

variable "apache_server_cert_secret_ocid" {
  description = "The OCID of the Vault secret containing the Apache server certificate (localhost.crt), used by API GW for mTLS trust store."
  type        = string
}

variable "functions_subnet_cidr" {
  description = "The CIDR block of the private subnet where the Functions application is deployed."
  type        = string
}
