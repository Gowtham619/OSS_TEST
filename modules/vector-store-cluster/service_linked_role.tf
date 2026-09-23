# A VPC-based OpenSearch domain requires the AWSServiceRoleForAmazonOpenSearchService
# service-linked role to exist in the account. It is account-wide (not
# per-domain), so only create it once across your whole AWS account/region —
# set create_service_linked_role = false in every other module call, or you
# will get an EntityAlreadyExists error on the second apply.
variable "create_service_linked_role" {
  description = "Whether to create the AWSServiceRoleForAmazonOpenSearchService service-linked role. Set true only once per account; false everywhere else."
  type        = bool
  default     = false
}

resource "aws_iam_service_linked_role" "opensearch" {
  count            = var.create_service_linked_role ? 1 : 0
  aws_service_name = "opensearchservice.amazonaws.com"
  description       = "Service-linked role allowing OpenSearch to manage ENIs in customer VPCs"
}
