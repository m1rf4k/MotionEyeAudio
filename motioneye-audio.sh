#!/usr/bin/env bash

# Set variables
operation=$1
motion_thread_id=$2
file_path=$3
camera_name=$4
audio_codec="acc"
audio_file_extention="acc"

camera_id="$(python -c 'import motioneye.motionctl; print motioneye.motionctl.motion_camera_id_to_camera_id('${motion_thread_id}')')"
motion_config_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
motion_camera_conf="${motion_config_dir}/camera-${camera_id}.conf"
# Below line was a temporary fix replacing camera ID with camera name due to cameraID/thread mismatch - motion_thread_id should fix this
# motion_camera_conf="$( egrep -l \^camera_name.${camera_name} ${motion_config_dir}/*.conf)"
netcam="$(if grep -q 'netcam_highres' ${motion_camera_conf};then echo 'netcam_highres'; else echo 'netcam_url'; fi)"
extension="$(echo ${file_path} | sed 's/^/./' | rev | cut -d. -f1  | rev)"

case ${operation} in
    start)
        credentials="$(grep netcam_userpass ${motion_camera_conf} | sed -e 's/netcam_userpass.//')"
        stream="$(grep ${netcam} ${motion_camera_conf} | sed -e "s/${netcam}.//")"
        full_stream="$(echo ${stream} | sed -e "s/\/\//\/\/${credentials}@/")"
        ffmpeg -y -i "${full_stream}" -c:a ${audio_codec} ${file_path}.${audio_file_extention} 2>&1 1>/dev/null &
        ffmpeg_pid=$!
        echo ${ffmpeg_pid} > /tmp/motion-audio-ffmpeg-camera-${camera_id}
        # echo ${ffmpeg_pid} > /tmp/motion-audio-ffmpeg-camera-${camera_name}
        ;;

    stop)
        # get motion_gap from camera config
        motion_gap="$(grep event_gap ${motion_camera_conf} | sed -e 's/event_gap.//')"
        # Kill the ffmpeg audio recording for the clip
        kill $(cat /tmp/motion-audio-ffmpeg-camera-${camera_id})
        rm -rf $(cat /tmp/motion-audio-ffmpeg-camera-${camera_id})
        # kill $(cat /tmp/motion-audio-ffmpeg-camera-${camera_name})
        # rm -rf $(cat /tmp/motion-audio-ffmpeg-camera-${camera_name})
        # cut the last part of audio file with motion_gap time to avoid sound without image when motion event is over
        ffmpeg -i ${file_path}.${audio_file_extention} -t $(( $(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 ${file_path}.${audio_file_extention} | cut -d\. -f1) - ${motion_gap} )) -acodec copy -vcodec copy ${file_path}-audiotemp.${audio_file_extention}
        mv -f ${file_path}-audiotemp.${audio_file_extention} ${file_path}.${audio_file_extention};
        # Merge the video and audio to a single file, and replace the original video file
        ffmpeg -y -i ${file_path} -i ${file_path}.${audio_file_extention} -c:v copy -c:a copy ${file_path}.temp.${extension};
        mv -f ${file_path}.temp.${extension} ${file_path};
        # Remove audio file after merging
        rm -f ${file_path}.${audio_file_extention};
        ;;

    *)
        echo "Usage ./motioneye-audio.sh start <camera-id> <full-path-to-moviefile>"
        # echo "Usage ./motioneye-audio.sh start <camera-name> <full-path-to-moviefile>"
        exit 1
esac
