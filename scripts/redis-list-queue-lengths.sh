#!/usr/bin/env bash

redis-cli -a redis -n 15 --scan | while read key; do
  type=$(redis-cli -a redis -n 15 TYPE "$key" 2>/dev/null)
  if [ "$type" = "list" ]; then
    len=$(redis-cli -a redis -n 15 LLEN "$key" 2>/dev/null)
    echo "$len  $key"
  fi
done | sort -rn
