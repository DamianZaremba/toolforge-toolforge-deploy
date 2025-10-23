#!/usr/bin/env python3
"""
Script to upgrade all taskruns to v1.

This is needed because all the v1beta1 stored taskruns will need to be converted *every time* anyone tries to select
any taskrun.

Currently in tools this means ~800 conversion requests for any request to the build service.


This has to be run from a k8s control node, *instead* of running the toolforge.component.deploy cookbook.

It will:
* go over all the taskruns in the image-build namespace
* download the v1 version (this needs a round to the conversion hook)
* download the v1beta1 version and extract the taskruns (this is the currently stored version)
* upload the v1 version (this effectively stores the v1 version as the main one)
"""
import difflib
import os
import sys
from typing import Any, Literal
import subprocess
import tempfile
import pathlib
import click
import yaml


CURDIR = pathlib.Path(__file__).parent
BASEDIR = CURDIR.parent.parent


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
    taskrun_names = [
        name.rsplit("/", 1)[-1] for name in raw_list.decode("utf-8").split()
    ]
    return taskrun_names


def get_taskrun(name: str, version: Literal["v1", "v1beta1"]) -> dict[str, Any]:
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
        f"taskruns.{version}.tekton.dev",
        name,
    ]
    try:
        output = subprocess.check_output(cmd)
    except subprocess.CalledProcessError as error:
        raise Exception(f"Error running {cmd}") from error

    return yaml.safe_load(output)


def k8s_apply(new_value: dict[str, Any]):
    """
    We don't have kubernetes python libs in the bastion/control nodes, so defaulting to cli.
    """
    tmp_file_fd, tmp_file_name = tempfile.mkstemp()
    # otherwise we leak open files
    tmp_file = pathlib.Path(tmp_file_name)
    with tmp_file.open("w") as tmp_file_df:
        yaml.safe_dump(new_value, tmp_file_df)
    os.close(fd=tmp_file_fd)

    cmd: list[str] = [
        "kubectl",
        "apply",
        "--namespace=image-build",
        "-f",
        f"{tmp_file}",
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
        "Running the taskrun upgrade script (only do so after upgrade!) for builds-builder to 0.121.0 "
        "(when we did the tekton migration)"
    )
    taskrun_names = get_all_names(resource="taskruns")
    click.echo(f"I'm going to migrate {len(taskrun_names)} taskruns")
    for taskrun_name in taskrun_names:
        click.echo(f"    Taskrun {taskrun_name}")
        v1_version = get_taskrun(name=taskrun_name, version="v1")
        v1beta1_version = get_taskrun(name=taskrun_name, version="v1beta1")
        click.echo("    Uploading v1 taskrun...")
        if not yes_all:
            click.echo(f"-- {taskrun_name} Diff ------------------------")
            diff = difflib.unified_diff(
                yaml.safe_dump(v1_version).splitlines(keepends=True),
                yaml.safe_dump(v1beta1_version).splitlines(keepends=True),
                fromfile="v1",
                tofile="v1beta1",
            )
            print("".join(diff), end="")
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

        k8s_apply(new_value=v1_version)

    click.echo(
        r"Done \o/, please run the functional tests from the bastion to make sure everything works as expected."
    )


if __name__ == "__main__":
    main()
