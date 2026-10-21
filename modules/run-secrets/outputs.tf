output "local_admin_password" {
  description = "Break-glass password for the hosts this run creates."
  value       = ephemeral.random_password.local_admin.result
  sensitive   = true
  ephemeral   = true
}

output "registration_token" {
  description = "The host pool's current registration token."
  value       = try(ephemeral.azapi_resource_action.registration_token[0].output.token, null)
  sensitive   = true
  ephemeral   = true
}
