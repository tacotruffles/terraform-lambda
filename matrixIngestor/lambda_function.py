import json, os, sys, io, urllib.parse
sys.path.append(os.path.join(os.path.dirname(__file__), "lib"))

from datetime import datetime, date
import re
import boto3
import pandas as pd
import numpy as np
from pymongo import *
from bson.objectid import ObjectId

sqs = boto3.client('sqs')
s3 = boto3.client('s3')

# # Create a new client and connect to the server
# client = MongoClient(os.getenv("MONGO_URL"))
# db = client[os.environ['MONGO_DB']]
# print("connected:", os.environ['MONGO_URL'])

# Helper to generate the correcty mongo connection string for where this code is running
from docdbHelper import * # mongo_uri() and is_lambda()
print(get_mongo_uri())
client = MongoClient(get_mongo_uri())
db = client[os.environ['MONGODB_DATABASE']]
print("connected:", os.environ['MONGODB_HOST'], os.environ['MONGODB_DATABASE'])

lessons_collection = db.lessons
lessonActivities_collection = db.lessonActivities

# Notes/instructions -----
# this is a 5 minute video… 30 fps => 9,000 frames
# Step 1: de-noise-ify it
# Step 2: find 90 second minimum “chunks” start frame, end frame, length in frames..
# what if teacher not in frame?
# is whole class doing individual activity count as ind or whole class?
# could start by looking for 90s of good data then zoom in
# 9000 frames, 30 fps, looking for 90 second chunks so I want divide into 2700 first 1s
# what is gap size between ones? --> how many times 1-frame gap between 1s
# ----------------
def process_vid(bucket, key):
    print("process_vid("+bucket+", "+key+")")
    # import data
    obj = s3.get_object(Bucket=bucket, Key=key)
    vid_df = pd.read_csv(io.BytesIO(obj['Body'].read()))

    video_df = vid_df.copy()
    video_df.loc[24] = video_df.iloc[23] # copied to make extended transition its own category
    video_df.rename(columns={video_df.columns[0]: "activity"}, inplace=True)

    # just activity labels hopefully for dictionary iteration? ------
    labels = [] # preferred dictionary keys, a1-a25
    for x in range(1,26):
        labels.append(f"a{x}")
    #print(labels)

    activity_labels_df = video_df[['activity']].copy() #dataframe of just the activity label/names
    minima = (30, 30, 30, 30, 30, 30, 30, 3, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 90)
    activity_labels_df["Minimum"] = minima
    activity_labels_df.iat[24, 0] = "Extended_Transition"
    activity_labels_df.insert(0, "label", labels)
    #print(activity_labels_df)

    # just frames ------
    vid_frames_only = video_df.drop('activity', axis=1) # dataframe of just the frames
    #print(vid_frames_only)

    # convert to numpy array
    vid_array = np.array(vid_frames_only) # array of just the frames
    #print(vid_array)
    #print(f"length of vid array: {len(vid_array)}")

    # date and time for stats:
    time = datetime.now()
    time = time.strftime("%H:%M")
    day = date.today()
    timestamp = (f"{day} {time}")
    key = re.sub(r'^uploads\/([A-Za-z0-9_]+\/)?', '', key) # remove uploads prefix

    stats = {"vidLength": (len(vid_frames_only.columns)) / 30,  # length of vid in seconds
             "processed": timestamp,
             "filename": key}  # date and time processed
    dict_moments = {}
    for idx, activity in enumerate(activity_labels_df["activity"]):
        for idx2, act in enumerate(video_df["activity"]):
            if activity == act: # matches up by activity name
                # because activity in Activity_label df assumes original minimum thresholds and order (like copies last row for ext. transitions)
                # idx = index ; lbl = a1-a25
                lbl = activity_labels_df["label"][idx]
                #print(f"{lbl}:{activity} {act} {vid_array[idx]}") # see all next to each other
                store = {}
                min_assigned = activity_labels_df["Minimum"][idx]
                chunk(vid_array[idx], store, min_assigned)
                itt = {lbl: store}
                dict_moments.update(itt)
            else:
                continue

    ##### create dictionary of activity lists and write to json #########
    dict_moments["stats"] = stats
    # Serializing json
    json_object = json.loads(json.dumps(dict_moments))

    # for sample iteration:
    # filename = f"{vid}"[:-len(".csv")]

    # Writing to sample.json
    # with open(f"{filename}.json", "w") as outfile:
        # outfile.write(json_object)
    return json_object


