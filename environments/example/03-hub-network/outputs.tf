# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.

output "networking_outputs" {
  description = "C31 avd-networking-outputs/v1 contract object."
  value       = module.hub_network.networking_outputs
}
