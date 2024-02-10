import json, os, sys, re
from datetime import datetime
sys.path.append(os.path.join(os.path.dirname(__file__), "lib"))

import urllib.parse
import boto3
from pymongo import *
from bson.objectid import ObjectId

sqs = boto3.client('sqs')
s3 = boto3.client('s3')

# client = MongoClient(os.getenv("MONGO_URL"))
# db = client[os.environ("MONGO_DB")]
# print("connected:", os.environ("MONGO_URL"))

# Helper to generate the correcty mongo connection string for where this code is running
from docdbHelper import * # mongo_uri() and is_lambda()
print(get_mongo_uri())
client = MongoClient(get_mongo_uri())
db = client[os.environ['MONGODB_DATABASE']]
print("connected:", os.environ['MONGODB_HOST'], os.environ['MONGODB_DATABASE'])

lessonActivities_collection = db.lessonActivities
sqsMessages_collection = db.sqsMessages
lessons_collection = db.lessons
log_collection = db.log

file_upload_message_url = os.getenv("SQS_URL")


def log_event(type, event, params):
    log_collection.insert_one({
        "type": type,
        "data": event,
        "owner": params["user"],
        "created": datetime.now(),
        "updated": datetime.now()
    })


def handle_file_upload(event, params):
    try:
        # query db look up filename in sqsMessages

        s3Client = boto3.client('s3')
        meta_object = s3Client.head_object(Bucket=os.getenv("S3_UPLOAD_BUCKET"), Key=params["key"])
        file_metadata = meta_object['Metadata']
        log_event("file metadata", { 'event': event, 'metadata': file_metadata }, params)
        print('orig file_metadata:', file_metadata)

        existing = sqsMessages_collection.find_one({ "videoKey": params["key"] })

        if existing:
            log_event("re-processing existing video", event, params)
            print("--> re-processing existing video")
            file_metadata['request-type'] = "reprocess existing video"
        else:
            log_event("processing new video", event, params)
            print("--> processing new video")
            file_metadata['request-type'] = "process new video"

        date_str = event['Records'][0]['eventTime']
        date_str = date_str.replace('Z', '+00:00')
        dt_object = datetime.fromisoformat(date_str).isoformat()

        # example metadata:

        #   orig file_metadata: {'environment': 'stage', 'lesson-id': '6595d73defd3497aba0a298a', 'lesson-name': 'foo bar', 'version': '01', 'lesson-date': '2024-01-01', 'class-id': '658e350d38b71bece7dc08a3'}
        # 	parsed file_metadata: {'environment': 'stage', 'lesson-id': '6595cd691fd1b4fbbb679ad4', 'lesson-name': 'foo bar', 'version': '01', 'lesson-date': datetime.datetime(2023, 8, 26, 0, 0), 'class-id': '658e350d38b71bece7dc08a3', 'request-type': 'process new video', 'class': '003', 'district': '010', 'school': '101', 'teacher': '053', 'subject': 'MATH1'}
        #   lesson_query: {'class': '003', 'subject': 'MATH1', 'lessonDate': datetime.datetime(2023, 8, 26, 0, 0)}

        lesson_query = {}
        # if we have an id, fetch the lesson
        if "lesson-id" in file_metadata:
            lesson_query = { "_id": ObjectId(file_metadata["lesson-id"]) }
            file_metadata['lessonid'] = file_metadata["lesson-id"]
        else:
            # else use filename info to create metadata and see if we can find it
            # format: class_school_disctict_teacher_subject_lessonDate_version eg: C003_D010_S101_T053_LMATH1_20230824_V10
            file_info = params["filename"].split('.')[0].split('_')
            for i in file_info:
                field = None
                if i[0] == 'C':
                    field = "class"
                elif i[0] == 'D':
                    field = "district"
                elif i[0] == 'S':
                    field = "school"
                elif i[0] == 'T':
                    field = "teacher"
                elif i[0] == 'L':
                    field = "subject"
                elif i[0] == 'V':
                    field = "version"
                elif re.match(r'\d{8}', i):
                    file_metadata['lesson-date'] = datetime.strptime(i, "%Y%m%d")
                    continue

                file_metadata[field] = i[1:]

            print('parsed file_metadata:', file_metadata)
 
            lesson_query = {
                "class": file_metadata['class'],
                "subject": file_metadata['subject'],
                "teacher": file_metadata['teacher']
                # "lessonDate": file_metadata['lesson-date']
            }

        print('lesson_query:', lesson_query)
        lesson_info = lessons_collection.find_one(lesson_query)

        if lesson_info:
            # found lesson, update metadata with db info
            for k in lesson_info.keys():
                file_metadata[k] = lesson_info[k]
            file_metadata['lessonid'] = str(lesson_info['_id'])
            print("found lesson:", file_metadata)
        else:
            # couldn't find lesson, create it with parsed metadata
            print("creating new lesson:", file_metadata)
            file_metadata['created'] = dt_object
            file_metadata['updated'] = dt_object

            lesson_info = lessons_collection.insert_one(file_metadata).inserted_id
            print('lesson_info:', lesson_info)
            file_metadata['lessonid'] = str(lesson_info)


        print('lesson:', lesson_info)

        file_metadata['filename'] = params["filename"]

        print('file_metadata:', file_metadata)
        # store data in sqsMessages
        event_info = {
            "requestType": file_metadata['request-type'],
            "environment": os.getenv("STAGE"), # file_metadata["environment"] ?
            "bucket": params["bucket"],
            "videoKey": params["key"],
            "filename": file_metadata["filename"],
            "filetype": file_metadata["filename"].split('.')[-1],
            "lessonid": ObjectId(file_metadata["lessonid"]),
            "videoid": file_metadata["filename"].split('.')[0],
            "event-time": dt_object,
            "updated": datetime.now()
        }

        msg_id = sqsMessages_collection.insert_one(event_info).inserted_id

        # for logging/debugging
        if event_info["_id"]:
            del event_info["_id"]
        event_info['messageid'] = str(msg_id)
        event_info['lessonid'] = str(file_metadata['lessonid'])
        event['event_info'] = event_info
        event['file_metadata'] = file_metadata
        event['params'] = params
        del event_info['updated'] # for the db, not sqs msg

        print('event_info:', event_info)
        message_body = json.dumps(event_info)

        # create sqs message
        sqs_send_response = sqs.send_message(
            QueueUrl=file_upload_message_url,
            MessageBody=message_body
        )
        event['message_data'] = message_body
        event['sqs_send_response'] = sqs_send_response
        log_event("video upload trigger", event, params)

        return "success"

    except Exception as e:
        print(e)
        raise e


def handle_sqs_message(event, params):
    params["user"] = "sqs"
    log_event("incoming sqs message", event, params)
    # TODO: check for statusUpdate field, handle accordingly


def lambda_handler(event, context):
    # print("Received event: " + json.dumps(event, indent=2))
    # "eventSourceARN": "arn:aws:sqs:us-east-1:765228178068:aiai-stage-incoming-status-updates", 
    # if event["eventSource"] == "aws:sqs":
    params = {}
    # print("processing event:", event)
    if event['Records'][0]['eventSource'] == "aws:s3":
        print("processing s3 event")
        # Get the object from the event and show its content type
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')

        file_info = key.split("/") # remove uploads/user prefixes
        print("file_info:", file_info)
        path = "/".join(file_info[1:])

        filename = file_info[-1]
        if len(file_info) > 2:
            user = file_info[-2]
        else:
            user = "unknown"

        params = { 'bucket': bucket, 'key': key, 'filename': filename, 'user': user, 'path': path }

        if event['Records'][0]['s3']['bucket']['name'] == os.getenv("S3_UPLOAD_BUCKET"):
            handle_file_upload(event, params)
    else:
        print("processing sqs event")
        handle_sqs_message(event, params)


