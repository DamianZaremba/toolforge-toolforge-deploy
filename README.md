# Toolforge deploy repository

This repository hosts the per-component code to deploy an instance of toolforge.

## Expected development flow

Note that the user does not need to write the image tag anywhere, only care
about the chart version.

Every chart version is bound to it's own image tag.

![created using draw.io](docs/component_cd_flow.png)

This is implemented in the cicd/gitlab-ci repository:
https://gitlab.wikimedia.org/repos/cloud/cicd/gitlab-ci/

# Deploying locally/by hand

Useful if you have your local minikube/kind for testing (see also
[lima-kilo](Portal:Toolforge/Admin/lima-kilo)). To get started, run

```
./depoly.sh --help
```

## Deploying on toolforge

We use a cookbook to deploy the components on this repository, that will clone
this repository and deploy the component on the right cluster. The cookbooks is
[`wmcs.toolforge.k8s.component.deploy`](https://gerrit.wikimedia.org/g/cloud/wmcs-cookbooks#installation%20cookbook):

```
user@laptop:~$ cookbook wmcs.toolforge.k8s.component.deploy -h
usage: cookbooks.wmcs.toolforge.k8s.component.deploy [-h] --cluster-name {tools,toolsbeta} [--task-id TASK_ID] [--no-dologmsg] (--component COMPONENT | --git-url GIT_URL) [--git-name GIT_NAME] [--git-branch GIT_BRANCH] [--deployment-command DEPLOYMENT_COMMAND]

WMCS Toolforge Kubernetes - deploy a kubernetes custom component

Usage example:
    cookbook wmcs.toolforge.k8s.component.deploy \
        --cluster-name toolsbeta \
        --component jobs-api

options:
  -h, --help            show this help message and exit
  --cluster-name {tools,toolsbeta}
                        cluster to work on (default: None)
  --task-id TASK_ID     Id of the task related to this operation (ex. T123456). (default: None)
  --no-dologmsg         To disable dologmsg calls (no SAL messages on IRC). (default: False)
  --component COMPONENT
                        component to deploy from the toolforge-deploy repo (default: None)
  --git-url GIT_URL     git URL for the source code (default: None)
  --git-name GIT_NAME   git repository name. If not provided, it will be guessed based on the git URL (default: None)
  --git-branch GIT_BRANCH
                        git branch in the source repository (default: main)
  --deployment-command DEPLOYMENT_COMMAND
                        command to trigger the deployment. (default: ./deploy.sh)
```

## Secrets

The secrets are pulled from a yaml file, by default it's
/etc/toolforge-deploy/secrets.yaml (populated by puppet on the control nodes).

You can specify an alternative file with the env var
SECRETS_FILE=/my/custom/secrets.yaml when running the deploy.sh script:

```
SECRETS_FILE=$PWD/test_secrets.yaml ./deploy.sh builds-api
```

In the values files templates (\*.yaml.gotmpl) you can get a secret with:

```
myVariable: {{ exec "../../helpers/get_secret.sh" (list "mySecret") }}
```

And you can try getting a secret manually by running the script directly:

```
> components/helpers/get_secret.sh mySecret
```

Note that if the secret does not exist, the template generation will fail with a
not-very-clear error from helmfile:

```
in ./helmfile.yaml: error during helmfile.yaml.part.0 parsing: template: stringTemplate:11:22: executing "stringTemplate" at <.Values.chartRepository>: map has no entry for key "chartRepository"
```

## Documentation for the services:

See:

- [General toolforge](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin)
- [Jobs service](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Kubernetes/Jobs_framework)
- [Build service](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Build_Service)
- [Envvars service](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Envvars_Service)
- [Ingress nginx](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Kubernetes/Networking_and_ingress)
- [Kubernetes metrics](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Kubernetes#Monitoring)

## Components

### API Gateway

This component is the entrypoint of any request to any toolforge API.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/api-gateway)

### Builds Admission

Part of the build service, it takes care of making sure the build requests
(currently PipelineRun resources) match our parameters.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/builds-admission)

### Builds API

Part of the build service, main API that users interact with, entry point for
build related requests.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/builds-api)

### Builds Builder

Part of the build service, this is the component that actually builds and pushes
the images, currently based on tekton pipelines.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/builds-builder)

### Calico

[Kubernetes CNI](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
that we use.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/calico)

### Cert Manager

Service to generate and reload the ssl certificates for any other component. We
have no code for it as we use directly upstream charts.

### Envvars Admission

Part of the envvars service, it injects the envvars (currently k8s secrets) into
the pods that need them.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/envvars-admission)

### Envvars API

Part of the envvars service, main API that users interact with, entry point for
envvar related requests.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/envvars-api)

### Image config

Configuration with the list of images available for the jobs service and
webservice cli.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/image-config)

### Ingress admission

Validates that ingress objects created by users don't interfere with other
users.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/ingress-admission)

### Ingress nginx

This is
[ingress element of k8s](https://kubernetes.io/docs/concepts/services-networking/ingress/)
that we use for http requests for tool webservices.

We have no code for it as we use upstream charts.

### Jobs API

Part of the jobs service, main API that users interact with, entry point for job
related requests.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/jobs-api)

### Jobs emailer

Part of the jobs service, this component takes care to email users when jobs
finish or fail.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/jobs-emailer)

### Maintain kubeusers

Takes care of creating all the bits and pieces necessary (ex. home directory,
k8s certs, ...) for new toolforge users.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/maintain-kubeusers)

### Registry admission

Validation webhook that makes sure new pods are only using images from
registries we allow.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/registry-admission)

### Volume admission

Takes care of adding the volumes for NFS, dumps and similar directories to user
created pods.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/volume-admission)

### WMCS k8s metrics

Part of Kubernetes metrics, set of tools to gather and expose metrics for
prometheus (or similar) to gather.

[Source code here](https://gitlab.wikimedia.org/repos/cloud/toolforge/wmcs-k8s-metrics)

This includes the following components:

- `cadvisor` generates Prometheus metrics about the Docker daemon and running
  containers.
- `kube-state-metrics` generates Prometheus metrics about Kubernetes API
  objects.
- `metrics-server` generates data for the Kubernetes metrics API (which powers
  `kubectl top`).
- `prometheus-rbac` generates access control rules so Prometheus can scrape
  workloads inside Kubernetes.

More information:
https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Kubernetes#Monitoring
