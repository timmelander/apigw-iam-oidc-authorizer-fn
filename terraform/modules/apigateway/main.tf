# apigw-iam-oidc-authorizer/terraform/modules/apigateway/main.tf

# This module creates an OCI API Gateway and deploys the OIDC authorizer routes.

# Create OCI API Gateway
resource "oci_apigateway_gateway" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.label_prefix}-apigw"
  endpoint_type  = "PRIVATE"
  subnet_id      = var.private_subnet_ocid
  network_security_group_ids = [oci_core_network_security_group.apigw_nsg.id]
}

# NSG for API Gateway
resource "oci_core_network_security_group" "apigw_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = var.vcn_ocid
  display_name   = "${var.label_prefix}-apigw-nsg"
}

# NSG Rule: Ingress from Load Balancer Public Subnet
resource "oci_core_network_security_group_security_rule" "apigw_nsg_ingress_lb" {
  network_security_group_id = oci_core_network_security_group.apigw_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.load_balancer_subnet_cidr
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

# NSG Rule: Egress to Apache Compute Private IP (mTLS)
resource "oci_core_network_security_group_security_rule" "apigw_nsg_egress_apache" {
  network_security_group_id = oci_core_network_security_group.apigw_nsg.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = "${var.apache_compute_ip}/32" # Specific IP
  destination_type          = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

# NSG Rule: Egress to Functions Private Subnet
resource "oci_core_network_security_group_security_rule" "apigw_nsg_egress_functions" {
  network_security_group_id = oci_core_network_security_group.apigw_nsg.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = var.functions_subnet_cidr # Assuming functions app is in the same private subnet as apigw for simplicity
  destination_type          = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

# NSG Rule: Egress to OCI IAM (Public Internet, for JWKS lookup)
resource "oci_core_network_security_group_security_rule" "apigw_nsg_egress_iam" {
  network_security_group_id = oci_core_network_security_group.apigw_nsg.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}


# Create API Deployment
resource "oci_apigateway_deployment" "this" {
  compartment_id = var.compartment_ocid
  gateway_id     = oci_apigateway_gateway.this.id
  display_name   = "${var.label_prefix}-deployment"
  path_prefix    = "/"

  specification {
    request_policies {
      authentication {
        type            = "JWT"
        is_anonymous_access_allowed = false
        audiences       = [var.oidc_client_id]
        token_auth_scheme = "Bearer"
        token_header    = "Authorization"
        issuers         = [var.oci_iam_base_url]
        max_clock_skew_in_seconds = 60 # Allow for some clock skew
        public_keys {
          type = "REMOTE_JWKS"
          uri  = "${var.oci_iam_base_url}/.well-known/jwks.json"
        }
      }
    }

    routes {
      path = "/healthz"
      methods = ["GET"]
      backend {
        type = "ORACLE_FUNCTIONS"
        function_id = var.health_function_id
        is_unauthorized_or_unauthenticated_access_allowed = true # No auth for health check
      }
    }

    routes {
      path = "/oauth2/callback"
      methods = ["GET"]
      backend {
        type = "ORACLE_FUNCTIONS"
        function_id = var.oidc_callback_function_id
        is_unauthorized_or_unauthenticated_access_allowed = true # No auth for OIDC callback
      }
    }

    routes {
      path = "/logout"
      methods = ["GET"]
      backend {
        type = "ORACLE_FUNCTIONS"
        function_id = var.logout_function_id
        is_unauthorized_or_unauthenticated_access_allowed = true # No auth for logout
      }
    }

    routes {
      path = "/*"
      methods = ["ANY"]
      backend {
        type = "HTTP"
        url  = "https://${var.apache_compute_ip}" # Backend is Apache
        
        # mTLS configuration for API Gateway as client to Apache as server
        ssl_configuration {
          client_certificate_secret_id = var.apigw_mtls_client_cert_secret_ocid
          client_private_key_secret_id = var.apigw_mtls_client_key_secret_ocid
          trust_store_secret_id        = var.apache_server_cert_secret_ocid # Apache's localhost.crt for API GW to trust
        }
      }
    }
  }
}
