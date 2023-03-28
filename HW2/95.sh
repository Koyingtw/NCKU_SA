#!/bin/bash

function usage() {
	echo -n -e "\nUsage: sahw2.sh {--sha256 hashes ... | --md5 hashes ...} -i files ...\n\n--sha256: SHA256 hashes to validate input files.\n--md5: MD5 hashes to validate input files.\n-i: Input files.\n"
}

function check_user_exist() {
    local username=$1
    getent passwd $username > null 2>&1
    if [ $? -eq 0 ]; then
        user_exist=1
    fi
}

function check_group_exist() {
    while [ $# -ge 1 ] ; do
        group=$1
        getent group $1 > null 2>&1
        if [ $? -ne 0 ] ; then
            pw groupadd ${group}
        fi

        shift
    done
}

function add() {
    username=$1
    password=$2
    shell=$3
    groups=$4

    check_group_exist ${groups//,/ }
    if [ "$groups" = "" ] ; then
        sudo echo $password | sudo pw useradd $username -m -h 0 -s $shell
    else
        sudo echo $password | sudo pw useradd $username -m -h 0 -s $shell -G $groups
    fi
}

### General & Hash Validation

hash_string_pos=0
file_string_pos=0
sha256=0
md5=0
hash_strings=()
files=()
prev_arg=""

while [ $# -ge 1 ] ; do
    case $1 in
    -h)
        # Provide -h option to show the help message.
        usage
        exit 0
        ;;
    --md5)
        md5=1
        prev_arg=$1
        ;;
    --sha256)
        sha256=1
        prev_arg=$1
        # echo $1
        ;;
    -i)
        prev_arg=$1
        ;;
    *)
        if [ "$prev_arg" = "--md5" ] || [ "$prev_arg" = "--sha256" ] ; then
            hash_strings+=("$1")
        elif [ "$prev_arg" = "-i" ] ; then
            files+=("$1")
        else
            # Invalid arguments should be rejected with a non zero status code, with the error message and help message.
            echo -n "Error: Invalid arguments." 1>&2
            usage
            exit 1
        fi
        ;;
    esac
    shift
done



if [ $(( $sha256 + $md5 )) = 2 ] ; then
    echo -n "Error: Only one type of hash function is allowed." 1>&2
    exit 2
fi

if [ ${#files[@]} != ${#hash_strings[@]} ] ; then
    echo -n "Error: Invalid values." 1>&2
    exit 3
fi

len=${#files[@]}

for ((i=0; i < len; i++)) ; do
    hash=${hash_strings[$i]}
    file=${files[$i]}

    if [ "$sha256" = 1 ] ; then
        checksum=$(sha256sum "$file" | cut -d' ' -f1)
    else
        checksum=$(md5sum "$file" | cut -d' ' -f1)
    fi

    if [ "$checksum" != "$hash" ]; then
        echo -n "Error: Invalid checksum." 1>&2
        exit 1
    fi
done

### Parsing Files

csv=0
json=0
create_users=()

if [ -e "/tmp/tmp.123456" ] ; then
    rm "/tmp/tmp.123456"
fi

users_tmp_file=`mktemp /tmp/tmp.123456`
echo -n "" > $users_tmp_file

usernames=()

for i in ${files[@]} ; do
    file=$i
    file_header=`file $file | awk '{print $2}'`

    if [ $file_header = "JSON" ] ; then
        cat $file | jq '.[] | .username' | tr -d '"' >> $users_tmp_file
    elif [ $file_header = "CSV" ] ; then
        awk -F ',' '{ if (NR!=1) {print $1}}' $file >> $users_tmp_file
    else
        echo -n "Error: Invalid file format." 1>&2
        exit 4
    fi
done

echo -n "This script will create the following user(s): "
while read line  ; do
    echo -n "$line "
done < $users_tmp_file
echo -n "Do you want to continue? [y/n]:"

rm $users_tmp_file

read line

if [ "$line" = "" ] || [ "$line" = "n" ] ; then
    exit 0
fi

### Create Users

for i in ${files[@]} ; do
    file=$i
    file_header=`file $file | awk '{print $2}'`
    username="none"
    password="none"
    shell="/bin/sh"
    groups=""


    if [ $file_header = "JSON" ] ; then
        username=`cat $file | jq '.[] | .username' | tr -d '"'`
        password=`cat $file | jq '.[] | .password' | tr -d '"'`
        shell=`cat $file | jq '.[] | .shell' | tr -d '"'`

        user_array=($(echo $username | awk '{for (i = 1; i <= NF; i++) printf("%s ", $i)}'))
        password_array=($(echo $password | awk '{for (i = 1; i <= NF; i++) printf("%s ", $i)}'))
        shell_array=($(echo $shell | awk '{for (i = 1; i <= NF; i++) printf("%s ", $i)}'))

        for ((i=0; i<${#user_array[@]}; i++)); do
            groups=`cat $file | jq --argjson index $i '.[$index] | .groups' | tr -d '[' | tr -d ']' | tr -d '"' | tr -d ' ' | tr -d '\n'`
            user_exist=0
            check_user_exist ${user_array[$i]}

            #echo "${user_array[$i]}, ${password_array[$i]}, ${shell_array[$i]}, ${groups}"

            if [ "$user_array[$i]" = "" ] ; then
                echo "JSON: Error: username is empty." 1>&2
                continue
            fi

            if [ $user_exist = 1 ] ; then
                echo "Warning: user ${user_array[$i]} already exists."
            else
                add ${user_array[$i]} ${password_array[$i]} ${shell_array[$i]} ${groups}
            fi
        done
    elif [ $file_header = "CSV" ] ; then
        linecnt=0

        while read line ; do
            linecnt=$(($linecnt + 1))
            IFS=',' read -ra fields <<< `echo $line | sed 's/ *, */,/g'`
            username=`echo ${fields[0]} | tr -d ' '`
            password=`echo ${fields[1]} | tr -d ' '`
            shell=`echo ${fields[2]} | tr -d ' '`
            groups=`echo ${fields[3]}`
            groups=${groups/ /,}


            if [ "$username" = "username" ] ; then
                continue
            fi

            user_exist=0
            group_exist=0
            check_user_exist $username

            if [ "$username" = "" ] ; then
                echo "CSV: Error: username is empty." 1>&2
                continue
            fi


            if [ $user_exist = 1 ] ; then
                echo "Warning: user $username already exists."
            else
                add $username $password $shell $groups
            fi
            
        done < $file
    fi
done