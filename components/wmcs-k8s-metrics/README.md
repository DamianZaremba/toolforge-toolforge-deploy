# wmcs-k8s-metrics

This component is atypical because it installs 4 charts:
* wmcs-metrics
* kube-state-metrics
* metrics-server
* metrics-server-api-certs

We should probably split it into 4 different components, this is tracked in
T388382.

The value of `kubeVersion` that you can find in the yaml files is a combination
of the requirements of the charts above. We manually update the value of
`kubeVersion` after upgrading any of the charts.

## wmcs-metrics

This chart serves two purposes:
* first, it installs various components into the cluster
* second, it creates the 'metrics' namespace for other charts to use

The source code for this chart is at:
https://gitlab.wikimedia.org/repos/cloud/toolforge/wmcs-k8s-metrics

### Upgrading wmcs-metrics

To publish a new version of this chart, create a MR in the source repo. The
GitLab pipeline will automatically publish a new version of the chart to
Harbor that you can use for testing.

Once the MR is merged in the source repo, the GitLab pipeline will automatically
open a "bump version" MR in this repo to set the new value of `chartVersion` in
`values/{env}.yaml`.

You can check the available versions at:
* https://toolsbeta-harbor.wmcloud.org/harbor/projects/1693/repositories/wmcs-k8s-metrics/artifacts-tab
* https://tools-harbor.wmcloud.org/harbor/projects/1454/repositories/wmcs-k8s-metrics/artifacts-tab

## kube-state-metrics

This is an upstream chart to generate and expose cluster-level metrics.

Upstream repo: https://github.com/kubernetes/kube-state-metrics

We keep a copy of the container images used by the chart in our container
registry at https://docker-registry.toolforge.org/

### Upgrading kube-state-metrics

For compatibility info see:
https://github.com/kubernetes/kube-state-metrics#compatibility-matrix

To find the Helm chart version corresponding to a specific component version:
```
helm search repo kube-state-metrics --versions
```

You also need to import the new image into our registry.

You can check the available versions in our registry here:
https://docker-registry.toolforge.org/#!/taglist/kube-state-metrics

To import a new version:
```
cloudcumin1001:~$ sudo cookbook wmcs.toolforge.k8s.image.copy_to_registry --task-id Txxxxxx --origin-image registry.k8s.io/kube-state-metrics/kube-state-metrics:vX.Y.Z --dest-image-name kube-state-metrics --dest-image-version vX.Y.Z
```

You can check the available versions in our registry here:
https://docker-registry.toolforge.org/#!/taglist/kube-state-metrics

See also:
* https://artifacthub.io/packages/helm/prometheus-community/kube-state-metrics/
* https://explore.ggcr.dev/?repo=registry.k8s.io%2Fkube-state-metrics%2Fkube-state-metrics
* https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Kubernetes/Docker-registry#Uploading_custom_docker_images_from_an_external_registry

## metrics-server

This is an upstream chart, providing a source of container resource metrics for
Kubernetes built-in autoscaling pipelines.

Upstream repo: https://github.com/kubernetes-sigs/metrics-server

We keep a copy of the container images used by the chart in our container
registry at https://docker-registry.toolforge.org/

### Upgrading metrics-server

For compatibility info see:
https://github.com/kubernetes-sigs/metrics-server#compatibility-matrix

To find the Helm chart version corresponding to a specific component version:
```
helm search repo metrics-server --versions
```

You also need to import the new image into our registry.

You can check the available versions in our registry here:
https://docker-registry.toolforge.org/#!/taglist/metrics-server

To import a new version:
```
cloudcumin1001:~$ sudo cookbook wmcs.toolforge.k8s.image.copy_to_registry --task-id Txxxxxx --origin-image registry.k8s.io/metrics-server/metrics-server:vX.Y.Z --dest-image-name metrics-server --dest-image-version vX.Y.Z
```

See also
* https://artifacthub.io/packages/helm/metrics-server/metrics-server
* https://explore.ggcr.dev/?repo=registry.k8s.io/metrics-server/metrics-server
* https://wikitech.wikimedia.org/wiki/Portal:Toolforge/Admin/Kubernetes/Docker-registry#Uploading_custom_docker_images_from_an_external_registry

## metrics-server-api-certs

This runs the upstream
[incubator/raw](https://github.com/helm/charts/tree/master/incubator/raw) Helm
chart. This upstream chart is deprecated and no longer maintained.

We install a copy from our `wmf-stable` Helm registry
(`https://helm-charts.wikimedia.org/stable`).

### Upgrading metrics-server-api-certs

To publish a new version to wmf-stable, you need to send a patch to
https://gerrit.wikimedia.org/r/plugins/gitiles/operations/deployment-charts/

List available versions with `helm search repo --versions wmf-stable/raw`
(run it from lima-kilo, or a host where the wmf-stable repo is installed).

To update the chart version we run in Toolforge, modify
`metricsServerApiCertsChartVersion` in `values/{env}.yaml`.
