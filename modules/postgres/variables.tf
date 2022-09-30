variable "certificate_issuer_ref" {
  type = object({
    name  = string
    kind  = string
    group = string
  })
}
