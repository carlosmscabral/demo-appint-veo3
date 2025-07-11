#!/bin/bash

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Stop on error.
set -e

# Source the environment variables.
source env.sh

# --- User Confirmation ---
echo "🛑 WARNING: This script will permanently delete the following resources:"
echo "   - Cloud Run Service: $SERVICE_NAME"
echo "   - Cloud Tasks Queue: $QUEUE_NAME"
echo "   - GCS Bucket: $GCS_BUCKET_URI"
echo "   - All Application Integration assets in this project."
echo "   - IAM roles granted by the deployment script."
echo ""
read -p "Are you sure you want to continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 1
fi

echo "🚀 Starting cleanup..."

# --- Cloud Run Service ---
echo "🗑️ Deleting Cloud Run service: $SERVICE_NAME..."
gcloud run services delete "$SERVICE_NAME" --region="$REGION" --quiet || echo "⚠️ Cloud Run service not found or already deleted."

# --- Cloud Tasks Queue ---
echo "🗑️ Deleting Cloud Tasks queue: $QUEUE_NAME..."
gcloud tasks queues delete "$QUEUE_NAME" --location="$REGION" --quiet || echo "⚠️ Cloud Tasks queue not found or already deleted."

# --- Application Integration Assets ---
echo "🗑️ Deleting Application Integration assets..."

echo "Installing integrationcli ..."
curl -L https://raw.githubusercontent.com/GoogleCloudPlatform/application-integration-management-toolkit/main/downloadLatest.sh | sh -
export PATH=$PATH:$HOME/.integrationcli/bin

if [ -z "$TOKEN" ]; then
  TOKEN=$(gcloud auth print-access-token)
fi

integrationcli prefs set --reg="$REGION" --proj="$PROJECT_ID" -t "$TOKEN"

integrationcli integrations delete -n veo-architecture || echo "⚠️ Integration 'veo-architecture' not found or already deleted."
integrationcli integrations delete -n gemini-v2 || echo "⚠️ Integration 'gemini-v2' not found or already deleted."
integrationcli integrations delete -n firestore || echo "⚠️ Integration 'firestore' not found or already deleted."
integrationcli integrations delete -n add-task-queue || echo "⚠️ Integration 'add-task-queue' not found or already deleted."
integrationcli integrations delete -n veo3 || echo "⚠️ Integration 'veo3' not found or already deleted."
integrationcli integrations delete -n poll-veo || echo "⚠️ Integration 'poll-veo' not found or already deleted."

integrationcli connectors delete -n vertex-1 || echo "⚠️ Connector 'vertex-1' not found or already deleted."
integrationcli connectors delete -n firestore || echo "⚠️ Connector 'firestore' not found or already deleted."

# --- GCS Bucket ---
echo "🗑️ Deleting GCS bucket: $GCS_BUCKET_URI..."
gsutil -m rm -r "$GCS_BUCKET_URI" || echo "⚠️ GCS bucket not found or already deleted."

# --- IAM Bindings ---
echo "🔑 Revoking IAM roles..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
gcloud projects remove-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$COMPUTE_SA" --role="roles/editor" --condition=None || echo "⚠️ IAM binding for Editor role not found."
gcloud projects remove-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$COMPUTE_SA" --role="roles/iam.serviceAccountTokenCreator" --condition=None || echo "⚠️ IAM binding for Service Account Token Creator role not found."

# --- Firestore Collection ---
echo "🔥 Firestore Collection Cleanup"
echo "   The script cannot automatically delete the Firestore collection '$STATE_COLLECTION'."
echo "   Please navigate to the Google Cloud Console and delete it manually."
echo ""

echo "✅ Cleanup complete!"
