#!/usr/bin/env python3
## Only run the first time we move from kustomize to helmfile
from __future__ import annotations
from subprocess import check_call, check_output
import click
from dataclasses import dataclass


@dataclass(frozen=True)
class Resource:
    kind: str
    name: str
    namespace: str
    release: str

    @classmethod
    def from_line(cls, line: str, namespace: str, release: str) -> "Resource":
        kind, name = line.split("/", 1)
        return cls(kind=kind, name=name, namespace=namespace, release=release)


@dataclass(frozen=True)
class ResourceMatch:
    kind: str = ""
    name: str = ""
    namespace: str = ""
    release: str = ""

    def matches(self, resource: Resource) -> bool:
        return bool(
            self.kind and self.kind == resource.kind
            and self.name and self.name == resource.name
            and self.namespace and self.namespace == resource.namespace
            and self.release and self.release == resource.release
        )


@dataclass(frozen=True)
class Release:
    name: str
    release_namespace: str
    resource_namespace: str
    selector: str
    resource_matches: list[ResourceMatch]

    def adopt(self, resource: Resource) -> None:
        resource_str = f"{resource.kind}/{resource.name}"
        adopt(
            release=self,
            resource=resource_str,
        )


SELECTOR = "app.kubernetes.io/part-of=toolforge-build-service"
TO_ADOPT = [
    Release(
        name="builds-builder",
        release_namespace="builds-builder",
        resource_namespace="tekton-pipelines",
        selector=SELECTOR,
        resource_matches=[
            ResourceMatch(kind="rolebinding"),
            ResourceMatch(kind="role"),
            ResourceMatch(kind="secret"),
            ResourceMatch(kind="persistentvolume"),
            ResourceMatch(kind="pipeline"),
            ResourceMatch(kind="task"),
            ResourceMatch(kind="serviceaccount"),
            ResourceMatch(kind="horizontalpodautoscaler"),
            ResourceMatch(kind="deployment"),
            ResourceMatch(kind="service"),
            ResourceMatch(kind="configmap"),

            ResourceMatch(kind="podsecuritypolicy", name="tekton-pipelines"),
            ResourceMatch(kind="clusterrole", namespace="default"),
            ResourceMatch(kind="clusterrolebinding", namespace="default"),
            ResourceMatch(kind="customresourcedefinition", namespace="default"),
            ResourceMatch(kind="validatingwebhookconfiguration", namespace="default"),
            ResourceMatch(kind="mutatingwebhookconfiguration", namespace="default"),
        ],
    ),
    Release(
        name="builds-builder",
        release_namespace="builds-builder",
        resource_namespace="image-build",
        selector=SELECTOR,
        resource_matches=[
            ResourceMatch(kind="role"),
            ResourceMatch(kind="rolebinding"),
            ResourceMatch(kind="secret"),
            ResourceMatch(kind="pipeline"),
            ResourceMatch(kind="task"),
            ResourceMatch(kind="configmap"),
            ResourceMatch(kind="serviceaccount"),
            ResourceMatch(kind="podsecuritypolicy", name="image-build-controller"),
            ResourceMatch(kind="podsecuritypolicy", name="image-build-defaults"),
            ResourceMatch(kind="persistentvolume", name="minikube-user-pvc"),
        ],
    ),
]


def annotate(resource: str, namespace: str, annotations: dict[str, str]) -> None:
    for name, value in annotations.items():
        check_call(
            ["kubectl", "annotate", f"-n={namespace}", "--overwrite", resource, f"{name}={value}"]
        )


def label(resource: str, namespace: str, labels: dict[str, str]) -> None:
    for name, value in labels.items():
        check_call(
            ["kubectl", "label", f"-n={namespace}", "--overwrite", resource, f"{name}={value}"]
        )


def adopt(resource: str, release: Release) -> None:
    annotate(resource, namespace=release.resource_namespace, annotations={
        "meta.helm.sh/release-name": release.name,
        "meta.helm.sh/release-namespace": release.release_namespace,
    })
    label(resource, namespace=release.resource_namespace, labels={"app.kubernetes.io/managed-by": "Helm"})


def get_kind(kind: str, namespace: str, selector: str) -> list[str]:
    output = check_output([
        "kubectl", "get", f"-n={namespace}", f"-l={selector}", f"{kind}", "-o=name"
    ])
    return output.decode("utf-8").splitlines()


def get_matches(resource_match: ResourceMatch, release: Release) -> list[Resource]:
    results = []

    namespace = resource_match.namespace or release.resource_namespace
    if not resource_match.name:
        for match in get_kind(kind=resource_match.kind, namespace=namespace, selector=release.selector):
            results.append(Resource.from_line(line=match, namespace=namespace, release=release.name))
    else:
        results.append(Resource(kind=resource_match.kind, name=resource_match.name, namespace=namespace, release=release.name))

    return results


@click.command()
@click.option(
    "--with-persistent-volume",
    is_flag=True,
    default=False,
)
def main(with_persistent_volume: bool):
    for release in TO_ADOPT:
        click.echo(f"## Adopting namespace {release.resource_namespace}")
        adopt(f"namespace/{release.resource_namespace}", release=release)
        for resource_match in release.resource_matches:
            for resource in get_matches(resource_match=resource_match, release=release):
                click.echo(click.style(f"## Adopting resource {resource}", fg="green"))
                if resource.kind != "persistentvolume" or with_persistent_volume:
                    release.adopt(resource=resource)


if __name__ == "__main__":
    main()
