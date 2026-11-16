mock_provider "msgraph" {}

variables {
  partner_tenant_id = "00000000-0000-0000-0000-000000000020"
  trust_mfa         = true
}

run "cross_tenant_partner_plans" {
  command = plan

  assert {
    condition     = msgraph_resource.partner.body.tenantId == "00000000-0000-0000-0000-000000000020"
    error_message = "Expected partner tenantId in Cross-Tenant Access body."
  }

  assert {
    condition     = msgraph_resource.partner.body.inboundTrust.isMfaAccepted == true
    error_message = "Expected isMfaAccepted to reflect trust_mfa = true."
  }
}
