#!/bin/sh
umask 022
set -e
cd "$(dirname "$0")"
make clean all CONFIGURATION=Release ARCHS=x86_64
make clean all CONFIGURATION=Debug ARCHS=x86_64
make clean

