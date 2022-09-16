resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "this" {
  name      = "cert-manager"
  namespace = kubernetes_namespace_v1.this.metadata[0].name

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

data "google_client_config" "current" {}

resource "google_service_account" "this" {
  account_id   = "letsencrypt-solver"
  display_name = "Let's Encrypt Solver"
}

resource "google_project_iam_member" "this" {
  project = data.google_client_config.current.project
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_service_account_key" "this" {
  service_account_id = google_service_account.this.name
}

resource "kubernetes_secret_v1" "solver_auth" {
  metadata {
    name      = "solver-auth"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    "key.json" = base64decode(google_service_account_key.this.private_key)
  }
}

resource "kubernetes_manifest" "issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "letsencrypt-production"
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "letsencrypt@emilbroman.me"
        privateKeySecretRef = {
          name = "private-key"
        }
        solvers = [
          {
            dns01 = {
              cloudDNS = {
                project = data.google_client_config.current.project
                serviceAccountSecretRef = {
                  name = kubernetes_secret_v1.solver_auth.metadata[0].name
                  key  = "key.json"
                }
              }
            }
          }
        ]
      }
    }
  }
}

locals {
  certificate_secret_name = "emilbroman-me-tls"
}

resource "kubernetes_manifest" "cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "certificate"
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      secretName = local.certificate_secret_name
      issuerRef = {
        name = kubernetes_manifest.issuer.manifest.metadata.name
      }
      dnsNames = ["*.emilbroman.me", "emilbroman.me"]
    }
  }
}
