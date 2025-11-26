# apigw-iam-oidc-authorizer/terraform/modules/identity_domain/variables.tf

variable "create_identity_domain" {
  description = "A boolean flag to indicate whether to create a new Identity Domain (true) or use an existing one (false)."
  type        = bool
  default     = false
}

variable "existing_identity_domain_ocid" {
  description = "The OCID of an existing Identity Domain to use if 'create_identity_domain' is false."
  type        = string
  default     = null
}

variable "existing_identity_domain_url" {
  description = "The base URL of an existing Identity Domain to use if 'create_identity_domain' is false."
  type        = string
  default     = null
}

variable "compartment_ocid" {
  description = "The OCID of the compartment where the Identity Domain will be created (if create_identity_domain is true)."
  type        = string
}

variable "domain_display_name" {
  description = "The display name of the Identity Domain to create."
  type        = string
  default     = "default-identity-domain"
}

variable "domain_description" {
  description = "The description of the Identity Domain to create."
  type        = string
  default     = "Identity Domain for OIDC Authorizer resources."
}

variable "region" {
  description = "The region for the Identity Domain."
  type        = string
}

variable "domain_license_type" {
  description = "The license type for the Identity Domain (e.g., FREE, STANDARD, PREMIUM, etc.)."
  type        = string
  default     = "FREE"
}
