resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = "ingress-controller"
  }
}

resource "random_id" "ingress_class" {
  prefix      = "ingress-class-"
  byte_length = 4
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
      issuerRef  = var.certificate_issuer_ref
      dnsNames   = ["*.emilbroman.me", "emilbroman.me"]
    }
  }
}

resource "helm_release" "this" {
  name      = "nginx-ingress-controller"
  namespace = kubernetes_namespace_v1.this.metadata[0].name

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"

  values = [yamlencode({
    controller = {
      ingressClassResource = {
        name = random_id.ingress_class.hex
      }
      extraArgs = {
        "default-ssl-certificate" = local.certificate_secret_name
      }
      config = {
        "force-ssl-redirect" = true
      }
    }
    tcp = {
      for service in var.exposed_tcp_services :
      service.port => "${service.namespace}/${service.name}:${service.port}"
    }
  })]
}

data "kubernetes_service_v1" "this" {
  depends_on = [helm_release.this]

  metadata {
    name      = "nginx-ingress-controller-ingress-nginx-controller"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
}
