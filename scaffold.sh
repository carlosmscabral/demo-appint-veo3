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

echo "🚀 Starting project scaffolding..."

echo "Installing integrationcli ..."
curl -L https://raw.githubusercontent.com/GoogleCloudPlatform/application-integration-management-toolkit/main/downloadLatest.sh | sh -
export PATH=$PATH:$HOME/.integrationcli/bin


source ./env.sh

if [ -z "$PROJECT_ID" ]; then
  echo "No PROJECT_ID variable set"
  exit
fi

if [ -z "$REGION" ]; then
  echo "No REGION variable set"
  exit
fi

if [ -z "$TOKEN" ]; then
  TOKEN=$(gcloud auth print-access-token)
fi

integrationcli prefs set --reg="$REGION" --proj="$PROJECT_ID" -t "$TOKEN"

cd veo-architecture/
integrationcli integrations scaffold -n cabral-veo-architecture -e dev

cd ../gemini-v2/
integrationcli integrations scaffold -n cabral-gemini-v2 -e dev

cd ../veo-3/
integrationcli integrations scaffold -n cabral-veo3 -e dev

cd ../add-task-queue/
integrationcli integrations scaffold -n cabral-add-task-queue -e dev

cd ../poll-veo/
integrationcli integrations scaffold -n cabral-poll-veo -e dev

cd ../firestore/
integrationcli integrations scaffold -n cabral-firestore -e dev




