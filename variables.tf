variable "image_name" {
  default = ""
}

variable "env" {
  default = "dev"
}

variable "ssh_key" {
  default = ""
}

variable "network" {
  default = ""
}

variable "subnet" {}

variable "region" {
}

variable "project" {
}

variable "cooldown_period" {
  default = "480"
}

variable "health_check_delay" {
  default = "300"
}

variable "availability_zones" {
  default     = "us-central1-a,us-central1-b,us-central1-c,us-central1-f"
  description = "Availability zones for launching the instances"
}

variable "zones" {
  type    = list(string)
  default = []
}

variable "gcp_health_check_cidr" {
  type    = list(string)
  default = ["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"]
}

variable "bootstrap" {
  type        = bool
  default     = true
  description = "Initial Bootstrap configurations"
}

variable "machine_type" {
  default = "g1-small"
}

variable "disaster_recovery" {
  type        = bool
  default     = false
  description = "Enable DR Health Checks on ELB"
}

variable "redundancy_zones" {
  type        = bool
  default     = false
  description = "Leverage Redundancy Zones within Consul for additional non-voting nodes."
}


variable "session_affinity" {
  default     = "NONE"
  description = "How to distribute load. Options are NONE, CLIENT_IP and CLIENT_IP_PROTO"
}
variable "cert_file" {
  default = ""
}

variable "key_file" {
  default = ""
}

variable "tls_enable" {
  type    = bool
  default = false
}

variable "external_lb" {
  type        = bool
  default     = false
  description = "Boolean whether to create an external load balancer for vault or not"
}

variable "ext_ip_address" {
  default     = null
  description = "IP address of the external load balancer for Vault, if empty one will be assigned. Default is null."
}

variable "name_prefix" {
  default     = "hashicorp"
  description = "prefix used in resource names"
}

variable "consul_health_check_path" {
  default = "/v1/operator/autopilot/health"
}

variable "vault_elb_health_check" {
  default     = "/v1/sys/health?activecode=200&standbycode=200&sealedcode=200&uninitcode=200"
  description = "Health check for Vault servers"
}

variable "vault_elb_health_check_active" {
  default     = "/v1/sys/health?standbyok=true"
  description = "Health check for Vault servers"
}

variable "vault_elb_health_check_dr" {
  default     = "/v1/sys/health?standbyok=true&drsecondarycode=200"
  description = "Health check for Vault servers"
}

variable "elb_internal" {
  type        = bool
  default     = true
  description = "make LB internal or external"
}

variable "public_ip" {
  type        = bool
  default     = false
  description = "should ec2 instance have public ip?"
}

variable "key_name" {
  default     = "default"
  description = "SSH key name for Vault and Consul instances"
}

variable "vault_nodes" {
  default     = "3"
  description = "number of Vault instances"
}

variable "consul_nodes" {
  default     = "5"
  description = "number of Consul instances"
}

variable "datacenter" {
}

variable "consul_cluster_version" {
  default     = "0-0-1"
  description = "Custom Version Tag for Upgrade Migrations"
}
variable "vault_cluster_version" {
  default     = "0-0-1"
  description = "Custom Version Tag for Upgrade Migrations"
}

variable "allowed_inbound_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks to permit inbound Vault access from"
  default     = []
}

variable "strong_consistency" {
  type        = bool
  description = "Use strong consistency with consul storage backend to avoid vault read requests failing during cluster blue/green AutoPilot upgrade."
  default     = true
}