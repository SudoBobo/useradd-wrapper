#!/bin/bash

function exitWithFormatError
{
echo "Ошибка в формате файла на строке $1"
echo 'Правильный формат файла:
user
user_name:qwerty
user_home_dir:
user_groups:bobo
password_hash:$1$Etg2ExUZ$F9NTP7omafhKIlqaBMqng1
user_uid:7777
user_gid:8888
login shell:/bin/bash
user
user_name:zozo
user_home_dir:
user_groups:
password_hash:
user_uid:77777
user_gid:8888
login shell:/bin/bash
end'
exit 1
}

FORMAT_ERROR='Ошибка в формате файла'
SEPARATOR='user'
FINISHER='end'

FILE=$1
#AV_SHELLS=$2
AV_SHELLS[0]="/bin/sh"
AV_SHELLS[1]="/bin/bash"
AV_SHELLS[2]="/sbin/nologin"
#AV_SHELLS_NO_LG=$3
AV_SHELLS_NO_LG[0]="/sbin/nologin"

if [ ! -f "$FILE" ]; then
    echo "Файла $FILE не существует"
    exit 1
fi

declare -a USER_NAME_ARR
declare -a USER_HOME_DIR_ARR
declare -a USER_GROUPS_ARR
declare -a PASSWORD_HASH_ARR
declare -a DEF_GROUP_ARR
declare -a UID_ARR
declare -a GID_ARR
declare -a SHELL_ARR

CURRENT_USER=0
COUNTER=0
LINE_NUM=0

#чтение из файла и проверка правильности формата ввода

while read LINE
do
    ((COUNTER = COUNTER + 1))
    ((LINE_NUM = LINE_NUM + 1))
    case $COUNTER in

        1)
            if [[ $LINE != $SEPARATOR ]]; then
                exitWithFormatError $LINE_NUM
            fi
        ;;

        2)
            if [[ ${LINE:0:10} == 'user_name:' ]]; then
                USER_NAME_ARR[CURRENT_USER]=${LINE:10}
            else
                exitWithFormatError $LINE_NUM
            fi
        ;;

        3)
            if [[ ${LINE:0:14} == 'user_home_dir:' ]]; then
                USER_HOME_DIR_ARR[CURRENT_USER]=${LINE:14}
            else
                exitWithFormatError $LINE_NUM
            fi
        ;;

        4)
            if [[ ${LINE:0:12} == 'user_groups:' ]]; then
                USER_GROUPS_ARR[CURRENT_USER]=${LINE:12}
            else
                exitWithFormatError $LINE_NUM
            fi
        ;;

        5)
            if [[ ${LINE:0:14} == 'password_hash:' ]]; then
                PASSWORD_HASH_ARR[CURRENT_USER]=${LINE:14}
            else
                exitWithFormatError $LINE_NUM
            fi

         ;;


         6)
            if [[ ${LINE:0:9} == 'user_uid:' ]]; then
                UID_ARR[CURRENT_USER]=${LINE:9}
            else
                exitWithFormatError $LINE_NUM
            fi
         ;;

         7)
            if [[ ${LINE:0:9} == 'user_gid:' ]]; then
                GID_ARR[CURRENT_USER]=${LINE:9}
            else
                exitWithFormatError $LINE_NUM
            fi

         ;;

         8)
            if [[ ${LINE:0:12} == 'user_uid:' ]]; then
                SHELL_ARR[CURRENT_USER]=${LINE:12}
            else
                exitWithFormatError $LINE_NUM
            fi

            # Переходим к обработке следующего пользователя
            COUNTER=0
            ((CURRENT_USER = CURRENT_USER + 1))
         ;;

    esac
done <"$FILE"

# Проверка введёных данных

