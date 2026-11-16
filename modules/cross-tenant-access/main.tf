resource "msgraph_resource" "partner" {
  url = "policies/crossTenantAccessPolicy/partners"

  body = {
    tenantId = var.partner_tenant_id
    b2bCollaborationInbound = {
      usersAndGroups = {
        accessType = var.b2b_inbound_access_type
        targets = [
          {
            target     = "AllUsers"
            targetType = "user"
          }
        ]
      }
      applications = {
        accessType = var.b2b_inbound_access_type
        targets = [
          {
            target     = "AllApplications"
            targetType = "application"
          }
        ]
      }
    }
    b2bCollaborationOutbound = {
      usersAndGroups = {
        accessType = var.b2b_outbound_access_type
        targets = [
          {
            target     = "AllUsers"
            targetType = "user"
          }
        ]
      }
      applications = {
        accessType = var.b2b_outbound_access_type
        targets = [
          {
            target     = "AllApplications"
            targetType = "application"
          }
        ]
      }
    }
    inboundTrust = {
      isMfaAccepted                       = var.trust_mfa
      isCompliantDeviceAccepted           = var.trust_compliant_device
      isHybridAzureADJoinedDeviceAccepted = var.trust_hybrid_joined_device
    }
    automaticUserConsentSettings = {
      inboundAllowed  = var.allow_automatic_user_consent_inbound
      outboundAllowed = var.allow_automatic_user_consent_outbound
    }
  }
}
