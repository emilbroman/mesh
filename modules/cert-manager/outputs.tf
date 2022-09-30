output "issuer_ref" {
  value = {
    group = "cert-manager.io"
    kind  = "ClusterIssuer"
    name  = kubernetes_manifest.issuer.manifest.metadata.name
  }
}

output "self_signed_issuer_ref" {
  value = {
    group = "cert-manager.io"
    kind  = "ClusterIssuer"
    name  = kubernetes_manifest.self_signed_issuer.manifest.metadata.name
  }
}
