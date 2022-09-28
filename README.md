# Using Fink on Kubernetes engine

This repository hosts files and procedure to run [Fink](https://github.com/astrolabsoftware/fink-broker) on Kubernetes.

## Compatibility matrix and images

You can already test Fink on Kubernetes using our [official images](https://hub.docker.com/r/julienpeloton/fink/tags). We summarised below the versions that have been tested:

| Fink version | Spark version | Kubernetes version| Image       | Status      |
|--------------|---------------|-------------------|-------------|-------------|
| 2.4          | 3.1.3         | 1.18              | julienpeloton/finkk8sdev:2.4_3.1.3 | production  |
| 0.7.0        | 2.4.4         | 1.15              | julienpeloton/fink:0.7.0_2.4.4 | production  |

You can try other combinations, but there is no guarantee that it works. You would simply use:

```bash
spark-submit --master $MASTERURL \
     --deploy-mode cluster \
     --conf spark.kubernetes.container.image=julienpeloton/finkk8sdev:2.4_3.1.3 \
     $OTHERCONF \
     /home/fink-broker/bin/stream2raw.py \
     $ARGS
```

See below for a full example.

## Kubernetes cluster installation

Information to install Kubernetes can found in the official documentation. Alternatively for test purposes, you can install minikube and run a local Kubernetes cluster.

### Start a Kubernetes cluster with minikube

First install minikube

```bash
brew install minikube
```

and start a Kubernetes cluster:

```bash
# Spark 2.4.x will not work for k8s version > 1.15
minikube start --cpus 4 --memory 7000 --kubernetes-version v1.15.0
```

See the compatibility matrix above to set your Kubernetes version correctly. We recommend to run 1.15.0 anyway for the moment. If you intend to run Fink with Spark 2.4.x, then you need to stick with Kubernetes version 1.15 maximum (see [here](https://issues.apache.org/jira/browse/SPARK-31786) and [there](https://github.com/apache/spark/pull/28625)).

Note that it is recommended to set at least 4 CPUs and somehow a large fraction of RAM (7GB in this example).

### Manage Pods

We need to give additional rights to our Kubernetes cluster to manage pods. This is due to Spark’s architecture — we deploy a Spark Driver, which can then create the Spark Executors in pods and then clean them up once the job is done

```bash
if ! kubectl get serviceaccount spark; then
    kubectl create serviceaccount spark
    kubectl create clusterrolebinding spark-role \
    	--clusterrole=edit \
    	--serviceaccount=default:spark --namespace=default
fi
```

## Build Fink docker image

### Download Apache Spark

First, you need to choose the Spark version with which you want to run Fink. See above the compatibility matrix. We recommend to use Spark 2.4.4 for the moment.

Download Spark and untar it in your prefered location:

```bash
# Assuming Scala 2.11
SPARK_VERSION=3.1.3
wget https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop2.7.tgz .
tar -xf ./spark-${SPARK_VERSION}-bin-hadoop3.2.tgz
export SPARK_HOME=${PWD}/spark-${SPARK_VERSION}-bin-hadoop3.2
```

### Install Fink additional files inside Spark

Clone this repository somewhere on your computer, and register the location:

```bash
git clone https://github.com/astrolabsoftware/fink-k8s
export FINKKUB=${PWD}/fink-k8s
```

Copy Fink files inside your Spark installation:

```bash
# base Spark image using openjdk:8
cp ${FINKKUB}/docker/Dockerfile_fink_base ${SPARK_HOME}/kubernetes/dockerfiles/spark

# Fink image
cp ${FINKKUB}/docker/Dockerfile_fink ${SPARK_HOME}/kubernetes/dockerfiles/spark/bindings/python

# Extra jars for Fink
cp ${FINKKUB}/jars/*.jar ${SPARK_HOME}/jars/

# Custom launcher
cp ${FINKKUB}/bin/docker-image-tool-fink.sh ${SPARK_HOME}/bin/
```

We have built an image based on `openjdk:11-jre` instead of the official `openjdk:11-jre-slim` which was not suited for our python environment (we heavily use glibc for example which is not in the alpine version). If you know how to easily build the Fink image using `openjdk:11-jre-slim`, contact us! Note that we do not release an image for R (not used), but feel free to contact us if you need it.

### Build Fink image

To build the image:

```bash
cd ${SPARK_HOME}

# remove the `-m` option if you are not using minikube
# use your docker account in -r if you are not using minikube
# tag contains fink version and spark version used
./bin/docker-image-tool-fink.sh -m -r test -t 2.4_3.1.3 -p ./kubernetes/dockerfiles/spark/bindings/python/Dockerfile_fink build
```

You should end up with an image around 3GB:

```bash
docker image ls
REPOSITORY                                TAG                 IMAGE ID            CREATED             SIZE
test/fink                                 2.4_3.1.3         3fcdf60b3356        35 seconds ago      3.06GB
```

We are actively working at reducing the size of the image (most of the size is taken by dependencies). If you want to use this image in production (not with minikube), you need also to push the image:

```bash
./bin/docker-image-tool-fink.sh -r <your docker account> -t 2.4_3.1.3 -p ./kubernetes/dockerfiles/spark/bindings/python/Dockerfile_fink push
```

## Examples

### Ingesting stream data with Fink & Kubernetes

The first step in Fink is to listen to a stream, decode the alert, and store those alerts on disk (`stream2raw`). You would simply do this step:

```bash
# login
eval $(minikube docker-env)

# get the apiserver ip
# Beware, it is different for each new minikube k8s cluster
kubectl cluster-info
--> Kubernetes master is running at https://127.0.0.1:32776
--> KubeDNS is running at ...

# submit the job from your computer!
spark-submit --master k8s://https://127.0.0.1:32776 \
     --deploy-mode cluster \
     --conf spark.executor.instances=1 \
     --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
     --conf spark.kubernetes.container.image=test/fink:0.7.0_2.4.4 \
     /home/fink-broker/bin/stream2raw.py \
     -servers xx.xx.xx.xx:port,yy.yy.yy.yy:port \
     -topic a_topic \
     -schema /home/fink-broker/schemas/template_schema_ZTF_3p3.avro \
     -startingoffsets_stream earliest \
     -rawdatapath file:///home/fink-broker/raw \
     -checkpointpath_raw file:///home/fink-broker/raw_checkpoint \
     -tinterval 2 -log_level INFO
```

Note:

- Servers are either ZTF/LSST ones (you need extra auth files), or Fink Kafka servers (replayed streams).
- `rawdatapath`, `checkpointpath_raw` should point to a hdfs (or s3) path in production (otherwise alerts will be collected inside the k8s cluster, and you won't access it!).

### Monitoring your job

The UI associated with any application can be accessed locally using kubectl port-forward:

```bash
kubectl port-forward <driver-pod-name> 4040:4040
```

and then navigate to `http://localhost:4040`.

### Terminating the job

We are running a streaming job, so just hitting CTRl+C will not stop the job (which will continue forever in the pods). To really terminate, you need to delete the master:

```bash
kubectl delete pod <driver-pod-name>
```

Beware, if you kill an executor, it will be recreated by Kubernetes.

### Troubleshooting

See pods status

```bash
kubectl get pods
NAME                                 READY   STATUS    RESTARTS   AGE
stream2raw-py-1598515989094-driver   1/1     Running   0          28m
stream2raw-py-1598515989094-exec-1   1/1     Running   0          27m
```

Access logs

```bash
kubectl logs <pod-driver-or-executor-name>
```

Basic information about the scheduling decisions made around the driver pod

```bash
kubectl describe pod <pod-driver-name>
```