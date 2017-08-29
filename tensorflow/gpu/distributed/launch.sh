#!/bin/bash
set -e

WORKER_NUMS=(2 4 8)
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
UPDATES=(parameter_server distributed_replicated)
BATCHES=(16 32 64 128)

for WORKER_NUM in ${WORKER_NUMS[@]}
do
    PS_NUM=$((${WORKER_NUM} + 2))
    for MODEL in ${MODELS[@]}
    do
        for UPDATE in ${UPDATES[@]}
        do
            NGPU=$((16 / ${WORKER_NUM}))
            for BATCH in ${BATCHES[@]}
            do
                [ ${WORKER_NUM} -le 4 ] && continue
                [ ${WORKER_NUM} -eq 8 -a "${MODEL}" = "vgg16" -a ${BATCH} -le 64 ] && continue
                [ "${MODEL}" = "inception4" -a ${BATCH} -ge 128 ] && continue
                [ "${MODEL}" = "resnet152" -a ${BATCH} -ge 128 ] && continue
                echo "Launching: ${PS_NUM}-ps:${WORKER_NUM}-worker/${MODEL}/${UPDATE}/${NGPU}-${BATCH}"

                ###########################################
                # make the PS_HOSTS variable
                ###########################################

                PS_HOSTS=""
                PS_IDX=0
                while [ ${PS_IDX} -lt ${PS_NUM} ]
                do
                    PS_HOSTS="${PS_HOSTS:+${PS_HOSTS},}tf-ps${PS_IDX}.user.svc.cluster.local:5000"
                    PS_IDX=$((${PS_IDX} + 1))
                done
                #echo "PS_HOSTS:"
                #echo "${PS_HOSTS}"

                ###########################################
                # make the WORKER_HOSTS variable
                ###########################################

                WORKER_HOSTS=""
                TASK_IDX=0
                while [ ${TASK_IDX} -lt ${WORKER_NUM} ]
                do
                    WORKER_HOSTS="${WORKER_HOSTS:+${WORKER_HOSTS},}tf-worker${TASK_IDX}.user.svc.cluster.local:5000"
                    TASK_IDX=$((${TASK_IDX} + 1))
                done
                #echo "WORKER_HOSTS:"
                #echo "${WORKER_HOSTS}"

                ###########################################
                # start one job for each ps
                ###########################################

                PS_IDX=0
                while [ ${PS_IDX} -lt ${PS_NUM} ]
                do
                    cat ps.yaml | \
                        sed -e "s/\$PS_IDX/${PS_IDX}/g" \
                            -e "s/\$PS_HOSTS/${PS_HOSTS}/g" \
                            -e "s/\$WORKER_HOSTS/${WORKER_HOSTS}/g" \
                            -e "s/\$MODEL/${MODEL}/g" \
                            -e "s/\$UPDATE/${UPDATE}/g" \
                            -e "s/\$BATCH/${BATCH}/g" | \
                        kubectl create -f -
                    PS_IDX=$((${PS_IDX} + 1))
                done

                ###########################################
                # wait until all ps activated
                ###########################################

                PS_IDX=0
                while [ ${PS_IDX} -lt ${PS_NUM} ]
                do
                    until [ "$(kubectl get job -n user tf-ps${PS_IDX} -o jsonpath='{.status.active}' 2>/dev/null)" = "1" ]; do :; done
                    PS_IDX=$((${PS_IDX} + 1))
                done

                ###########################################
                # start one job for each worker
                ###########################################

                TASK_IDX=0
                while [ ${TASK_IDX} -lt ${WORKER_NUM} ]
                do
                    cat worker.yaml | \
                        sed -e "s/\$TASK_IDX/${TASK_IDX}/g" \
                            -e "s/\$WORKER_NUM/${WORKER_NUM}/g" \
                            -e "s/\$PS_HOSTS/${PS_HOSTS}/g" \
                            -e "s/\$WORKER_HOSTS/${WORKER_HOSTS}/g" \
                            -e "s/\$MODEL/${MODEL}/g" \
                            -e "s/\$UPDATE/${UPDATE}/g" \
                            -e "s/\$NGPU/${NGPU}/g" \
                            -e "s/\$BATCH/${BATCH}/g" | \
                        kubectl create -f -
                    TASK_IDX=$((${TASK_IDX} + 1))
                done

                ###########################################
                # wait until all workers succeeded
                ###########################################

                TASK_IDX=0
                while [ ${TASK_IDX} -lt ${WORKER_NUM} ]
                do
                    until [ "$(kubectl get job -n user tf-worker${TASK_IDX} -o jsonpath='{.status.succeeded}' 2>/dev/null)" = "1" ]; do :; done
                    TASK_IDX=$((${TASK_IDX} + 1))
                done

                ###########################################
                # clean all worker jobs
                ###########################################

                TASK_IDX=0
                while [ ${TASK_IDX} -lt ${WORKER_NUM} ]
                do
                    cat worker.yaml | \
                        sed -e "s/\$TASK_IDX/${TASK_IDX}/g" \
                            -e "s/\$WORKER_NUM/${WORKER_NUM}/g" \
                            -e "s/\$PS_HOSTS/${PS_HOSTS}/g" \
                            -e "s/\$WORKER_HOSTS/${WORKER_HOSTS}/g" \
                            -e "s/\$MODEL/${MODEL}/g" \
                            -e "s/\$UPDATE/${UPDATE}/g" \
                            -e "s/\$NGPU/${NGPU}/g" \
                            -e "s/\$BATCH/${BATCH}/g" | \
                        kubectl delete -f -
                    TASK_IDX=$((${TASK_IDX} + 1))
                done

                ###########################################
                # wait for all workers removed
                ###########################################

                TASK_IDX=0
                while [ ${TASK_IDX} -lt ${WORKER_NUM} ]
                do
                    until ! kubectl get job -n user tf-worker${TASK_IDX} &>/dev/null; do :; done
                    TASK_IDX=$((${TASK_IDX} + 1))
                done

                ###########################################
                # clean all ps jobs
                ###########################################

                PS_IDX=0
                while [ ${PS_IDX} -lt ${PS_NUM} ]
                do
                    cat ps.yaml | \
                        sed -e "s/\$PS_IDX/${PS_IDX}/g" \
                            -e "s/\$PS_HOSTS/${PS_HOSTS}/g" \
                            -e "s/\$WORKER_HOSTS/${WORKER_HOSTS}/g" \
                            -e "s/\$MODEL/${MODEL}/g" \
                            -e "s/\$UPDATE/${UPDATE}/g" \
                            -e "s/\$BATCH/${BATCH}/g" | \
                        kubectl delete -f -
                    PS_IDX=$((${PS_IDX} + 1))
                done

                ###########################################
                # wait for all ps removed
                ###########################################

                PS_IDX=0
                while [ ${PS_IDX} -lt ${PS_NUM} ]
                do
                    until ! kubectl get job -n user tf-ps${PS_IDX} &>/dev/null; do :; done
                    PS_IDX=$((${PS_IDX} + 1))
                done

                sleep 1
            done
        done
    done
done

# vim: set ts=4 sw=4 et :
