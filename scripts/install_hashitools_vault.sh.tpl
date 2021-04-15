#!/usr/bin/env bash

echo "Starting deployment from image: ${image}"
export availability_zone="$(curl http://metadata.google.internal/computeMetadata/v1/instance/zone -H "Metadata-Flavor: Google" | awk -F'/' '{print $NF}')"
export instance_id=$(curl http://metadata.google.internal/computeMetadata/v1/instance/name -H "Metadata-Flavor: Google")
export LOCAL_IPV4=$(curl http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip -H "Metadata-Flavor: Google")

cat << EOF > /etc/consul.d/consul.hcl
datacenter          = "${datacenter}"
data_dir            = "/opt/consul/data"
advertise_addr      = "$${LOCAL_IPV4}"
client_addr         = "127.0.0.1"
log_level           = "INFO"
ui                  = true

# GCP cloud join
retry_join          = ["provider=gce project_name=${project} tag_value=${environment_name}-consul"]

acl {
  enable_token_persistence = true
  tokens {
    agent = "${agent_vault_token}"
  }
}

encrypt = "${gossip_key}"
EOF

cat << EOF > /etc/consul-snapshot.d/consul-snapshot.json
{
	"snapshot_agent": {
		"http_addr": "127.0.0.1:8500",
		"token": "${snapshot_token}",
		"datacenter": "${datacenter}",
		"snapshot": {
			"interval": "30m",
			"retain": 336,
			"deregister_after": "8h"
		},
	    "google_storage": {
            "bucket": "${bucket}"
        }
	}
}
EOF
chown -R consul:consul /etc/consul-snapshot.d/*
chmod -R 640 /etc/consul-snapshot.d/*
chown -R consul:consul /etc/consul.d/*
chmod -R 640 /etc/consul.d/*

systemctl daemon-reload
systemctl enable consul
systemctl start consul

while true; do
    curl http://127.0.0.1:8500/v1/catalog/service/consul && break
    sleep 5
done

systemctl enable consul-snapshot
systemctl start consul-snapshot

%{ if tls_enable }
echo ${server_cert} | base64 --decode > /tmp/vault.crt.enc
echo ${server_key} | base64 --decode > /tmp/vault.key.enc

gcloud kms decrypt --ciphertext-file=/tmp/vault.crt.enc \
  --project ${project} --location ${region} \
  --keyring ${key_ring} --key ${crypto_key} \
  --plaintext-file=/etc/vault.d/vault.crt

gcloud kms decrypt --ciphertext-file=/tmp/vault.key.enc \
  --project ${project} --location ${region} \
  --keyring ${key_ring} --key ${crypto_key} \
  --plaintext-file=/etc/vault.d/vault.key
%{ endif }

cat << EOF > /etc/vault.d/vault.hcl
disable_performance_standby = true
ui = true
storage "consul" {
  address          = "127.0.0.1:8500"
  path             = "vault"%{ if strong_consistency }
  consistency_mode = "strong"%{ endif }
  token            = "${vault_app_token}"
}
listener "tcp" {
  address     = "0.0.0.0:8200"
  %{ if tls_enable }
  tls_disable = false
  tls_cert_file = "/etc/vault.d/vault.crt"
  tls_key_file = "/etc/vault.d/vault.key"
  %{ else }
  tls_disable = true
  %{ endif }
}
seal "gcpckms" {
    project     = "${project}"
    region      = "${region}"
    key_ring    = "${key_ring}"
    crypto_key  = "${crypto_key}"
}
EOF

chown -R vault:vault /etc/vault.d/*
chmod -R 640 /etc/vault.d/*

systemctl enable vault
systemctl start vault