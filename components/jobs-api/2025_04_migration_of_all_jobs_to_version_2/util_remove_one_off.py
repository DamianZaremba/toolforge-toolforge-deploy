#!/usr/bin/env python3
import sys
import yaml
from typing import Any


def is_oneoff(job: dict[str, Any]) -> bool:
    """
    Check if a job is a oneoff job.
    """
    return "schedule" not in job and not job.get("continuous", False)


def main():
    """
    This script removes all oneoff jobs from the YAML file.
    """
    if len(sys.argv) != 2:
        print("Usage: ./util_remove_one_off.py <jobs_file>")
        sys.exit(1)

    jobs_file = sys.argv[1]
    print(f"Processing jobs file: {jobs_file}")

    with open(jobs_file, "r") as f:
        jobs = yaml.safe_load(f)

    if jobs is None:
        print(f"No jobs found in {jobs_file}. Nothing to do.")
        return

    if not isinstance(jobs, list):
        print(f"Error: YAML content is not a list (got {type(jobs)}). Skipping.")
        sys.exit(1)

    print(f"Loaded {len(jobs)} jobs from {jobs_file}")

    original_count = len(jobs)
    jobs = [job for job in jobs if not is_oneoff(job)]
    removed_count = original_count - len(jobs)

    print(f"Removed {removed_count} one-off jobs, keeping {len(jobs)} jobs")

    with open(jobs_file, "w") as f:
        yaml.dump(jobs, f)

    print(f"Updated {jobs_file} with filtered jobs")


if __name__ == "__main__":
    main()
