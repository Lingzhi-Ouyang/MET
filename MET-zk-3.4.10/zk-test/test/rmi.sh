#!/bin/bash

rmiregistry 2599 -J-Djava.rmi.server.codebase=file:///../api/target/api-1.0-SNAPSHOT.jar &
