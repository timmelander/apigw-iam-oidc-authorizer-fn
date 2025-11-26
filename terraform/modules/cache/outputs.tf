output "cache_id" {
  description = "The OCID of the cache cluster"
  value       = oci_redis_redis_cluster.this.id
}

output "cache_endpoint" {
  description = "The primary endpoint for the cache cluster"
  value       = oci_redis_redis_cluster.this.primary_endpoint_ip_address
}

output "cache_fqdn" {
  description = "The FQDN of the cache cluster"
  value       = oci_redis_redis_cluster.this.primary_fqdn
}

output "cache_port" {
  description = "The port for the cache cluster"
  value       = 6379
}
