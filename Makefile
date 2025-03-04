.PHONY: help all create delete deploy check clean app webv test reset-prometheus reset-grafana jumpbox

help :
	@echo "Usage:"
	@echo "   make all              - create a cluster and deploy the apps"
	@echo "   make loop             - inner loop that builds and deploys the app"
	@echo "   make create           - create a k3d cluster with linkerd"
	@echo "   make setup            - setup linkerd and fluentbit"
	@echo "   make check            - check the cluster, including linkerd"
	@echo "   make delete           - delete the k3d cluster"
	@echo "   make app              - build and push local app docker image"
	@echo "   make deploy           - deploy the app to the cluster"
	@echo "   make undeploy         - delete the app from the cluster"
	@echo "   make jumpbox          - deploy a 'jumpbox' pod"
	@echo "   make pull             - pull linkerd images, because the k3s cluster fails to pull them sometimes"
	@echo "   make prime            - import linkerd images into the cluster"
	@echo "   make bootstrap.       - bootstrap creates and configures the cluster with image pull and import help"
	@echo "   make allp             - all with image import into the cluster at the right step"

all : delete create setup check app deploy

# This version of the setup pulls and imports the linkerd images to avoid pull issues on deploy
bootstrap :  delete pull create prime setup
allp : delete create prime setup app deploy

loop : app undeploy deploy

delete :
	# delete the cluster (if exists)
	@# this will fail harmlessly if the cluster does not exist
	@k3d cluster delete

create :
	@# create the cluster and wait for ready
	@# this will fail harmlessly if the cluster exists
	@# default cluster name is k3d-k3s-default

	k3d cluster create --registry-use k3d-registry.localhost:5000 --config deploy/k3d/k3d.yaml

	# wait for cluster to be ready
	@kubectl wait node --for condition=ready --all --timeout=30s

setup :
	# deploy linkerd with monitoring
	# from https://linkerd.io/2.10/getting-started/
	@deploy/linkerd/install_linkerd.sh
	@linkerd install --image-pull-policy IfNotPresent | kubectl apply -f -
	@linkerd jaeger install | kubectl apply -f - # Jaeger collector and UI
	@linkerd viz install --set jaegerUrl=jaeger.linkerd-jaeger:16686 | kubectl apply -f - # on-cluster metrics stack
	# to see, use: linkerd viz dashboard &

	# deploy fluent bit
	-kubectl apply -f deploy/fluentbit/fluentbit.yaml
	-kubectl create secret generic log-secrets --from-literal=WorkspaceId=dev --from-literal=SharedKey=dev -n fluentbit
	-kubectl apply -f deploy/fluentbit/stdout-config.yaml
	-kubectl apply -f deploy/fluentbit/fluentbit-pod.yaml

	-helm repo add traefik https://helm.traefik.io/traefik
	-helm repo update

	# wait for the pods to start
	@kubectl wait po -A --for condition=ready --all --timeout=60s

	# display pod status
	@kubectl get po -A

check :
	@linkerd check

	# display pod status
	@kubectl get po -A

app :
	@cd app; docker-compose build
	@k3d image import -t pickle:local
	@k3d image import -t pickle_words:local
	@k3d image import -t pickle_signer:local

deploy :
	# build the local image and load into k3d
	@kubectl apply -f deploy/app/pickle.yaml -n pickle
	-helm install traefik traefik/traefik -n pickle -f ./deploy/traefik/traefik_values.yaml
	-kubectl apply -f deploy/app/pickle_ingress.yaml

undeploy :
	-kubectl delete namespace pickle

jumpbox :
	@# start a jumpbox pod
	@-kubectl delete pod jumpbox --ignore-not-found=true

	@kubectl run jumpbox --image=alpine --restart=Always -- /bin/sh -c "trap : TERM INT; sleep 9999999999d & wait"
	@kubectl wait pod jumpbox --for condition=ready --timeout=30s
	@kubectl exec jumpbox -- /bin/sh -c "apk update && apk add bash curl httpie" > /dev/null
	@kubectl exec jumpbox -- /bin/sh -c "echo \"alias ls='ls --color=auto'\" >> /root/.profile && echo \"alias ll='ls -lF'\" >> /root/.profile && echo \"alias la='ls -alF'\" >> /root/.profile && echo 'cd /root' >> /root/.profile" > /dev/null


pull :
	# linkerd-related images don't always pull from the cluster
	@docker pull cr.l5d.io/linkerd/controller:stable-2.10.2
	@docker pull cr.l5d.io/linkerd/grafana:stable-2.10.2
	@docker pull cr.l5d.io/linkerd/metrics-api:stable-2.10.2
	@docker pull cr.l5d.io/linkerd/proxy:stable-2.10.2
	@docker pull cr.l5d.io/linkerd/proxy-init:v1.3.11
	@docker pull cr.l5d.io/linkerd/tap:stable-2.10.2
	@docker pull cr.l5d.io/linkerd/web:stable-2.10.2
	@docker pull prom/prometheus:v2.19.3
	

prime :
	# linkerd-related images don't always pull from the cluster
	@k3d image import -t cr.l5d.io/linkerd/controller:stable-2.10.2
	@k3d image import -t cr.l5d.io/linkerd/grafana:stable-2.10.2
	@k3d image import -t cr.l5d.io/linkerd/metrics-api:stable-2.10.2
	@k3d image import -t cr.l5d.io/linkerd/proxy:stable-2.10.2
	@k3d image import -t cr.l5d.io/linkerd/proxy-init:v1.3.11
	@k3d image import -t cr.l5d.io/linkerd/tap:stable-2.10.2
	@k3d image import -t cr.l5d.io/linkerd/web:stable-2.10.2
	@k3d image import -t prom/prometheus:v2.19.3
