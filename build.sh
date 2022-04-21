#!/bin/bash

docker build -t boot2docker/boot2docker:base base/
docker build -t boot2docker/boot2docker-rootfs rootfs/
docker rm build-boot2docker
# you will need more than 2GB memory for the next step
docker run --name build-boot2docker boot2docker/boot2docker-rootfs
docker cp build-boot2docker:/boot2docker.iso