# Image URL to use all building/pushing image targets
VERSION = $(shell git describe --tags )
IMG = ghcr.io/tribock/go-via:$(VERSION)
TODAY = $(shell date -u +'%Y-%m-%d')
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.26.0


# Variables for generating API client, informer etc.
LISTER_GEN       = go run k8s.io/code-generator/cmd/lister-gen
INFORMER_GEN     = go run k8s.io/code-generator/cmd/informer-gen
CLIENT_GEN       = go run k8s.io/code-generator/cmd/client-gen
CONVERSION_GEN   = go run k8s.io/code-generator/cmd/conversion-gen
DOC_GEN          = go run ./tools/cmd/doc
XNS_INFORMER_GEN = go run github.com/maistra/xns-informer/cmd/xns-informer-gen

empty :=
space := $(empty) $(empty)

kube_api_packages = $(subst $(space),$(empty), \
	$(kube_base_output_package)/core/v1 \
	)

kube_base_output_package = gitlab.soultec.ch/soultec/souldeploy
kube_clientset_package   = $(kube_base_output_package)/client
kube_listers_package     = $(kube_base_output_package)/client/listers
kube_informers_package   = $(kube_base_output_package)/client/informers
xns_informers_package    = $(kube_base_output_package)/client/xnsinformer
path_apis = "./app/api/..."
header_file              = "zarf/hack/boilerplate.go.txt"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests:  ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=caas-role crd webhook paths=".//app//..." output:crd:artifacts:config=zarf/config/crd/bases output:dir=zarf/config/rbac
	$(CONTROLLER_GEN) rbac:roleName=caas-role crd webhook paths=".//business//..." output:crd:artifacts:config=zarf/config/crd/bases output:dir=zarf/config/rbac

.PHONY: generate
generate:  ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	- go generate

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test:  ## Run tests.
	 go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: manifests generate fmt vet statik ## Build manager binary.
	go build -o bin/manager app/main.go

.PHONY: run
run: docker-build ## Run a controller from your host.
	docker run -p 8443:8443 ${IMG}

.PHONY: devrun
devrun:  generate ## Run a controller from your host.
	export LOG_LEVEL=DEBUG; go run -ldflags "-X main.commit=${VERSION} -X main.date=${TODAY}" *.go

.PHONY: devrun-web
devrun-web:  ## Run a controller from your host.
	INSECURE=true go run app/api/main.go 
# If you wish built the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64 ). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: generate fmt vet statik ## Build docker image with the manager.
	docker buildx build --build-arg CI_COMMIT_TAG=${VERSION} --build-arg DATE=${TODAY} --push --platform linux/arm64/v8,linux/amd64 . -t ${IMG}

.PHONY: docker-build-push
docker-build-push: docker-build ## Push docker image with the manager.
	docker push ${IMG}
	docker tag ${CERT_IMG} ${CERT_LATEST_PUB}
	docker push ${CERT_IMG}
	docker push ${CERT_LATEST_PUB}
	VERSION=$(VERSION) DATE=${TODAY} envsubst < zarf/config/manager/kustomization.tmpl > zarf/config/manager/kustomization.yaml
	VERSION=$(VERSION) envsubst < zarf/k8s/base/kustomization.tmpl > zarf/k8s/base/kustomization.yaml

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}
	docker tag ${CERT_IMG} ${CERT_LATEST_PUB}
	docker push ${CERT_IMG}
	docker push ${CERT_LATEST_PUB}
	VERSION=$(VERSION) DATE=${TODAY} envsubst < zarf/config/manager/kustomization.tmpl > zarf/config/manager/kustomization.yaml
	VERSION=$(VERSION) envsubst < zarf/k8s/base/kustomization.tmpl > zarf/k8s/base/kustomization.yaml

# PLATFORMS defines the target platforms for  the manager image be build to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - able to use docker buildx . More info: https://docs.docker.com/build/buildx/
# - have enable BuildKit, More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image for your registry (i.e. if you do not inform a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To properly provided solutions that supports more than one platform you should use this option.
PLATFORMS ?= linux/arm64,linux/amd64
.PHONY: docker-buildx
docker-buildx: test ## Build and push docker image for the manager for cross-platform support
	# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
	- docker buildx create --name project-v3-builder
	docker buildx use project-v3-builder
	- CI_COMMIT_TAG=${VERSION} docker buildx build --push --platform=$(PLATFORMS) --tag ${IMG} -f Dockerfile.cross .
	- docker buildx rm project-v3-builder
	rm Dockerfile.cross

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build zarf/config/crd | kubectl apply -f -
	echo "clone ispo repo: https://gitlab.ixcloud.ch/k8s-operators/ispo"
	echo "execute: kubectl kustomize ../ispo/zarf/config/crd/ | kubectl apply -f -"

.PHONY: install-dev
install-dev: manifests kustomize install ## Install sample CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build zarf/config/samples/crd | kubectl apply -f -
	$(KUSTOMIZE) build zarf/config/samples | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build zarf/config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	## cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build zarf/k8s/base | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build zarf/k8s/base| kubectl delete --ignore-not-found=$(ignore-not-found) -f -


##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
ENVTEST ?= $(LOCALBIN)/setup-envtest

## Tool Versions
KUSTOMIZE_VERSION ?= v4.5.7
CONTROLLER_TOOLS_VERSION ?= v0.16.2

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary. If wrong version is installed, it will be removed before downloading.
$(KUSTOMIZE): $(LOCALBIN)
	@if test -x $(LOCALBIN)/kustomize && ! $(LOCALBIN)/kustomize version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(LOCALBIN)/kustomize version is not expected $(KUSTOMIZE_VERSION). Removing it before installing."; \
		rm -rf $(LOCALBIN)/kustomize; \
	fi
	test -s $(LOCALBIN)/kustomize || { curl -Ss $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) $(LOCALBIN); }

.PHONY: statik
statik: ## Embed static files using statik
	statik -src=./web/src/assets -dest=./app/statik

