resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = "postgres"
  }
}

locals {
  labels = {
    "app.kubernetes.io/name"      = "postgres"
    "app.kubernetes.io/component" = "database"
  }
}

resource "random_password" "this" {
  length  = 32
  special = true
}

locals {
  root_user = "postgres"
}

resource "kubernetes_secret_v1" "root_auth" {
  metadata {
    name      = "postgres-root"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    POSTGRES_USER     = local.root_user
    POSTGRES_PASSWORD = random_password.this.result
  }
}

locals {
  certificate_secret_name = "postgres-tls"
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
      issuerRef  = var.certificate_issuer_ref
      commonName = local.certificate_secret_name
      isCA       = true
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
    }
  }
}

resource "kubernetes_stateful_set_v1" "this" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = 1

    service_name = "postgres"

    selector {
      match_labels = local.labels
    }

    volume_claim_template {
      metadata {
        name      = "postgres-data"
        namespace = kubernetes_namespace_v1.this.metadata[0].name
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "standard-rwo"
        resources {
          requests = {
            storage = "20Gi"
          }
        }
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:14.5-alpine"

          command = [
            "docker-entrypoint.sh",
            "postgres",
            "-c", "ssl=on",
            "-c", "ssl_cert_file=/etc/ssl/tls.crt",
            "-c", "ssl_key_file=/etc/ssl/tls.key",
          ]

          port {
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.root_auth.metadata[0].name
            }
          }

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql"
          }

          volume_mount {
            name       = "tls"
            mount_path = "/etc/ssl"
            read_only  = true
          }
        }

        security_context {
          run_as_user = 70
          fs_group    = 70
        }

        volume {
          name = "tls"
          secret {
            secret_name  = local.certificate_secret_name
            default_mode = "0600"
          }
        }
      }
    }
  }
}

locals {
  external_port = 5432
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    selector = local.labels

    port {
      port        = local.external_port
      target_port = 5432
    }
  }
}
