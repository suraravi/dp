#!/bin/bash

# By Default, get gogs seed data from the latest of the current branch
destDir="seed"

branch=$(git branch | grep \* | cut -d ' ' -f2)


tagList="tagdetails.txt"
gogsTag="gogs_TAG_NAME"

branchOrCommit=${branch}

if [ -f ${tagList} ]; then
  commit=$(cat ${tagList} | grep ${gogsTag} 2>/dev/null | cut -d'-' -s -f2 2>/dev/null | head -n 1 2>/dev/null )
  if [ ! -z ${commit} ]; then
     branchOrCommit=${commit}
  fi
fi

echo "Downloading seed data from ma-cp-gogs repo using branch/commit of ${branchOrCommit}"

if [ -d ${destDir} ]; then
  echo "Removing existing directory ${destDir}"
  rm -rf ${destDir}
fi

echo "Downloading seed data from ma-cp-gogs repo using branch/commit of ${branchOrCommit}"

curl --user readonly:readonly "http://stash.us.manh.com/rest/api/latest/projects/DOCKYARD/repos/ma-cp-gogs/archive?format=tgz&at=${branchOrCommit}" | tar -xz ${destDir} 2>/dev/null

if [ $? -gt 0 ]; then
   echo "ERROR - Failed to download seed data from branch/commit of ${branchOrCommit}"
   exit 2
fi

