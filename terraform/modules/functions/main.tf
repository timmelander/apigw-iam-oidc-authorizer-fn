# OCI Functions Module
# Deploys all 5 functions for the OIDC authentication solution

# Create OCI Functions Application
resource "oci_functions_application" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.label_prefix}-app"
  subnet_ids     = [var.subnet_ocid]

  config = {
    # Application-level config shared by all functions
    OCI_CACHE_ENDPOINT = var.cache_endpoint
  }
}

# Dynamic Group for Functions to access Vault secrets
resource "oci_identity_dynamic_group" "functions" {
  compartment_id = var.tenancy_ocid
  name           = "${var.label_prefix}-functions-dg"
  description    = "Dynamic group for OIDC auth functions"
  matching_rule  = "ALL {resource.type = 'fnfunc', resource.compartment.id = '${var.compartment_ocid}'}"
}

# Policy for Functions to read Vault secrets
resource "oci_identity_policy" "functions_vault" {
  compartment_id = var.compartment_ocid
  name           = "${var.label_prefix}-functions-vault-policy"
  description    = "Allow functions to read vault secrets"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.functions.name} to read secret-family in compartment id ${var.compartment_ocid}"
  ]
}

# ============================================
# Function: health
# ============================================
resource "oci_functions_function" "health" {
  application_id     = oci_functions_application.this.id
  display_name       = "health"
  image              = "${var.container_repo}/health:${var.function_version}"
  memory_in_mbs      = 128
  timeout_in_seconds = 30
}

# ============================================
# Function: oidc_authn (Login initiation)
# ============================================
resource "oci_functions_function" "oidc_authn" {
  application_id     = oci_functions_application.this.id
  display_name       = "oidc_authn"
  image              = "${var.container_repo}/oidc_authn:${var.function_version}"
  memory_in_mbs      = 256
  timeout_in_seconds = 60

  config = {
    OCI_IAM_BASE_URL           = var.oci_iam_base_url
    OIDC_REDIRECT_URI          = "https://${var.gateway_hostname}/auth/callback"
    OCI_VAULT_CLIENT_CREDS_OCID = var.client_creds_secret_ocid
    STATE_TTL_SECONDS          = "300"
    DEFAULT_RETURN_TO          = "/"
  }
}

# ============================================
# Function: oidc_callback (OAuth callback)
# ============================================
resource "oci_functions_function" "oidc_callback" {
  application_id     = oci_functions_application.this.id
  display_name       = "oidc_callback"
  image              = "${var.container_repo}/oidc_callback:${var.function_version}"
  memory_in_mbs      = 256
  timeout_in_seconds = 60

  config = {
    OCI_IAM_BASE_URL           = var.oci_iam_base_url
    OIDC_REDIRECT_URI          = "https://${var.gateway_hostname}/auth/callback"
    OCI_VAULT_CLIENT_CREDS_OCID = var.client_creds_secret_ocid
    OCI_VAULT_PEPPER_OCID      = var.pepper_secret_ocid
    SESSION_TTL_SECONDS        = "28800"
    SESSION_COOKIE_NAME        = "session_id"
    DEFAULT_RETURN_TO          = "/"
    COOKIE_DOMAIN              = var.cookie_domain
  }
}

# ============================================
# Function: apigw_authzr (Session authorizer)
# ============================================
resource "oci_functions_function" "apigw_authzr" {
  application_id     = oci_functions_application.this.id
  display_name       = "apigw_authzr"
  image              = "${var.container_repo}/apigw_authzr:${var.function_version}"
  memory_in_mbs      = 256
  timeout_in_seconds = 60

  config = {
    OCI_VAULT_PEPPER_OCID = var.pepper_secret_ocid
    SESSION_COOKIE_NAME   = "session_id"
  }
}

# ============================================
# Function: oidc_logout (Session termination)
# ============================================
resource "oci_functions_function" "oidc_logout" {
  application_id     = oci_functions_application.this.id
  display_name       = "oidc_logout"
  image              = "${var.container_repo}/oidc_logout:${var.function_version}"
  memory_in_mbs      = 256
  timeout_in_seconds = 60

  config = {
    OCI_IAM_BASE_URL         = var.oci_iam_base_url
    POST_LOGOUT_REDIRECT_URI = "https://${var.gateway_hostname}/logged-out"
    SESSION_COOKIE_NAME      = "session_id"
    COOKIE_DOMAIN            = var.cookie_domain
  }
}
