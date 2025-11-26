# apigw-iam-oidc-authorizer/terraform/modules/compartment/variables.tf

variable "create_compartment" {
  description = "A boolean flag to indicate whether to create a new compartment (true) or use an existing one (false)."
  type        = bool
  default     = false
}

variable "existing_compartment_ocid" {
  description = "The OCID of an existing compartment to use if 'create_compartment' is false."
  type        = string
  default     = null
}

variable "compartment_name" {
  description = "The name of the compartment to create."
  type        = string
  default     = "default-compartment-name" # Placeholder, will be overridden by label_prefix
}

variable "compartment_description" {
  description = "The description of the compartment to create."
  type        = string
  default     = "Compartment for OIDC Authorizer resources."
}

variable "parent_compartment_id" {
  description = "The OCID of the parent compartment (usually tenancy OCID) for the new compartment."
  type        = string
}
