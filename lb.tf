resource "google_compute_health_check" "consul_hc" {
  project = var.project

  name                = "consul-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 5
  unhealthy_threshold = 10 # 100 seconds

  http_health_check {
    request_path = var.consul_health_check_path
    port         = "8500"
  }
}

resource "google_compute_health_check" "vault_hc" {
  #used for internal backend
  project             = var.project
  name                = "vault-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 100 seconds
  dynamic "https_health_check" {
    for_each = var.tls_enable ? ["enabled"] : []
    content {
      request_path = var.vault_elb_health_check
      port         = 8200
    }
  }
  dynamic "http_health_check" {
    for_each = var.tls_enable ? [] : ["enabled"]
    content {
      request_path = var.vault_elb_health_check
      port         = "8200"
    }
  }
}

resource "google_compute_forwarding_rule" "internal_fr" {
  count                 = var.external_lb ? 0 : 1
  project               = var.project
  region                = var.region
  network               = var.network
  subnetwork            = "projects/${var.project}/regions/${var.region}/subnetworks/${var.subnet}"
  load_balancing_scheme = "INTERNAL"
  name                  = "vault-lb-forwarding-rule"
  backend_service       = google_compute_region_backend_service.vault_be.self_link
  ports                 = [8200]
}

resource "google_compute_region_backend_service" "vault_be" {
  project               = var.project
  region                = var.region
  load_balancing_scheme = "INTERNAL"

  backend {
    group          = google_compute_region_instance_group_manager.vault_igm.instance_group
    balancing_mode = "CONNECTION"
  }
  name          = "vault-backend-service"
  protocol      = "TCP"
  timeout_sec   = 10
  health_checks = [google_compute_health_check.vault_hc.self_link]
}

resource "google_compute_https_health_check" "vault_https_hc" {
  count               = var.tls_enable ? 1 : 0
  project             = var.project
  name                = "vault-https-hc"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 100 seconds
  port                = 8200
  request_path        = var.vault_elb_health_check
}

resource "google_compute_http_health_check" "vault_http_hc" {
  //change this to ? 0 : 1
  count               = var.tls_enable ? 1 : 1
  project             = var.project
  name                = "vault-http-hc"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 100 seconds
  port                = 8200
  request_path        = var.vault_elb_health_check
}

resource "google_compute_forwarding_rule" "external_fr" {
  count                 = var.external_lb ? 1 : 0
  project               = var.project
  name                  = "vault-ext-lb"
  target                = google_compute_target_pool.vault_tp.self_link
  load_balancing_scheme = "EXTERNAL"
  port_range            = 8200
  region                = var.region
  ip_address            = var.ext_ip_address
  ip_protocol           = "TCP"
}

resource "google_compute_target_pool" "vault_tp" {
  project          = var.project
  name             = "vault-external-target-pool"
  region           = var.region
  session_affinity = var.session_affinity
  //and change this to var.tls_enable ? https_check : http_check
  //https://github.com/terraform-providers/terraform-provider-google/issues/18
  health_checks = var.tls_enable ? [google_compute_http_health_check.vault_http_hc.0.self_link] : [google_compute_http_health_check.vault_http_hc.0.self_link]
}