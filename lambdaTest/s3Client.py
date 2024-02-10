import boto3

# Get Text File from S3 Lambda Event generated from a Trigger
# See: s3-trigger-event.json for example event
def getTextFile(event):
  # Get S3 Object URL
  s3_event = event['Records'][0]['s3']
  s3_bucket = s3_event['bucket']['name']
  s3_key = s3_event['object']['key']
  
  # Setup S3 Client
  s3_client = boto3.client('s3')

  s3_response = s3_client.get_object(
    Bucket=s3_bucket,
    Key=s3_key
  )

  # Get object contents - assuming text file
  s3_object_body = s3_response.get('Body')

  # Read the data in bytes format and convert it to string
  content_str = s3_object_body.read().decode()

  return content_str
