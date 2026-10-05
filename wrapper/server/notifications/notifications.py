import os
import hashlib
import json
# Brainstorming
# Directories for depositing notifications: 
# One for raw text that can be inserted into JSON
# Another for notification JSON. Maybe unnecessary?

SAVE_DIR = "./saved"

def collect_notifications(drop_dir: str):
    notifications = parse_unread(drop_dir)

    files = os.listdir(SAVE_DIR)
    for file in files:
        path = os.path.join(SAVE_DIR, file)
        with open(path, 'r') as f:
            notification = json.load(f)
        notifications.append(notification)

    return notifications

def parse_unread(drop_dir: str):
    found_notifications = []

    files = os.listdir(drop_dir)
    for file in files:
        path = os.path.join(drop_dir, file)
        with open(path, 'r') as f:
            text = f.read()
        stat = os.stat(path)
        time = stat.st_mtime_ns
        notification = build_notification(text, time)

        save_notification(notification, path)

        found_notifications.append(notification)

    return found_notifications

def build_notification(text: str, time: int):

    text_and_time = f'{text}{time}'
    hash_object = hashlib.sha256(text_and_time.encode('utf-8'))
    hex_dig = hash_object.hexdigest()

    return {
        "id": hex_dig,
        "text": text,
        "time": time,
        "thisBoot": True # TODO: Infer this somehow
    }

def save_notification(notification: dict, path: str):
    os.makedirs(SAVE_DIR, exist_ok=True)

    saved_path = os.path.join(SAVE_DIR, f"{notification['id']}.json")
    with open(saved_path, 'w') as f:
        json.dump(notification, f)

    try:
        os.remove(path)
    except:
        print(f"Could not delete raw notification file at path: {path}")

def delete_notification(id: str):
    try:
        os.remove(os.path.join(SAVE_DIR, f"{id}.json"))
    except:
        print(f"Could not delete notification file with id: {id}")
