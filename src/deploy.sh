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
                       iamcredentials.googleapis.com

# Determine the full service account email
if [[ $SERVICE_ACCOUNT != *"@"* ]]; then
    SA_EMAIL="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
else
    SA_EMAIL="$SERVICE_ACCOUNT"
fi

# Grant the service account the ability to create signed URLs
# Grant the service account the ability to create signed URLs
echo "🔑 Granting Service Account Token Creator role to $SA_EMAIL..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --condition=None --quiet || echo "✅ Role already exists or cannot be added, skipping."

echo "🔑 Granting Application Integration Invoker role to $SA_EMAIL..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/integrations.integrationInvoker" \
    --condition=None --quiet || echo "✅ Role already exists or cannot be added, skipping."

# Grant necessary roles to the default Compute Engine SA for build/deploy
echo "🔑 Granting necessary roles to default Compute Engine SA..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
COMPUTE_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
compute_sa_roles_to_grant=(
    "roles/storage.objectViewer"
    "roles/logging.logWriter"
    "roles/artifactregistry.writer"
    "roles/firestore.admin"
    "roles/cloudtasks.admin"
)
for role in "${compute_sa_roles_to_grant[@]}"; do
    echo "  -> Granting $role..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$COMPUTE_SA_EMAIL" \
        --role="$role" \
        --condition=None --quiet || echo "   (Note: Role may have already existed, which is safe to ignore.)"
done

# Build and deploy the Cloud Run service
echo "📦 Building and deploying the Cloud Run service..."
gcloud run deploy "$SERVICE_NAME" \
  --source . \
  --region "$REGION" \
  --allow-unauthenticated \
  --service-account "$SA_EMAIL" \
  --set-env-vars "PROJECT_ID=$PROJECT_ID,REGION=$REGION,SERVICE_ACCOUNT=$SA_EMAIL"

echo "✅ Deployment complete."
