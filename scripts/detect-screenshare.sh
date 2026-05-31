#!/bin/bash
# Detects active screen sharing by checking PipeWire for video input streams
# that are not webcam devices
while true; do
  count=$(pw-dump 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    count = 0
    for obj in data:
        mc = obj.get('info',{}).get('props',{}).get('media.class','')
        name = obj.get('info',{}).get('props',{}).get('node.name','')
        if 'Stream/Input/Video' in mc and 'v4l2' not in name and 'camera' not in name.lower():
            count += 1
    print(count)
except:
    print(0)
" 2>/dev/null)
  echo "${count:-0}"
  sleep 2
done
