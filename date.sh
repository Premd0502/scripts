#!/bin/bash
now=$(date +"%d-%m-%Y")
if [ -d "/opt/jbooks/$now" ]; then
                echo "download  directory .. OK"
        else
                    mkdir /opt/jbooks/$now
                    chmod -R 777 /opt/jbooks/$now
        fi
