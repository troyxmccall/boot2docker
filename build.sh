#!/bin/bash

docker build -t boot2docker .
if [ $? -ne 0 ]; then
    echo "Docker build failed. Stopping the script."
    exit 1
fi

docker run --rm boot2docker > boot2docker.iso
#make a backup of the final v19.03.12 release just in case
wget --output-document boot2docker-v19.03.12.iso https://github.com/boot2docker/boot2docker/releases/download/v19.03.12/boot2docker.iso
# stop our machine
docker-machine stop default
# copy our new iso
cp boot2docker.iso ~/.docker/machine/machines/default/
# start back up
docker-machine start default
