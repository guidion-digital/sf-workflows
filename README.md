# Salesforce Deployment Workflows

This repository hosts reusable GitHub Actions workflows that standardize how our
teams deploy Salesforce projects and packages. The most commonly reused
workflow is [`sf_deployer.yaml`](.github/workflows/sf_deployer.yaml), which
handles authenticating with Salesforce, selecting the appropriate test level,
and posting deployment updates to Slack.

## Using `sf_deployer.yaml` from another repository

You can call the workflow remotely by referencing it with the `uses` keyword in
your own GitHub Actions configuration. The example below demonstrates how a
consumer repository can trigger a deployment manually, pass a branch name, and
fan out secrets from organization or environment storage.

```yaml
# .github/workflows/deploy_develop.yaml in the consumer repository


name: Deploy sf-home to dev environment

on:
  push:
    branches:
      - "dev"

jobs:
  deploy:
    uses: guidion-digital/sf-workflows/.github/workflows/sf_deployer.yaml@v0
    with:
      environment_name: dev
      SF_LOGIN_URL: ${{ vars.SF_LOGIN_URL_DEV }}
      SF_USERNAME: ${{ vars.SF_USERNAME_DEV }}
      SF_CLIENT_ID: ${{ vars.SF_CLIENT_ID_DEV }}
      SLACK_CHANNEL: ${{ vars.slack_channel }}
      source_dir: ${{ vars.source_dir }}
      test_dir:  ${{ vars.test_dir }}
    secrets: 
      SF_CLIENT_KEY: ${{ secrets.SF_CLIENT_KEY_DEV }}
      SLACK_TOKEN: ${{ secrets.SLACK_TOKEN }}
```

### Required GitHub environment setup

- Most secrets and variables are defined on the Guidion Organization level
  they can be shared with the repository that need these values. 
  Ask Team Infra to add these secrets and variables to the repositories.

- For example the following organization variables inputs are available for dev: `SF_LOGIN_URL`, `SF_USERNAME`, and `SF_CLIENT_ID`:

  `SF_LOGIN_URL_DEV`

  `SF_LOGIN_USERNAME_DEV`

  `SF_CLIENT_ID_DEV`

- For example the following organization secret inputs are available for dev: `SF_CLIENT_KEY` and `SLACK_TOKEN`

  `SF_CLIENT_KEY_DEV`

  `SLACK_TOKEN`

### Additional tips

- Omit optional inputs like `sf_testlevel`, `slack_channel`, or `test_dir` to
  rely on the defaults defined by the reusable workflow.
- If you do not need Slack notifications, you can remove the `slack_channel`
  input and `SLACK_TOKEN` secret.
- The workflow runs in the `salesforce/cli:latest-slim` container. Ensure your
  deployment artifacts (e.g., the `src` directory) are compatible with the
  Salesforce CLI deploy commands.
