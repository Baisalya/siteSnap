# Walkthrough - Live Video Watermark Upgrade

I have implemented a major upgrade to the video recording feature. The watermark in the recorded videos now updates **live** every second, reflecting real-time changes in location, time, and direction.

## Changes Made

### 1. Data Tracking during Recording
- **CameraState**: Added `videoDataHistory` to store a list of metadata snapshots.
- **CameraViewModel**: Introduced a `Timer` that triggers every second while recording video. Each tick captures the current `OverlayData` (GPS, Compass, Time) and saves it to the history list.

### 2. Dynamic Overlay Processing
- **VideoWatermarkProcessor**:
    - Added `generateVideoOverlaySequence`: This function generates a sequence of PNG images (one for each second of the video) based on the tracked history.
    - Added `applyOverlaySequenceToVideo`: Uses FFmpeg to map the image sequence onto the video. It uses the `-framerate 1` input flag to ensure each image stays on screen for exactly one second, matching the capture rate.

### 3. Cleanup & Optimization
- The temporary image sequence directory is automatically deleted after processing to save device storage.
- Maintained `ultrafast` FFmpeg presets to keep processing times as low as possible for long recordings.

## Verification Summary
- **Code Review**: Verified that the timer starts exactly when recording begins and stops/cancels when recording ends (including cases like switching cameras or errors).
- **FFmpeg Logic**: The command `[1:v]setpts=PTS-STARTPTS` ensures the overlay sequence starts at the beginning of the video and stays synchronized.

## How to Test
1. Open the app and switch to **VIDEO** mode.
2. Start recording.
3. While recording, move around to change your GPS coordinates or rotate the phone to change the compass direction.
4. Stop recording and wait for the "Processing video..." notification to finish.
5. Open the gallery and watch the video. You will see the coordinates and direction in the watermark updating live!
