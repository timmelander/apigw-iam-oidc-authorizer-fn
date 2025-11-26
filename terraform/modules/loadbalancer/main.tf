# apigw-iam-oidc-authorizer/terraform/modules/loadbalancer/main.tf

# This module creates an OCI Flexible Load Balancer.

# Generate self-signed certificate for the Load Balancer
resource "tls_private_key" "lb_private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "lb_self_signed_cert" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.lb_private_key.private_key_pem

  subjects {
    common_name  = var.lb_domain_name
    organization = "OCI-OIDC-Authorizer"
  }

  valid_until = timeadd(timestamp(), "8760h") # 1 year
  is_ca_certificate = true
  
  dns_names = [var.lb_domain_name]
  ip_addresses = [var.load_balancer_public_ip] # If using static public IP

  usages = [
    "client_auth",
    "server_auth",
    "digital_signature",
    "key_encipherment",
    "key_agreement",
  ]
}

# Upload the certificate to OCI Certificate service
resource "oci_load_balancer_certificate" "lb_certificate" {
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  certificate_name = "${var.label_prefix}-lb-cert"
  private_key_body = tls_private_key.lb_private_key.private_key_pem
  public_certificate_body = tls_self_signed_cert.lb_self_signed_cert.cert_pem
}

# Create OCI Flexible Load Balancer
resource "oci_load_balancer_load_balancer" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.label_prefix}-lb"
  shape          = "flexible"
  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 100
  }
  subnet_ids     = [var.public_subnet_ocid]
  is_private     = false # Public Load Balancer
  network_security_group_ids = [oci_core_network_security_group.lb_nsg.id]
}

# NSG for Load Balancer
resource "oci_core_network_security_group" "lb_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = var.vcn_ocid
  display_name   = "${var.label_prefix}-lb-nsg"
}

# NSG Rule: Ingress from Internet (HTTPS)
resource "oci_core_network_security_group_security_rule" "lb_nsg_ingress_https" {
  network_security_group_id = oci_core_network_security_group.lb_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

# NSG Rule: Egress to API Gateway Private Subnet
resource "oci_core_network_security_group_security_rule" "lb_nsg_egress_apigw" {
  network_security_group_id = oci_core_network_security_group.lb_nsg.id
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = var.api_gateway_subnet_cidr
  destination_type          = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

# Backend Set for API Gateway
resource "oci_load_balancer_backend_set" "apigw_backend_set" {
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  name             = "${var.label_prefix}-apigw-backend-set"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "HTTP"
    port              = 443 # API Gateway listener port
    url_path          = "/healthz"
    response_body_regex = ".*ok.*" # Health check from API Gateway function
    # Other health check parameters can be tuned
  }

  ssl_configuration {
    # If the API Gateway uses HTTPS, and the LB connects to it over HTTPS.
    # No trust store needed if API GW certificate is publicly trusted.
    # Otherwise, you would add a ca_certificate_id here.
    # For now, assuming API Gateway has a certificate trusted by OCI LB by default.
    protocol = "TLS" 
    verify_hostname = false # Might need to be true in prod if using proper certs
  }
}

# Add API Gateway as backend to the Backend Set
resource "oci_load_balancer_backend" "apigw_backend" {
  backend_set_name = oci_load_balancer_backend_set.apigw_backend_set.name
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  ip_address       = var.apigateway_private_ip
  port             = 443
  weight           = 1
}

# Listener for HTTPS traffic
resource "oci_load_balancer_listener" "https_listener" {
  load_balancer_id         = oci_load_balancer_load_balancer.this.id
  name                     = "${var.label_prefix}-https-listener"
  default_backend_set_name = oci_load_balancer_backend_set.apigw_backend_set.name
  port                     = 443
  protocol                 = "HTTPS"
  ssl_configuration {
    certificate_name = oci_load_balancer_certificate.lb_certificate.certificate_name
    protocol         = "TLSv1.2"
    cipher_suite_name = "oci-tls-12-recommended" # OCI recommended cipher suite
  }
}
