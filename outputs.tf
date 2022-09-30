output "ingress_class" {
  value = module.ingress_controller.ingress_class
}

output "external_ip" {
  value = module.ingress_controller.external_ip
}

output "postgres_auth" {
  sensitive = true
  value = {
    external_host        = module.ingress_controller.external_ip
    cluster_host         = "${module.postgres.service_name}.${module.postgres.namespace}"
    port                 = module.postgres.service_port
    database             = module.postgres.root_user.username
    username             = module.postgres.root_user.username
    password             = module.postgres.root_user.password
    tls_secret_namespace = module.postgres.namespace
    tls_secret_name      = module.postgres.certificate_secret_name
  }
}

output "certificate_issuer_ref" {
  value = module.cert_manager.issuer_ref
}

output "self_signed_certificate_issuer_ref" {
  value = module.cert_manager.self_signed_issuer_ref
}
