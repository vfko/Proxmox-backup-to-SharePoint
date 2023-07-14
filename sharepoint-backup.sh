#!/bin/bash

#############
# Functions #
#############

isRootUser () {
  if [ "`id -u`" -ne 0 ]; then
    echo "Access denied!"
    exit
  fi
}

getHelp() {
    echo -e "\n# Proxmox Backup to SharePoint #\n"
    echo -e "Need to install PnP CLI for Microsoft 365 and set login"
    echo -e "PnP CLI Microsoft 365: https://pnp.github.io/cli-microsoft365/\n\n"
    echo -e "sharepoint-backup.sh <option> <value>\n"
    echo -e "--vmid             set VMID"
    echo -e "--compress         compress format [lzo, gzip, zstd], default=zstd"
    echo -e "--storage          name of storage"
    echo -e "--max-files        maximum of backup files (older will be deleted)"
    echo -e "--sp-max-files     maximum of backup files stored on SharePoint (older will be deleted)"
    echo -e "--mail-to          email notification about result of backup (optional)"
    echo -e "--sp-url           SharePoint site URL: https://<tenant>.sharepoint.com/sites/<site-name>"
    echo -e "--sp-path          path to SP folder to which the backup will be uploaded: 'Shared Document/Sales/Invoices'"
    echo -e "--verbose          enable verbose mod"
    echo -e ""
}

setVmid() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [[ ${INPUT_PARAMETERS[$i]} == "--vmid" ]]; then
            INDEX=$((i + 1))
            echo ${INPUT_PARAMETERS[$INDEX]}
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo 0
    fi
}

setCompress() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [ ${INPUT_PARAMETERS[$i]} == "--compress" ]; then
            INDEX=$((i + 1))
            echo ${INPUT_PARAMETERS[$INDEX]}
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo "zstd"
    fi
}

setStorage() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [ ${INPUT_PARAMETERS[$i]} == "--storage" ]; then
            INDEX=$((i + 1))
            echo ${INPUT_PARAMETERS[$INDEX]}
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo "is_set"
    fi
}

setMaxFiles() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [ ${INPUT_PARAMETERS[$i]} == "--max-files" ]; then
            INDEX=$((i + 1))
            echo ${INPUT_PARAMETERS[$INDEX]}
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo 100
    fi
}

setSpMaxFiles() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [ ${INPUT_PARAMETERS[$i]} == "--sp-max-files" ]; then
            INDEX=$((i + 1))
            echo ${INPUT_PARAMETERS[$INDEX]}
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo 0
    fi
}

setMailTo() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [ ${INPUT_PARAMETERS[$i]} == "--mail-to" ]; then
            INDEX=$((i + 1))
            echo ${INPUT_PARAMETERS[$INDEX]}
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo "nobody@nodomain.no"
    fi
}

setSpUrl() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [ ${INPUT_PARAMETERS[$i]} == "--sp-url" ]; then
            INDEX=$((i + 1))
            echo ${INPUT_PARAMETERS[$INDEX]}
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo "is_set"
    fi
}

setSpPath() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [ ${INPUT_PARAMETERS[$i]} == "--sp-path" ]; then
            INDEX=$((i + 1))
            echo ${INPUT_PARAMETERS[$INDEX]}
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo "is_set"
    fi
}

setVerbose() {
    INPUT_PARAMETERS=("$@")
    IS_SET=0
    for i in ${!INPUT_PARAMETERS[@]}; do
        if [ ${INPUT_PARAMETERS[$i]} == "--verbose" ]; then
            INDEX=$((i + 1))
            echo "is_set"
            IS_SET=1
        fi
    done

    if [ $IS_SET -eq 0 ]; then
        echo "none"
    fi
}

checkIfStorageExist () {
    LINE_WITH_STORAGE=(`cat -n /etc/pve/storage.cfg | grep "$1"`)
    if [ -z $LINE_WITH_STORAGE ]; then
        echo -e "\nStorage doesn't exist\n"
        exit
    fi
}

checkIfVmidExist () {
    VMID_CONFIG=(`/usr/sbin/qm config "$1" 2> /dev/null`)
    CONTAINER_CONFIG=(`/usr/sbin/pct config "$1" 2> /dev/null`)

    if [[ -z $VMID_CONFIG && -z $CONTAINER_CONFIG ]]; then
        echo -e "\nVMID or CTID doesn't exist\n"
        exit
    fi
}

checkIfCompressFormatIsValid() {
  ENTRY_FORMAT="$1"
  USAGE_COMPRESS_FORMAT=( "zstd" "ZSTD" "lzo" "LZO" "gzip" "GZIP" )
  IS_IN_ARRAY=0
  for i in ${USAGE_COMPRESS_FORMAT[@]}; do
    if [ "$i" == "$ENTRY_FORMAT" ]; then
      IS_IN_ARRAY=1
    fi
  done
  if [ $IS_IN_ARRAY -eq 0 ]; then
    echo -e "\nCompress format is not valid.\n"
    exit
  fi
}

