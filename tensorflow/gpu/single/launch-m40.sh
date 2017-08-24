#!/bin/bash
set -e

MODELS=(vgg16
        vgg19
        lenet
        googlenet
        alexnet
        trivial
        inception3
        inception4
        resnet50
        resnet152
)
UPDATES=(parameter_server replicated)
NGPUS=(1)
BATCHES=(16 32 64 128)

for MODEL in ${MODELS[@]}
do
    for UPDATE in ${UPDATES[@]}
    do
        for NGPU in ${NGPUS[@]}
        do
            for BATCH in ${BATCHES[@]}
            do
                [ "${MODEL}" = "inception3" -a ${BATCH} -ge 128 ] && continue
                [ "${MODEL}" = "inception4" -a ${BATCH} -ge 64 ] && continue
                [ "${MODEL}" = "resnet152" -a ${BATCH} -ge 64 ] && continue
                cat m40.yaml | \
                    sed -e "s/\$MODEL/${MODEL}/g" \
                        -e "s/\$UPDATE/${UPDATE}/" \
                        -e "s/\$NGPU/${NGPU}/" \
                        -e "s/\$BATCH/${BATCH}/" | \
                    kubectl create -f -
                until [ "$(kubectl get job -n user tensorflow-m40 -o jsonpath='{.status.succeeded}' 2>/dev/null)" = "1" ]; do :; done
                cat m40.yaml | \
                    sed -e "s/\$MODEL/${MODEL}/g" \
                        -e "s/\$UPDATE/${UPDATE}/" \
                        -e "s/\$NGPU/${NGPU}/" \
                        -e "s/\$BATCH/${BATCH}/" | \
                    kubectl delete -f -
                until ! kubectl get job -n user tensorflow-m40 &>/dev/null; do :; done
            done
        done
    done
done

# vim: set ts=4 sw=4 et :
