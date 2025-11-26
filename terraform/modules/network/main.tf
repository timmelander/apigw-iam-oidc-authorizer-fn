# apigw-iam-oidc-authorizer/terraform/modules/network/main.tf

# This module provides existing network OCIDs or can create new network resources.
# For this project, we are primarily using existing network resources.

resource "null_resource" "network_pass_through" {
  # This null_resource exists purely to demonstrate module usage when
  # existing resources are passed through, and to hold outputs.
  # In a real scenario where network resources are created,
  # actual oci_* resources would be defined here.
}
