variable "compartment_ocid" {
  description = "The OCID of the compartment"
  type        = string
}

variable "label_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "subnet_ocid" {
  description = "The OCID of the subnet for the cache cluster"
  type        = string
}

variable "node_count" {
  description = "Number of nodes in the cache cluster"
  type        = number
  default     = 1
}

variable "node_memory_in_gbs" {
  description = "Memory per node in GB"
  type        = number
  default     = 2
}

variable "software_version" {
  description = "Redis software version"
  type        = string
  default     = "REDIS_7_0"
}

variable "nsg_ids" {
  description = "List of NSG OCIDs to associate with the cache"
  type        = list(string)
  default     = []
}
