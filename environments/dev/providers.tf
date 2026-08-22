terraform {
  # Remote state configuration via Terraform Cloud or private Terraform Enterprise (TFE)
  cloud {
    hostname     = "tfe.enterprise.local" # Your private Terraform Enterprise hostname (Subject to change)
    organization = "Enterprise-NetOps"
    workspaces {
      name = "sdwan-netops-dev"
    }
  }
}

provider "sdwan" {
  # SD-WAN Manager credentials are parameterized via environment variables on the runner:
  # - SDWAN_URL (https://<vmanage-ip-or-fqdn>)
  # - SDWAN_USERNAME
  # - SDWAN_PASSWORD
  # insecure = true allows testing against self-signed certificates in lab/CML environments.
  insecure = true
}

