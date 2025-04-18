#!/bin/bash

# Remove old packages folder
if [ -d "Packages" ]; then
    rm -rf ./Packages
fi
if [ -d "DevPackages" ]; then
    rm -rf ./DevPackages
fi
if [ -d "ServerPackages" ]; then
    rm -rf ./ServerPackages
fi

# Install packages
wally install

if [ ! -d "Packages" ]; then
    mkdir "Packages"
fi
if [ ! -d "DevPackages" ]; then
    mkdir "DevPackages"
fi
if [ ! -d "ServerPackages" ]; then
    mkdir "ServerPackages"
fi

# Sourcemap generation
rojo sourcemap --output sourcemap.json default.project.json
