output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "service_name" {
  value = kubernetes_service_v1.this.metadata[0].name
}

output "service_port" {
  value = local.external_port
}

output "certificate_secret_name" {
  value = local.certificate_secret_name
}

output "root_user" {
  value = {
    username = local.root_user
    password = random_password.this.result
  }
}
