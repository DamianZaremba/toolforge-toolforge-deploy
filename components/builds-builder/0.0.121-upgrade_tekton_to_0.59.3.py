#!/usr/bin/env python3
"""
Script to upgrade builds-builder and builds-api to the newer tekton 0.59.3.


This has to be run from a k8s control node, *instead* of running the toolforge.component.deploy cookbook.

It will:
* patch existing tekton CRDs
* download the newer ones and patch them too
* upgrade builds-builder (this pulls the newer tekton)
* upgrade builds-api (with support for the newer tekton)
* unpatch the new CRDs to have the same conversion hooks they had from upstream

"""
from typing import Any
import requests
import subprocess
import tempfile
import pathlib
import click
import yaml


CRDS_URL = "https://gitlab.wikimedia.org/repos/cloud/toolforge/builds-builder/-/raw/1851d220d2ec264823e964ec0c08fdd8ee8fb8d0/deployment/chart/crds/tekton.yaml?inline=false"
CURDIR = pathlib.Path(__file__).parent
BASEDIR = CURDIR.parent.parent
REMOVE_CONVERSIONS_PATCH = {
    "spec": {"conversion": {"$retainKeys": ["strategy"], "strategy": "None"}}
}


def patch_existing_crds_without_hooks():
    existing_crds = (
        subprocess.check_output(["kubectl", "get", "crds", "-o=name"])
        .decode("utf-8")
        .split()
    )

    for crd in existing_crds:
        if not crd.endswith("tekton.dev"):
            continue
        # we need to patch the old to remove the conversion webhook *before* applying the new
        patch(
            patch=REMOVE_CONVERSIONS_PATCH,
            object_fqp=crd,
        )


def apply_crds_without_hooks():
    response = requests.get(CRDS_URL)
    response.raise_for_status()

    crds_data = list(yaml.safe_load_all(response.text))
    for crd in crds_data:
        if "conversion" in crd["spec"]:
            # Yep, the string 'None', not the json `null` value
            crd["spec"]["conversion"]["strategy"] = "None"
            del crd["spec"]["conversion"]["webhook"]

    apply(k8s_objects=crds_data)


def upgrade_builds_builder():
    subprocess.check_call([f"{BASEDIR}/deploy.sh", "builds-builder", "--wait"])


def upgrade_builds_api():
    subprocess.check_call([f"{BASEDIR}/deploy.sh", "builds-api", "--wait"])


def apply_crds_with_hooks():
    response = requests.get(CRDS_URL)
    response.raise_for_status()

    crds_data = list(yaml.safe_load_all(response.text))
    apply(k8s_objects=crds_data)


def patch(patch: dict[str, Any], object_fqp: str):
    """
    We don't have kubernetes python libs in the bastion/control nodes, so defaulting to cli.

    object_fqd is the fully qualified path, like:
        customresourcedefinition.apiextensions.k8s.io/taskruns.tekton.dev
    """
    tmp_file = pathlib.Path(tempfile.mktemp())
    with tmp_file.open("w") as tmp_file_df:
        yaml.safe_dump(patch, tmp_file_df)

    cmd: list[str] = [
        "kubectl",
        "patch",
        "--patch-file",
        str(tmp_file),
        object_fqp,
    ]
    try:
        subprocess.check_call(cmd)
    except subprocess.CalledProcessError as error:
        raise Exception(f"Error running {cmd}") from error

    tmp_file.unlink()


def apply(k8s_objects: list[dict[str, Any]]):
    """
    We don't have kubernetes python libs in the bastion/control nodes, so defaulting to cli.
    """
    if isinstance(k8s_objects, dict):
        # in case we get passed a single object directly, we want a list of them
        k8s_objects = [k8s_objects]

    tmp_file = pathlib.Path(tempfile.mktemp())
    with tmp_file.open("w") as tmp_file_df:
        yaml.safe_dump_all(k8s_objects, tmp_file_df)

    cmd: list[str] = ["kubectl", "apply", "-f", str(tmp_file)]
    try:
        subprocess.check_call(cmd)
    except subprocess.CalledProcessError as error:
        raise Exception(f"Error running {cmd}") from error

    tmp_file.unlink()


# order matters
STAGES = {
    "patch_existing_crds_without_hooks": patch_existing_crds_without_hooks,
    "apply_crds_without_hooks": apply_crds_without_hooks,
    "upgrade_builds_builder": upgrade_builds_builder,
    "upgrade_builds_api": upgrade_builds_api,
    "apply_crds_with_hooks": apply_crds_with_hooks,
}


@click.command(help=__doc__)
@click.option(
    "--stage",
    "stages",
    type=click.Choice(
        choices=list(STAGES.keys()),
    ),
    multiple=True,
    default=list(STAGES.keys()),
)
def main(stages: list[str]):
    click.echo("Running the upgrade script for builds-builder to 0.121.0")
    for stage in stages:
        click.echo(f"{stage}: starting")
        stage_fn = STAGES[stage]
        stage_fn()
        click.echo(f"{stage}: done")

    click.echo(
        r"Done \o/, please run the functional tests from the bastion to make sure everything works as expected."
    )


if __name__ == "__main__":
    main()
