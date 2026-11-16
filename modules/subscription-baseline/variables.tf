variable "resource_providers" {
  type        = list(string)
  description = "Azure Resource Provider namespaces to register on the current provider subscription."
  default = [
    "Microsoft.DesktopVirtualization",
    "Microsoft.Compute",
    "Microsoft.Network",
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.OperationalInsights",
    "Microsoft.ManagedServices",
    "Microsoft.Quota",
  ]
}
