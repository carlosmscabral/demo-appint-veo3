document.addEventListener("DOMContentLoaded", () => {
    const form = document.getElementById("video-form");
    const statusDiv = document.getElementById("status");
    const videoPlayer = document.getElementById("video-player");

    form.addEventListener("submit", async (e) => {
        e.preventDefault();

        const formData = new FormData(form);
        const imageFile = formData.get("image");
        const prompt = formData.get("prompt");
        const gcsUri = formData.get("gcs-uri");

        if (!imageFile || !prompt || !gcsUri) {
            statusDiv.textContent = "Please fill out all fields.";
            return;
        }

        statusDiv.textContent = "Uploading and processing...";
        videoPlayer.style.display = "none";

        const reader = new FileReader();
        reader.readAsDataURL(imageFile);
        reader.onload = async () => {
            const imageBase64 = reader.result.split(",")[1];
            const imageMimeType = imageFile.type;

            try {
                const response = await fetch("/generate-video", {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({
                        imageBase64,
                        prompt,
                        imageMimeType,
                        gcsUri,
                    }),
                });

                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }

                const data = await response.json();
                const { uuid } = data;

                statusDiv.textContent = `Processing... UUID: ${uuid}`;

                // Start polling for status
                pollStatus(uuid);

            } catch (error) {
                console.error("Error:", error);
                statusDiv.textContent = "An error occurred.";
            }
        };
    });

    async function pollStatus(uuid) {
        const interval = setInterval(async () => {
            try {
                const response = await fetch(`/status/${uuid}`);
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }

                const data = await response.json();

                if (data.status === "done") {
                    clearInterval(interval);
                    statusDiv.textContent = "Video generated!";
                    videoPlayer.src = data.gcsURI;
                    videoPlayer.style.display = "block";
                } else if (data.status === "error") {
                    clearInterval(interval);
                    statusDiv.textContent = "An error occurred during video generation.";
                } else {
                    statusDiv.textContent = `Processing... Status: ${data.status}`;
                }
            } catch (error) {
                clearInterval(interval);
                console.error("Error polling status:", error);
                statusDiv.textContent = "An error occurred while polling for status.";
            }
        }, 30000); // Poll every 30 seconds
    }
});
