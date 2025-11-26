# apigw-iam-oidc-authorizer/terraform/modules/compute/outputs.tf

output "compute_instance_id" {
  description = "The OCID of the created Compute instance."
  value       = oci_core_instance.this.id
}

output "compute_public_ip" {
  description = "The public IP address of the Compute instance (if assigned)."
  value       = oci_core_instance.this.public_ip
}

output "compute_private_ip" {
  description = "The private IP address of the Compute instance."
  value       = oci_core_instance.this.private_ip
}

output "apache_nsg_id" {
  description = "The OCID of the Network Security Group for the Apache Compute instance."
  value       = oci_core_network_security_group.apache_nsg.id
}
