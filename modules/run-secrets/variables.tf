variable "host_pool_id" {
  description = "Host pool to read the registration token from (modules/control-plane's registration_host_pool_id)."
  type        = string
}

variable "read_registration_token" {
  description = "Read the token. False when there are no session hosts to register."
  type        = bool
  default     = true
}
