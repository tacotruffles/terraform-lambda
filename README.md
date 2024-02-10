# Lambda - Layer 3 - IaC

## Prereqs

Configure Repo Secrets:

* `AWS_ACCESS_KEY_ID`: AWS CLI deployment user access key
* `AWS_SECRET_ACCESS_KEY`: AWS CLI deployment user secret key
* `LAMBDA_STAGE_DOTENV`: Stage pipeline `.env` file contents
* `LAMBDA_PROD_DOTENV`: Prod pipeline `.env` file contents

# Stand up CI/CD pipeline and IaC

* Create `stage` and `prod` branches as needed to deploy IaC and application pipelines
* Subsequent merges into the each branch will build and deploy the Lambda application in the typical CI/CD pattern.

# Test VPC/Static IP

TBD