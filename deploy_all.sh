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

echo "🚀 Initiating deployment sequence..."

# Source environment variables
if [ -f "$(dirname "$0")/env.sh" ]; then
    echo " sourcing environment variables..."
    source "$(dirname "$0")/env.sh"
else
    echo "❌ Critical Error: env.sh not found. Deployment cannot proceed."
    exit 1
fi

# Validate that all necessary environment variables are set and not empty
echo "🧐 Validating environment variables..."

variables_to_check=(
    "PROJECT_ID"
    "REGION"
    "SERVICE_NAME"
    "SERVICE_ACCOUNT"
    "QUEUE_NAME"
    "STATE_COLLECTION"
    "STATE_DB"
    "GCS_BUCKET_URI"
)

all_vars_valid=true
for var in "${variables_to_check[@]}"; do
    if [ -z "${!var}" ] || [[ "${!var}" == "<your-"*">" ]]; then
        echo "❌ Error: Environment variable $var is missing or has a placeholder value."
        all_vars_valid=false
    fi
done

if [ "$all_vars_valid" = "false" ]; then
    echo "🛑 Deployment halted due to missing or invalid environment variables."
    exit 1
fi

echo "✅ All environment variables are properly set."

# Force gcloud re-authentication
echo "🔐 Forcing gcloud re-authentication..."
gcloud auth login


# Enable necessary GCP APIs
echo "🛠️ Enabling required GCP APIs..."

apis_to_enable=(
    "cloudresourcemanager.googleapis.com"
    "integrations.googleapis.com"
    "secretmanager.googleapis.com"
    "firestore.googleapis.com"
    "cloudtasks.googleapis.com"
    "connectors.googleapis.com"
    "compute.googleapis.com"
    "cloudbuild.googleapis.com"
    "aiplatform.googleapis.com"
)

for api in "${apis_to_enable[@]}"; do
    echo "  -> Enabling $api..."
    gcloud services enable "$api" --project="$PROJECT_ID"
    if [ $? -ne 0 ]; then
        echo "❌ Error enabling $api. Deployment halted."
        exit 1
    fi
done

echo "✅ All necessary APIs are enabled."

# --- Manual Step: Enable Application Integration --- #
echo "🛑 IMPORTANT: Manual step required!"
echo "You must now enable Application Integration for your selected region in the Google Cloud Console."
echo "1. Click the following link to open the console:"
echo "   https://console.cloud.google.com/integrations?project=$PROJECT_ID"
echo "2. Select the '$REGION' region and click 'Enable'."
echo "3. Wait for the process to complete."
echo "For more details, see: https://cloud.google.com/application-integration/docs/setup-application-integration#quick"
read -p "Press [Enter] to continue once you have enabled Application Integration in the console..."

# --- Service Account Setup --- #
echo "🔎 Setting up service account..."

# Check if SERVICE_ACCOUNT is a full email or a short name
if [[ $SERVICE_ACCOUNT == *"@"* ]]; then
    echo "  -> Using existing service account: $SERVICE_ACCOUNT"
    SA_EMAIL="$SERVICE_ACCOUNT"
else
    SA_NAME="$SERVICE_ACCOUNT"
    SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  -> Checking for service account: $SA_EMAIL"
    if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &> /dev/null; then
        echo "✅ Service account '$SA_EMAIL' already exists."
    else
        echo "🤔 Service account '$SA_EMAIL' not found. Creating it..."
        gcloud iam service-accounts create "$SA_NAME" \
            --display-name="VEO Demo Service Account ($SA_NAME)" \
            --project="$PROJECT_ID"
        if [ $? -ne 0 ]; then
            echo "❌ Error creating service account. Deployment halted."
            exit 1
        fi
        echo "✅ Service account '$SA_EMAIL' created."
    fi
fi

# Grant necessary IAM roles to the service account
echo "🔑 Granting IAM roles to service account..."

echo "  -> Granting Cloud Run Service Agent role to Cloud Build SA..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
    --role="roles/run.serviceAgent" \
    --condition=None --quiet || echo "✅ Role already exists or cannot be added, skipping."

# Grant necessary roles to the default Compute Engine SA for build/deploy
echo "  -> Granting necessary roles to default Compute Engine SA..."
COMPUTE_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
compute_sa_roles_to_grant=(
    "roles/storage.objectViewer"
    "roles/logging.logWriter"
    "roles/artifactregistry.writer"
    "roles/datastore.owner"
    "roles/cloudtasks.admin"
    "roles/aiplatform.admin"
)
for role in "${compute_sa_roles_to_grant[@]}"; do
    echo "    -> Granting $role..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$COMPUTE_SA_EMAIL" \
        --role="$role" \
        --condition=None --quiet || echo "     (Note: Role may have already existed, which is safe to ignore.)"
done

