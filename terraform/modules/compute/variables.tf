# apigw-iam-oidc-authorizer/terraform/modules/compute/variables.tf

variable "compartment_ocid" {
  description = "The OCID of the compartment where the Compute instance will be created."
  type        = string
}

variable "tenancy_ocid" {
  description = "The OCID of your OCI tenancy (used for AD lookup)."
  type        = string
}

variable "label_prefix" {
  description = "A prefix for resource names to ensure uniqueness."
  type        = string
}

variable "private_subnet_ocid" {
  description = "The OCID of the private subnet where the Compute instance will be deployed."
  type        = string
}

variable "ssh_public_key" {
  description = "The SSH public key to be placed on the compute instance."
  type        = string
  sensitive   = true
}

variable "compute_shape" {
  description = "The shape of the OCI Compute instance."
  type        = string
}

variable "compute_image_ocid" {
  description = "The OCID of the Oracle Linux 10 image to use for the compute instance."
  type        = string
}

variable "vcn_ocid" {
  description = "The OCID of the VCN where the Compute instance's VNIC will be created."
  type        = string
}

variable "mtls_client_cert_secret_ocid" {
  description = "The OCID of the Vault secret containing the Apache mTLS client certificate."
  type        = string
}

variable "mtls_client_key_secret_ocid" {
  description = "The OCID of the Vault secret containing the Apache mTLS client key."
  type        = string
}

variable "apigw_client_cert_secret_ocid" {
  description = "The OCID of the Vault secret containing the API Gateway's client certificate (for Apache's trust store)."
  type        = string
}

variable "api_gateway_subnet_cidr" {
  description = "The CIDR block of the private subnet where the API Gateway is deployed. Used for NSG ingress rule."
  type        = string
}
