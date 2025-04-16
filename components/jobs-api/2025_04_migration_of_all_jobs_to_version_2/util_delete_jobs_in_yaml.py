#!/usr/bin/env python3
import sys
import yaml
import subprocess


def main():
    """
    This script deletes all the jobs in the provided yaml.
    """
    if len(sys.argv) != 2:
        print("Usage: ./util_delete_jobs_in_yaml.py <user> <jobs_file>")
        sys.exit(1)

    user = sys.argv[1]
    jobs_file = sys.argv[2]

    print(f"Processing jobs file {jobs_file} for user {user}")
    with open(jobs_file, "r") as f:
        jobs = yaml.safe_load(f)

    print(f"{len(jobs)} jobs to be deleted...")
    delete_count = 0
    for job in jobs:
        result = subprocess.run(f"sudo -i -u {user} -- bash -c \"toolforge jobs delete {job['name']}\"", shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"Successfully deleted job {job['name']} for user {user}")
            delete_count += 1
        else:
            print(f"Failed to delete job {job['name']} for user {user}")

    print(f"{delete_count} jobs successfully deleted")

if __name__ == "__main__":
    main()
