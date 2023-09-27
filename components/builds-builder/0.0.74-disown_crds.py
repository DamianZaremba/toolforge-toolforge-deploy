#!/usr/bin/env python3
# We need to disown the crds as now they are installed separately in the crd step (helm hook) and not owned anymore,
# so help would remove them if we don't disown them beforehand.
from __future__ import annotations
import json
from subprocess import check_call, check_output
import click
from dataclasses import dataclass

import yaml
import gzip
import base64


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

    def disown(self, resource: Resource) -> None:
        resource_str = f"{resource.kind}/{resource.name}"
        disown(
            release=self,
            resource=resource_str,
        )


SELECTOR = "app.kubernetes.io/part-of=toolforge-build-service"
TO_DISOWN = [
    Release(
        name="builds-builder",
        release_namespace="builds-builder",
        resource_namespace="default",
        selector=SELECTOR,
        resource_matches=[
            ResourceMatch(kind="customresourcedefinition", namespace="default"),
        ],
    ),
]


def remove_annotations(resource: str, namespace: str, annotations: list[str]) -> None:
    for annotation in annotations:
        check_call(
            ["kubectl", "annotate", f"-n={namespace}", "--overwrite", resource, f"{annotation}-"]
        )


def remove_label(resource: str, namespace: str, labels: list[str]) -> None:
    for label in labels:
        check_call(
            ["kubectl", "label", f"-n={namespace}", "--overwrite", resource, f"{label}-"]
        )


def disown(resource: str, release: Release) -> None:
    remove_annotations(resource, namespace=release.resource_namespace, annotations=[
        "meta.helm.sh/release-name",
        "meta.helm.sh/release-namespace",
    ])
    remove_label(resource, namespace=release.resource_namespace, labels=["app.kubernetes.io/managed-by"])


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
    "--dry-run",
    is_flag=True,
    default=False,
)
def main(dry_run: bool):
    prefix = ""
    if dry_run:
        prefix = "DRY-RUN: "

    for release in TO_DISOWN:
        for resource_match in release.resource_matches:
            click.echo(f"checking {resource_match}")
            for resource in get_matches(resource_match=resource_match, release=release):
                click.echo(click.style(f"{prefix}## Adopting resource {resource}", fg="green"))
                if not dry_run:
                    release.disown(resource=resource)
                else:
                    click.echo("   Not really, dry run")

        click.echo(f"Now remember to remove the release state: kubectl delete secrets -n={release.release_namespace}")


if __name__ == "__main__":
    main()
