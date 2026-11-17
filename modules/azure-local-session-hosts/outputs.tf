output "host_names" {
  description = "Azure Local session host names."
  value       = sort(keys(local.hosts))
}

output "vm_instance_ids" {
  description = "Azure Stack HCI virtual machine instance resource IDs."
  value       = [for k in sort(keys(local.hosts)) : azapi_resource.vm_instance[k].id]
}

output "hybrid_compute_machine_ids" {
  description = "Azure Arc HybridCompute machine resource IDs."
  value       = [for k in sort(keys(local.hosts)) : azapi_resource.hybrid_machine[k].id]
}
