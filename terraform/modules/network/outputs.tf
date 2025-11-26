# apigw-iam-oidc-authorizer/terraform/modules/network/outputs.tf

output "vcn_ocid" {
  description = "The OCID of the VCN used by the module."
  value       = var.vcn_ocid
}

output "public_subnet_ocid" {
  description = "The OCID of the public subnet used by the module."
  value       = var.public_subnet_ocid
}

output "private_subnet_ocid" {
  description = "The OCID of the private subnet used by the module."
  value       = var.private_subnet_ocid
}
