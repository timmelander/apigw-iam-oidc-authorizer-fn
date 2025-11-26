# apigw-iam-oidc-authorizer/terraform/provider.tf

# Configure the Oracle Cloud Infrastructure (OCI) Provider
provider "oci" {
  # The tenancy_ocid, user_ocid, fingerprint, and private_key_path can be
  # sourced from environment variables, CLI config file (~/.oci/config),
  # or explicitly defined here. For production, environment variables
  # or instance principals are recommended.
  #
  # Example using environment variables:
  # OCI_TENANCY_OCID, OCI_USER_OCID, OCI_FINGERPRINT, OCI_PRIVATE_KEY_PATH, OCI_REGION
  #
  # For local testing, ensure your ~/.oci/config is correctly set up.
  # If you are running this within an OCI Compute instance, you can use
  # instance principals for authentication by omitting these attributes
  # (though a 'auth = "InstancePrincipal"' may be needed in some older provider versions).
}
