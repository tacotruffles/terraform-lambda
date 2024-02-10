from s3Client import getTextFile

# Use this Lambda handler as a wrapper to make local development easier
def handler (event, context):

  # from getTextFile import s3Client
  txt_content = getTextFile(event)
  
  # output text contents
  print(txt_content)
  return txt_content


# import requests
# def handler (event, context):
#   response = requests.get("https://swapi.py4e.com/api/people/2/")
#   print(response.json)
#   return response.json()