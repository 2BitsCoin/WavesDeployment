#!/bin/bash

# Decalre variables
EXITCODE=0
NOLOAD=0
SNAME=''
aryname=''
config=''
linenb=0
arycnt=0

declare -A config

# Set working directory
CPATH="/var/lib/scripts/deploy"
cd $CPATH
#
# Check usage
if [ -z "$1" ]; then
    echo "Usage: deploy {TARGET_NETWORK} {PATH_TO_DEB_DIR_TO_DEPLOY}"
    exit
fi

# Prepare connections to deploy
touch ./keys/keys

# Check if upload needed
if ! [ -z "$2" ]; then

# Prelare file to deploy
DSTNAME="current.deploy"

if test -f "$2"; then DEBNAME=$2; else
    DEBNAME=$(ls -tr $2/*.deb|head -1)
#    SNAME=$(echo $DEBNAME| sed 's/[A-Za-z0-9_-\.]+\.[A-Za-z0-9]+//g')
fi

if [ -z "$DEBNAME" ]; then
    die "Error: File for deploy not found"
fi

#cp $DEBNAME ./uploads/$SNAME

else
    NOLOAD=1
    echo "Info: nothing be uploaded"
fi


TARGET=$1
if [ ! -f "./conf/$TARGET" ]; then
    die "Error: Target configuration not found"
fi

# Check ssh connections
make_conn() {
FILENAME=''

    find $CPATH/keys/*.pem -type f | while read FILENAME; do
    CCONN=$(/usr/bin/ssh -o StrictHostKeyChecking=no -q -n -i $FILENAME ubuntu@$HOST)
    if [ $? -eq 0 ]; then
        echo "$HOST:$FILENAME" >> ./keys/keys
    fi
    done

}

die() {
   printf >&2 "%s\n" "$@"
   exit 1
}

# Read config for deploy network
while read line; do
   ((++linenb))
   if [[ $line =~ ^[[:space:]]*$ ]]; then
        ((++arycnt))
        continue
   elif [[ $line =~ ^\[([[:alpha:]][[:alnum:]]*)\]$ ]]; then
      aryname=${BASH_REMATCH[1]}
      declare -A $aryname
    csect+=( ${BASH_REMATCH[1]} )
   elif [[ $line =~ ^([^=]+)=(.*)$ ]]; then
      [[ -n aryname ]] || die "*** Error line $linenb: corrupted config section defined"
      printf -v ${aryname}["${BASH_REMATCH[1]}"] "%s" "${BASH_REMATCH[2]}"
   else
      die "*** Error line $linenb: $line"
   fi
done < ./conf/$TARGET

# Following config
for i in "${csect[@]}"
do
    host="$i[host]"
    HOST=${!host}
    KEY=$(grep $HOST ./keys/keys)
    if [ $? -eq 0 ]; then
        KNAME=$( grep $HOST ./keys/keys|tail -1|cut -d : -f2 )
    else
        make_conn
        KNAME=$( grep $HOST ./keys/keys|tail -1|cut -d : -f2 )
        if [ ${#KNAME} -eq 0 ]; then
            echo "Key not found for $HOST. Place key file (*.pem) to $CPATH/keys directoy."
            EXITCODE=1
            continue
        fi
    fi

# Copy some to deployment host
    if [ $NOLOAD -eq 0 ]; then
    echo "Copying $DEBNAME to $HOST:"
    scp -o StrictHostKeyChecking=no -i $KNAME $DEBNAME ubuntu@$HOST:/tmp/$DSTNAME
    echo "Loaded To: $HOST ."
    fi

# Get random string for task file name
    tname=$( cat /dev/urandom | tr -dc '0-9' | fold -w 256 | head -n 1 | head --bytes 16 )
    cp ./scenes/$TARGET /tmp/dep$tname

# Prepare outside script with regexp
    while read rsline; do
        key="$( echo $rsline|grep "w{"|sed -e "s/^.*w{//"|sed -e "s/}.*$//" )"
        if ! [ -z $key ];then
            if ! [ -z $i[$key] ]; then
                val="$i[$key]"
                val=${!val}
                echo $rsline|sed -e "s/w{$key}/$val/g" >> /tmp/dep$tname.r
            fi
        else
            echo $rsline >> /tmp/dep$tname.r
        fi
    done < /tmp/dep$tname
    mv /tmp/dep$tname.r /tmp/dep$tname

# Show outside script
    echo "*Executing:"
    cat /tmp/dep$tname
    echo "*via ssh."

# SSH remote exec
    ssh -i $KNAME ubuntu@$HOST 'bash -s' < /tmp/dep$tname
    echo "*Done."

# Clear garbage
    rm -f /tmp/dep$tname
done

# Check if errors
if [ $EXITCODE -eq 1 ]; then
    die "Deploy unsucessful. Check hosts configuration."
fi
