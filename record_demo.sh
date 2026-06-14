#!/bin/bash
set -e

echo "=== Pihu Display Demo Recording ==="

# 1. Setup port forwarding
echo "Setting up port forward..."
/opt/homebrew/bin/adb forward tcp:27183 tcp:27183

# 2. Start macOS Host app in background
echo "Launching macOS Host app..."
./mac-host/.build/debug/pihu-display-host > host_capture.log 2>&1 &
HOST_PID=$!

# 3. Launch Android app
echo "Launching Android App..."
/opt/homebrew/bin/adb shell am start -n com.pihu.display/.MainActivity

# 4. Wait for stream to establish
echo "Waiting 5 seconds for connection..."
sleep 5

# 5. Start recordings
echo "Starting screen recording on Android..."
/opt/homebrew/bin/adb shell screenrecord --time-limit 15 /sdcard/android_record.mp4 &
ANDROID_REC_PID=$!

echo "Starting screen recording on macOS..."
/opt/homebrew/bin/ffmpeg -f avfoundation -i "1" -t 15 -pix_fmt yuv420p -r 30 -y mac_record.mp4 > ffmpeg_capture.log 2>&1 &
MAC_REC_PID=$!

# Wait for recordings to finish
echo "Recording in progress... waiting for processes to complete..."
wait $MAC_REC_PID || true
wait $ANDROID_REC_PID || true

# 6. Stop macOS Host app
echo "Stopping macOS Host app..."
kill $HOST_PID || true

# 7. Pull Android recording
echo "Pulling Android recording..."
sleep 1
/opt/homebrew/bin/adb pull /sdcard/android_record.mp4 android_record.mp4

# 8. Combine videos side-by-side
echo "Combining videos side-by-side using FFmpeg..."
/opt/homebrew/bin/ffmpeg -y -i mac_record.mp4 -i android_record.mp4 -filter_complex "[0:v]scale=-1:720[v0];[1:v]scale=-1:720[v1];[v0][v1]hstack=inputs=2[v]" -map "[v]" demo.mp4

# 9. Clean up temporary files
echo "Cleaning up temporary video files..."
rm -f mac_record.mp4 android_record.mp4
/opt/homebrew/bin/adb shell rm /sdcard/android_record.mp4

echo "=== Demo video created successfully as demo.mp4 ==="
