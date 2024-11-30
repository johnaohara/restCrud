#!/bin/bash
#set -eux

trap shutdown SIGKILL SIGTERM SIGINT

CID=
ITERATIONS=10

shutdown() {
  cleanup
  exit 1  
}

kill_loop(){
  pgrep loop.sh | xargs kill -15
}

cleanup()
{
  echo ""
  echo "Cleaning up resources:"
  podman kill $CID
  podman rm $CID
}

declare -r IMAGE=${1}

echo "Testing ${IMAGE}"

if [[ ${2} == 1 ]] 
then
  CPUS="2"
else
  LAST_CPU=$((2 + ${2} -1 ))
  CPUS="2-${LAST_CPU}"	
fi

kill_loop

echo "CPUS=${CPUS}"

for i in $(seq 1 $ITERATIONS)
do
  sleep 2
  
  echo "" > output2

  ./loop.sh rest_crud &
  LOOP_PID=$!

  CID=$(podman run --privileged -d --net=host --memory=1g --cpuset-cpus ${CPUS} ${IMAGE})
  sleep 5
  # Wait for container application to start listening on port 9090, timeout wait after 5s
  # timeout 5s /bin/bash -c "until /usr/sbin/ss -tnl sport = :9090 | grep -q LISTEN; do sleep 0.1 || exit; done"
  podman logs ${CID}

  # Grab First Response
  FR_TIME="$(head -1 output2)" # from loop.sh
  let stopMillis=$(date "+%s%N" -d "${FR_TIME}")/1000000

  #use docker inspect to get start time
  time2=$(podman inspect ${CID} | grep StartedAt | awk '{print $2}'| awk '{gsub("\"", " "); print $1}'| awk '{gsub("T"," "); print}'|awk '{print substr($0, 1, length($0)-6)}')
  time2="$time2 $( date "+%z")"
  #echo "start time"
  echo $time2
  echo $FR_TIME
  let startMillis=$(date "+%s%N" -d "$time2")/1000000
  let sutime=${stopMillis}-${startMillis}
  echo "First Response Time in ms: $sutime"

  sleep 5
  PID=$(ps -ef | grep java | grep -v grep | awk '{print $2}' | tail -1)
  FP=$(ps -o rss= ${PID} | numfmt --from-unit=1024 --to=iec | awk '{gsub("M"," "); print $1}')
  FP2=$(cat /proc/${PID}/smaps | grep 'Rss' | awk '{total+=$2;} END{print total;}' | numfmt --from-unit=1024 --to=iec | awk '{gsub("M"," "); print $1}')
  #echo "Footprint in MB:        : $FP"
  echo "Footprint in MB:        : $FP2"

  cleanup

done

kill_loop

exit 0