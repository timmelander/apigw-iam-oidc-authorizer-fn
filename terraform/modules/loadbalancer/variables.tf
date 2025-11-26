# apigw-iam-oidc-authorizer/terraform/modules/loadbalancer/variables.tf

variable "compartment_ocid" {
  description = "The OCID of the compartment where the Load Balancer will be created."
  type        = string
}

variable "label_prefix" {
  description = "A prefix for resource names to ensure uniqueness."
  type        = string
}

variable "public_subnet_ocid" {
  description = "The OCID of the public subnet where the Load Balancer will be deployed."
  type        = string
}

variable "vcn_ocid" {
  description = "The OCID of the VCN where the Load Balancer NSG will be created."
  type        = string
}

variable "apigateway_private_ip" {
  description = "The private IP address of the API Gateway endpoint to be used as a backend."
  type        = string
}

variable "load_balancer_public_ip" {
  description = "The public IP address to associate with the Load Balancer (optional, can be dynamic)."
  type        = string
  default     = "" # If empty, OCI will assign a dynamic public IP
}

variable "lb_domain_name" {
  description = "The common name for the Load Balancer's self-signed SSL certificate."
  type        = string
  default     = "oidc-auth-lb.example.com"
}

variable "api_gateway_subnet_cidr" {
  description = "The CIDR block of the private subnet where the API Gateway is deployed. Used for LB NSG egress rule."
  type        = string
}
