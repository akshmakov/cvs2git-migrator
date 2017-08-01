#!/bin/bash

### cvs2git-migrator.sh
###
### This is a CVS Import Coordinator Script
###
### Usage: (see usage function) 
###
### ./cvs2git-migrator.sh [options] module
###   options:     
###     -c=/--cvsroot= cvsroot e.g. :pserver:user@cvs:/home/cvs/ (note: cannot use cvsroot with password embedded like :pserver:user:pwd@host)
###     -m=/--module= module (can be specified here instead of at end)
###     -o=/--options= options file for cvs2git (default: ~/.cvs2git.options)
###     --cvspassword= password to provide to cvs server
###     --cache= cache dir (default ~/.cvs2git-cache/)
###     --output= output directory (default: ./ )
###     --verbose= verbose (extra messages)
###
###   module: cvs module to import (can be directory in order to import only submodule)
###
### General Script Steps:
###   cvsclone the cvs directory
###   cvs2git to extract blob and data
###   git fast import to create the repo from blob
###
### Dependencies:
###   cvsclone
###   cv2git (cvs2svn)
###   git 
###
### This Script has some caching capability 


######################################
## Boiler Plate Functions ############
######################################


PROGNAME=$(basename $0)

function error_exit
{

    #----------------------------------------------------------------
    #Function for exit due to fatal program error
    #Accepts 1 argument:
    #string containing descriptive error message
    #----------------------------------------------------------------


    echo "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

function usage
{

    #--------------------------------------
    # print the usage doc
    #--------------------------------------

    cat <<-EOF
Usage: $PROGNAME [OPTIONS] module
  OPTIONS:     
    -c=/--cvsroot= : cvsroot e.g. :pserver:user@cvs:/home/cvs/ 
             (note: cannot use cvsroot with password embedded like :pserver:user:pwd@host)
             Overrides CVSROOT

    -m=/--module= : module (alternative opt)
    -o=/--options= : options file for cvs2git (default: /etc/cvs2git-migrator/cvs2git.options or ~/cvs2git-migrator/cvs2git.options if it exists)
    -n=/--no-cache : disable caching
    --cvspassword= : password to provide to cvs server
    --cache= cache dir (default ~/.cvs2git-migrator/cache)
    --output= output directory (default: pwd )
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
  

EOF
    exit 0
}

###########################################
## Configurable Vars (Put Defaults Here) ##
###########################################

OUTPUT=${CVS2GIT_OUTPUT_DIR-`pwd`}

CACHE=${CVS2GIT_CACHE_DIR-"${HOME}/.cvs2git-migrator/cache"}

_OPTIONS_1="${HOME}/.cvs2git-migrator/cvs2git.options"
_OPTIONS_2="/etc/cvs2git-migrator/cvs2git.options"

if [[ -e $_OPTIONS_1 ]] ; then
   OPTIONS= $_OPTIONS_1
else
   OPTIONS= $_OPTIONS_2
fi

OPTIONS=${CVS2GIT_OPTIONS-$OPTIONS}
	  
MODULE=${CVS2GIT_MODULE-}

VERBOSE=${CVS2GIT_VERBOSE-}

CVSROOT=${CVSROOT-}

CVS_PASSWORD=${CVS_PASSWORD-}


######################################
## ARG Parsing to Set Vars ###########
######################################

if [[ $# = 0 && -z $MODULE ]]; then
    usage
fi

#we use the construction
#${i#*=} to strip the
# option string of everything before =
while [[ $# -gt 0 ]]
do
    i="$1"
    case $i in
	-c=*|--cvsroot=*)
	    CVSROOT=${i#*=}
	    echo "option: --cvsroot $CVSROOT"
	    shift
	    ;;
	-m=*|--module=*)
	    MODULE=${i#*=}
	    echo "option: --module $MODULE" 
	    shift
	    ;;
	-o=*|--options=*)
	    OPTIONS=${i#*=}
	    echo "option: --options $OPTIONS" 
	    shift
	    ;;
	--cvspassword=*)
	    CVS_PASSWORD="${i#*=}"
	    echo "option: --cvspassword is set" 
	    shift
	    ;;
	--cache=*)
	    CACHE=${i#*=}
	    echo "option: --cache $CACHE" 
	    shift
	    ;;
	-n|--no-cache)
	    CACHE=""
	    echo "options: --no-cache"
	    shift
	    ;;
	--output=*)
	    OUTPUT=${i#*=}
	    echo "option: --output $OUTPUT" 
	    shift
	    ;;
	-v|--verbose)
	    VERBOSE=1
	    shift
	    ;;
	-h|--help)
	    usage
	    shift
	    ;;
	
	-*|--*)
	    error_exit "unknown option $1"
	    ;;
	*)
	    break
	    ;;
    esac
done

if [[ -n $1 ]]; then
    MODULE=$1
    echo "module: $MODULE"
elif [[ -z $MODULE ]]; then
    error_exit "You Need to Specificy a Module"
fi


#setup verbose mode
if [ "$VERBOSE" = 1 ]; then
    exec 4>&2 3>&1
