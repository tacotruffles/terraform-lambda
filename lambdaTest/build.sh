#!/bin/bash

# if [  -z "$1" ] 
# then 
#   FILE_NAME="layer.zip"
# else 
#   FILE_NAME="$1.zip"
# fi

# Ensure build folder for Terraform
mkdir ../build

# Install Python Dependencies
rm -rf ../build/$1
pip install -r requirements.txt -t ../build/$1
cp * ../build/$1
echo "../build/$1"

# Terraform Handles ZIPing build folders contents