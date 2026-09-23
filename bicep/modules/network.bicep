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

@description('''
Short name identifying this lab. Every resource name in every module derives
from it, which is what lets several labs coexist in one subscription and what
lets the management commands find a lab knowing nothing but its name.

3-9 characters, lowercase letters and digits.

The 9-character ceiling is arithmetic, not taste. Windows computer names are
limited to 15 characters, session hosts are named vm-<labName>-<n>, and
sessionHostCount allows a two-digit index:

    'vm-' (3) + labName (9) + '-' (1) + '49' (2) = 15

A longer lab name produces a computer name ARM rejects, and it rejects it at
the session host phase -- after the network, storage and host pool are already
built.
''')
@minLength(3)
@maxLength(9)
param labName string = 'lab'

@description('Address space for the virtual network, in CIDR notation.')
param vnetCidr string

@description('Address range for the session host subnet. Must sit inside vnetCidr.')
param subnetCidr string

@description('Idle timeout in minutes for outbound NAT flows.')
@minValue(4)
@maxValue(120)
param natIdleTimeoutInMinutes int = 4

@description('Tags applied to every resource in this module.')
param tags object = {}

// ---------------------------------------------------------------------------
// Derived names. Resource names are not parameters: they are a function of the
// lab name, which is what makes a lab addressable by name alone from the
// management layer. Overridable names would mean two sources of truth about
// what a lab's resources are called.
// ---------------------------------------------------------------------------
var vnetName = 'vnet-avdlab-${labName}'
var nsgName = 'nsg-avdlab-${labName}'
var natGatewayName = 'natgw-avdlab-${labName}'
var publicIpName = 'pip-avdlab-${labName}'

// The subnet is a child of the VNet, so its name is already scoped and cannot
// collide with another lab's. It stays constant deliberately.
var subnetName = 'snet-avdlab-hosts'

// Identity tag, merged into whatever the caller passed. This is what finds
// stray resources that outlived their resource group.
var labTags = union(tags, { 'avdlab-name': labName })

// ---------------------------------------------------------------------------
// Network security group
//
// Deliberately minimal. Azure's default rules already deny all inbound traffic
// that doesn't originate from within the VNet or the load balancer, so the
// explicit deny below is defense in depth and, frankly, a talking point: it
// makes "there is no way in" legible to anyone reading the template.
//
// We do NOT lock down outbound to an allowlist of AVD service tags here. Doing
// so is a legitimate hardening step, but it belongs to the harder tier:
// the required tag set shifts, and a stale allowlist fails in a way that looks
// exactly like a broken deployment on stage.
// ---------------------------------------------------------------------------
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: labTags
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
  tags: labTags
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
  tags: labTags
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
  tags: labTags
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
