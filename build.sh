#!/bin/bash

docker build -t boot2docker . && docker run —rm boot2docker > boot2docker.iso
