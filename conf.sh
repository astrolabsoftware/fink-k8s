# Minikube Parameters
# -------------------

# Kubernetes version
K8S_VERSION="v1.25.1"

# Desired number of CPU for minikube
# if the value is above the maximum number of CPUs on the host, it will fallback to the maximum number of CPUs on the host
CPUS=4


# Spark parameters
# ----------------
# Assuming Scala 2.11

# Spark version
readonly SPARK_VERSION="3.1.3"

# Name for the Spark archive
readonly SPARK_NAME="spark-${SPARK_VERSION}-bin-hadoop3.2"

# Spark install location
readonly SPARK_INSTALL_DIR="${HOME}/fink-k8s-tmp"

export SPARK_HOME="${SPARK_INSTALL_DIR}/${SPARK_NAME}"
export PATH="$SPARK_HOME/bin:$PATH"


# Build parameters
# ----------------
# Repository address
readonly REPO=local
# Tag to apply to the built image, or to identify the image to be pushed
readonly TAG="2.7_3.1.3"
readonly FINK_IMAGE_NAME="finkk8sdev"
# Full image name
# can be overridden using environment variable "FINK_K8S_IMAGE"
readonly FINK_K8S_IMAGE=${FINK_K8S_IMAGE:-"$REPO/finkk8sdev:$TAG"}


# Spark job 'stream2raw' parameters
# ---------------------------------
KAFKA_SOCKET=${KAFKA_SOCKET:-"128.0.0.1:24499"}
KAFKA_TOPIC=${KAFKA_TOPIC:-"changemetopicname"}

