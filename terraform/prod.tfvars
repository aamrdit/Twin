project_name             = "twin"
environment              = "prod"
#bedrock_model_id         = "amazon.nova-pro-v1:0"  # Use better model for production
bedrock_model_id = "eu.amazon.nova-pro-v1:0"

lambda_timeout           = 60
api_throttle_burst_limit = 20
api_throttle_rate_limit  = 10
use_custom_domain        = true
root_domain              = "aamrdit.com"  # Replace with your actual domaincd