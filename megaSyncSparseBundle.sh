#!/bin/bash

# configure your mega root directory here:
megaRoot="/backups"
logFile=""
statusFile=""
testMode=false # set to true to not really do changes

# you better know what you are doing if you change anything from here on
tmpFolder="./.syncSparsBundle.tmp"

function log() {
  echo -e "$1"
  
  if [ ! -z "$logFile" ]; then
    echo -e "$1" >> "$logFile"
  fi
}

function status() {
  if [ ! -z "$statusFile" ]; then
    echo "megaSyncSparseBundle $bundleName status: $1" > "$statusFile"
  fi
}

function cleanup {
  log "\nStopping mega-sync for bundle $bundleName...     "
  # disable mega-sync
  syncId=$(mega-sync | grep "$megaRoot/$bundleName" | awk '{print $1}')
  mega-sync -d "$syncId" > /dev/null
  status "Sync stopped"
}

function abspath() {
  python -c "import os,sys; print(os.path.realpath(sys.argv[1]))" $1
}

bundleFile=$(abspath "$1")

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

(
  cd "$dir" || exit

  if [ -z "$bundleFile" ]; then
    echo "Usage: ./megaSyncSparsBundle.sh [Location of your bundle file]"
    exit 1
  fi

  if [ -z "$megaRoot" ]; then
    echo "Mega Root variable not configured."
    exit 1
  fi

  mega-ls "$megaRoot" 2&> /dev/null
  if [ $? -gt 0 ]; then
    echo "Failed to list your remote mega root: $megaRoot"
    echo "Make sure this command works: 'mega-ls $megaRoot"
    exit 1
  fi

  if [ ! -d "$bundleFile" ]; then
    echo "Bundle file $bundleFile does not exist"
    exit 1
  fi

  date=$(date)
  echo -e "\n############## INIT NEW SESSION @ $date:" >> "$logFile"

  bundleName=$(basename "$bundleFile" | sed "s#/##")

  # purge and create tmp folder
  rm -Rf $tmpFolder
  mkdir $tmpFolder

  dirsToWatch=("bands" "mapped")

  # collect remote files to be deleted
  status "Comparing to remote..."
  log "comparing to remote ..."
  for dir in "${dirsToWatch[@]}"
  do
    if [ -d "$bundleFile/$dir/" ]; then
      ls "$bundleFile/$dir/" | sort > $tmpFolder/$dir.local
      mega-ls $megaRoot/$bundleName/$dir/ | sort | grep -v / > $tmpFolder/$dir.mega

      diff $tmpFolder/$dir.local $tmpFolder/$dir.mega | grep ">" | sed "s#> #$megaRoot/$bundleName/$dir/#" >> $tmpFolder/toBeDeleted
    fi
  done

  # delete remote files
  status "Deleting remote files..."
  log "deleting unnecessary remote files ..."
  while read fileToBeDeleted; do
    log "\t * rm remote file: $fileToBeDeleted"
    if [ "$testMode" = false ] ; then
      mega-rm $fileToBeDeleted
    fi
  done <$tmpFolder/toBeDeleted

  # purge tmp folder
  rm -Rf $tmpFolder

  # now that remote is cleaned, activate mega sync
  status "Syncing..."
  log "syncing..."
  if [ "$testMode" = true ] ; then
    log "TestMode, no sync therefore. Done."
    exit 0
  else
    mega-ls "$megaRoot/$bundleName" 2&> /dev/null
    if [ $? -gt 0 ]; then
        log "\t creating remote bundle..."
        mega-mkdir "$megaRoot/$bundleName"
    fi
    
    mega-sync "$bundleFile/" "$megaRoot/$bundleName/"
  fi

  trap cleanup EXIT

  # wait for mega-sync to finish
  while (true); do
    state=$(mega-sync | grep "$megaRoot/$bundleName" | sed "s#/.*$megaRoot/$bundleName\(.*\)#\1#g" | awk '{print $2}')
    syncState=$(mega-sync | grep "$megaRoot/$bundleName" | sed "s#/.*$megaRoot/$bundleName\(.*\)#\1#g" | awk '{print $3}')

    if [[ "$state" = "Active" ]] && [[ "$syncState" = "Synced" ]]; then
      echo
      log "Finished sync."
      break
    else
      localFileSize=$(du -s "$bundleFile" | awk '{print $1}')
      remoteFileSize=$(mega-du "$megaRoot/$bundleName" | grep Total | awk '{print $4}')
      doneInPercent=$(echo "scale = 1; $remoteFileSize / 1024 * 100 / $localFileSize" | bc)
      
      status "Syncing (~$doneInPercent% done)..."
      log "\t waiting for sync to finish ~$doneInPercent% done... (Current mega-sync state: $state, syncState=$syncState)"
    fi
    sleep 2
  done
)
