# apigw-iam-oidc-authorizer/terraform/modules/network/variables.tf

variable "compartment_ocid" {
  description = "The OCID of the compartment where network resources exist or will be created."
  type        = string
}

variable "vcn_ocid" {
  description = "The OCID of the Virtual Cloud Network (VCN) to use."
  type        = string
}

variable "public_subnet_ocid" {
  description = "The OCID of the public subnet to use for the Load Balancer."
  type        = string
}

variable "private_subnet_ocid" {
  description = "The OCID of the private subnet to use for the API Gateway and Compute instance."
  type        = string
}
