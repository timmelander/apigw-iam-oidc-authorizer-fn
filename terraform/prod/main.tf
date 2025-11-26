# apigw-iam-oidc-authorizer/terraform/environments/prod/main.tf

# This file orchestrates the deployment of all OCI resources using modules.

# Define local variables for easier reference
locals {
  label_prefix        = var.label_prefix
  compartment_ocid    = var.compartment_ocid
  tenancy_ocid        = var.tenancy_ocid
  region              = var.region
  ssh_public_key      = var.ssh_public_key
  compute_shape       = var.compute_instance_shape
  compute_image_ocid  = var.compute_image_ocid
  vcn_ocid            = var.vcn_ocid
  public_subnet_ocid  = var.public_subnet_ocid
  private_subnet_ocid = var.private_subnet_ocid
  oci_iam_domain_ocid = var.oci_iam_domain_ocid
  oci_iam_base_url    = var.oci_iam_base_url
  oidc_client_id      = var.oidc_client_id
}

# --- MODULE CALLS ---
# The actual module calls will go here once modules are defined.
# They will pass variables to the modules and use outputs from other modules.

# 1. Compartment (if creating a new one, otherwise use existing)
module "compartment" {
  source                    = "../../modules/compartment"
  create_compartment        = false # Use existing compartment
  existing_compartment_ocid = local.compartment_ocid
  parent_compartment_id     = local.tenancy_ocid # Not used when using existing, but required by module
  compartment_name          = "${local.label_prefix}-compartment" # Not used when using existing, but required by module
}

# 2. Network (VCN, Subnets, etc. if creating new)
module "network" {
  source              = "../../modules/network"
  compartment_ocid    = local.compartment_ocid
  vcn_ocid            = local.vcn_ocid
  public_subnet_ocid  = local.public_subnet_ocid
  private_subnet_ocid = local.private_subnet_ocid
}

# 3. Identity Domain (if creating new, otherwise use existing)
module "identity_domain" {
  source                       = "../../modules/identity_domain"
  create_identity_domain       = false # Use existing Identity Domain
  existing_identity_domain_ocid = local.oci_iam_domain_ocid
  existing_identity_domain_url = local.oci_iam_base_url
  compartment_ocid             = local.compartment_ocid # Required by module, but not used when using existing
  domain_display_name          = "${local.label_prefix}-id-domain" # Required by module, but not used when using existing
  region                       = local.region # Required by module, but not used when using existing
}

# 4. OIDC Confidential Application (updating existing)
module "confidential_app" {
  source                       = "../../modules/confidential_app"
  create_confidential_app      = false # Use existing confidential app
  existing_app_id              = "ec366479cf1f49b99261a2d94291f724" # apigw-oidc-app
  existing_client_id           = local.oidc_client_id # From input var.oidc_client_id
  compartment_ocid             = local.compartment_ocid
  iam_domain_idcs_endpoint     = local.oci_iam_base_url # Base URL for IDCS operations
  label_prefix                 = local.label_prefix
  oauth_client_redirect_uris   = ["https://${module.loadbalancer.load_balancer_public_ip}/oauth2/callback"]
  oauth_client_post_logout_redirect_uris = ["https://${module.loadbalancer.load_balancer_public_ip}/logout"]
  depends_on                   = [module.loadbalancer] # Depends on LB IP to set redirect URIs
}

# 5. OCI Vault for secrets
module "vault" {
  source                     = "../../modules/vault"
  compartment_ocid           = local.compartment_ocid
  label_prefix               = local.label_prefix
  apache_mtls_client_cert_pem = var.apache_mtls_client_cert_pem
  apache_mtls_client_key_pem  = var.apache_mtls_client_key_pem
  apigw_mtls_client_cert_pem  = var.apigw_mtls_client_cert_pem
  apigw_mtls_client_key_pem   = var.apigw_mtls_client_key_pem
  apache_server_cert_pem     = var.apache_server_cert_pem
}

# 6. OCI Functions Deployment
module "functions" {
  source                       = "../../modules/functions"
  compartment_ocid             = local.compartment_ocid
  label_prefix                 = local.label_prefix
  private_subnet_ocid          = module.network.private_subnet_ocid
  oci_functions_container_repo = var.oci_functions_container_repo
  oci_iam_base_url             = local.oci_iam_base_url
  oidc_client_id               = local.oidc_client_id
  client_secret_ocid           = module.vault.oidc_client_secret_ocid
  lb_public_ip                 = module.loadbalancer.load_balancer_public_ip
  depends_on                   = [module.vault, module.loadbalancer] # Depend on vault for secrets and LB for public IP
}

# 7. OCI Compute Instance (Apache HTTP Server)
module "compute" {
  source                     = "../../modules/compute"
  compartment_ocid           = local.compartment_ocid
  tenancy_ocid               = local.tenancy_ocid
  label_prefix               = local.label_prefix
  private_subnet_ocid        = module.network.private_subnet_ocid
  ssh_public_key             = local.ssh_public_key
  compute_shape              = local.compute_shape
  compute_image_ocid         = local.compute_image_ocid
  vcn_ocid                   = local.vcn_ocid
  mtls_client_cert_secret_ocid = module.vault.apache_mtls_cert_secret_ocid
  mtls_client_key_secret_ocid  = module.vault.apache_mtls_key_secret_ocid
  apigw_client_cert_secret_ocid = module.vault.apigw_client_cert_secret_ocid
  api_gateway_subnet_cidr    = var.api_gateway_subnet_cidr # This will be the same as private_subnet_ocid for API GW.
  depends_on                 = [module.vault, module.network] # Depends on Vault for secrets and Network for subnets/VCN
}

# 8. OCI API Gateway
module "apigateway" {
  source                       = "../../modules/apigateway"
  compartment_ocid             = local.compartment_ocid
  label_prefix                 = local.label_prefix
  private_subnet_ocid          = module.network.private_subnet_ocid
  vcn_ocid                     = local.vcn_ocid
  load_balancer_subnet_cidr    = var.load_balancer_subnet_cidr
  oci_iam_base_url             = local.oci_iam_base_url
  oidc_client_id               = local.oidc_client_id
  apache_compute_ip            = module.compute.compute_private_ip
  health_function_id           = module.functions.health_function_id
  oidc_callback_function_id    = module.functions.oidc_callback_function_id
  logout_function_id           = module.functions.logout_function_id
  apigw_mtls_client_cert_secret_ocid = module.vault.apigw_mtls_client_cert_secret_ocid
  apigw_mtls_client_key_secret_ocid = module.vault.apigw_mtls_client_key_secret_ocid
  apache_server_cert_secret_ocid = module.vault.apache_server_cert_secret_ocid
  functions_subnet_cidr        = module.network.private_subnet_ocid # Assuming functions and APIGW are in the same private subnet
  depends_on                   = [module.vault, module.network, module.functions, module.compute]
}

# 9. OCI Flexible Load Balancer
module "loadbalancer" {
  source                     = "../../modules/loadbalancer"
  compartment_ocid           = local.compartment_ocid
  label_prefix               = local.label_prefix
  public_subnet_ocid         = module.network.public_subnet_ocid
  vcn_ocid                   = local.vcn_ocid
  apigateway_private_ip      = module.apigateway.apigateway_private_ip
  load_balancer_public_ip    = "" # Let OCI assign public IP
  lb_domain_name             = var.lb_domain_name
  api_gateway_subnet_cidr    = var.api_gateway_subnet_cidr
  depends_on                 = [module.apigateway] # Depends on API Gateway for private IP
}