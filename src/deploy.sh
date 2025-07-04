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

set -e

# Change to the script's directory
cd "$(dirname "$0")"

# Source environment variables
if [ -f "../env.sh" ]; then
  source "../env.sh"
else
  echo "../env.sh not found. Please create it based on the example."
  exit 1
fi

# Enable required GCP APIs
echo "📦 Enabling required GCP APIs..."
gcloud services enable run.googleapis.com \
                       integrations.googleapis.com \
                       iamcredentials.googleapis.com \
                       aiplatform.googleapis.com

# --- Service Account and Permissions Setup --- #
echo "🔑 Setting up service account and permissions..."

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "  -> Using default Compute Engine service account: $SA_EMAIL"
echo "  -> Granting Editor role to default Compute Engine SA..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/editor" \
    --condition=None --quiet || echo "     (Note: Role may have already existed, which is safe to ignore.)"

# Build and deploy the Cloud Run service
echo "📦 Building and deploying the Cloud Run service..."
gcloud run deploy "$SERVICE_NAME" \
  --source . \
  --region "$REGION" \
  --allow-unauthenticated \
  --service-account "$SA_EMAIL" \
  --set-env-vars "PROJECT_ID=$PROJECT_ID,REGION=$REGION,SERVICE_ACCOUNT=$SA_EMAIL"

echo "✅ Deployment complete."
