# apigw-iam-oidc-authorizer/terraform/modules/loadbalancer/outputs.tf

output "load_balancer_id" {
  description = "The OCID of the Load Balancer."
  value       = oci_load_balancer_load_balancer.this.id
}

output "load_balancer_public_ip" {
  description = "The public IP address of the OCI Flexible Load Balancer."
  value       = oci_load_balancer_load_balancer.this.ip_addresses[0].ip_address
}

output "load_balancer_nsg_id" {
  description = "The OCID of the Network Security Group for the Load Balancer."
  value       = oci_core_network_security_group.lb_nsg.id
}
