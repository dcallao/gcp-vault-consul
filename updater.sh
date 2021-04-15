#!/usr/bin/env bash
set -e
command -v gcloud >/dev/null 2>&1 || { echo >&2 "gcloud not found. Install from https://cloud.google.com/sdk/install." ; exit 1; }
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 project-name region consul-instance-group-name"
    exit 1
fi
TIMEOUT=60
MAX_NODE=10
MIN_NODE=5
PROJECT=$1
REGION=$2
IGM=$3

for x in $(seq $MAX_NODE $MIN_NODE); do
    gcloud compute instance-groups managed set-autoscaling ${IGM} --project ${PROJECT} --region=${REGION} \
    --max-num-replicas ${MAX_NODE} --min-num-replicas ${x}
    sleep ${TIMEOUT}
done