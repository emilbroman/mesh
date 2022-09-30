variable "certificate_issuer_ref" {
  type = object({
    name  = string
    kind  = string
    group = string
  })
}

variable "exposed_tcp_services" {
  type = list(object({
    namespace = string
    name      = string
    port      = number
  }))
  default = []
}
