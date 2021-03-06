#!/usr/bin/env bash

CORDA_JAR_NAME="corda.jar"
DOORMAN_CN_TO_USE=${DOORMAN_CN:-BasicDoorman}
NETWORKMAP_CN_TO_USE=${NETWORKMAP_CN:-BasicNetworkMap}

rm -rf notary
rm -rf spring-boot-network-map

(
  mkdir notary
  cd notary || exit

  if [[ ! -f ${CORDA_JAR_NAME} ]]; then
    wget -O ${CORDA_JAR_NAME} https://ci-artifactory.corda.r3cev.com/artifactory/corda-releases/net/corda/corda/4.0/corda-4.0.jar
  fi

  cat >node.conf <<EOT
myLegalName="O=Notary Service,L=London,C=GB"
notary {
    validating=false
}
p2pAddress="${PUBLIC_ADDRESS}:10200"
rpcSettings {
    address="localhost:10003"
    adminAddress="localhost:10004"
}
detectPublicIp=false
rpcUsers=[]
devMode=true
compatibilityZoneURL="http://${PUBLIC_ADDRESS}:8080"
devModeOptions{
    allowCompatibilityZone=true
}
EOT

  java -jar ${CORDA_JAR_NAME} generate-node-info
)

(
  git clone https://github.com/roastario/spring-boot-network-map.git
  cd spring-boot-network-map || exit
  ./gradlew clean build
  cp build/libs/spring-boot-network-map-1.0-SNAPSHOT.jar ../nms.jar
)

java -Djava.security.egd=file:/dev/urandom -jar nms.jar --nodesDirectoryUrl=file:notary/ --doormanCN="${DOORMAN_CN_TO_USE}" --networkMapCN="${NETWORKMAP_CN_TO_USE}" &
NMS_PID=$!

let EXIT_CODE=255
while [ ${EXIT_CODE} -gt 0 ]; do
  sleep 2
  echo "Waiting for network map to start"
  wget -t 1 -O /dev/null http://localhost:8080/network-map
  let EXIT_CODE=$?
done

(
  cd notary || exit

  cat >run-node.sh <<EOF
while :
do
  rm -f network-parameters
  java -jar corda.jar
done
EOF

  screen -dmS notary-node bash run-node.sh
  NOTARY_PID=$!

  echo "Started notary with PID=${NOTARY_PID}"
  echo "Started nms with PID=${NMS_PID}"

  function ctrl_c() {
    echo "Killing notary ${NOTARY_PID}"
    kill ${NOTARY_PID}
    wait ${NOTARY_PID}
    echo "Killing network-map-service ${NOTARY_PID}"
    kill ${NMS_PID}
    wait ${NMS_PID}
    kill $$
  }

  # trap ctrl-c and call ctrl_c()
  trap ctrl_c INT

  while :; do
    sleep 1
  done
)
