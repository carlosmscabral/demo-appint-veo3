# Web Application Plan

This document outlines the plan for creating a web application that allows users to generate videos using a GCP Application Integration backend.

## 1. Architecture Overview

We will build a single, consolidated web application using a Python web framework like **Flask** and deploy it to **Cloud Run**. This approach simplifies development, deployment, and management by having the frontend and backend logic in the same codebase.

The application will consist of:

*   A **Python backend** (Flask) to handle API requests and communicate with the GCP Application Integration APIs.
*   A **vanilla JavaScript frontend** to provide the user interface and interact with the backend.

The Cloud Run service will be configured with a service account that has the necessary permissions to invoke the Application Integration APIs, simplifying the authentication process.

## 2. Frontend

The frontend will be a single HTML page with JavaScript to handle user interactions.

### UI Components:

*   **Image Upload:** An `<input type="file">` element for the user to select an image from their local machine.
*   **Prompt Input:** A `<textarea>` for the user to enter a text prompt.
*   **GCS URI Input:** An `<input type="text">` for the user to provide a Google Cloud Storage URI.
*   **Submit Button:** A `<button>` to trigger the video generation process.
*   **Status Display:** A `<div>` to show the current status of the video generation (e.g., "Uploading...", "Processing...", "Done!", "Error").
*   **Video Player:** A `<video>` element to display the generated video.

### JavaScript Logic:

1.  **Form Submission:**
    *   On submit, the JavaScript will prevent the default form submission.
    *   It will read the selected image file and convert it to a base64 encoded string.
    *   It will get the image's MIME type from the file object.
    *   It will gather the prompt text and the GCS URI from the input fields.
2.  **API Interaction:**
    *   It will send a `POST` request to a backend endpoint (e.g., `/generate-video`) with the image base64, prompt, MIME type, and GCS URI.
    *   The backend will respond with a `uuid`.
3.  **Polling:**
    *   Once the `uuid` is received, the frontend will start polling a backend status endpoint (e.g., `/status/<uuid>`) every 30 seconds.
    *   The polling will continue until the status is "done" or "error".
4.  **Displaying Results:**
    *   If the status is "done", the frontend will receive the GCS URI of the generated video and set it as the `src` of the video player.
    *   If the status is "error", it will display an error message to the user.

## 3. Backend (Flask)

The backend will be a simple Flask application with three main endpoints.

### Endpoints:

*   **`GET /`**:
    *   This endpoint will serve the main `index.html` file.
*   **`POST /generate-video`**:
    *   This endpoint will receive the `imageBase64`, `prompt`, `imageMimeType`, and `storageURI` from the frontend.
    *   It will use the Google API Python client library to call the first Application Integration API (`cabral-veo-architecture_reqVideo`).
    *   It will return the `uuid` from the API response to the frontend.
*   **`GET /status/<uuid>`**:
    *   This endpoint will be used for polling.
    *   It will call the second Application Integration API (`cabral-veo-architecture_polling`) with the provided `uuid`.
    *   It will return the status response (`{"status": "...", "gcsURI": "..."}` or `{"status": "..."}`) to the frontend.

## 4. Authentication

*   **Frontend-to-Backend:** No authentication will be implemented between the frontend and the backend for this simple application.
*   **Backend-to-GCP:** The Cloud Run service will be deployed with a dedicated service account. This service account will have the "roles/integrations.invoker" IAM role to allow it to call the Application Integration APIs. The Python client libraries will automatically use the credentials of this service account when running on Cloud Run.

## 5. User Experience

*   The UI will be kept clean and simple.
*   The application will provide real-time feedback to the user about the status of the video generation process.
*   A loading indicator will be displayed while the video is being processed.
*   Error messages will be user-friendly.
*   The final video will be playable directly in the browser.

## 6. Proposed Project Structure

```
.
├── src/
│   ├── PLAN.md
│   ├── app.py           # Flask application
│   ├── requirements.txt # Python dependencies
│   ├── static/
│   │   ├── css/
│   │   │   └── style.css
│   │   └── js/
│   │       └── script.js
│   └── templates/
│       └── index.html
└── ...
```
