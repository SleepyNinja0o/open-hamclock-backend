#!/bin/bash
# This script reads .env and prints it in Lighttpd config format

echo "setenv.set-environment = ("

while IFS='=' read -r key value; do
  # Skip comments and empty lines
  [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
  echo "  \"$key\" => \"$value\","
done < /opt/hamclock-backend/.env

echo ")"

