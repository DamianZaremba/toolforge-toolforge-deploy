#!/usr/bin/env bats
# bats file_tags=tools,volume-admission,smoke


set -o nounset

setup() {
    load "../../global-common"
    _global_setup
}


setup_file() {
    # cleanup just in case
    toolforge jobs flush 2>/dev/null || :
}


@test "modify a job to mount some non-allowed path makes pods fail to start" {
    rand_string="test-$RANDOM"
    # start a job and make sure it ran
    toolforge \
        jobs \
        run \
        --continuous \
        --command="while true; do echo '$rand_string' | tee \$TOOL_DATA_DIR/$rand_string.out; done" \
        --mount=all \
        --image="python3.11" \
        "$rand_string"

    retry "grep '$rand_string' '$HOME/$rand_string.out'"

    # Modify the deployment to add extra mount, and force a restart
    kubectl patch deployment "$rand_string" \
        --type='json' \
        -p='[
            {
                "op": "add",
                "path": "/spec/template/spec/volumes",
                "value": []
            },
            {
                "op": "add",
                "path": "/spec/template/spec/volumes/-",
                "value": {
                    "name": "sneaky-mount",
                    "hostPath": {
                        "type": "Directory",
                        "path": "/var/log"
                    }
                }
            }, {
                "op": "add",
                "path": "/spec/template/spec/containers/0/volumeMounts",
                "value": []
            }, {
                "op": "add",
                "path": "/spec/template/spec/containers/0/volumeMounts/-",
                "value": {
                    "name": "sneaky-mount",
                    "mountPath": "/worker_logs"
                }
            }
        ]'

    # ensure the pod is failing to start up due to the volume admission controller
    retry "kubectl get deployment '$rand_string' -o json \
        | jq '.status.conditions[].message' \
        | grep 'No hostPath volumes allowed'"
}


@test "adding a volume called 'home' with the wrong path is not allowed" {
    rand_string="test-$RANDOM"
    # start a job and make sure it ran
    toolforge \
        jobs \
        run \
        --continuous \
        --command="while true; do echo '$rand_string' | tee \$TOOL_DATA_DIR/$rand_string.out; done" \
        --mount=all \
        --image="python3.11" \
        "$rand_string"

    retry "grep '$rand_string' '$HOME/$rand_string.out'"

    # Modify the deployment to add extra mount, and force a restart
    kubectl patch deployment "$rand_string" \
        --type='json' \
        -p='[
            {
                "op": "add",
                "path": "/spec/template/spec/volumes",
                "value": []
            },
            {
                "op": "add",
                "path": "/spec/template/spec/volumes/-",
                "value": {
                    "name": "home",
                    "hostPath": {
                        "type": "Directory",
                        "path": "/var/log"
                    }
                }
            }, {
                "op": "add",
                "path": "/spec/template/spec/containers/0/volumeMounts",
                "value": []
            }, {
                "op": "add",
                "path": "/spec/template/spec/containers/0/volumeMounts/-",
                "value": {
                    "name": "home",
                    "mountPath": "/worker_logs"
                }
            }
        ]'

    # ensure the pod is failing to start up due to the volume admission controller
    retry "kubectl get deployment '$rand_string' -o json \
        | jq '.status.conditions[].message' \
        | grep 'No hostPath volumes allowed'"
}


teardown() {
    _global_teardown
}
