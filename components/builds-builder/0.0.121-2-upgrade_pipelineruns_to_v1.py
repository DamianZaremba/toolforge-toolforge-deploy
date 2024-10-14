#!/usr/bin/env python3
"""
Script to upgrade all pipelineruns to v1.

This is needed because all the v1beta1 stored pipelineruns will need to be converted *every time* anyone tries to select
any pipelinerun.

Currently in tools this means ~800 conversion requests for any request to the build service.


This has to be run from a k8s control node, *instead* of running the toolforge.component.deploy cookbook.

It will:
* go over all the pipelineruns in the image-build namespace
* download the v1 version (this needs a round to the conversion hook)
* download the v1beta1 version and extract the taskruns (this is the currently stored version)
* add the `childRefeneces` section with the taskruns to the v1 version
* upload the modified v1 version (this effectively stores the v1 version retaining the links to taskruns)
"""
from typing import Any, Literal
import subprocess
import tempfile
import pathlib
import click
import yaml


CURDIR = pathlib.Path(__file__).parent
BASEDIR = CURDIR.parent.parent


def get_pipelinerun_names() -> list[str]:
    return get_all_names(resource="pipelineruns")


def get_taskrun_names() -> list[str]:
    return get_all_names(resource="taskruns")


def get_all_names(resource: str) -> list[str]:
    """This will be the only request that takes >10s."""
    cmd: list[str] = [
        "kubectl",
        "get",
        "-o",
        "name",
        "-n",
        "image-build",
        resource,
    ]
    try:
        raw_list = subprocess.check_output(cmd)
    except subprocess.CalledProcessError as error:
        raise Exception(f"Error running {cmd}") from error

    # they output the type prefixed, we only want the name
    pipelinerun_names = [
        name.rsplit("/", 1)[-1] for name in raw_list.decode("utf-8").split()
    ]
    return pipelinerun_names


def get_pipeline(name: str, version: Literal["v1", "v1beta1"]) -> dict[str, Any]:
    """
    We don't have kubernetes python libs in the bastion/control nodes, so defaulting to cli.
    """
    cmd: list[str] = [
        "kubectl",
        "get",
        "-n",
        "image-build",
        "-o",
        "yaml",
        f"pipelineruns.{version}.tekton.dev",
        name,
    ]
    try:
        output = subprocess.check_output(cmd)
    except subprocess.CalledProcessError as error:
        raise Exception(f"Error running {cmd}") from error

    return yaml.safe_load(output)


def k8s_patch_status_subresource(new_value: dict[str, Any], pipelinerun_name: str):
    """
    We don't have kubernetes python libs in the bastion/control nodes, so defaulting to cli.
    """
    tmp_file = pathlib.Path(tempfile.mktemp())
    with tmp_file.open("w") as tmp_file_df:
        yaml.safe_dump(new_value, tmp_file_df)

    cmd: list[str] = [
        "kubectl",
        "patch",
        "pipelineruns",
        "--namespace=image-build",
        "--subresource=status",
        "--type=merge",
        f"--patch-file={tmp_file}",
        pipelinerun_name,
    ]
    try:
        subprocess.check_call(cmd)
    except subprocess.CalledProcessError as error:
        raise Exception(f"Error running {cmd}") from error

    tmp_file.unlink()


@click.command(help=__doc__)
def main() -> None:
    yes_all = False
    click.echo(
        "Running the pipelinerun upgrade script (only do so after upgrade!) for builds-builder to 0.121.0"
    )
    pipelinerun_names = get_all_names(resource="pipelineruns")
    click.echo(f"I'm going to migrate {len(pipelinerun_names)} pipelineruns")
    all_taskrun_names = get_all_names(resource="taskruns")
    for pipelinerun_name in pipelinerun_names:
        click.echo(f"    Pipelinerun {pipelinerun_name}")
        v1_version = get_pipeline(name=pipelinerun_name, version="v1")
        if "childReferences" in v1_version["status"]:
            click.echo(
                "        Skipping, it seems it's already stored in version v1 (it has childReferences)"
            )
            continue

        v1_version["status"]["childReferences"] = []
        v1beta1_version = get_pipeline(name=pipelinerun_name, version="v1beta1")
        if "taskRuns" not in v1beta1_version["status"]:
            # fall back to filtering from the known runs
            taskrun_names = [
                taskrun_name
                for taskrun_name in all_taskrun_names
                if taskrun_name.startswith(pipelinerun_name)
            ]
            if not taskrun_names:
                click.echo(
                    "      Skipping, the v1beta1 version has no task runs, maybe it failed completely to launch?"
                )
                continue
        else:
            taskrun_names = list(v1beta1_version["status"]["taskRuns"].keys())

        patch: dict[str, Any] = {"status": {"childReferences": []}}
        for taskrun_name in taskrun_names:
            patch["status"]["childReferences"].append(
                {
                    "apiVersion": "tekton.dev/v1",
                    "kind": "TaskRun",
                    "name": taskrun_name,
                    "pipelineTaskName": "build-from-git",
                }
            )

        click.echo("    Uploading modified v1 pipelinerun...")
        if not yes_all:
            click.echo(f"-- {pipelinerun_name} ------------------------")
            print(yaml.safe_dump(patch))
            click.echo("--------------------------")
            answer = click.prompt(
                "Are you sure you want to continue?",
                default="all",
                type=click.Choice(choices=["yes", "no", "all"]),
                show_choices=True,
            )
            if answer == "no":
                click.echo("Aborting")
                return
            if answer == "all":
                yes_all = True

        k8s_patch_status_subresource(new_value=patch, pipelinerun_name=pipelinerun_name)

    click.echo(
        r"Done \o/, please run the functional tests from the bastion to make sure everything works as expected."
    )


if __name__ == "__main__":
    main()
