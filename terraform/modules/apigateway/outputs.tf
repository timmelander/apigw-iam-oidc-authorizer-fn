# apigw-iam-oidc-authorizer/terraform/modules/apigateway/outputs.tf

output "apigateway_id" {
  description = "The OCID of the API Gateway."
  value       = oci_apigateway_gateway.this.id
}

output "apigateway_private_ip" {
  description = "The private IP address of the API Gateway endpoint."
  value       = oci_apigateway_gateway.this.ip_addresses[0].ip_address
}

output "api_gateway_deployment_endpoint" {
  description = "The deployment endpoint URL of the OCI API Gateway."
  value       = oci_apigateway_deployment.this.endpoint
}

output "apigw_nsg_id" {
  description = "The OCID of the Network Security Group for the API Gateway."
  value       = oci_core_network_security_group.apigw_nsg.id
}
