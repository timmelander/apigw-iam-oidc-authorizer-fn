# apigw-iam-oidc-authorizer/terraform/modules/compartment/outputs.tf

output "compartment_ocid" {
  description = "The OCID of the created or existing compartment."
  value       = var.create_compartment ? oci_identity_compartment.this[0].id : var.existing_compartment_ocid
}
