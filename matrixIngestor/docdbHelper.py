# AWS Document DB Helper
import os

# If the below environment variables exit, then this code is running inside an AWS Lambda function
def is_lambda():
  return bool(os.getenv('LAMBDA_TASK_ROOT', False)) and bool(os.getenv('AWS_EXECUTION_ENV', False)) 

# Generates the necessary connection URI for local vs lambda execution
# Connect to DocumentDB with the CA Cert Bundle provide by AWS
# Must be placed in root of project folder and availble via `wget` command as documented here: 
# https://docs.aws.amazon.com/documentdb/latest/developerguide/connect-from-outside-a-vpc.html
def get_mongo_uri():
  return 'mongodb://{user}:{password}@{host}:{port}/?tls=true&tlsCAFile=global-bundle.pem&tlsAllowInvalidHostnames=true&retryWrites=false&w=majority{localParam}'.format(
  user=os.environ['MONGODB_USERNAME'],
  password=os.environ['MONGODB_PASSWORD'],
  host=os.environ['MONGODB_HOST'] if is_lambda() else 'localhost',
  port=os.environ['MONGODB_PORT'], 
  db=os.environ['MONGODB_DATABASE'],
  localParam = '' if is_lambda() else '&directConnection=true'
)
