/*
  hostpool.bicep — the pooled AVD host pool, and the registration token that
  session hosts use to join it.

  TWO THINGS HERE ARE LESS OBVIOUS THAN THEY LOOK.

  1. The registration token is not a readable property.
     `registrationInfo.token` is write-only: a GET on the host pool never returns
     it. The only way to obtain it is the listRegistrationTokens() action, which
     is why this module calls that rather than reading hostPool.properties.
     The token is a credential -- it authorizes a machine to join the pool -- so
     the output is marked @secure(). It still lands in the deployment history at
     the ARM layer, which is a reason to keep expiry short, not a reason to relax.

  2. `registrationTokenOperation: 'Update'` mints a NEW token on every deployment.
     That is deliberate. Tokens expire (max 30 days, and we default to hours), and
     a re-run that reuses an expired token produces the failure mode Section 8
     warns about: everything deploys successfully and the pool sits empty because
     no host could register. Idempotent in the sense that matters -- converging on
     "a valid token exists" -- rather than "the same bytes come back."
*/

@description('Name of the host pool. 3-64 chars.')
@minLength(3)
@maxLength(64)
param hostPoolName string

@description('Azure region.')
param location string = resourceGroup().location

@description('Name shown to users in the client.')
param friendlyName string = 'AVD Lab Kit — Pooled'

@description('Description of the host pool.')
param hostPoolDescription string = 'Deployed by AVD Lab Kit (Easy Mode). Safe to delete with the resource group.'

@description('''
Pooled is the Easy Mode choice: multiple users share the session hosts, which is
what makes a 2-3 host lab meaningfully demonstrate load balancing at all.
''')
@allowed([
  'Pooled'
  'Personal'
])
param hostPoolType string = 'Pooled'

@description('''
BreadthFirst spreads new sessions across all available hosts — the right default
for a demo, because it visibly puts users on different hosts. DepthFirst fills one
host before moving to the next, which is cheaper in production but makes a
three-host pool look like a one-host pool on stage.
''')
@allowed([
  'BreadthFirst'
  'DepthFirst'
])
param loadBalancerType string = 'BreadthFirst'

@description('Maximum concurrent sessions per session host.')
@minValue(1)
@maxValue(999999)
param maxSessionLimit int = 4

@description('''
Required for the scaling plan (scalingplan.bicep) to bring deallocated hosts back
when a user connects. Without it, autoscale can shut hosts down and nothing turns
them back on — which is exactly the sort of thing that only reveals itself live.
''')
param startVMOnConnect bool = true

@description('''
Custom RDP properties, semicolon-terminated.

`targetisaadjoined:i:1` lets clients that are NOT joined to this Entra tenant
connect to Entra-joined session hosts (web, macOS, iOS, Android, and any local
Windows box that is not joined/registered to the same tenant). Without it, those
clients simply fail — a bad surprise when presenting from a laptop that is not on
the demo tenant.

The property is superseded by `enablerdsaadauth:i:1`, which gives true single
sign-on. That is the nicer experience, but it requires granting admin consent to
the Windows Cloud Login service principal at tenant level first -- another Entra
consent step on top of the Section 6 ones, and another thing to go wrong on stage.
Easy Mode takes the boring option and leaves SSO as a deliberate choice.
''')
param customRdpProperty string = 'targetisaadjoined:i:1;'

@description('''
Expiry for the session host registration token. Defaults to 8 hours from
deployment: long enough for a full build plus a slow demo, short enough that a
leaked token in a deployment log is worthless by the following morning.

utcNow() is only legal as a parameter default — that restriction is what makes
templates deterministic on re-deploy. Do not try to inline it below.
''')
param tokenExpirationTime string = dateTimeAdd(utcNow(), 'PT8H')

@description('''
Desktop means the app group published to users is a full desktop rather than
individual RemoteApps. Must agree with what appgroup.bicep actually creates.
''')
@allowed([
  'Desktop'
  'RailApplications'
  'None'
])
param preferredAppGroupType string = 'Desktop'

@description('Tags applied to every resource in this module.')
param tags object = {}

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2025-10-10' = {
  name: hostPoolName
  location: location
  tags: tags
  properties: {
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    preferredAppGroupType: preferredAppGroupType
    friendlyName: friendlyName
    description: hostPoolDescription
    maxSessionLimit: maxSessionLimit
    startVMOnConnect: startVMOnConnect
    customRdpProperty: customRdpProperty

    // Not a validation ring. Leaving this false keeps the pool on the standard
    // AVD service release train rather than opting into early agent updates.
    validationEnvironment: false

    registrationInfo: {
      expirationTime: tokenExpirationTime
      registrationTokenOperation: 'Update'
    }
  }
}

@description('Resource ID of the host pool. Consumed by appgroup.bicep and scalingplan.bicep.')
output hostPoolId string = hostPool.id

@description('Name of the host pool.')
output hostPoolName string = hostPool.name

@description('Registration token for session hosts. Secret: it authorizes a machine to join this pool.')
@secure()
output registrationToken string = hostPool.listRegistrationTokens().value[0].token

@description('When the registration token stops working.')
output registrationTokenExpiry string = tokenExpirationTime
