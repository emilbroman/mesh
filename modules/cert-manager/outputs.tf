output "certificate_secret_name" {
  value = "${kubernetes_namespace_v1.this.metadata[0].name}/${local.certificate_secret_name}"
}
