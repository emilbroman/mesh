terraform {
  backend "gcs" {
    bucket = "emilbroman-terraform-state"
    prefix = "mesh"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">=4.36.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.13.1"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">=2.6.0"
    }
  }
}

provider "google" {
  project = "emilbroman"
}

data "google_client_config" "current" {}

data "terraform_remote_state" "cloud" {
  backend = "gcs"

  config = {
    bucket = "emilbroman-terraform-state"
    prefix = "cloud-infrastructure"
  }
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cloud.outputs.cluster_url
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cloud.outputs.cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cloud.outputs.cluster_url
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cloud.outputs.cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
  }
}

module "postgres" {
  source                 = "./modules/postgres"
  certificate_issuer_ref = module.cert_manager.self_signed_issuer_ref
}

module "ingress_controller" {
  source                 = "./modules/ingress-controller"
  certificate_issuer_ref = module.cert_manager.issuer_ref
  exposed_tcp_services = [
    {
      namespace = module.postgres.namespace
      name      = module.postgres.service_name
      port      = module.postgres.service_port
    }
  ]
}

module "cert_manager" {
  source        = "./modules/cert-manager"
  ingress_class = module.ingress_controller.ingress_class
}

module "logs" {
  source = "./modules/logs"
}

resource "google_dns_record_set" "this" {
  for_each = toset(["", "*."])

  name = "${each.value}${data.terraform_remote_state.cloud.outputs.domain}."
  type = "A"
  ttl  = 60

  managed_zone = data.terraform_remote_state.cloud.outputs.dns_zone_name

  rrdatas = [module.ingress_controller.external_ip]
}
