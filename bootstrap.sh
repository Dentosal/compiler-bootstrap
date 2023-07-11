#!/bin/sh -eu

cd bootstrap_asm
nasm -f bin -o ../bootstrap bootstrap.asm && chmod +x ../bootstrap
cd ..
./bootstrap input.txt output.txt
