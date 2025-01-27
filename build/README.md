# NREL Staff Instructions for Building Custom Singularity Images for HPC usage

## *NOTE: THIS ONLY SUPPORTS OPENSTUDIO VERSIONS > 3.0*

## Modify the Dockerfile to change OpenStudio version

## Editing the Gemfile to install the Gems of your choice

* Determine which specific commit of OpenStudio Standards you want to pull. You will need the full SHA.

* Open `/ComStock-Internal/resources/Gemfile` in a text editor and update the existing strings with the SHA you want.

* Save the Gemfile.

## Creating Singularity Image

* Build Singularity/Docker Image

    ```bash
    cd C:\path\to\comstock-internal
    ```

* Build Singularity/Docker Image

    ```bash
    docker build -t singularity -f build/singularity/Dockerfile ./build
    ```

* Pull and deploy registry image

    ```bash
    docker pull registry:2
    docker run -d -p 5000:5000 --name registry registry:2
    ```

* Build OpenStudio Container (Locally) and push it to the local registry

    ```bash
    docker build -t docker-openstudio -f build/Dockerfile --progress plain .
    docker tag docker-openstudio:latest 127.0.0.1:5000/docker-openstudio:latest
    docker push 127.0.0.1:5000/docker-openstudio:latest
    ```

* Launch the Container (in privileged mode with docker.sock mounted in the container)

    __*Windows: change the line endings in your `C:\path\to\comstock-internal\build\singularity\build_singularity.sh` file from Windows (CR LF) to Unix (LF).  You can do this with Notepad++ using Edit > EOL Conversion or VSCode using the Change End of Line Sequence command.  If you don't, you will get the error `: No such file or directory` in the next step*__

    ```bash
    cd C:\path\to\comstock-internal\build
    ```

    ```bash
    # Mac/Linux:
    docker run -it --rm --privileged -v $(pwd):/root/build -v /var/run/docker.sock:/var/run/docker.sock --network container:registry singularity /root/build/singularity/build_singularity.sh

    # Windows:
    docker run -it --rm --privileged -v %CD%:/root/build -v /var/run/docker.sock:/var/run/docker.sock --network container:registry singularity /root/build/singularity/build_singularity.sh
    ```

* The singularity image should be at `C:\path\to\comstock-internal\build docker-openstudio.simg`. Hop inside the singularity container to test the new image

    ```bash
    # Start the docker container

    # Mac/Linux:
    docker run -it --privileged --rm -v $(pwd):/root/build singularity /bin/bash

    # Windows:
    docker run -it --privileged --rm -v %CD%:/root/build singularity /bin/bash
    ```

    ```bash
    # Load the singularity image inside this docker container

    # Mac/Linux:
    singularity shell -B $(pwd):/singtest docker-openstudio.simg

    # Windows:
    singularity shell docker-openstudio.simg
    ```

    ```bash
    # List the gems available to the openstudio CLI
    openstudio --verbose --bundle /var/oscli/Gemfile --bundle_path /var/oscli/gems --bundle_without native_ext gem_list

    # You should see output similar to this.
    # Verify that the openstudio-standards gem specified has the expected SHA:
    bundler (1.17.1) ':/ruby/2.2.0/gems/bundler-1.17.1'
    rake (12.3.1) '/var/oscli/gems/ruby/2.2.0/gems/rake-12.3.1'
    ansi (1.5.0) '/var/oscli/gems/ruby/2.2.0/gems/ansi-1.5.0'
    ast (2.4.1) '/var/oscli/gems/ruby/2.2.0/gems/ast-2.4.1'
    builder (3.2.4) '/var/oscli/gems/ruby/2.2.0/gems/builder-3.2.4'
    docile (1.3.2) '/var/oscli/gems/ruby/2.2.0/gems/docile-1.3.2'
    git (1.3.0) '/var/oscli/gems/ruby/2.2.0/gems/git-1.3.0'
    json_pure (2.2.0) '/var/oscli/gems/ruby/2.2.0/gems/json_pure-2.2.0'
    minitest (5.4.3) '/var/oscli/gems/ruby/2.2.0/gems/minitest-5.4.3'
    ruby-progressbar (1.10.1) '/var/oscli/gems/ruby/2.2.0/gems/ruby-progressbar-1.10.1'
    minitest-reporters (1.2.0) '/var/oscli/gems/ruby/2.2.0/gems/minitest-reporters-1.2.0'
    openstudio-workflow (1.3.4) '/var/oscli/gems/ruby/2.2.0/gems/openstudio-workflow-1.3.4'
    parallel (1.12.1) '/var/oscli/gems/ruby/2.2.0/gems/parallel-1.12.1'
    parser (2.7.1.4) '/var/oscli/gems/ruby/2.2.0/gems/parser-2.7.1.4'
    powerpack (0.1.2) '/var/oscli/gems/ruby/2.2.0/gems/powerpack-0.1.2'
    rainbow (3.0.0) '/var/oscli/gems/ruby/2.2.0/gems/rainbow-3.0.0'
    unicode-display_width (1.7.0) '/var/oscli/gems/ruby/2.2.0/gems/unicode-display_width-1.7.0'
    rubocop (0.54.0) '/var/oscli/gems/ruby/2.2.0/gems/rubocop-0.54.0'
    rubocop-checkstyle_formatter (0.4.0) '/var/oscli/gems/ruby/2.2.0/gems/rubocop-checkstyle_formatter-0.4.0'
    simplecov-html (0.10.2) '/var/oscli/gems/ruby/2.2.0/gems/simplecov-html-0.10.2'
    simplecov (0.16.1) '/var/oscli/gems/ruby/2.2.0/bundler/gems/simplecov-98c33ffcb40f'
    openstudio_measure_tester (0.1.7) '/var/oscli/gems/ruby/2.2.0/gems/openstudio_measure_tester-0.1.7'
    openstudio-extension (0.1.2) '/var/oscli/gems/ruby/2.2.0/gems/openstudio-extension-0.1.2'
    openstudio-gems (2.9.0) '/var/oscli'
    openstudio-standards (0.2.11) '/var/oscli/gems/ruby/2.2.0/bundler/gems/openstudio-standards-841741dfcd5f'
                                                                                              ^^^^SHA HERE^^^^
    ```

