# Migration of all the jobs to the latest job version

Task: T359649

## Files

* `01_create_tools_migrations_list.sh`: This file get's the name of the tools that have jobs that require migration (for both scheduled and continuous jobs).
* `02_create_tools_jobs_dump.sh`:  This script will create a dump of the jobs of all the tools gotten in Step 1 by becoming the respective tools and running toolforge jobs dump -f <dump_file_path>.
* `03_migrate_tool_jobs_to_latest_version.sh`:  This script takes the dumps created in Step 2, becomes the respective tools and runs toolforge jobs load <dump_file_path>. This is really all we need to do to migrate the whole jobs.
* `util_remove_one_off.py`: This script removes one-off jobs from a job list. `02_create_tools_jobs_dump.sh` depends on this script to function.
* `util_delete_jobs_in_yaml.py`: This script deletes all the jobs in a job list. It is neccessary because `jobs load` has lost the ability to detect drift in job versions, so the way to update a jobs version is now to manually delete it before loading. `03_migrate_tool_jobs_to_latest_version.sh` depends on this script to function.

## To test the scripts

1. `ssh login.toolforge.org` and create these scripts on your home dir. **Note** that you need to be a toolforge admin for this to work.
2. `sudo -i -u tools.maintain-harbor`
3. `toolforge jobs flush` to make sure no job exists.
4. copy the `test_cron_script.sh` to the home dir of the tool if not there.
5. `kubectl create -f v1_continous_job_sample.yaml -f v1_cronjob_sample.yaml`. I specifically made them to use the old `version 1` format so that's already done for you (you can inspect the files to make sure). Note that they have `maintain-harbor` hardcoded in them, if you want to use another tool like `tf-test` in lima-kilo, you can run `sed -ie 's/maintain-harbor/tf-test/g' v1_continuous_job_sample.yaml v1_cronjob_sample.yaml`.
6. now `toolforge jobs list` should show that these jobs have been created.
7. write the name `maintain-harbor` into the file `/tmp/tools-migration/tools_migration_list.txt` and save it. This is because we are not going to run the script `create_tools_migrations_list.sh` since that will populate `/tmp/tools-migration/tools_migration_list.txt` with the name of the tools that needs migration. We don't want that so we do that part manually.
8. execute `./create_tools_jobs_dump.sh`. You must have created this file in **1**.
9. execute `./migrate_tool_jobs_to_latest_version.sh`. You must have created this file in **1**.
10. You can check the k8s spec of these jobs to verify that they have been updated to the latest job version.
11. check `/tmp/tools-migration/tools_migration.log` for logs if there is a need.
