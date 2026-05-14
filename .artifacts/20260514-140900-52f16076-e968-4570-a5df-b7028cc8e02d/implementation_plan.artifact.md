# Implementation Plan - Live Video Watermark Upgrade

Upgrade the video recording feature to include a live, updating watermark in the recorded video file. This will ensure that time, coordinates, and other metadata change in the video as they changed during recording.

## User Review Required

> [!IMPORTANT]
> - **Processing Time**: Generating a live watermark for a video is more computationally intensive than a static one. For a 30-second video, it may take 10-20 seconds to process on a modern device.
> - **Storage**: Temporary image files will be generated during processing and then deleted. This requires some free space (~50-100MB for a 1-minute video).

## Proposed Changes

### Camera Feature

#### [CameraState.dart](file:///C:/Users/baish/Downloads/siteSnap/lib/features/camera/data/CameraState.dart)
- Add `videoDataHistory` to store `OverlayData` samples during recording.

#### [camera_viewmodel.dart](file:///C:/Users/baish/Downloads/siteSnap/lib/features/camera/presentation/camera_viewmodel.dart)
- Implement a 1-second timer during video recording to sample `OverlayData`.
- Store samples in `videoDataHistory`.
- Update `stopVideoRecording` to pass the entire history to the processor.

---

### Overlay Feature

#### [video_watermark_processor.dart](file:///C:/Users/baish/Downloads/siteSnap/lib/features/overlay/presentation/video_watermark_processor.dart)
- Update `applyOverlayToVideo` to accept a list of `OverlayData` instead of a single `Uint8List`.
- Implement `generateVideoOverlaySequence` to create a series of PNG files.
- Update FFmpeg command to use `-framerate 1 -i temp_overlay_%d.png` for overlaying.

---

### Core Utilities (Optional but recommended)

#### [datetime_utils.dart](file:///C:/Users/baish/Downloads/siteSnap/lib/core/utils/datetime_utils.dart)
- Ensure formatting is consistent.

## Verification Plan

### Manual Verification
- Start video recording.
- Walk around or rotate the device to change coordinates and direction.
- Wait for recording to finish and process.
- Play the recorded video in the gallery and verify that the watermark updates every second.
- Check that the date/time in the video watermark matches the recording time.