* If the above returned the expected OpenStudio Standards version, push rename the simg file and push it to Eagle. [`SIMG_VERSION_NAME` and `SIMG_VERSION_SHA`](https://nrel.github.io/buildstockbatch/project_defn.html#openstudio-version-overrides) should be set to a unique combination for each new singularity image. This provides the means of specifying this singularity image in the ComStock project YAML. [See also the ComStock HPC Training document.](../comstock_hpc_training.md#example-yml-file-contents-documentation) __`SIMG_VERSION_SHA` must be the SHA of the version of OpenStudio included, NOT the SHA of openstudio-standards.__ To signify a custom version of openstudio-standards, set the `SIMG_VERSION_NAME` to something meaningful. Something like: `SIMG_VERSION_NAME=os_340_stds_b50172b4cc18` and `SIMG_VERSION_SHA=4bd816f785`.

    ```bash
    # Rename the container

    # Mac/Linux:
    export SIMG_VERSION_NAME=example-v1
    export SIMG_VERSION_SHA=0123456789
    mv docker-openstudio.simg OpenStudio-$SIMG_VERSION_NAME.$SIMG_VERSION_SHA-Singularity.simg

    # Windows:
    # In your file explorer, rename docker-openstudio.simg
    # to:
    # OpenStudio-SIMG_VERSION_NAME.SIMG_VERSION_SHA-Singularity.simg
    ```

* Next: copy the singularity image to your home directory on eagle using the tool of your choice.

* Record the details of the Singularity image, including the openstudio-standards SHA and the version of OpenStudio used, in the Singularity Images tab of the Run Dashboard spreadsheet.

* The final step is moving the container from your home directory on eagle to the [singularity image directory](../comstock_hpc_training.md#example-yml-file-contents-documentation), typically `/shared-projects/buildstock/singularity-images` or `/project/my-project/singularity-images`.

* You're now ready to update your YAML and run!

## Using Singularity Container outside of Buildstock Batch

* Download singularity image from S3

    ```bash
    curl -SLO https://s3.amazonaws.com/openstudio-builds/2.6.0/OpenStudio-2.6.0.ac20db5eff-Singularity.simg
    ```

* Run singularity container

    ```bash
    module load singularity-container
    # Mount /scratch for analysis
    singularity shell -B /scratch:/scratch OpenStudio-2.6.0.ac20db5eff-Singularity.simg

    # Call bash (without --norc) for now until LANG is fixed
    bash

    openstudio --version
    ```

* Running singularity in line

    ```bash
    singularity exec -B /scratch:/var/simdata/openstudio OpenStudio-2.6.0.ac20db5eff-Singularity.simg openstudio run -w in.osw
    ```