for (( c=0; c<CURRENT_USER; c++ ))
do

    # Проверка, существует ли пользоваталем с таким именем
    getent passwd ${USER_NAME_ARR[c]} > /dev/null 2&>1
    if [ $? -eq 0 ]; then
        echo "Пользователь ${USER_NAME_ARR[c]} уже существует"
        exit 1
    fi

    # Проверка, существует ли пользователь с такими UID

    # Проверка, существует ли пользовательская директория и создание директории с названием по-умолчанию
    if [ -z ${USER_HOME_DIR_ARR[c]} ]; then
        USER_HOME_DIR_ARR[c]="/home/${USER_NAME_ARR[c]}"
    fi

        if [ -d "${USER_HOME_DIR_ARR[c]}" ]; then
        echo "Директория с названием ${USER_HOME_DIR_ARR[c]} уже существует"
        exit 1
    fi

    # Если оболочка не указана, то ставим по-умолчанию
    if [[ -z ${SHELL_ARR[c]} ]]; then
        SHELL_ARR[c]="/bin/bash"
    fi

    # Проверка, существует ли оболочка с таким названием

    IS_VALID=0

    for SHELL in AV_SHELL
    do
        if [[ $SHELL == ${SHELL_ARR[c]} ]]; then
            IS_VALID=1
        fi
    done

    if [[ $IS_VALID -eq 0 ]]; then
        echo "Оболочка ${SHELL_ARR[c]} не установлена"
        exit 1
    fi

    # Если пароль пустой, то проверяем, соответствует ли оболочка этому случаю

    if [[ -z ${PASSWORD_HASH_ARR[c]} ]]; then

        IS_VALID=0
        for SHELL_NO_LG in AV_SHELL_NO_LG
            do
                if [[ $SHELL_NO_LG == ${SHELL_ARR[c]} ]]; then
                    IS_VALID=1
                fi
            done

            if [[ $IS_VALID -eq 0 ]]; then
                echo "Оболочка ${SHELL_ARR[c]} не подходит для пользователя без пароля. Она была заменена на ${AV_SHELLS_NO_LG[0]}"
                SHELL_ARR[c]=AV_SHELLS_NO_LG[0]
            fi
    fi


    # Проверка существования группы по умолчанию, которая вводится по GID
    # Если их не существует, то создаём её

    getent group ${GID_ARR[c]} > /dev/null 2&>1
    if ! [ $? -eq 0 ]; then
        "Создана группа ${GID_ARR[c]}"
        groupadd "${USER_NAME_ARR}-main-group" -g ${GID_ARR[c]}
    fi


    # Проверка существования вторичных групп по имени
    # Если какой-то группы не существует, то создаём её

    IN=${USER_GROUPS_ARR[c]}
    USER_GROUPS=$(echo $IN | tr "," "\n")

    for GROUP in $USER_GROUPS
    do
        getent group $GROUP > /dev/null 2&>1
            if ! [ $? -eq 0 ]; then
                "Создана группа ${GROUP}"
                groupadd $GROUP
            fi
    done
done

# Добавление пользователей
for (( c=0; c<CURRENT_USER; c++ ))
do
    # пользователь имеет всё, кроме uid, gid, вторичные группы, пароль
    CMD="/usr/sbin/useradd -d ${USER_HOME_DIR_ARR[c]} -s ${SHELL_ARR[c]}"

    # Если пользователь имеет вторичные группы
    if ![[ -z ${USER_GROUPS_ARR[c]}; then
        CMD="$CMD -G ${USER_GROUPS_ARR[c]}"
    fi

    # Если пользователь имеет uid
    if ![[ -z ${UID_ARR[c]} ]]; then
        CMD="$CMD -u ${UID_ARR[c]}"
    fi

    # Если пользователь имеет gid

    if ![[ -z ${GID_ARR[c]} ]]; then
        CMD="$CMD -g ${GID_ARR[c]}"
    fi

    # Если пользователь имеет пароль

    if ![[ -z ${PASSWORD_HASH_ARR[c]} ]]; then
        CMD="$CMD -p ${PASSWORD_HASH_ARR[c]}"
    fi

    CMD="$CMD ${USER_NAME_ARR[c]}"
    $CMD
done

echo 'Пользователи успешно добавлены'
exit 0
