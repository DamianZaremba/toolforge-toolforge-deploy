#!/usr/bin/env bats
# shellcheck disable=SC2155
# SC2155 (warning): Declare and assign separately to avoid masking return values.
# bats file_tags=tools,components-api,slow,deploy-tests
set -o nounset


setup_file() {
    load "components-common"
    export BATS_NO_PARALLELIZE_WITHIN_FILE=true

    [[ ! -f "$BATS_SKIP_FILE" ]] && flush_everything
}

setup() {
    load "components-common"
    _components_setup
    export TOOL_NAME="${USER#*.}"

    cat > "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config.yaml <<EOC
config_version: "v1beta1"
components:
  component1:
    component_type: continuous
    build:
      repository: $SAMPLE_REPO_URL
      ref: main
    run:
      command: web
EOC

    cat > "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config-with-scheduled.yaml <<EOC
config_version: "v1beta1"
components:
  component1:
    component_type: continuous
    build:
      repository: $SAMPLE_REPO_URL
      ref: main
    run:
      command: web
  cron1:
    component_type: scheduled
    build:
      reuse_from: component1
    run:
      schedule: "@daily"
      command: web
EOC
}

@test "creating deploy with same ref reuses the build" {
    toolforge components config delete --yes-im-sure &>/dev/null || :
    toolforge components config create "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config.yaml
    toolforge components deployment create
    retry "toolforge components deployment list --json | jq -e '.data.deployments[0].status == \"successful\"'"
    old_build_id=$(toolforge components deployment list --json | jq '.data.deployment[0].builds.component1.build_id')

    toolforge components deployment create
    retry "toolforge components deployment list --json | jq -e '.data.deployments[0].builds.component1.build_id != \"no-id-yet\"'"
    new_build_id=$(toolforge components deployment list --json | jq '.data.deployment[0].builds.component1.build_id')

    assert_equal "$old_build_id" "$new_build_id"

    # make sure it worked, short-circuit if it failed
    retry "toolforge components deployment show --json | jq -e '.status | IN (\"successful\", \"failed\", \"skipped\", \"cancelled\")'" 300
    retry "toolforge components deployment show --json | jq -e '.status == \"successful\"'" 2
}


@test "adding scheduled job that reuses existing component build reuses it" {
    toolforge components config create "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config-with-scheduled.yaml
    old_build_id=$(toolforge components deployment list --json | jq '.data.deployment[0].builds.component1.build_id')

    toolforge components deployment create
    retry "toolforge components deployment list --json | jq -e '.data.deployments[0].builds.component1.build_id != \"no-id-yet\"'"
    first_component_new_build_id=$(toolforge components deployment list --json | jq '.data.deployment[0].builds.component1.build_id')
    second_component_new_build_id=$(toolforge components deployment list --json | jq '.data.deployment[0].builds.cron1.build_id')

    assert_equal "$old_build_id" "$first_component_new_build_id"
    assert_equal "$old_build_id" "$second_component_new_build_id"

    # make sure it worked, short-circuit if it failed
    retry "toolforge components deployment show --json | jq -e '.status | IN (\"successful\", \"failed\", \"skipped\", \"cancelled\")'" 300
    retry "toolforge components deployment show --json | jq -e '.status == \"successful\"'" 2
}


teardown() {
    _components_teardown
}
