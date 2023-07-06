# Toolforge deploy repository

This repository hosts the per-component code to deploy an instance of toolforge.

To get started, run

```
./depoly.sh --help
```

## Expected development flow

Note that the user does not need to write the image tag anywhere, only care
about the chart version.

Every chart version is bound to it's own image tag.

![created using draw.io](docs/component_cd_flow.png)

This is implemented in the cicd/gitlab-ci repository:
https://gitlab.wikimedia.org/repos/cloud/cicd/gitlab-ci/

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

### kubernetes-metrics

This are the Toolforge Kubernetes metrics components.

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
