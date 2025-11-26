# apigw-iam-oidc-authorizer/terraform/environments/prod/variables.tf

# This file defines the input variables for the 'prod' environment.
# These variables will typically be set via a terraform.tfvars file or environment variables.

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
  default     = "oidc-auth-prod"
}

variable "ssh_public_key" {
  description = "The SSH public key to be placed on the compute instance."
  type        = string
}

variable "compute_instance_shape" {
  description = "The shape of the OCI Compute instance."
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "compute_image_ocid" {
  description = "The OCID of the Oracle Linux 10 image to use for the compute instance."
  type        = string
  # Example for us-chicago-1 (can be found in OCI Console -> Compute -> Instances -> Create Instance -> Choose Image)
  # You might need to update this based on your region and desired OS image.
  # For Oracle Linux 10, search the OCI Console for images or use OCI CLI:
  # oci compute image list --compartment-id <image_compartment_ocid> --operating-system "Oracle Linux" --operating-system-version "10" --query 'data[?contains("display-name",`Oracle-Linux-10`)] | [0].id' --raw-output
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

variable "oci_functions_container_repo" {
  description = "The OCI Container Registry repository URL for storing function images (e.g., 'phx.ocir.io/your_tenancy_namespace/your_repo_name')."
  type        = string
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

variable "load_balancer_subnet_cidr" {
  description = "The CIDR block of the public subnet where the Load Balancer is deployed. Used for API Gateway NSG ingress rule."
  type        = string
}

variable "api_gateway_subnet_cidr" {
  description = "The CIDR block of the private subnet where the API Gateway is deployed. Used for NSG ingress rule for Compute."
  type        = string
}

variable "lb_domain_name" {
  description = "The common name for the Load Balancer's self-signed SSL certificate."
  type        = string
  default     = "oidc-auth-lb.example.com"
}

# Add placeholder variables for any manual inputs needed during Terraform apply
# For example, OCID of an existing Identity Domain.
# If you plan to create Identity Domain via Terraform, this variable might be removed.
