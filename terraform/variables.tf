# apigw-iam-oidc-authorizer/terraform/variables.tf

variable "tenancy_ocid" {
  description = "The OCID of your OCI tenancy."
  type        = string
}

variable "compartment_ocid" {
  description = "The OCID of the compartment where resources will be created."
  type        = string
}

variable "region" {
  description = "The OCI region where resources will be deployed."
  type        = string
}

variable "label_prefix" {
  description = "A prefix for resource names to ensure uniqueness."
  type        = string
  default     = "oidc-auth"
}

variable "ssh_public_key" {
  description = "The SSH public key to be placed on the compute instance."
  type        = string
}

variable "compute_instance_shape" {
  description = "The shape of the OCI Compute instance."
  type        = string
  default     = "VM.Standard.E4.Flex" # A flexible shape, adjust as needed
}

variable "compute_image_ocid" {
  description = "The OCID of the Oracle Linux 10 image to use for the compute instance."
  type        = string
  # Example for us-chicago-1 (can be found in OCI Console -> Compute -> Instances -> Create Instance -> Choose Image)
  # ocid1.image.oc1.us-chicago-1.aaaaaaaawlzzswc4j7vgh4z3n6g6h2u3q7f2y5x8t6d0c1m4e9v2s0r1p3o5e7w9x
  # Use 'oci compute image list --compartment-id <image_compartment_ocid> --operating-system "Oracle Linux" --operating-system-version "8" --query 'data[?contains("display-name",`Oracle-Linux-8`)] | [0].id' --raw-output'
  # This should be Oracle Linux 10, check for exact image
}

variable "vcn_ocid" {
  description = "The OCID of the Virtual Cloud Network (VCN) to deploy resources into."
  type        = string
}

variable "public_subnet_ocid" {
  description = "The OCID of the public subnet for the Load Balancer."
  type        = string
}

variable "private_subnet_ocid" {
  description = "The OCID of the private subnet for the API Gateway and Compute instance."
  type        = string
}

variable "oci_iam_domain_ocid" {
  description = "The OCID of the OCI IAM Identity Domain to use."
  type        = string
}

variable "oci_iam_base_url" {
  description = "The base URL of the OCI IAM Identity Domain (e.g., https://idcs-xxxx.identity.oraclecloud.com)."
  type        = string
}

variable "oidc_client_id" {
  description = "The Client ID of the OIDC Confidential Application."
  type        = string
}

# The actual client secret will be generated and stored in Vault,
# this is just for reference in case it needs to be passed.
# variable "oidc_client_secret" {
#   description = "The Client Secret of the OIDC Confidential Application."
#   type        = string
#   sensitive   = true
# }
