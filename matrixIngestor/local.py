import json
from main import handler

# Load test event file
with open('s3-trigger-event.json') as json_file: # 
  file_contents = json.load(json_file)

print(file_contents)

# Invoke Lambda Handler to run test event
handler(file_contents, {})
