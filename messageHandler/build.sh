#!/bin/bash

rm -rf ../build/$1
rm -rf ../build/$1/lib/

# Ensure build folder for Terraform
mkdir -p ../build/$1
mkdir -p ../build/$1/lib

# Install Python Dependencies
pip3 install -r requirements.txt -t ../build/$1/lib/
cp * ../build/$1
echo "../build/$1"
cd ../build

# Terraform Handles ZIPing build folders contents
# zip -r lambda_function.zip *  