roles_to_grant=(
    "roles/integrations.integrationAdmin"
    "roles/connectors.admin"
    "roles/storage.admin"
    "roles/aiplatform.admin"
    "roles/cloudtasks.admin"
    "roles/cloudbuild.builds.builder"
    "roles/datastore.owner"
)

for role in "${roles_to_grant[@]}"; do
    echo "  -> Granting $role..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" \
        --condition=None --quiet
    if [ $? -ne 0 ]; then
        # This command can fail if the role is already present, so we check stderr.
        # We can ignore the error if it's just a conflict.
        echo "   (Note: Role may have already existed, which is safe to ignore.)"
    fi
done

echo "✅ All necessary IAM roles granted."

# Verify or create Firestore database
echo "🗂️ Verifying Firestore database..."
if gcloud firestore databases describe --database="$STATE_DB" --project="$PROJECT_ID" &> /dev/null; then
    echo "✅ Firestore database '$STATE_DB' already exists."
else
    echo "🤔 Firestore database '$STATE_DB' not found. Creating it in Native mode..."
    gcloud firestore databases create --database="$STATE_DB" --location="$REGION" --type=firestore-native --project="$PROJECT_ID"
    if [ $? -ne 0 ]; then
        echo "❌ Error creating Firestore database. Deployment halted."
        exit 1
    fi
    echo "✅ Firestore database '$STATE_DB' created."
fi

# Verify or create Cloud Tasks queue
echo "📨 Verifying Cloud Tasks queue..."
if gcloud tasks queues describe "$QUEUE_NAME" --location="$REGION" --project="$PROJECT_ID" &> /dev/null; then
    echo "✅ Cloud Tasks queue '$QUEUE_NAME' already exists."
else
    echo "🤔 Cloud Tasks queue '$QUEUE_NAME' not found. Creating it..."
    gcloud tasks queues create "$QUEUE_NAME" \
        --location="$REGION" \
        --max-attempts=3 \
        --max-dispatches-per-second=0.167 \
        --max-concurrent-dispatches=5 \
        --http-oauth-service-account-email-override="$SA_EMAIL" \
        --http-oauth-token-scope-override="https://www.googleapis.com/auth/cloud-platform" \
        --min-backoff=10s \
        --max-backoff=300s \
        --max-doublings=3 \
        --project="$PROJECT_ID"
    if [ $? -ne 0 ]; then
        echo "❌ Error creating Cloud Tasks queue. Deployment halted."
        exit 1
    fi
    echo "✅ Cloud Tasks queue '$QUEUE_NAME' created."
fi

# Verify or create GCS Bucket
echo "🪣 Verifying GCS bucket..."
if gcloud storage buckets describe "$GCS_BUCKET_URI" --project="$PROJECT_ID" &> /dev/null; then
    echo "✅ GCS bucket '$GCS_BUCKET_URI' already exists."
else
    echo "🤔 GCS bucket '$GCS_BUCKET_URI' not found. Creating it..."
    gcloud storage buckets create "$GCS_BUCKET_URI" -l "$REGION" --project="$PROJECT_ID"
    if [ $? -ne 0 ]; then
        echo "❌ Error creating GCS bucket. Deployment halted."
        exit 1
    fi
    echo "✅ GCS bucket '$GCS_BUCKET_URI' created."
fi

# Prepare Application Integration configuration
echo "📝 Updating Application Integration configuration..."

echo "Installing integrationcli ..."
curl -L https://raw.githubusercontent.com/GoogleCloudPlatform/application-integration-management-toolkit/main/downloadLatest.sh | sh -
export PATH=$PATH:$HOME/.integrationcli/bin

if [ -z "$TOKEN" ]; then
  TOKEN=$(gcloud auth print-access-token)
fi

integrationcli prefs set --reg="$REGION" --proj="$PROJECT_ID" -t "$TOKEN"

CONFIG_FILE="veo-architecture/dev/config-variables/veo-architecture-config.json"

# Detect OS for sed compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_IN_PLACE_FLAG="-i ''"
else
    SED_IN_PLACE_FLAG="-i"
fi

# Substitute placeholders with environment variable values directly in the config file
sed $SED_IN_PLACE_FLAG "s|#QUEUE_NAME#|$QUEUE_NAME|g" "$CONFIG_FILE"
sed $SED_IN_PLACE_FLAG "s|#STATE_COLLECTION#|$STATE_COLLECTION|g" "$CONFIG_FILE"
sed $SED_IN_PLACE_FLAG "s|#STATE_DB#|$STATE_DB|g" "$CONFIG_FILE"

echo "✅ Application Integration configuration updated."

# Prepare Gemini V2 configuration
echo "📝 Updating Gemini V2 configuration..."

GEMINI_CONFIG_FILE="gemini-v2/dev/config-variables/gemini-v2-config.json"

