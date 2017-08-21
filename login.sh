#!/bin/bash

kubectl run login \
    --image=kyechou/pause:latest-dev \
    --restart=Never \
    --overrides='{
                "apiVersion": "v1",
                    "spec": {
                        "containers": [{
                            "name": "login",
                            "image": "kyechou/pause:latest-dev",
                            "volumeMounts": [{
                                "mountPath": "/mnt",
                                "name": "volume1"
                            }]
                        }],
                        "volumes": [{
                            "name": "volume1",
                            "nfs": {
                                "server": "nfs-server",
                                "path": "/..."
                            }
                        }]
                    }
                }' -- pause >/dev/null
until [ "$(kubectl get pod login -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ]; do :; done

kubectl exec login -it -- bash -il

kubectl delete pod login >/dev/null
until ! kubectl get pod login &>/dev/null; do :; done

# vim: set ts=4 sw=4 et :
