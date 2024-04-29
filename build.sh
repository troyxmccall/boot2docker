#!/bin/bash

docker build -t boot2docker .
if [ $? -ne 0 ]; then
    echo "Docker build failed. Stopping the script."
    exit 1
fi

docker run --rm boot2docker > boot2docker.iso
# stop our machine
docker-machine stop default
# copy our new iso
cp boot2docker.iso ~/.docker/machine/machines/default/
# start back up
docker-machine start default
