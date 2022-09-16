output "external_ip" {
  value = data.kubernetes_service_v1.this.status[0].load_balancer[0].ingress[0].ip
}

output "ingress_class" {
  value = random_id.ingress_class.hex
}
