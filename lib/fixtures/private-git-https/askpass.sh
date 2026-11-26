#!/bin/sh
# shellcheck shell=sh disable=SC2154 # CRED_LOG comes from the test that runs git
printf 'prompt: %s\n' "$1" >>"$CRED_LOG"
