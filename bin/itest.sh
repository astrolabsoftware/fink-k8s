#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Create docker image containing Fink packaged for k8s

# @author  Fabrice Jammes

set -euo pipefail

DIR=$(cd "$(dirname "$0")"; pwd -P)

readonly FINKKUB=$(readlink -f "${DIR}/..")
. $FINKKUB/conf.sh

# login
eval $(minikube docker-env)

# submit the job in cluster mode - 1 driver + 1 executor
FINK_ALERT_SCHEMA="/home/fink/fink-broker/schemas/1628364324215010017.avro"
KAFKA_STARTING_OFFSET="earliest"
ONLINE_DATA_PREFIX="/home/fink/fink-broker/online"
FINK_TRIGGER_UPDATE=2
LOG_LEVEL="INFO"

# get the apiserver ip
API_SERVER_URL=$(kubectl -n kube-system get pod -l component=kube-apiserver \
  -o=jsonpath="{.items[0].metadata.annotations.kubeadm\.kubernetes\.io/kube-apiserver\.advertise-address\.endpoint}")

# Set RBAC
# see https://spark.apache.org/docs/latest/running-on-kubernetes.html#rbac
kubectl create serviceaccount spark --dry-run=client -o yaml | kubectl apply -f -
kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount=default:spark \
  --namespace=default --dry-run=client -o yaml | kubectl apply -f -

readonly SPARK_LOG_FILE="/tmp/spark-submit.log"
echo "Launch Spark job in background (log file: $SPARK_LOG_FILE)"
spark-submit --master "k8s://https://${API_SERVER_URL}" \
    --deploy-mode cluster \
    --conf spark.executor.instances=1 \
    --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
    --conf spark.kubernetes.container.image="$FINK_K8S_IMAGE" \
    --conf spark.driver.extraJavaOptions="-Divy.cache.dir=/home/fink -Divy.home=/home/fink" \
    local:///home/fink/fink-broker/bin/stream2raw.py \
    -servers "${KAFKA_SOCKET}" -topic "${KAFKA_TOPIC}" \
    -schema "${FINK_ALERT_SCHEMA}" -startingoffsets_stream "${KAFKA_STARTING_OFFSET}" \
    -online_data_prefix "${ONLINE_DATA_PREFIX}" \
    -tinterval "${FINK_TRIGGER_UPDATE}" -log_level "${LOG_LEVEL}" >& $SPARK_LOG_FILE &

COUNTER=0
while [ $(kubectl get pod -l spark-role -o go-template='{{printf "%d\n" (len  .items)}}') -ne 2 \
  -o $COUNTER -lt 20 ]
do
  echo "Wait for Spark pods to be created"
  echo "---------------------------------"
  sleep 2
  echo "spark-submit logs (30 lines):"
  echo "-----------------------------"
  tail -n 30 "$SPARK_LOG_FILE"
  let COUNTER=COUNTER+1
done

echo "Wait for Spark pods to be running"
if ! kubectl wait --timeout=60s --for=condition=Ready pods -l spark-role
then
  echo "spark-submit logs:"
  echo "------------------"
  cat /tmp/spark-submit.log
fi

kubectl describe pods -l "spark-role in (executor, driver)"

# TODO a cli option
# kubectl delete pod -l "spark-role in (executor, driver)"


