from flask import Flask, render_template, request, jsonify
from googleapiclient.discovery import build
from google.cloud import storage
import os
import logging
import datetime
import google.auth
import google.auth.transport.requests

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

app = Flask(__name__)

# GCP Configuration
PROJECT_ID = os.environ.get("PROJECT_ID")
REGION = os.environ.get("REGION")
SERVICE_ACCOUNT = os.environ.get("SERVICE_ACCOUNT")

# API Configuration
BASE_URL = "https://integrations.googleapis.com"

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/generate-video", methods=["POST"])
def generate_video():
    logging.info("Received request for /generate-video")
    try:
        logging.info(f"Request headers: {request.headers}")
        logging.info(f"Request raw data: {request.get_data(as_text=True)}")

        data = request.get_json()
        if not data:
            logging.error("Request body is not valid JSON or is empty.")
            return jsonify({"error": "Invalid JSON."}), 400
        
        logging.info(f"Request JSON data: {data}")

        logging.info(f"Using PROJECT_ID: {PROJECT_ID} and REGION: {REGION}")
        
        image_base64 = data.get("imageBase64")
        prompt = data.get("prompt")
        image_mime_type = data.get("imageMimeType")
        gcs_uri = data.get("gcsUri")

        logging.info(f"Prompt: {prompt}, MimeType: {image_mime_type}, GCS URI: {gcs_uri}")

        logging.info("Building integrations service...")
        service = build("integrations", "v1")
        logging.info("Integrations service built successfully.")

        integration_name = f"projects/{PROJECT_ID}/locations/{REGION}/integrations/veo-architecture"
        request_body = {
            "triggerId": "api_trigger/veo-architecture_reqVideo",
            "inputParameters": {
                "imageBase64": {"stringValue": image_base64},
                "userQuery": {"stringValue": prompt},
                "imageMimeType": {"stringValue": image_mime_type},
                "storageURI": {"stringValue": gcs_uri},
            }
        }

        logging.info(f"Executing integration: {integration_name}")
        logging.info(f"Request body: {request_body}")
        response = service.projects().locations().integrations().execute(
            name=integration_name,
            body=request_body
        ).execute()
        logging.info(f"Integration response: {response}")

        output_params = response.get("outputParameters", {})
        
        # The actual response seems to be nested inside a 'returnPayload' parameter
        return_payload = output_params.get("returnPayload", {})
        
        # The uuid is inside this payload
        uuid = return_payload.get("uuid")

        logging.info(f"Extracted UUID: {uuid}")

        return jsonify({"uuid": uuid})

    except Exception as e:
        logging.error(f"An unexpected error occurred in /generate-video: {e}", exc_info=True)
        return jsonify({"error": "An internal server error occurred."}), 500

def generate_signed_url(gcs_uri):
    if not gcs_uri:
        return None
    
    try:
        storage_client = storage.Client()
        bucket_name, blob_name = gcs_uri.replace("gs://", "").split("/", 1)
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)

        # Get the default credentials and refresh them to get an access token.
        # This is the key step to prove we have the right to use the IAM signing API.
        credentials, project = google.auth.default()
        request = google.auth.transport.requests.Request()
        credentials.refresh(request)

        # Generate a signed URL using the IAM API signing flow.
        # This requires both the service account email and a valid access token.
        signed_url = blob.generate_signed_url(
            version="v4",
            expiration=datetime.timedelta(minutes=60),
            method="GET",
            service_account_email=SERVICE_ACCOUNT,
            access_token=credentials.token,
        )
        logging.info(f"Generated signed URL successfully.")
        return signed_url
    except Exception as e:
        logging.error(f"Failed to generate signed URL for {gcs_uri}: {e}", exc_info=True)
        return None

@app.route("/status/<uuid>", methods=["GET"])
def get_status(uuid):
    logging.info(f"Received request for /status/{uuid}")
    try:
        logging.info("Building integrations service for polling...")
        service = build("integrations", "v1")
        logging.info("Integrations service for polling built successfully.")

        integration_name = f"projects/{PROJECT_ID}/locations/{REGION}/integrations/veo-architecture"
        request_body = {
            "triggerId": "api_trigger/veo-architecture_polling",
            "inputParameters": {
                "uuid": {"stringValue": uuid}
            }
        }

        logging.info(f"Polling integration: {integration_name} for UUID: {uuid}")
        response = service.projects().locations().integrations().execute(
            name=integration_name,
            body=request_body
        ).execute()
        logging.info(f"Polling response: {response}")

        output_parameters = response.get("outputParameters", {})
        
        # The actual response seems to be nested inside a 'returnPayload' parameter
        return_payload = output_parameters.get("returnPayload", {})
        
        # The status and gcsURI are inside this payload
        status = return_payload.get("status")
        gcs_uri = return_payload.get("gcsURI")

        signed_gcs_uri = None
        if status == "done" and gcs_uri:
            signed_gcs_uri = generate_signed_url(gcs_uri)

        logging.info(f"Polling result - Status: {status}, GCS URI: {gcs_uri}, Signed URL: {signed_gcs_uri}")

        return jsonify({"status": status, "gcsURI": signed_gcs_uri})

    except Exception as e:
        logging.error(f"An unexpected error occurred in /status/{uuid}: {e}", exc_info=True)
        return jsonify({"error": "An internal server error occurred."}), 500
