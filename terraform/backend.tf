# apigw-iam-oidc-authorizer/terraform/backend.tf

# Optional: Configure a Terraform remote backend to store state.
# This prevents state from being stored locally and facilitates collaboration.
#
# Example using an OCI Object Storage bucket (S3-compatible API):
/*
terraform {
  backend "s3" {
    endpoint         = "https://<your_object_storage_namespace>.compat.objectstorage.<your_region>.oraclecloud.com"
    bucket           = "<your_bucket_name>"
    key              = "terraform.tfstate"
    region           = "<your_region>"
    skip_region_validation = true
    skip_credentials_validation = true
    skip_metadata_api_check = true
    force_path_style = true

    # Configure authentication for OCI Object Storage S3-compatible API
    # Replace with your OCI API Key details or Instance Principal configuration
    # Example using user API key:
    # access_key = "..."
    # secret_key = "..."
  }
}
*/
