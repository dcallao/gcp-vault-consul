#!/usr/bin/env bash

echo "Starting deployment from AMI: ${image}"
INSTANCE_NAME=`curl http://metadata.google.internal/computeMetadata/v1/instance/name -H "Metadata-Flavor: Google"`
AVAILABILITY_ZONE="$(curl http://metadata.google.internal/computeMetadata/v1/instance/zone -H "Metadata-Flavor: Google" | awk -F'/' '{print $NF}')"
LOCAL_IPV4=$(curl http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip -H "Metadata-Flavor: Google")

cat << EOF > /etc/consul.d/consul.hcl
datacenter          = "${datacenter}"
server              = true
bootstrap_expect    = ${bootstrap_expect}
data_dir            = "/opt/consul/data"
advertise_addr      = "$${LOCAL_IPV4}"
client_addr         = "0.0.0.0"
log_level           = "INFO"
ui                  = true
leave_on_terminate  = true

# GCP cloud join
retry_join          = ["provider=gce project_name=${project} tag_value=${environment_name}-consul"]

performance {
    raft_multiplier = 1
}

acl {
  enabled        = true
  %{ if bootstrap }default_policy = "allow"%{ else }default_policy = "deny"%{ endif }
  enable_token_persistence = true
  tokens {
    master = "${master_token}"%{ if !bootstrap }
    agent  = "${agent_server_token}"%{ endif }
  }
}

encrypt = "${gossip_key}"
EOF

cat << EOF > /etc/consul.d/autopilot.hcl
autopilot {%{ if redundancy_zones }
  redundancy_zone_tag = "az"%{ endif }
  upgrade_version_tag = "consul_cluster_version"
}
EOF
 %{ if redundancy_zones }
cat << EOF > /etc/consul.d/redundancy_zone.hcl
node_meta = {
    az = "$${AVAILABILITY_ZONE}"
}
EOF
%{ endif }

cat << EOF > /etc/consul.d/cluster_version.hcl
node_meta = {
    consul_cluster_version = "${consul_cluster_version}"
}
EOF
%{ if bootstrap }
cat << EOF > /tmp/bootstrap_tokens.sh
#!/bin/bash
export CONSUL_HTTP_TOKEN=${master_token}
echo "Creating Consul ACL policies......"
if ! consul kv get acl_bootstrap 2>/dev/null; then
  consul kv put acl_bootstrap 1
  echo '
  node_prefix "" {
    policy = "write"
  }
  service_prefix "" {
    policy = "read"
  }
  agent_prefix "" {
    policy = "write"
  }' | consul acl policy create -name consul-agent-vault -rules -

  echo '
  node_prefix "" {
    policy = "write"
  }
  service_prefix "" {
    policy = "read"
  }
  service "consul" {
    policy = "write"
  }
  agent_prefix "" {
    policy = "write"
  }' | consul acl policy create -name consul-agent-server -rules -

  echo '
  key_prefix "vault/" {
    policy = "write"
  }
  service "vault" {
    policy = "write"
  }
  session_prefix "" {
    policy = "write"
  }
  node_prefix "" {
    policy = "write"
  }
  agent_prefix "" {
    policy = "write"
  }' | consul acl policy create -name vault -rules -

  echo '
  acl = "write"
  key "consul-snapshot/lock" {
  policy = "write"
  }
  session_prefix "" {
  policy = "write"
  }
  service "consul-snapshot" {
  policy = "write"
  }' | consul acl policy create -name snapshot_agent -rules -

  echo '
  node_prefix "" {
    policy = "read"
  }
  service_prefix "" {
    policy = "read"
  }
  session_prefix "" {
    policy = "read"
  }
  agent_prefix "" {
    policy = "read"
  }
  query_prefix "" {
    policy = "read"
  }
  operator = "read"' |  consul acl policy create -name anonymous -rules -

  consul acl token create -description "consul agent vault token" -policy-name consul-agent-vault -secret "${agent_vault_token}" 1>/dev/null
  consul acl token create -description "consul agent server token" -policy-name consul-agent-server -secret "${agent_server_token}" 1>/dev/null
  consul acl token create -description "vault application token" -policy-name vault -secret "${vault_app_token}" 1>/dev/null
  consul acl token create -description "consul snapshot agent" -policy-name snapshot_agent -secret "${snapshot_token}" 1>/dev/null
  consul acl token update -id anonymous -policy-name anonymous 1>/dev/null
else
  echo "Bootstrap already completed"
fi
EOF

chmod 700 /tmp/bootstrap_tokens.sh

%{ endif }
chown -R consul:consul /etc/consul.d
chmod -R 640 /etc/consul.d/*

systemctl daemon-reload
systemctl enable consul
systemctl start consul

while true; do
    curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -e . && break
    sleep 5
done

until [[ $TOTAL_NEW -ge ${total_nodes} ]]; do
    TOTAL_NEW=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -er 'map(select(.NodeMeta.consul_cluster_version == "${consul_cluster_version}")) | length'`
    sleep 5
    echo "Current New Node Count: $TOTAL_NEW"
done

until [[ $LEADER -eq 1 ]]; do
    let LEADER=0
    echo "Fetching new node ID's"
    NEW_NODE_IDS=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -r 'map(select(.NodeMeta.consul_cluster_version == "${consul_cluster_version}")) | .[].ID'`
    until [[ $VOTERS -eq ${bootstrap_expect} ]]; do
        let VOTERS=0
        for ID in $NEW_NODE_IDS; do
            echo "Checking $ID"
            curl -s http://127.0.0.1:8500/v1/operator/autopilot/health | jq -e ".Servers[] | select(.ID == \"$ID\" and .Voter == true)" && let "VOTERS+=1" && echo "Current Voters: $VOTERS"
            sleep 2
        done
    done
    echo "Checking Old Nodes"
    OLD_NODES=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -er 'map(select(.NodeMeta.consul_cluster_version != "${consul_cluster_version}")) | length'`
    echo "Current Old Node Count: $OLD_NODES"
    until [[ $OLD_NODES -eq 0 ]]; do
        OLD_NODES=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -er 'map(select(.NodeMeta.consul_cluster_version != "${consul_cluster_version}")) | length'`
        OLD_NODE_IDS=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -r 'map(select(.NodeMeta.consul_cluster_version != "${consul_cluster_version}")) | .[].ID'`
        for ID in $OLD_NODE_IDS; do
            echo "Checking Old $ID"
            curl -s http://127.0.0.1:8500/v1/operator/autopilot/health | jq -e ".Servers[] | select(.ID == \"$ID\" and .Voter == false)" && let "OLD_NODES-=1" && echo "Checking Old Nodes for Voters: $OLD_NODES"
            sleep 2
        done
    done
    LEADER_ID=`curl -s http://127.0.0.1:8500/v1/operator/autopilot/health | jq -er ".Servers[] | select(.Leader == true) | .ID"`
    curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -er ".[] | select(.ID == \"$LEADER_ID\" and .NodeMeta.consul_cluster_version == \"${consul_cluster_version}\")" && let "LEADER+=1" && echo "New Leader: $LEADER_ID"
    sleep 2
done

%{ if bootstrap }/tmp/bootstrap_tokens.sh%{ endif }
echo "$INSTANCE_IMAGE determined all nodes to be healthy and ready to go <3"