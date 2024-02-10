import os
import json
from dotenv import load_dotenv
from main import handler

# Load .env variables
load_dotenv()

# Test for .env ingestion
print(os.environ['STAGE'])
print(os.environ['MONGODB_URI'])

# Load test event file
with open('s3-trigger-event.json') as json_file: # 
  file_contents = json.load(json_file)

print(file_contents)

# Invoke Lambda Handler to run test event
handler(file_contents, {})
