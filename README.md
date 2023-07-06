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

## Documentation for the services:

See:

- [General toolforge](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin)
- [Jobs service](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Kubernetes/Jobs_framework)
- [Build service](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Build_Service)
- [Envvars service](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Envvars_Service)
- [Ingress nginx](https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Kubernetes/Networking_and_ingress)
