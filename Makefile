SSH_FLAGS := -D -e


DOCKER_NETWORK := docker


GITORBIT_IMAGE := yoanlin/gitorbit
GITORBIT_HOSTPORT := 2022
GITORBIT_CONTAINER_NAME := gitorbit

CID_FILE := .container_id

configmap.yaml:
	kubectl create configmap git-server-config --from-file=mongo.json=config/k8s.json -o yaml --dry-run > $@

config: configmap.yaml
	kubectl create configmap git-server-config --from-file=mongo.json=config/k8s.json

stop:
	[[ -f $(CID_FILE) ]] && docker stop $(GITORBIT_CONTAINER_NAME) $$(cat $(CID_FILE)) || true
	rm -f $(CID_FILE)

push:
	docker push $(GITORBIT_IMAGE)

build:
	docker build --build-arg CACHE=$$(date +%s) --tag $(GITORBIT_IMAGE) .

run: stop
	# -e Write debug logs to standard error instead of the system log.
	docker network create $(DOCKER_NETWORK) || true
	docker run --name $(GITORBIT_CONTAINER_NAME) \
		--network $(DOCKER_NETWORK) \
		--detach \
		--rm \
		--publish $(GITORBIT_HOSTPORT):22 \
		$(GITORBIT_IMAGE) /usr/sbin/sshd $(SSH_FLAGS) > $(CID_FILE)
	cat $(CID_FILE)