# def to chunk moments by minimum of x seconds (90 sec = 2700 frames, 20 s = 600 frames, 5 seconds = 150 frames)
def chunk(activity_array, activity_dict, minimum):
    moments = [] # list to contain each moment, or consecutive 1 frames of minimum threshold
    list_for_dict = [] # this list is appended to dict at end of fcn, otherwise the dict just stores final moment info
    all_lengths = [] # list to contain each iteration's duration
    idx_matching_1 = np.where(activity_array == 1)[0]
    consecutive_groups_of_1_idx = np.split(idx_matching_1, np.where(np.diff(idx_matching_1) != 1)[0] + 1)
    # print(consecutive_groups_of_1_idx)
    for item in consecutive_groups_of_1_idx:
        # print(f"item: {item}")
        if len(item) >= (minimum*30): # to get in num of frames
            moments.append(item)
            # print("moments:", moments)
            # print(moments)
            for moment in moments: # is an array of indices (to be converted to frames)
                start_frame = moment[0]+1
                end_frame = moment[-1]+1
                duration = round(((end_frame-moment[0])/30),ndigits=2) # 30 fps
                start_seconds = round((start_frame/30), ndigits=1)
                end_seconds = round((end_frame/30), ndigits=1)
            all_lengths.append(duration)  # each moments length stored in a list so we can take the average
            list_for_dict.append({
                "s": start_seconds,  # seconds into video when moment starts
                "e": end_seconds,  # seconds into video when moment ends
                "l": duration,  # length in seconds of moment
                "sf": int(start_frame),  # start frame
                "ef": int(end_frame)  # end frame
            })
            activity_dict["moments"] = list_for_dict

        else:
            activity_dict["moments"] = list_for_dict
           # activity_list_for_dict["min"] = None

        """
        all_lengths.append(duration)  # each moments length stored in a list so we can take the average
        list_for_dict.append({
            "s": start_seconds, # seconds into video when moment starts
            "e": end_seconds, # seconds into video when moment ends
            "l": duration, # length in seconds of moment
            "sf": int(start_frame), # start frame
            "ef": int(end_frame) # end frame
        })
        activity_dict["moments"] = list_for_dict
        """


        # print(f" start frame: {start_frame} \n end frame: {end_frame} \n length(s): {duration}")
        # print(moments)
    # print(f"durations total: {all_lengths}")

    activity_dict["numMoments"] = len(moments)
    activity_dict["min"] = int(minimum)
    if len(all_lengths) > 0:
        avg = round((sum(all_lengths) / len(all_lengths)), ndigits=2)
        # print(avg)
        activity_dict["avgLength"] = avg
        activity_dict["length"] = round(sum(all_lengths), ndigits=2)


# Table lessons {
#   _id objectId [primary key]
#   class string [ref: < organizations.name]
#   length string
#   comments "objectId[]" [ref: < comments._id]
#   reflections "objectID[]" [ref: < reflections._id]
#   teacherId objectId [ref: < users._id]
#   oranizationId objectId [ref: < organizations._id]
#   type string [note: 'researcher or student']
#   videoData videoData
#   created date
#   updated date
#   status string [note: 'need to define what are potential statuses in the pipeline']
#   videoUrl string [note: 's3 bucket location']
#   uploadedBy objectId
#   lessonActivity objectId [ref: - lessonActivity._id]
#   summary string
#   goal string
# }
# Table lessonActivity {
#   _id objectId [primary key]
#   lessonId objectId [ref: - lessons._id]
#   data object 
#   fileName string [note: 'to s3 bucket source']
#   created date
#   updated date
#   notes string 
# }

def save_lessonActivity(filename, data, lessonId):
    print("saving lessonActivity")
    lessonActivities_collection.insert_one({
        "lessonId": lessonId,
        "data": data,
        "fileName": filename,
        "created": datetime.now(),
        "updated": datetime.now(),
        "notes": "test"
    })
    return list(lessonActivities_collection.find({ "fileName": filename }))[0]


def save_lesson(filename, data):
    print("saving lesson", data)
    lesson = None
    lessonId = None
    lessonActivity = list(lessonActivities_collection.find({ "fileName": filename }))

    # if lessonActivity exists for this file, pull up existing lesson
    if len(lessonActivity) > 0:
        lesson = lessons_collection.find_one({ "_id": lessonActivity[0]["lessonId"] })
        print('lesson:', lesson)
        # if lesson exists, update it
        if lesson:
            lessonId = lesson["_id"]
            # save new activity
            lessonActivity = save_lessonActivity(filename, data, lessonId)
            # update lesson and add new activityId if not present
            update = { "updated": datetime.now() }
            print("lesson exists, updating")
            # print("lesson.lessonActivity[]:", lesson["lessonActivity"])
            # print("lessonActivity._id", lessonActivity["_id"])
            if lessonActivity["_id"] not in lesson["lessonActivity"]:
                update["lessonActivity"] = lesson["lessonActivity"].append(lessonActivity["_id"])
            # print("update:", update)
            lessons_collection.update_one(
                { "_id": ObjectId(lessonId) },
                { "$set": update }
            )
    # if lesson doesn't exist, create it (should never happen, as vid import does this. remove?)
    if lesson is None:
        print('creating new lesson')
        lesson = {
            "class": "",
            "comments": [],
            "reflections": [],
            "teacherId": None,
            "oranizationId": None,
            "type": None,
            "videoData": None,
            "created": datetime.now(),
            "updated": datetime.now(),
            "status": None,
            "videoUrl": None,
            "uploadedBy": None,
            "lessonActivity": [],
            "summary": "",
            "goal": ""
        }
        new_lesson = lessons_collection.insert_one(lesson)
        # create lessonActivity
        lessonActivity = save_lessonActivity(filename, data, new_lesson.inserted_id)
        # update lesson with activityId
        lessons_collection.update_one(
            { "_id": ObjectId(new_lesson.inserted_id) },
            { "$set": { "lessonActivity": [lessonActivity["_id"]] }}
        )

    else:
        pass # update existing lesson lessonactivity.push if not present


def lambda_handler(event, context):
    print("starting matrix processing")
    try:
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')

        data = process_vid(bucket, key)
        key = re.sub(r'^uploads\/([A-Za-z0-9_]+\/)?', '', key) # remove uploads prefix
        save_lesson(key, data)
    except Exception as e:
        print(e)
        raise e


