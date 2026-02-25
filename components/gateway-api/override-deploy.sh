#!/bin/sh
exec kubectl apply --server-side -f gateway-api.yaml
