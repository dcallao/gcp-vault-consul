# TF module to standup Vault-Consul cluster

3 Vault nodes, 5 Consul backend

## Deploying
- Build your packer images
- Create `terraform.tfvars` file
```
project                = "your-project"
region                 = "us-central1"
zones                  = ["us-central1-b", "us-central1-c", "us-central1-f"]
network                = "central"
subnet                 = "subnet1"
image_name             = "gcp-vault-1-3-1-consul-1-6-2"
machine_type           = "g1-small"
consul_cluster_version = "0-0-1"
vault_cluster_version  = "0-0-1"
datacenter             = "us-central1"
allowed_inbound_cidrs  = ["0.0.0.0/0"]
bootstrap              = true
cooldown_period        = 60
health_check_delay     = 90
external_lb            = false
tls_enable             = true
key_file               = "CiQA5cgR2Yun/K"
cert_file              = "CiQA5cgR2ZNGI9"
```
- `terraform plan; terraform apply`
- Login to one of the vault nodes and init
```
vault operator init
```
- Change your `bootstrap` flag to `false`.
```
project                = "your-project"
region                 = "us-central1"
zones                  = ["us-central1-b", "us-central1-c", "us-central1-f"]
network                = "central"
subnet                 = "subnet1"
image_name             = "gcp-vault-1-3-1-consul-1-6-2"
machine_type           = "g1-small"
consul_cluster_version = "0-0-5"
vault_cluster_version  = "0-0-1"
datacenter             = "us-central1"
allowed_inbound_cidrs  = ["0.0.0.0/0"]
bootstrap              = false
cooldown_period        = 60
health_check_delay     = 90
external_lb            = false
tls_enable             = true
key_file               = "CiQA5cgR2Yun/K"
cert_file              = "CiQA5cgR2ZNGI9"
```
- `terraform plan; terraform apply`
- TODO: Remove --- Run updater script `./updater.sh`

## Requirement
- A project
- A vault/consul Packer image
- VPC with subnets in your region
- Allow GCP health checks to access your nodes - https://cloud.google.com/load-balancing/docs/health-checks
  `35.191.0.0/16, 130.211.0.0/22, 209.85.152.0/22, 209.85.204.0/22`
- Enable private access for your subnet - https://cloud.google.com/vpc/docs/configure-private-google-access

## API's to enable
- Compute Engine
- KMS

## Resources created and Permissions
- GCS Bucket
- KMS Ring and Crypto Key
- HTTP Health Checks
- Firewall rules - more info down below.
- Service Account - to run instances with required permission. These permissions are:
    - enrypter/decrypter on the key ring
    - object creator on the GCS bucket
    - compute viewer inside the project
- Instance groups and Instance Templates
- Autoscaler policy
- Loadbalancer frontend and backend services
- Forwarding rule for the load balancer
- Target Pool for external load balancer

## Ports Used
Ports used by Consul are well documented here - https://www.consul.io/docs/install/ports.html

The following ports are allowed in the gcp firewall resouce:
```
TCP - "8200", "8500", "8300", "8301", "8302", "8201", "8600"
UDP - "8301", "8302", "8600"
```

## Step by step guide for new project
- Create a new project
- Enable Compute Engine and KMS APIs
- Create a vpc and a subnet
- Enable Private access within the subnet
`gcloud compute networks subnets update subnet1 --region us-central1 --enable-private-ip-google-access --project=hashi-vault-project`
or
`private_ip_google_access = true` if using Terraform to create subnet.
- Add firewall rule to allow ssh ingress from your workstation, or you can use GCP's IAP for TCP forwarding
and add 35.235.240.0/20 ssh access to your subnet in your firewall rule. Documentation is [here](https://cloud.google.com/iap/docs/using-tcp-forwarding).
- Add your ssh key to Metadata if you plan to ssh to the instances for debugging.
- Create a service account, grant owner permission to the project ->
you can also give specific roles to the service account -> #TODO
- Download JSON key for the service account and export the path of the JSON file as GOOGLE_APPLICATION_CREDENTIALS
- Build packer image from `packer` directory. Set your project name, network and subnet at a minimum in `vars.json` file.
- Plan and Apply tf module - set terraform.tfvars file to your needs.

## TLS support
- For testing you can generate a self-signed cert in one line
```
openssl req -subj '/CN=vault.company.com/O=Owner/C=US' -new -newkey rsa:2048 -sha256 -days 365 -nodes -x509 -keyout server.key -out server.crt
```

- Generate cipher with keyring, for cert and private key.
```
cat server.crt | gcloud kms encrypt --project project_name \
    --location us-central1 \
    --keyring vt-keyring \
    --key vault-key-primary \
    --plaintext-file - --ciphertext-file - | base64
```

- Use base64 outputs as inputs to your tf variables, and set tls flag
```
tls_enable             = true
key_file               = "CiQA5cgR2Yu..."
cert_file              = "CiQA..."
```
### Migrating to TLS
If you have a Vault implementation with `tls_enabled` set to `false`, you can easily upgrade
to TLS by setting `tls_enabled` to `true` and adding a new Vault instance template as follows:
```
tls_enabled            = true
vault_cluster_version  = "new-version"
```
Going back to non-TLS is not as easy. You will have to delete the Vault IGM, change `vault_cluster_version` and
`tls_enabled` to `false`.

## Public IP load balancer
- Set tf var `external_lb` to true.
```
external_lb            = true
```
- Currently GCP does not support https_health checks for target pools. We are using http_health check when
creating the `google_compute_target_pool` resource. See comments in [lb.tf](lb.tf) file. Here's also a link to
[Github issue](https://github.com/terraform-providers/terraform-provider-google/issues/18).
