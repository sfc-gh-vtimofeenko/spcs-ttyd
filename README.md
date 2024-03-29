When working with containers it's useful to have a proper shell inside the
environment for debugging or general research purposes. This repository contains
the package definition and a Github action that creates and pushes a container
with bash as a webshell:

![screenshot of ttyd running in browser](./doc/main_screenshot.png)

# How to

There are two sample images provided:

- Nix-based one
- [Debian-based one](./non-nix/Dockerfile)

The instructions below could be applied to either one of them

## Initial setup

Follow the [common setup](https://docs.snowflake.com/developer-guide/snowpark-container-services/tutorials/common-setup)
tutorial to have the image repository and a compute pool in your account.

## With Github actions

1. Fork/clone this repository in your Github account
2. In your copy of this repository add action secrets (repository Settings >
   Secrets and variables > Actions):

    - `REGISTRY_URL`:
      `<snowflakeOrg-snowflakeAccount>.registry.snowflakecomputing.com/<database>/<schema>/<registry_name>`.
      See output of `SHOW IMAGE REPOSITORIES` for exact value
    - `SNOWFLAKE_USER`: username of Snowflake user that has access to the image
      repository
    - `SNOWFLAKE_PASSWORD`: password for `SNOWFLAKE_USER`

3. Run "Build and push image to Snowflake" action for the chosen image

## Without Github actions

SPCS (at the time of writing) only works with `x86_64` images. So, on an M1
machine you would need access to a remote builder capable of building `x86_64`
packages – for example a virtual machine.

### Nix-based workflow

The nix-based image requires [`nix`](https://nixos.org/download).

1. Have `nix` available (optionally with `direnv`)
2. Clone the repository
3. Configure the environment variables:

    If using `direnv`: edit `.envrc`.

    Otherwise, define `REGISTRY_URL`, `SNOWFLAKE_USER` and `SNOWFLAKE_PASSWORD`
    variables

4. Run `nix run <pathToClonedRepo>#buildAndPushToSpcs -- "ttydContainer"`

### Docker-based workflow

Change directory to `./non-nix/` and follow the "Build image and upload" steps
from [Snowpark container services
tutorial](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/tutorials/tutorial-1#build-an-image-and-upload).

## Final steps

After the image has been pushed to Snowflake (through action or from local
machine).

1. Create the service:

    ```SQL
    CREATE SERVICE <serviceName>
    IN COMPUTE POOL <computePoolName>
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: <container_name>
          image: /<database>>/<schema>/<registry_name>/<containerTag>:latest
          command:
            - "ttyd"
            - "--port=8000"
            - "--writable"
            - "sh"
      endpoints:
        - name: ttyd
          port: 8000
          public: true
    $$;
    ```

    where `<containerTag>` is `nix-ttydcontainer` or `ttydcontainer`. Check
    action logs for the specific value.

2. Wait for endpoints provisioning to complete (you can monitor the output of
   `SHOW ENDPOINTS IN SERVICE <serviceName>`)
3. Open the `ttyd` endpoint URL

# Packages in the container

The container comes with certain tools pre-installed (see the list in [package
definition](./packages/ttydContainer/package.nix)).

Additional packages can be temporarily pulled in as:

```shell
$ nix shell nixpkgs#hello
$ hello
Hello World!
# or
$ nix run nixpkgs#hello
Hello World!
```

This works for any package from [nixpkgs](https://search.nixos.org/) or for any
flake reference.

To add/remove a package to the container, edit the [container
definition](./packages/ttydContainer/package.nix) file and
rerun the pipeline.

# Running without Nix (general instructions)

The main mechanism through which the shell is displayed in the browser is
[ttyd](https://tsl0922.github.io/ttyd/) which can be added to any other Docker
image.

A sample Debian-based image is provided in this repo.
