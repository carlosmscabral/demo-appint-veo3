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

echo "📦 Setting up GCP environment variables..."

# Set your Google Cloud project ID
export PROJECT_ID="dynolab-153020"

# Set the default region for your GCP resources
export REGION="us-east1"


# Set the Cloud Run service name
export SERVICE_NAME="veo-app"

# Set the service account for the Cloud Run service
export SERVICE_ACCOUNT="532862411978-compute@developer.gserviceaccount.com"

# Set the queue name
export QUEUE_NAME="<your-queue-name>"

# Set the state collection name
export STATE_COLLECTION="<your-state-collection>"

# Set the state database name
export STATE_DB="<your-state-db>"

echo "✅ GCP environment variables set."
echo "PROJECT_ID: $PROJECT_ID"
echo "REGION: $REGION"
echo "SERVICE_NAME: $SERVICE_NAME"
echo "SERVICE_ACCOUNT: $SERVICE_ACCOUNT"
echo "QUEUE_NAME: $QUEUE_NAME"
echo "STATE_COLLECTION: $STATE_COLLECTION"
echo "STATE_DB: $STATE_DB"

gcloud config set project $PROJECT_ID