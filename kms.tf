resource "google_service_account" "vault_kms_service_account" {
  account_id   = "vault-gcpkms"
  display_name = "Vault KMS for auto-unseal"
  project      = var.project
}

resource "google_kms_key_ring" "key_ring" {
  project  = var.project
  name     = "vt-keyring"
  location = var.region
}

# Create a crypto key for the key ring
resource "google_kms_crypto_key" "crypto_key_pri" {
  name            = "vault-key-primary"
  key_ring        = google_kms_key_ring.key_ring.self_link
  rotation_period = "100000s"
}

resource "google_kms_key_ring_iam_binding" "vault_iam_kms_binding" {
  # key_ring_id = "${google_kms_key_ring.key_ring.id}"
  key_ring_id = "${var.project}/${var.region}/${google_kms_key_ring.key_ring.name}"
  role        = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.vault_kms_service_account.email}",
  ]
}

resource "google_project_iam_member" "viewer" {
  project = var.project
  member  = "serviceAccount:${google_service_account.vault_kms_service_account.email}"
  role    = "roles/compute.viewer"
}

data "google_kms_secret" "vault_cert" {
  count      = var.tls_enable ? 1 : 0
  crypto_key = google_kms_crypto_key.crypto_key_pri.self_link
  ciphertext = var.cert_file
}

data "google_kms_secret" "vault_key" {
  count      = var.tls_enable ? 1 : 0
  crypto_key = google_kms_crypto_key.crypto_key_pri.self_link
  ciphertext = var.key_file
}