else
    exec 4>/dev/null 3>/dev/null
fi

############################################
## Project Init ############################
############################################


echo "Starting CVS2GIT Import"


#replace dir slashes in CVS Module with '-'
PROJECT_NAME=$(echo $MODULE | sed -e 's/\//-/g')
PROJECT_NAME="${PROJECT_NAME,,}"


echo "-debug- DBG Project Name: $PROJECT_NAME" >&3

PROJECT_QUALIFIED_NAME=$PROJECT_NAME-$(date +"%Y%m%d-%H%M%S")
echo "-debug- Project Qualified Name: $PROJECT_QUALIFIED_NAME" >&3

#root project directory
PROJECT_DIR=`cd $OUTPUT && pwd`/$PROJECT_QUALIFIED_NAME
echo "-debug- Project Dir: $PROJECT_DIR" >&3

if [[ ! -e $PROJECT_DIR ]]; then
    mkdir -p $PROJECT_DIR
    echo "Creating New Project in $PROJECT_DIR"
elif [[ ! -d $PROJECT_DIR ]]; then
    echo "$PROJECT_DIR exists but is not a directory" >&4
    error_exit "$LINENO: $PROJECT_DIR is not a directory"
fi
    


if  [[ -z $CACHE ]]; then
    echo "-debug- run with --no-cache using $PROJECT_DIR for cache" >&3
    CACHE=$PROJECT_DIR
fi

if  [[  ! -e $CACHE ]]; then
    echo "-debug- no cache dir creating $CACHE" >&3
    mkdir -p $CACHE
fi

if [[ ! -d $CACHE ]]; then
   echo "$CACHE exists but is not a directory" >&4
   error_exit "$LINENO: $CACHE is not a directory"
fi



############################################
## cvsclone     ############################
############################################


	

echo "Cloning CVS Repository $CVSROOT/$MODULE"

# if local cvsroot
if [[ -e $CVSROOT && -d $CVSROOT/$MODULE && ! -d $CACHE/$MODULE ]]; then
    (
	cd $CACHE && \
	mkdir -p $MODULE/CVSROOT && \
	cp -rf $CVSROOT/$MODULE/* $MODULE/ 
    )
    
elif [[ ! -d $CACHE/$MODULE ]]; then
    ## We try a few strategies to lo\gin to cvs and clone
    ## If .cvspass exists and has something then we reuse those credentials
    ## If the password is provided as argument or env we construct a login from that
    ## Otherwise we drop to STDIN to login


    if [[ ! -z $CVS_PASSWORD ]]; then
	echo "Logging into CVS Repository using provided password"
	cvs_local=$(echo $CVSROOT | sed -e "s/@/:$CVS_PASSWORD@/g")
	cvs  -d "$cvs_local" login
	unset cvs_local
    elif [[ -s ${HOME}/.cvspass ]]; then
	cvs login
    fi

    (  
	cd $CACHE \
	    && cvsclone -d $CVSROOT $MODULE\
	    && mkdir -p $MODULE/CVSROOT\
	    && echo "Succesfully Cloned CVS Module $CVSROOT/$MODULE"
    )

    #cvs logout

else
    echo "Using Cached Version of CVS Module in $CACHE/$MODULE"
fi


if [[ $CACHE = $PROJECT_DIR ]]; then
    (
	cd $PROJECT_DIR\
	    && mv $MODULE "cvs-data"\
	    && echo "-debug- Renaming CVS Data to \"cvs-data\"" >&3
    )
else
    (
	cd $PROJECT_DIR\
	    && cp -rf $CACHE/$MODULE "cvs-data" \
	    && echo "-debug- Copying CVS Module to Project Working Directory $PROJECT_DIR" >&3
    )
fi


################################################
#import the data into git   ####################
################################################

if [[ -f $OPTIONS ]]; then
    (
	cd $PROJECT_DIR \
	    && cvs2git \
		   --options=$OPTIONS\
	    && echo "Importing CVS Data into Git BLOB and DATA Files"
    )
else
   error_exit "$LINENO: cvs2git cannot run \$OPTIONS=$OPTIONS not defined or is not a file (use --options to specify), options required for meaningful import"
fi    



if [[ -e "$PROJECT_DIR/git-blob.dat" && -e "$PROJECT_DIR/git-dump.dat" ]]; then
    (
	cd $PROJECT_DIR \
	    && git init --bare $PROJECT_NAME.git \
	    && cd $PROJECT_NAME.git \
	    && cat ../git-blob.dat ../git-dump.dat | \
		git fast-import \
	    && git-move-refs.py \
	    && git gc --prune=now \
	    && echo "Created Bare Git Repository from CVS2GIT Dump in $PROJECT_DIR/$PROJECT_NAME.git"

    )
else
    error_exit "$LINENO: git fast-import cannot run cv2git failed to create correct blob and dump files in $PROJECT_DIR"
fi

if (which cowsay); then
    cowsay "-CVS2GIT Import Completed-"
else
    echo "-CVS2GIT Import Complete-"
fi

exit 0

