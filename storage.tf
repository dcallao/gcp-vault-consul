resource "random_id" "environment_name" {
  byte_length = 4
  prefix      = "${var.name_prefix}-"
}

resource "google_storage_bucket" "repo" {
  name          = "${random_id.environment_name.hex}-consul-data"
  project       = var.project
  storage_class = "NEARLINE"
}

resource "google_storage_bucket_iam_member" "iam" {
  bucket = google_storage_bucket.repo.name
  member = "serviceAccount:${google_service_account.vault_kms_service_account.email}"
  role   = "roles/storage.objectCreator"
}