
data "google_compute_image" "consul_image" {
  project = var.project
  name    = var.image_name
}

locals {
  image_id = var.image_name == "" ? data.google_compute_image.consul_image.name : var.image_name
}

data "template_file" "install_hashitools_consul" {
  template = file("${path.module}/scripts/install_hashitools_consul.sh.tpl")

  vars = {
    project                = var.project
    image                  = local.image_id
    environment_name       = random_id.environment_name.hex
    datacenter             = var.datacenter
    bootstrap_expect       = var.redundancy_zones ? length(split(",", var.availability_zones)) : var.consul_nodes
    total_nodes            = var.consul_nodes
    gossip_key             = random_id.consul_gossip_encryption_key.b64_std
    master_token           = random_uuid.consul_master_token.result
    agent_vault_token      = random_uuid.consul_agent_vault_token.result
    agent_server_token     = random_uuid.consul_agent_server_token.result
    vault_app_token        = random_uuid.consul_vault_app_token.result
    snapshot_token         = random_uuid.consul_snapshot_token.result
    consul_cluster_version = var.consul_cluster_version
    asg_name               = "${random_id.environment_name.hex}-consul-${var.consul_cluster_version}"
    redundancy_zones       = var.redundancy_zones
    bootstrap              = var.bootstrap
  }
}

data "template_file" "install_hashitools_vault" {
  template = file("${path.module}/scripts/install_hashitools_vault.sh.tpl")

  vars = {
    project            = var.project
    region             = var.region
    key_ring           = google_kms_key_ring.key_ring.name
    crypto_key         = google_kms_crypto_key.crypto_key_pri.name
    image              = local.image_id
    environment_name   = random_id.environment_name.hex
    datacenter         = var.datacenter
    bucket             = google_storage_bucket.repo.name
    gossip_key         = random_id.consul_gossip_encryption_key.b64_std
    agent_vault_token  = random_uuid.consul_agent_vault_token.result
    vault_app_token    = random_uuid.consul_vault_app_token.result
    snapshot_token     = random_uuid.consul_snapshot_token.result
    strong_consistency = var.strong_consistency
    tls_enable         = var.tls_enable
    server_key         = var.tls_enable ? data.google_kms_secret.vault_key.0.ciphertext : ""
    server_cert        = var.tls_enable ? data.google_kms_secret.vault_cert.0.ciphertext : ""
  }
}

resource "google_compute_region_instance_group_manager" "vault_igm" {
  project = var.project
  region  = var.region
  name    = "vault-igm"

  base_instance_name        = "vault"
  distribution_policy_zones = var.zones

  target_pools = [google_compute_target_pool.vault_tp.self_link]

  version {
    instance_template = google_compute_instance_template.vault_it.self_link
    name              = "${random_id.environment_name.hex}-vault-${var.vault_cluster_version}"
  }

  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = var.vault_nodes //must be 0 or equal to the number of zones
    max_unavailable_fixed        = 0               //must be 0 or equal to the number of zones
    min_ready_sec                = var.health_check_delay
  }
  dynamic "auto_healing_policies" {
    for_each = var.tls_enable ? [google_compute_https_health_check.vault_https_hc.0.self_link] : [google_compute_http_health_check.vault_http_hc.0.self_link]
    content {
      health_check      = auto_healing_policies.value
      initial_delay_sec = var.health_check_delay
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "google_compute_instance_template" "vault_it" {
  project = var.project

  name        = "vault-template-${var.vault_cluster_version}"
  description = "This template is used to create vault server instances."

  tags = ["allow-consul-vault", "${random_id.environment_name.hex}-consul"]

  labels = {
    environment = var.env
  }

  instance_description = "description assigned to instances"
  machine_type         = var.machine_type
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  disk {
    source_image = data.google_compute_image.consul_image.name
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = "projects/${var.project}/regions/${var.region}/subnetworks/${var.subnet}"
  }

  metadata_startup_script = data.template_file.install_hashitools_vault.rendered

  service_account {
    email  = google_service_account.vault_kms_service_account.email
    scopes = ["cloud-platform", "compute-rw", "userinfo-email", "storage-ro"]
  }
}

resource "google_compute_region_instance_group_manager" "consul_igm" {
  project = var.project
  region  = var.region
  name    = "consul-igm"

  base_instance_name        = "consul"
  distribution_policy_zones = var.zones

  version {
    instance_template = google_compute_instance_template.consul_it.self_link
    name              = "${random_id.environment_name.hex}-consul-${var.consul_cluster_version}"
  }

  named_port {
    name = "custom"
    port = 8500
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.consul_hc.self_link
    initial_delay_sec = var.health_check_delay
  }
  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = var.consul_nodes //must be 0 or equal to the number of zones
    max_unavailable_fixed        = 0                //must be 0 or equal to the number of zones
    min_ready_sec                = var.health_check_delay
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_template" "consul_it" {
  project = var.project

  name        = "consul-template-${var.consul_cluster_version}"
  description = "This template is used to create consul server instances."

  tags = ["allow-consul-vault", "${random_id.environment_name.hex}-consul"]
  labels = {
    environment = var.env
  }

  instance_description = "Consul node instance version ${var.consul_cluster_version}"
  machine_type         = var.machine_type
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  // Create a new boot disk from an image
  disk {
    source_image = data.google_compute_image.consul_image.name
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = "projects/${var.project}/regions/${var.region}/subnetworks/${var.subnet}"
  }

  metadata_startup_script = data.template_file.install_hashitools_consul.rendered

  service_account {
    email  = google_service_account.vault_kms_service_account.email
    scopes = ["cloud-platform", "compute-rw", "userinfo-email", "storage-ro"]
  }
}

resource "google_compute_region_autoscaler" "vault_autoscaler" {
  //GCP doesnt like dots in names
  name    = "${random_id.environment_name.hex}-vault-${var.vault_cluster_version}"
  project = var.project
  region  = var.region
  target  = google_compute_region_instance_group_manager.vault_igm.self_link

  autoscaling_policy {
    max_replicas    = var.vault_nodes * 2
    min_replicas    = var.vault_nodes
    cooldown_period = var.cooldown_period
  }
}

resource "google_compute_region_autoscaler" "consul_autoscaler" {
  //GCP doesnt like dots in names
  name    = "${random_id.environment_name.hex}-consul-${var.consul_cluster_version}"
  project = var.project
  region  = var.region

  target = google_compute_region_instance_group_manager.consul_igm.self_link

  autoscaling_policy {
    max_replicas    = var.consul_nodes * 2
    min_replicas    = var.consul_nodes
    cooldown_period = var.cooldown_period
  }
}

resource "google_compute_firewall" "allow_consul_vault" {
  name    = "allow-consul-vault"
  network = var.network
  project = var.project

  allow {
    protocol = "tcp"
    ports    = ["8200", "8500", "8300", "8301", "8302", "8201", "8600"]
  }
  allow {
    protocol = "udp"
    ports    = ["8301", "8302", "8600"]
  }
  source_ranges = var.allowed_inbound_cidrs
}

resource "google_compute_firewall" "allow_vault_health_checks" {
  name    = "allow-vault-consul-health-check"
  network = var.network
  project = var.project

  allow {
    protocol = "tcp"
    ports    = ["8200", "8500"]
  }
  source_ranges = var.gcp_health_check_cidr
}