# Substitute placeholders with environment variable values directly in the config file
sed $SED_IN_PLACE_FLAG "s|#PROJECT_ID#|$PROJECT_ID|g" "$GEMINI_CONFIG_FILE"
sed $SED_IN_PLACE_FLAG "s|#REGION#|$REGION|g" "$GEMINI_CONFIG_FILE"

echo "✅ Gemini V2 configuration updated."

# Prepare VEO3 configuration
echo "📝 Updating VEO3 configuration..."

VEO3_CONFIG_FILE="veo3/dev/config-variables/veo3-config.json"
VEO3_OVERRIDES_FILE="veo3/dev/overrides/overrides.json"

# Substitute placeholders with environment variable values directly in the config file
sed $SED_IN_PLACE_FLAG "s|#STATE_COLLECTION#|$STATE_COLLECTION|g" "$VEO3_CONFIG_FILE"
sed $SED_IN_PLACE_FLAG "s|#STATE_DB#|$STATE_DB|g" "$VEO3_CONFIG_FILE"
sed $SED_IN_PLACE_FLAG "s|#SERVICE_ACCOUNT#|$SA_EMAIL|g" "$VEO3_OVERRIDES_FILE"

echo "✅ VEO3 configuration updated."

# Prepare Poll VEO configuration
echo "📝 Updating Poll VEO configuration..."

POLL_VEO_OVERRIDES_FILE="poll-veo/dev/overrides/overrides.json"

# Substitute placeholders with environment variable values directly in the config file
sed $SED_IN_PLACE_FLAG "s|#SERVICE_ACCOUNT#|$SA_EMAIL|g" "$POLL_VEO_OVERRIDES_FILE"

echo "✅ Poll VEO configuration updated."

# Prepare Add Task Queue configuration
echo "📝 Updating Add Task Queue configuration..."

ADD_TASK_QUEUE_OVERRIDES_FILE="add-task-queue/dev/overrides/overrides.json"

# Substitute placeholders with environment variable values directly in the config file
sed $SED_IN_PLACE_FLAG "s|#SERVICE_ACCOUNT#|$SA_EMAIL|g" "$ADD_TASK_QUEUE_OVERRIDES_FILE"

echo "✅ Add Task Queue configuration updated."

# --- Deploy Application Integration assets --- #
echo "🚀 Deploying Application Integration assets..."

# Deploy gemini-v2 integration
echo "  -> Deploying gemini-v2..."
(cd gemini-v2 && integrationcli integrations apply -f . -e dev --wait=true -g)
if [ $? -ne 0 ]; then
    echo "❌ Error deploying gemini-v2 integration. Deployment halted."
    exit 1
fi
echo "✅ gemini-v2 integration deployed."

# Deploy veo3 integration
echo "  -> Deploying veo3..."
(cd veo3 && integrationcli integrations apply -f . -e dev --wait=true -g)
if [ $? -ne 0 ]; then
    echo "❌ Error deploying veo3 integration. Deployment halted."
    exit 1
fi
echo "✅ veo3 integration deployed."

# Deploy add-task-queue integration
echo "  -> Deploying add-task-queue..."
(cd add-task-queue && integrationcli integrations apply -f . -e dev --wait=true -g)
if [ $? -ne 0 ]; then
    echo "❌ Error deploying add-task-queue integration. Deployment halted."
    exit 1
fi
echo "✅ add-task-queue integration deployed."

# Deploy firestore integration
echo "  -> Deploying firestore..."
(cd firestore && integrationcli integrations apply -f . -e dev --wait=true -g)
if [ $? -ne 0 ]; then
    echo "❌ Error deploying firestore integration. Deployment halted."
    exit 1
fi
echo "✅ firestore integration deployed."

# Deploy poll-veo integration
echo "  -> Deploying poll-veo..."
(cd poll-veo && integrationcli integrations apply -f . -e dev --wait=true -g)
if [ $? -ne 0 ]; then
    echo "❌ Error deploying poll-veo integration. Deployment halted."
    exit 1
fi
echo "✅ poll-veo integration deployed."

# Deploy veo-architecture integration
echo "  -> Deploying veo-architecture..."
(cd veo-architecture && integrationcli integrations apply -f . -e dev --wait=true -g)
if [ $? -ne 0 ]; then
    echo "❌ Error deploying veo-architecture integration. Deployment halted."
    exit 1
fi
echo "✅ veo-architecture integration deployed."

# --- Deploy Web App (Optional) --- #
echo "🌐 The backend infrastructure and integrations are now deployed."
read -p "Do you want to deploy the Python web application to Cloud Run as well? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Deploying Python web application..."
    ./src/deploy.sh
    if [ $? -ne 0 ]; then
        echo "❌ Error deploying Python web application. Deployment halted."
        exit 1
    fi
    echo "✅ Python web application deployed."
else
    echo "⏩ Skipping web application deployment."
fi

echo "🎉 All deployments complete!"
