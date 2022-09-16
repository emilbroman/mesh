resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = "ingress-controller"
  }
}

resource "random_id" "ingress_class" {
  prefix      = "ingress-class-"
  byte_length = 4
}

resource "helm_release" "this" {
  name      = "nginx-ingress-controller"
  namespace = kubernetes_namespace_v1.this.metadata[0].name

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"

  set {
    name  = "controller.ingressClassResource.name"
    value = random_id.ingress_class.hex
  }

  set {
    name  = "controller.extraArgs.default-ssl-certificate"
    value = var.certificate_secret_name
  }

  set {
    name  = "controller.config.force-ssl-redirect"
    value = "true"
  }
}

data "kubernetes_service_v1" "this" {
  depends_on = [helm_release.this]

  metadata {
    name      = "nginx-ingress-controller-ingress-nginx-controller"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
}
