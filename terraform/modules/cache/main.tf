# OCI Cache (Redis) Module
# Provides session storage for the OIDC authentication solution

resource "oci_redis_redis_cluster" "this" {
  compartment_id     = var.compartment_ocid
  display_name       = "${var.label_prefix}-cache"
  node_count         = var.node_count
  node_memory_in_gbs = var.node_memory_in_gbs
  software_version   = var.software_version
  subnet_id          = var.subnet_ocid

  # Optional: NSG for additional security
  nsg_ids = var.nsg_ids
}
