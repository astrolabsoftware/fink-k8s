# Fink kubernetes

Dockerfile_fink_base --> kubernetes/spark

Dockerfile_fink --> kubernetes/spark/bindings/python

docker-image-tool-fink.sh -> bin/

## with minikube
./bin/docker-image-tool-fink.sh -m -r test -t pysparkfink -p ./kubernetes/dockerfiles/spark/bindings/python/Dockerfile_fink build

## without minikube
./bin/docker-image-tool-fink.sh -r test -t pysparkfink -p ./kubernetes/dockerfiles/spark/bindings/python/Dockerfile_fink build
