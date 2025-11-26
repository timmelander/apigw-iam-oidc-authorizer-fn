# apigw-iam-oidc-authorizer/terraform/modules/confidential_app/variables.tf

variable "create_confidential_app" {
  description = "A boolean flag to indicate whether to create a new Confidential Application (true) or use an existing one (false)."
  type        = bool
  default     = false
}

variable "existing_app_id" {
  description = "The ID of an existing Confidential Application to use if 'create_confidential_app' is false. (This is the app ID, not the client ID)"
  type        = string
  default     = null
}

variable "existing_client_id" {
  description = "The Client ID of an existing Confidential Application to use if 'create_confidential_app' is false."
  type        = string
  default     = null
}

variable "compartment_ocid" {
  description = "The OCID of the compartment where the Identity Domain resides (for app creation)."
  type        = string
}

variable "iam_domain_idcs_endpoint" {
  description = "The IDCS endpoint URL for the OCI IAM Identity Domain (e.g., https://idcs-xxxx.identity.oraclecloud.com/oauth2/v1/token)."
  type        = string
}

variable "app_display_name" {
  description = "The display name of the Confidential Application to create."
  type        = string
  default     = "OIDC-Confidential-App"
}

variable "app_description" {
  description = "The description of the Confidential Application to create."
  type        = string
  default     = "OIDC Confidential Application for API Gateway Authorizer"
}

variable "oauth_client_grant_types" {
  description = "List of OAuth client grant types (e.g., [\"authorization_code\", \"refresh_token\"])."
  type        = list(string)
  default     = ["authorization_code", "refresh_token"]
}

variable "oauth_client_redirect_uris" {
  description = "List of OAuth client redirect URIs (e.g., [\"https://<lb_ip>/oauth2/callback\"])."
  type        = list(string)
}

variable "oauth_client_post_logout_redirect_uris" {
  description = "List of OAuth client post logout redirect URIs."
  type        = list(string)
}

variable "label_prefix" {
  description = "A prefix for resource names to ensure uniqueness."
  type        = string
}
