# apigw-iam-oidc-authorizer/terraform/versions.tf

terraform {
  required_version = ">= 1.0.0" # Specify your desired Terraform version

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0" # Specify your desired OCI provider version
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}
