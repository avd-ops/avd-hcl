/*
  network.bicep — VNet, subnet, NSG, and the outbound egress path.

  Two things about this module are worth understanding, because both look like
  security mistakes until you know why they aren't:

  1. There are NO inbound NSG rules and NO public IPs on session hosts.
     That isn't a shortcut for the sake of a simple lab. AVD uses a
     reverse-connect transport: the session host opens an *outbound* HTTPS
     connection to the AVD service, and user sessions ride back down it.
     Nothing ever connects inbound to a session host. There is no RDP port to
     expose, and no bastion required to make it work.

  2. There IS a NAT gateway, which owns the only public IP in this template.
     As of the API versions released after 2026-03-31, new virtual networks
     default to *private* subnets: `defaultOutboundAccess` is false, and Azure
     no longer hands VMs an implicit outbound IP. Session hosts still need
     egress on 443 to reach the AVD control plane, Entra ID, and Azure Files —
     without an explicit egress path the AVD agent can never register and the
     host pool comes up empty. The NAT gateway is that path. It gives outbound
     only; it accepts nothing inbound.
*/

@description('Azure region for all networking resources.')
param location string = resourceGroup().location

@description('Name of the virtual network.')
param vnetName string

@description('Address space for the virtual network, in CIDR notation.')
param vnetCidr string

@description('Name of the session host subnet.')
param subnetName string = 'snet-avdlab-hosts'

@description('Address range for the session host subnet. Must sit inside vnetCidr.')
param subnetCidr string

@description('Name of the network security group applied to the session host subnet.')
param nsgName string = 'nsg-avdlab-hosts'

@description('Name of the NAT gateway providing outbound internet access.')
param natGatewayName string = 'natgw-avdlab'

@description('Name of the public IP address attached to the NAT gateway. This is the only public IP in the lab, and it is outbound-only.')
param publicIpName string = 'pip-avdlab-natgw'

@description('Idle timeout in minutes for outbound NAT flows.')
@minValue(4)
@maxValue(120)
param natIdleTimeoutInMinutes int = 4

@description('Tags applied to every resource in this module.')
param tags object = {}

// ---------------------------------------------------------------------------
// Network security group
//
// Deliberately minimal. Azure's default rules already deny all inbound traffic
// that doesn't originate from within the VNet or the load balancer, so the
// explicit deny below is defense in depth and, frankly, a talking point: it
// makes "there is no way in" legible to anyone reading the template.
//
// We do NOT lock down outbound to an allowlist of AVD service tags here. Doing
// so is a legitimate hardening step, but it's a Hard Mode concern (Section 13):
// the required tag set shifts, and a stale allowlist fails in a way that looks
// exactly like a broken deployment on stage.
// ---------------------------------------------------------------------------
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Deny-Inbound-RDP'
        properties: {
          description: 'AVD reverse-connect needs no inbound RDP. Nothing should ever match this rule; if something does, investigate.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4000
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outbound egress: public IP -> NAT gateway -> subnet
// ---------------------------------------------------------------------------
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard' // NAT gateway requires a Standard SKU public IP.
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: natGatewayName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: natIdleTimeoutInMinutes
    publicIpAddresses: [
      {
        id: publicIp.id
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Virtual network + subnet
//
// The subnet is declared inline rather than as a child resource so the whole
// network shape is readable in one place. `defaultOutboundAccess: false` is set
// explicitly rather than left to the API-version default: relying on the
// default means this template's behavior silently changes depending on which
// apiVersion string it carries, which is exactly the kind of drift the March
// 2026 retirement caused in the first place.
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetCidr
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetCidr
          defaultOutboundAccess: false
          natGateway: {
            id: natGateway.id
          }
          networkSecurityGroup: {
            id: nsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

@description('Resource ID of the virtual network.')
output vnetId string = vnet.id

@description('Resource ID of the session host subnet. Consumed by sessionhosts.bicep.')
output subnetId string = vnet.properties.subnets[0].id

@description('Name of the session host subnet.')
output subnetName string = subnetName

@description('Resource ID of the network security group.')
output nsgId string = nsg.id

@description('Resource ID of the NAT gateway providing outbound egress.')
output natGatewayId string = natGateway.id

@description('The deterministic outbound IP address for all session host egress. Useful when an upstream firewall or SaaS allowlist needs to know where this lab calls from.')
output outboundIpAddress string = publicIp.properties.ipAddress
