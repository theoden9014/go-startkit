REPOSITORY              ?= github.com/theoden9014/go-makefile
NAME                    ?= go-makefile

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
	GOOS ?= linux
endif
ifeq ($(UNAME_S),Darwin)
	GOOS ?= darwin
endif

# Settings for golang
GO                      ?= go
GOFMT                   ?= go fmt
GOVET                   ?= go vet
BINARY                  := $(NAME)
SUFFIX                  := .go
PKGS                    := $(shell go list ./... | grep -v /vendor/)
SOURCES                 := $(foreach pkg, $(PKGS), $(wildcard $(GOPATH)/src/$(pkg)/*$(SUFFIX)))
LINTERS                 := golint vet misspell
CGO_ENABLED             := 0
GOOS                    := $(shell uname | tr '[A-Z]' '[a-z]')
GOMETALINTER_OPTIONS    := $(addprefix --enable , $(LINTERS))
GRAPH_OUT_FILE          := graph.png
COVER_OUT_FILE          := coverage.out
COVERVIEW_OUT_FILE      := coverage.html

#
# Versioning
#
VERSION                 ?= $(shell git describe --tags --abbrev=0 2>/dev/null)
REVISION                ?= $(shell git rev-parse --short HEAD)
GOVERSION               := $(shell go version | cut -d ' ' -f3 | sed 's/^go//')
LDFLAGS                 ?= -s -X 'main.gVersion=$(VERSION)' \
                              -X 'main.gGitcommit=$(REVISION)' \
                              -X 'main.gGoversion=$(GOVERSION)'

#
# Docker
#
DOCKER                          ?= docker
DOCKER_IMAGE_NAME               := $(NAME)
DEVELOP_DOCKER_IMAGE_NAME       := $(NAME)-dev
BUILD_DOCKER_IMAGE_NAME         := $(NAME)-build
DOCKERFILE                      := Dockerfile
DEVELOP_STAGE                   := development
BUILD_STAGE                     := builder
DEFAULT_DOCKER_BUILD_OPTS       := -f $(DOCKERFILE) --build-arg name=$(NAME) --build-arg repository=$(REPOSITORY)
DOCKER_BUILD_DEVELOP_STAGE_OPTS := $(DEFAULT_DOCKER_BUILD_OPTS) -t $(DEVELOP_DOCKER_IMAGE_NAME) --target $(DEVELOP_STAGE)
DOCKER_BUILD_BUILD_STAGE_OPTS   := $(DEFAULT_DOCKER_BUILD_OPTS) -t $(BUILD_DOCKER_IMAGE_NAME) --target $(BUILD_STAGE)
DOCKER_BUILD_OPTS               := $(DEFAULT_DOCKER_BUILD_OPTS) -t $(DOCKER_IMAGE_NAME)


.DEFAULT_GOAL := help

#
# Dependency Tools
#
GOMETALINTER_URL ?= https://github.com/alecthomas/gometalinter/releases/download/v2.0.11/gometalinter-2.0.11-$(GOOS)-amd64.tar.gz
GOLINT := $(GOPATH)/bin/gometalinter
$(GOLINT):
	curl -ksfL \
		-o gometalinter.tar.gz \
		$(GOMETALINTER_URL)
	tar --strip=1 -xf gometalinter.tar.gz -C $(GOPATH)/bin && rm -f gometalinter.tar.gz
GODEP := $(GOPATH)/bin/dep
$(GODEP):
	$(GO) get -u github.com/golang/dep/...
GRAPH := $(GOPATH)/bin/godepgraph
$(GRAPH):
	$(GO) get -u github.com/kisielk/godepgraph
$(BINARY): $(SOURCES)
	CGO_ENABLED=$(CGO_ENABLED) $(GO) build -ldflags "$(LDFLAGS)" -a -installsuffix cgo -o $(BINARY)
$(COVER_OUT_FILE):
	@$(foreach pkg,$(PKGS),$(GO) test -covermode count -coverprofile=coverage.$(notdir $(pkg)).out $(pkg) || exit;)
	@$(foreach pkg,$(PKGS),cat coverage.$(notdir $(pkg)).out >> _coverage.out; rm -f coverage.$(notdir $(pkg)).out || exit;)
	@echo "mode: count" > $(COVER_OUT_FILE)
	@cat  _coverage.out | sort -r | uniq > $(COVER_OUT_FILE)
	@rm -f _coverage.out
$(COVERVIEW_OUT_FILE):
	@$(GO) tool cover -html=coverage.out -o $(COVERVIEW_OUT_FILE)
$(GRAPH_OUT_FILE):
	@$(GRAPH) -horizontal $(REPOSITORY) | dot -Tpng -o $(GRAPH_OUT_FILE)

##################################
# Main targets from here
##################################
all: setup vendor check build
check: lint test ## Runs all tests
setup: $(GOLINT) $(GODEP) $(GRAPH) ## Install dependency tools
# Build application tasks from here
vendor: $(GODEP) Gopkg.toml Gopkg.lock ## Vendoring from Gopkg.lock
	$(GODEP) ensure -vendor-only
format:
	@$(GOFMT)
build: format $(BINARY) ## Build the binary
test: ## Run the unit tests
	go test -race -v $(shell go list ./... | grep -v /vendor/)
lint: format $(GOLINT) ## Lint all files
	$(GOLINT) --disable-all \
		$(GOMETALINTER_OPTIONS) \
		--vendor --fast ./...
cover: $(COVER_OUT_FILE) ## Update coverage.out
coverview: cover $(COVERVIEW_OUT_FILE) ## Coverage view
graph: $(GRAPH) $(GRAPH_OUT_FILE) ## Generate dependencies map

.PHONY: all check setup vendor format build test lint cover coverview graph

# Docker targets from here
docker: ## Build server image
	docker build $(DOCKER_BUILD_OPTS) .
login: docker-build-develop-stage ## Login to development environment with container
	docker run --rm -it \
	-v $(PWD):/go/src/$(REPOSITORY) \
	-p 8080:8080 \
	$(DEVELOP_DOCKER_IMAGE_NAME) \
	/bin/bash
docker-check: docker-build-develop-stage ## Run 'make check' inside container
	docker run --rm -it \
	$(DEVELOP_DOCKER_IMAGE_NAME) \
	make check
docker-coverview: docker-build-develop-stage ## Run 'make coverview' inside container
	docker run --rm -it \
	-v $(PWD):/go/src/$(REPOSITORY) \
	$(DEVELOP_DOCKER_IMAGE_NAME) \
	make coverview
docker-graph: docker-build-develop-stage ## Run 'make graph' inside container
	docker run --rm -it \
	-v $(PWD):/go/src/$(REPOSITORY) \
	$(DEVELOP_DOCKER_IMAGE_NAME) \
	make graph
docker-build-develop-stage:
	docker build $(DOCKER_BUILD_DEVELOP_STAGE_OPTS) .
docker-build-build-stage:
	docker build $(DOCKER_BUILD_BUILD_STAGE_OPTS) .

.PHONY: docker login docker-check docker-coverview docker-graph docker-build-develop-stage docker-build-build-stage

# Other tasks from here
version: ## Print version
	@echo Version: $(VERSION)
	@echo Revision: $(REVISION)
	@echo GoVersion: $(GOVERSION)

clean: ## Clean up build artifacts
	@rm -rf $(BINARY)
	@rm -rf $(COVER_OUT_FILE)
	@rm -rf $(COVERVIEW_OUT_FILE)
	@rm -rf $(GOVIZ_OUT_FILE)
	@go clean
	@docker images 2>/dev/null | grep -q "$(DOCKER_IMAGE_NAME)" && docker rmi "$(DOCKER_IMAGE_NAME)" || true;
	@docker images 2>/dev/null | grep -q "$(DEVELOP_DOCKER_IMAGE_NAME)" && docker rmi "$(DEVELOP_DOCKER_IMAGE_NAME)" || true;
	@docker images 2>/dev/null | grep -q "$(BUILD_DOCKER_IMAGE_NAME)" && docker rmi "$(BUILD_DOCKER_IMAGE_NAME)" || true;

help: ## Display this help message
	@cat $(MAKEFILE_LIST) | grep -e "^[a-zA-Z_\-]*: *.*## *" | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: version clean help