checkIfIsApiInstalled() {
    TEMP_FILE="$HOME/temp.file"
    touch $TEMP_FILE
    m365 spo file add 2> /dev/null > $TEMP_FILE
    RESULT=(`cat $TEMP_FILE`)
    rm $TEMP_FILE

    if [ ${#RESULT[@]} -eq 0 ]; then
        echo -e "\Need install PnP API"
        exit
    fi
}

getStoragePath() {
    TEMP_FILE="$HOME/temp.file"
    TEMP_FILE_1="$HOME/temp.file1"
    touch $TEMP_FILE
    touch $TEMP_FILE_1
    cat -n /etc/pve/storage.cfg | grep ": $1" > $TEMP_FILE
    CONFIG_LINE_WITH_STORAGE=(`cat $TEMP_FILE`)
    NUM_OF_LINE=${CONFIG_LINE_WITH_STORAGE[0]}
    NUM_OF_LINE_WITH_PATH=$((NUM_OF_LINE + 1))
    cat -n /etc/pve/storage.cfg | grep $NUM_OF_LINE_WITH_PATH > $TEMP_FILE
    cat $TEMP_FILE | grep "path" > $TEMP_FILE_1
    LINE_WITH_PATH=(`cat $TEMP_FILE_1`)
    rm $TEMP_FILE
    rm $TEMP_FILE_1

    for i in ${!LINE_WITH_PATH[@]}; do
        if [ ${LINE_WITH_PATH[$i]} == "path" ]; then
        index=$((i + 1))
        STORAGE_PATH=${LINE_WITH_PATH[$index]}
        fi
    done

    RESULT="$STORAGE_PATH/dump"

    if [ ${RESULT:0:5} == "/dump" ]; then
        echo -e "\nCan't get path to storage\n."
        exit
    else
        echo $RESULT
    fi
}

getLocalFilePath() {
    STORAGE_PATH="$1"
    VMID="$2"
    TEMP_FILE=$HOME/temp.file
    touch $TEMP_FILE
    ls -rt $STORAGE_PATH | grep "\-$VMID-" > $TEMP_FILE
    FILES=(`cat $TEMP_FILE`)
    BACKUP_FILES=()

    for i in ${FILES[@]}; do
        if [[ ${i:(-4)} == ".lzo" || ${i:(-3)} == ".gz" || ${i:(-4)} == ".zst" ]]; then
            BACKUP_FILES+=($i)
        fi
    done

    rm $TEMP_FILE
    LOCAL_FILE=(`echo ${BACKUP_FILES[0]}`)

    if [ ${STORAGE_PATH:(-1)} == "/" ]; then
        echo "$STORAGE_PATH$LOCAL_FILE"
    else
        echo "$STORAGE_PATH/$LOCAL_FILE"
    fi
}

#################
# Authorization #
#################

isRootUser

########
# Help #
########

ALL_PARAMETERS=("--vmid" "--compress" "--storage" "--max-files" "--mail-to" "--sp-url" "--sp-path" "--verbose")

IS_FIRST_PARAM_VALID=0

for i in ${ALL_PARAMETERS[@]}; do
    if [[ "$1" == "$i" ]]; then
        IS_FIRST_PARAM_VALID=1
    fi
done

if [ $IS_FIRST_PARAM_VALID -eq 0 ]; then
    getHelp
    exit
fi

####################
# Global variables #
####################

VMID=`setVmid "$@" 2> /dev/null`
COMPRESS=`setCompress "$@" 2> /dev/null`
STORAGE=`setStorage "$@" 2> /dev/null`
MAXFILES=`setMaxFiles "$@" 2> /dev/null`
SPMAXFILES=`setSpMaxFiles "$@" 2> /dev/null`
MAIL_TO=`setMailTo "$@" 2> /dev/null`
SP_URL=`setSpUrl "$@" 2> /dev/null`
SP_PATH=`setSpPath "$@" 2> /dev/null`
VERBOSE=`setVerbose "$@" 2> /dev/null`

if [ $VERBOSE == "is_set" ]; then
    echo -e "\n################"
    echo -e "# Check optons #"
    echo -e "################"
    echo "VMID: $VMID"
    echo "COMPRESS: $COMPRESS"
    echo "STORAGE: $STORAGE"
    echo "MAX FILES: $MAXFILES"
    echo "SP MAX FILES: $SPMAXFILES"
    echo "MAIL TO: $MAIL_TO"
    echo "SP URL: $SP_URL"
    echo -e "SP PATH: $SP_PATH\n"
    sleep 1
fi


################
# Main routine #
################

# check VMID
checkIfVmidExist $VMID

if [ $VERBOSE == "is_set" ]; then
    echo "VMID is valid"
    sleep 1
fi

# check storage
checkIfStorageExist $STORAGE

if [ $VERBOSE == "is_set" ]; then
    echo "Storage is valid"
    sleep 1
fi

# validate compress format
checkIfCompressFormatIsValid $COMPRESS

if [ $VERBOSE == "is_set" ]; then
    echo "Compress format is valid"
    sleep 1
fi

# check SharePoint API
checkIfIsApiInstalled

if [ $VERBOSE == "is_set" ]; then
    echo "API is installed"
    sleep 1
fi

# make backup

if [ $VERBOSE == "is_set" ]; then
    echo -e "\n#####################"
    echo -e "# Let's make backup #"
    echo -e "#####################\n"
    sleep 1
fi

/usr/bin/vzdump $((VMID)) --compress $COMPRESS --storage $STORAGE --maxfiles $MAXFILES --mailto $MAIL_TO


# remove old backups on SP

if [ $SPMAXFILES -gt 0 ]; then

    if [ $VERBOSE == "is_set" ]; then
        echo -e "\n##############################################"
        echo -e "# Now we will try remove old backups from SP #"
        echo -e "##############################################"
        sleep 1
    fi

    TEMP_FILE="$HOME/temp.file"
    touch $TEMP_FILE
    m365 spo file list -u "$SP_URL" -f "$SP_PATH" > $TEMP_FILE
    TEMP_FILE_CONTENT=(`cat $TEMP_FILE | grep "\"Name\"" | grep vzdump | grep "\-$VMID-"`)
    rm $TEMP_FILE

    BACKUP_FILES=()

    for i in ${TEMP_FILE_CONTENT[@]}; do
        if [ ${i:0:7} == "\"vzdump" ]; then
            BACKUP=${i//"\""/""}
            BACKUP=${BACKUP//","/""}
            BACKUP_FILES+=("$BACKUP")
        fi
    done

    if [ $VERBOSE == "is_set" ]; then
        sleep 1
        echo -e "\n# List of backups stored on SP #:"
        for i in ${BACKUP_FILES[@]}; do echo $i; done
    fi

    NUM_OF_SP_BACKUPS=0

    for i in ${BACKUP_FILES[@]}; do NUM_OF_SP_BACKUPS=$((NUM_OF_SP_BACKUPS + 1)); done

    if [ $NUM_OF_SP_BACKUPS -ge $SPMAXFILES ]; then

        if [ $NUM_OF_SP_BACKUPS -eq $SPMAXFILES ]; then
            NUM_OF_DELETED_ITEMS=1
        elif [ $SPMAXFILES -eq 1 ]; then
            NUM_OF_DELETED_ITEMS=$NUM_OF_SP_BACKUPS
        else
            NUM_OF_DELETED_ITEMS=$((NUM_OF_SP_BACKUPS - SPMAXFILES +1))
        fi

        for ((i=0; $i-$NUM_OF_DELETED_ITEMS; i=$i+1)); do

            if [ ${SP_URL:(-1)} == "/" ]; then
                SLASH=""
            else
                SLASH="/"
            fi

            FILE=${BACKUP_FILES[$i]}
            FILE_WITH_PATH=$SP_PATH$SLASH$FILE
            if [ $VERBOSE == "is_set" ]; then
                echo -e "\nRemoving $FILE_WITH_PATH from $SP_URL"
                /usr/local/bin/m365 spo file remove --webUrl "$SP_URL" --url "$FILE_WITH_PATH" --verbose --confirm
            else
                /usr/local/bin/m365 spo file remove --webUrl "$SP_URL" --url "$FILE_WITH_PATH" --confirm
            fi

        done
    else
        echo -e "\nThe amount of backups is less then the limit. None will be deleted.\n"
        sleep 1
    fi
fi

# upload to SharePoint
STORAGE_PATH=`getStoragePath $STORAGE`
UPLOADED_FILE=`getLocalFilePath $STORAGE_PATH $VMID`

if [ $VERBOSE == "is_set" ]; then
    echo -e "\n##########################################"
    echo -e "# Let's try to send backup to SharePoint #"
    echo -e "##########################################"
    sleep 1
    echo -e "\nSTORAGE PATH: $STORAGE_PATH"
    sleep 1
    echo "UPLOADED FILE: $UPLOADED_FILE"
    sleep 1
    /usr/local/bin/m365 spo file add -u "$SP_URL" -f "$SP_PATH" -p "$UPLOADED_FILE" --verbose
    echo -e "\n\nEnd of script"
else
    /usr/local/bin/m365 spo file add -u "$SP_URL" -f "$SP_PATH" -p "$UPLOADED_FILE"
fi