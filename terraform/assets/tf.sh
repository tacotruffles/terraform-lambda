#!/bin/bash
# PARAMTERS: 
#   $1 - terraform command -> init / apply / output / destroy
#   $2 - stage 

# Pull in Terraform Configuration
source ../tf.cfg
ASSET_TYPE="lambda"

# Setup Terraform Environment Variables for Stage
case $2 in
  prod) # PROD
    TF_STAGE="prod"
    echo "Configuring $TF_STAGE"
    # Set Terraform Variables
    ;;
  *) # STAGE is default
    TF_STAGE="stage"
    echo "Configuring $TF_STAGE"
    # Set Terraform Variables
    ;;
esac

# Terraform .tfvars Overrides
TF_STATE_BUCKET="$PREFIX-$TF_STAGE-tf-states"
TF_STATE_KEY="$PREFIX-$TF_STAGE-$ASSET_TYPE-s3-trigger.tf"
TF_STATE_TABLE="$PREFIX-$TF_STAGE-$ASSET_TYPE"

export TF_VAR_stage=$TF_STAGE
export TF_VAR_prefix=$PREFIX
export TF_VAR_aws_region=$AWS_REGION
export TF_VAR_aws_profile=$AWS_PROFILE
export TF_VAR_domain_name=$DOMAIN_NAME
export TF_VAR_tf_state_bucket=$TF_STATE_BUCKET
export TF_VAR_tf_state_key=$TF_STATE_KEY
# TBD export TF_VAR_tf_state_table=$TF_STATE_TABLE

echo "==================================================="
echo "STAGE: $TF_STAGE"
echo "AWS PROFILE: $AWS_PROFILE"
echo "AWS REGION: $AWS_REGION"
echo "TERRAFORM STATE: $TF_STATE_BUCKET/$TF_STATE_KEY"
[  -z "$1" ] && echo "ACTION: output" || echo "ACTION: $1"
echo "==================================================="

case $1 in
  # For switching branches
  clean)
    rm -R .terraform/
    rm .terraform.lock.hcl
    ;;
  # Initialize Terraform or Pull down existing backend
  init)
    terraform init \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="key=$TF_STATE_KEY" \
      -backend-config="region=$AWS_REGION" \
      -backend-config="profile=$AWS_PROFILE" 
    # TBD -backend-config="lock_table=$TF_STATE_TABLE"
    ;;
  # env)
  #   # Extract API URL state that was passed through outputs
  #   terraform refresh
  #   API_URL=$(terraform show -json | echo "VITE_API_URL=$(jq -r '.values.outputs.api_base_url.value')")
  #   [  -z "$API_URL" ] &&  exit 1 || echo $API_URL > ../../www/.env
  #   echo $API_URL
  #   jq --version
  #   ;;
  plan)
    terraform plan 
    ;;
  apply)
    # Uncomment for the one-time import of existing media bucket
    # terraform import aws_s3_bucket.uploads aiai-stage-upload
    # terraform import aws_s3_bucket.matrix_uploads aiai-stage-matrix
    terraform apply --auto-approve
    ;;
  state)
    terraform state list
    ;;
  validate)
    terraform validate
    ;;
  destroy)
    # Comment out the lines below if want to prevent your S3 buckets from getting obliterated
    terraform state rm aws_s3_bucket.uploads
    terraform state rm aws_s3_bucket.matrix_uploads
    terraform destroy --auto-approve
    ;;
  *) # output is default
    terraform output
    ;;
esac