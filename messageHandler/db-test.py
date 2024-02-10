# This file can be deleted.
import json, os, sys, io, urllib.parse
sys.path.append(os.path.join(os.path.dirname(__file__), "lib"))

from pymongo import * 

# Helper to generate the correcty mongo connection string for where this code is running
from docdbHelper import * # mongo_uri() and is_lambda()

# If running locally ingest the .env file
if not is_lambda():
  from dotenv import load_dotenv
  load_dotenv()

client = MongoClient(get_mongo_uri())
db = client[os.environ['MONGODB_DATABASE']]
print("connected:", os.environ['MONGODB_HOST'])

users_collection = db.users
result = users_collection.find_one()

print(result)