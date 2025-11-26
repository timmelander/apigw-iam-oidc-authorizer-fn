# apigw-iam-oidc-authorizer/terraform/modules/compartment/main.tf

# This module creates an OCI Compartment.

resource "oci_identity_compartment" "this" {
  count = var.create_compartment ? 1 : 0 # Only create if create_compartment is true

  compartment_id = var.parent_compartment_id
  description    = var.compartment_description
  name           = var.compartment_name
  enable_delete  = true # Allows compartment to be deleted even if not empty
}

output "compartment_ocid" {
  description = "The OCID of the created compartment."
  value       = var.create_compartment ? oci_identity_compartment.this[0].id : var.existing_compartment_ocid
}
