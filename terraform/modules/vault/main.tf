# apigw-iam-oidc-authorizer/terraform/modules/vault/main.tf

# This module creates an OCI Vault, a Master Encryption Key, and stores various secrets.

# Create OCI Vault
resource "oci_kms_vault" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.label_prefix}-vault"
  vault_type     = var.vault_type # E.g., "VIRTUAL_PRIVATE" or "SHARED"
}

# Create Master Encryption Key
resource "oci_kms_key" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.label_prefix}-master-key"
  key_shape {
    algorithm = "AES"
    length    = 256
  }
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = var.key_protection_mode # E.g., "HSM" or "SOFTWARE"
}

# Store OIDC Client Secret
resource "random_password" "oidc_client_secret_gen" {
  length  = 64
  special = true
  override_special = "!@#$%^&*()-_=+"
}

resource "oci_vault_secret" "oidc_client_secret" {
  compartment_id = var.compartment_ocid
  secret_content {
    content      = base64encode(random_password.oidc_client_secret_gen.result) # Use generated secret
    content_type = "BASE64"
  }
  secret_name      = "${var.label_prefix}-oidc-client-secret"
  vault_id         = oci_kms_vault.this.id
  key_id           = oci_kms_key.this.id
  secret_type = "PLAIN_TEXT" # For consistency with UI manual creation, content is base64 encoded
}

# Store Apache mTLS Client Certificate (provided as input)
resource "oci_vault_secret" "apache_mtls_client_cert" {
  compartment_id = var.compartment_ocid
  secret_content {
    content      = base64encode(var.apache_mtls_client_cert_pem)
    content_type = "BASE64"
  }
  secret_name      = "${var.label_prefix}-apache-mtls-client-cert"
  vault_id         = oci_kms_vault.this.id
  key_id           = oci_kms_key.this.id
  secret_type = "PLAIN_TEXT"
}

# Store Apache mTLS Client Key (provided as input)
resource "oci_vault_secret" "apache_mtls_client_key" {
  compartment_id = var.compartment_ocid
  secret_content {
    content      = base64encode(var.apache_mtls_client_key_pem)
    content_type = "BASE64"
  }
  secret_name      = "${var.label_prefix}-apache-mtls-client-key"
  vault_id         = oci_kms_vault.this.id
  key_id           = oci_kms_key.this.id
  secret_type = "PLAIN_TEXT"
}

# Store API Gateway mTLS Client Certificate (provided as input)
resource "oci_vault_secret" "apigw_mtls_client_cert" {
  compartment_id = var.compartment_ocid
  secret_content {
    content      = base64encode(var.apigw_mtls_client_cert_pem)
    content_type = "BASE64"
  }
  secret_name      = "${var.label_prefix}-apigw-mtls-client-cert"
  vault_id         = oci_kms_vault.this.id
  key_id           = oci_kms_key.this.id
  secret_type = "PLAIN_TEXT"
}

# Store API Gateway mTLS Client Key (provided as input)
resource "oci_vault_secret" "apigw_mtls_client_key" {
  compartment_id = var.compartment_ocid
  secret_content {
    content      = base64encode(var.apigw_mtls_client_key_pem)
    content_type = "BASE64"
  }
  secret_name      = "${var.label_prefix}-apigw-mtls-client-key"
  vault_id         = oci_kms_vault.this.id
  key_id           = oci_kms_key.this.id
  secret_type = "PLAIN_TEXT"
}

# Store Apache Server Certificate (localhost.crt for API GW trust store)
resource "oci_vault_secret" "apache_server_cert" {
  compartment_id = var.compartment_ocid
  secret_content {
    content      = base64encode(var.apache_server_cert_pem)
    content_type = "BASE64"
  }
  secret_name      = "${var.label_prefix}-apache-server-cert"
  vault_id         = oci_kms_vault.this.id
  key_id           = oci_kms_key.this.id
  secret_type = "PLAIN_TEXT"
}
