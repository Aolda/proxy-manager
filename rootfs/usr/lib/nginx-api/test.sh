#!/bin/sh
output=$(nginx -t 2>&1)
status=$?

if [ $status -eq 0 ]; then
  echo "Status: 200 OK"
  echo "Content-Type: text/plain"
  echo ""
  echo "$output"
else
  echo "Status: 500 Internal Server Error"
  echo "Content-Type: text/plain"
  echo ""
  echo "$output"
fi