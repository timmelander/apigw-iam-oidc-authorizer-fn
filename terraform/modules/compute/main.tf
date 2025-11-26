# apigw-iam-oidc-authorizer/terraform/modules/compute/main.tf

# This module creates an OCI Compute instance running Oracle Linux 10
# with Apache HTTP Server configured via cloud-init for mTLS.

resource "oci_core_instance" "this" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name # Assumes first AD
  display_name        = "${var.label_prefix}-apache-compute"
  shape               = var.compute_shape

  source_details {
    source_id   = var.compute_image_ocid
    source_type = "image"
  }

  create_vnic_details {
    subnet_id        = var.private_subnet_ocid
    display_name     = "${var.label_prefix}-vnic"
    hostname_label   = "${var.label_prefix}-apache"
    assign_public_ip = false # Compute instance in private subnet, no public IP
    nsg_ids          = [oci_core_network_security_group.apache_nsg.id]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/../../apache/user_data.yaml", {
      MTLS_CLIENT_CERT_SECRET_OCID  = var.mtls_client_cert_secret_ocid
      MTLS_CLIENT_KEY_SECRET_OCID   = var.mtls_client_key_secret_ocid
      APIGW_CLIENT_CERT_OCID        = var.apigw_client_cert_secret_ocid
      API_GATEWAY_SUBNET_CIDR       = var.api_gateway_subnet_cidr # Pass NSG's CIDR or API GW's subnet CIDR
    }))
  }
}

# Data source to get availability domains for the region
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# NSG for Apache Compute Instance
resource "oci_core_network_security_group" "apache_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = var.vcn_ocid
  display_name   = "${var.label_prefix}-apache-nsg"
}

# NSG Rule: Allow SSH from anywhere (for easy access, refine in production)
resource "oci_core_network_security_group_security_rule" "apache_nsg_ssh_ingress" {
  network_security_group_id = oci_core_network_security_group.apache_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 22
      min = 22
    }
  }
}

# NSG Rule: Allow HTTPS (mTLS) from API Gateway Private Subnet
resource "oci_core_network_security_group_security_rule" "apache_nsg_https_ingress_apigw" {
  network_security_group_id = oci_core_network_security_group.apache_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  # Source is the API Gateway's private subnet CIDR
  source                    = var.api_gateway_subnet_cidr
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      max = 443
      min = 443
    }
  }
}

# NSG Rule: Allow Egress to all ports (for updates, OCI Vault, IAM, etc.)
resource "oci_core_network_security_group_security_rule" "apache_nsg_egress_all" {
  network_security_group_id = oci_core_network_security_group.apache_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}
