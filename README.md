# `cvs2git-migrator`

This Project contains the cvs2git-migrator.sh script that is used to import and convert a CVS repository to a Git repository. CVS Repo can be local or remote with anonymous or password protected  access.

This README provides setup and execution information.

This Docker image cleanly encapsulates the environment needed for import, but it is not required, you may easily run the script by installing the requirements on your local system. 


## Introduction ##

Import CVS to GIT repositories is done by utilizing the `cvs2git` utility that is part of the `cvs2svn` project. This is a standard package on most linux distributions. 

This utility generates two files, a blob and a dump, that together are ingested by the native `git` utility to import a repository. 

Additionally, this script uses a utility called `cvsclone` to get a complete repository with history remotely, this utility is not necessary if you can provide a file system copy of the root repository. This utility is not being updated and is not distributed, but functions fine, so it is built from a signle source file in the docker container, or you may do so locally  (see [`Dockerfile`](Dockerfile) ) 
[p
## Requirements ##

Script Requirements
 - `cvsclone`
 - `cvs2git` (installed by `cvs2svn`)
 - `git`

Docker Requirments
 -  amd64 linux system
 - `docker`
 - `docker-compose` (optional)

## Usage ##

The migrator script is simple to use, the default options script is normally good enough, but you will need to customize the Author Name mapping if you would like your commits associated with contemporary git committer info.

```sh
# import a sourceforge project module with history via anon pserver
$ cvs2git-migrator --cvsroot=":pserver:anonymous:PROJ.sourceforge.net:/cvsroot/PROJ" MODULE
# import a local cvs repo (fastest)
$ cvs2git-migrator --cvsroot="/srv/cvsroot/" MODULE
```

There are multiple configuration options to modify the directories and to facilitate password login, most of those parameters can also be set as environment variables, running `cvs2git-migrator --help` will print the complete usage doc, which is reproduced below

```sh

Usage: cvs2git-migrator.sh [OPTIONS] module
  OPTIONS:
    -c=/--cvsroot= : cvsroot e.g. :pserver:user@cvs:/home/cvs/
                   (note: cannot use cvsroot with password embedded like :pserver:user:pwd@host)
                   Overrides CVSROOT

    -m=/--module= : module (alternative opt)
    -o=/--options= : options file for cvs2git (default: /etc/cvs2git-migrator/cvs2git.options or ~/cvs2git-migrator/cvs2git.options if it exists)
    -n=/--no-cache : disable caching
    --cvspassword= : password to provide to cvs server
    --cache= cache dir (default ~/.cvs2git-migrator/cache)
    --output= output directory (default: cwd )
    --verbose= verbose (extra messages)

  module: cvs module to submodule to import

  Environment Variables for optionless invocation
    CVS2GIT_OUTPUT_DIR - --output
    CVS2GIT_CACHE_DIR  - --cache
    CVS2GIT_OPTIONS    - -/--options
    CVS2GIT_MODULE     - -m/--module module
    CVS2GIT_VERBOSE    - -v/--verbose
    CVS_PASSWORD       - --cvspassword
    CVSROOT            - -c/--cvsroot
		

```


### Output ###

The script will create a "project folder" in the output directory. The name of the project is created from the module being imported with a datecode added, e.g. importing the module `Module/Submodule` will create a project folder named `module_submodule-YYYYMMDD-HHmmss`, the output of the conversions will be placed in this folder. You can specify the output directory as a command argument, by default the project folder is created in the present working directory. 

After sucessful completion, the following will be created in the project folder

 - `/cvs-data` 
   A copy of the CVS Module with entire History (source of conversion)
 - `/git-blob.dat` and `/git-dump.dat`
   Dumps from the cvs2git conversion which are used to populate the new git repository
 - `/project_name.git`
   The Bare git repository that is ready to push to any upstream.
   
   
### CVS Cache ###

In order to debug/test imports with different options and to reduce load on the upstream CVS server, the script has some built in cvs caching capability.

The cache is stored in the `~/.cvs2git-migrator/cache` folder, when used in the default docker image this is  `/workdir/.cvs2git-migrator/cache

The script is not smart enough to update already cached Modules. If you experience trouble with caching, delete the cache directory or use the utility in `--no-cache` flag. If you would like to change the cache directory you may use the `--cache=` option

### Password ###

`cvs2git-migrator` will attempt several strategies to log in to a cvs repository that requires a password.

 - Provided via argument
 - .cvspass file in the user home dir (previous login)
 - From the envar `CVS_PASSWORD`
 - User Prompt

what does not work is

 - Embedded password CVSROOT e.g. `:pserver:user:pwd@cvs.example.com:/cvsroot/`

### CVS2GIT Options (CVS Author Conversions) ###

CVS keeps author names as their linux login (just username) in commits. CVS2GIT provides a way to map usernames to "First Name <email>" format for associating git users.

The object `entry_transforms` in [cvs2git.options](cvs2git-default.options) Defines the Mapping from cvs usernames to their name and email for global association across git.

You may indicate the options file as an argument `--options=`, envar `CVS2GIT_OPTIONS`, or by creating an options file either `/etc/cvs2git-migrator/cvs2git.options` or `~/.cvs2git-migrator/cvs2git.options`


## Docker ##

There are two ways to execute the conversion in docker

 - Using `docker run` to execute like a local script
 - Using `docker-compose` to run a preconfigured conversion


In this Example we will use a local folder `./output` to persist the data  in the container, you may use any directory you wish.

### docker run ###

using docker run is very much the same as executing locally with dependencies installed and default options file pre-installed

```sh
# execute a conversion
$ docker -v "$(pwd)/output:workdir" akshmakov/cvs2git-migrator --cvsroot="..." --cvspassword="secret" --no-cache MODULE
# Using envars
$ docker -v "$(pwd)/output:workdir -e "CVSROOT=..." -e "CVS2GIT_MODULE=mymodule" akshmakov/cvs2git-migrator
```

### docker-compose ###


`docker-compose` is a scripting layer on top of the `docker` virtualization daemon, it is a convenient way to multiplex or predefine the configuration of multiple conversions

```docker-compose.yml
## a compose file the imports 5 modules from a local repo when run
version: '2'
services:
  base:
    image: akshmakov/cvs2git-migrator
    environment:
      CVSROOT:"/srv/cvsroot"
    volumes:
      - "my-custom.options:/etc/cvs2git-migrator/cvs2git.options"
      - "/local/cvs/root:/srv/cvsroot"
      - "./output:/workdir"
    command: --no-cache 
  moduleA: 
    extends: base
    environment:
      CVS2GIT_MODULE: moduleA
  moduleB:
    extends: base
    environment: 
      CVS2GIT_MODULE: moduleB
  moduleC:
    extends: base
    environment: 
      CVS2GIT_MODULE: moduleC
```
   

Execute the conversions with Docker-Compose

```
docker-compose up -d
```
to view the status of a conversion


```
docker-compose logs moduleC
```



### Password Handling ###

the `cvsclone` portion of the conversion requires access to the CVS Repository, and thus may require your password.

The docker-image is set up to accept your password using STDIN when executing in interactive mode, either `docker-compose up` without `-d` or `docker-compose run cvs2git` 

Alternatively, you may choose to mount your `~/.cvspass` file in the docker container by adding the line `~/.cvspass:/workdir/.cvspass:ro` in the `docker-compose.yml` file. This will allow you to run `cvs login` in your host machine which populates the `.cvspass` file with an encrypted form of your password. 

You may also provide the password in plain-text as an environment variable for the docker container. 


## Additional Info ##

This Project Builds into a docker container image based on the Ubuntu 16.04 official Docker.IO image

The [Dockerfile](./Dockerfile) provides the Recipe to build the container image.

### building ###

`docker-compose build`

to only execute the build step using docker-compose, or

`docker build -t local/cvs2git-migrator.`

To build manually. Note that the tag for the manual step is different from the autocreated tag of the docker-compose tool.

You can customize the image by extending it, for example to have a docker image hosting a permanent copy of your CVS data for future users

```Dockerfile
EXTENDS akshmakov/cvs2git-migrator

COPY my-cvs-root /srv/cvsroot

ENV CVSROOT /srv/cvsroot
```


### image information ###

This image uses cvsclone, cvs2git, and git fast-import to port the repository.

cvsclone and the related git-move-refs.py are old unupdated external tools and have been shared here in the /external/ directory. In the image they are installed under /usr/local/bin/

The image defines the internal working directory /workdir/ which is intended to be the output directory for the cvs import work.

cvs2git requires an options file, a default  options file is defined in [`cvs2git-default.options`](cvs2git-default.options). 


### docker user information ###


The typical configuration for docker does not have UID mapping enabled (see : [this doc](https://docs.docker.com/engine/security/userns-remap/#enable-userns-remap-on-the-daemon) ), so files created by the container will be owned by root on your machine. 

Therefore it is recommended to execute the cvs conversion on a machine you have `sudo` access to, in order to `chown` those files when you are finished.

At this juncture, UID mapping is *possible*, but requires more extensive configuration of your docker daemon and may require changing some kernel configuration, using `sudo chown` is not acceptable you can persue documentation on the web or file an Issue.





