# POC Terraform Configuration
# Simplified deployment for testing and validation
#
# Architecture:
#   Browser → API Gateway (Public) → Functions → OCI Cache
#                                  → Backend (HTTP)
#
# Prerequisites:
#   - Existing VCN with public and private subnets
#   - Existing OCI IAM Identity Domain with Confidential App
#   - Function images built and pushed to OCIR

terraform {
  required_version = ">= 1.0.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

provider "oci" {
  region = var.region
}

# ============================================
# Local Variables
# ============================================
locals {
  label_prefix = var.label_prefix
}

# ============================================
# OCI Cache (Redis) - Session Storage
# ============================================
module "cache" {
  source = "../modules/cache"

  compartment_ocid   = var.compartment_ocid
  label_prefix       = local.label_prefix
  subnet_ocid        = var.private_subnet_ocid
  node_count         = 1
  node_memory_in_gbs = 2
}

# ============================================
# OCI Vault - Secrets Storage
# ============================================
resource "oci_kms_vault" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.label_prefix}-vault"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "this" {
  compartment_id      = var.compartment_ocid
  display_name        = "${local.label_prefix}-key"
  management_endpoint = oci_kms_vault.this.management_endpoint

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# Client Credentials Secret
resource "oci_vault_secret" "client_creds" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.this.id
  secret_name    = "${local.label_prefix}-client-creds"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(jsonencode({
      client_id     = var.oidc_client_id
      client_secret = var.oidc_client_secret
    }))
  }
}

# HKDF Pepper Secret (for session encryption)
resource "random_bytes" "pepper" {
  length = 32
}

resource "oci_vault_secret" "pepper" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.this.id
  secret_name    = "${local.label_prefix}-hkdf-pepper"

  secret_content {
    content_type = "BASE64"
    content      = random_bytes.pepper.base64
  }
}

# ============================================
# OCI Functions
# ============================================
module "functions" {
  source = "../modules/functions"

  compartment_ocid         = var.compartment_ocid
  tenancy_ocid             = var.tenancy_ocid
  label_prefix             = local.label_prefix
  subnet_ocid              = var.private_subnet_ocid
  container_repo           = var.container_repo
  function_version         = var.function_version
  cache_endpoint           = module.cache.cache_fqdn
  oci_iam_base_url         = var.oci_iam_base_url
  gateway_hostname         = oci_apigateway_gateway.this.hostname
  client_creds_secret_ocid = oci_vault_secret.client_creds.id
  pepper_secret_ocid       = oci_vault_secret.pepper.id

  depends_on = [module.cache, oci_vault_secret.client_creds, oci_vault_secret.pepper]
}

# ============================================
# API Gateway (Public)
# ============================================
resource "oci_apigateway_gateway" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.label_prefix}-gateway"
  endpoint_type  = "PUBLIC"
  subnet_id      = var.public_subnet_ocid
}

# API Deployment with Custom Authorizer
resource "oci_apigateway_deployment" "this" {
  compartment_id = var.compartment_ocid
  gateway_id     = oci_apigateway_gateway.this.id
  display_name   = "${local.label_prefix}-deployment"
  path_prefix    = "/"

  specification {
    logging_policies {
      execution_log {
        is_enabled = true
        log_level  = "INFO"
      }
    }

    # Custom Authorizer using apigw_authzr function
    request_policies {
      authentication {
        type                         = "CUSTOM_AUTHENTICATION"
        function_id                  = module.functions.apigw_authzr_function_id
        is_anonymous_access_allowed  = true

        validation_failure_policy {
          type          = "MODIFY_RESPONSE"
          response_code = "302"
          response_header_transformations {
            set_headers {
              items {
                name      = "Location"
                values    = ["/auth/login"]
                if_exists = "OVERWRITE"
              }
            }
          }
        }
      }
    }

    # Anonymous Routes
    routes {
      path    = "/health"
      methods = ["GET"]
      backend {
        type        = "ORACLE_FUNCTIONS_BACKEND"
        function_id = module.functions.health_function_id
      }
      request_policies {
        authorization {
          type = "ANONYMOUS"
        }
      }
    }

    routes {
      path    = "/auth/login"
      methods = ["GET"]
      backend {
        type        = "ORACLE_FUNCTIONS_BACKEND"
        function_id = module.functions.oidc_authn_function_id
      }
      request_policies {
        authorization {
          type = "ANONYMOUS"
        }
      }
    }

    routes {
      path    = "/auth/callback"
      methods = ["GET"]
      backend {
        type        = "ORACLE_FUNCTIONS_BACKEND"
        function_id = module.functions.oidc_callback_function_id
      }
      request_policies {
        authorization {
          type = "ANONYMOUS"
        }
      }
    }

    routes {
      path    = "/auth/logout"
      methods = ["GET", "POST"]
      backend {
        type        = "ORACLE_FUNCTIONS_BACKEND"
        function_id = module.functions.oidc_logout_function_id
      }
      request_policies {
        authorization {
          type = "ANONYMOUS"
        }
      }
    }

    routes {
      path    = "/logged-out"
      methods = ["GET"]
      backend {
        type = "HTTP_BACKEND"
        url  = "${var.backend_url}/logged-out.html"
      }
      request_policies {
        authorization {
          type = "ANONYMOUS"
        }
      }
    }

    routes {
      path    = "/"
      methods = ["GET"]
      backend {
        type = "HTTP_BACKEND"
        url  = "${var.backend_url}/index.html"
      }
      request_policies {
        authorization {
          type = "ANONYMOUS"
        }
      }
    }

    # Protected Routes
    routes {
      path    = "/welcome"
      methods = ["GET"]
      backend {
        type = "HTTP_BACKEND"
        url  = "${var.backend_url}/cgi-bin/userinfo.cgi"
      }
      request_policies {
        authorization {
          type = "AUTHENTICATION_ONLY"
        }
        header_transformations {
          set_headers {
            items {
              name      = "X-User-Sub"
              values    = ["$${request.auth[sub]}"]
              if_exists = "OVERWRITE"
            }
            items {
              name      = "X-User-Email"
              values    = ["$${request.auth[email]}"]
              if_exists = "OVERWRITE"
            }
            items {
              name      = "X-User-Name"
              values    = ["$${request.auth[name]}"]
              if_exists = "OVERWRITE"
            }
            items {
              name      = "X-User-Groups"
              values    = ["$${request.auth[groups]}"]
              if_exists = "OVERWRITE"
            }
          }
        }
      }
    }
  }

  depends_on = [module.functions]
}

# ============================================
# Outputs
# ============================================
output "gateway_url" {
  description = "The public URL of the API Gateway"
  value       = "https://${oci_apigateway_gateway.this.hostname}"
}

output "cache_endpoint" {
  description = "The OCI Cache endpoint"
  value       = module.cache.cache_fqdn
}

output "functions_app_id" {
  description = "The Functions application OCID"
  value       = module.functions.application_id
}

output "vault_id" {
  description = "The Vault OCID"
  value       = oci_kms_vault.this.id
}
