#!/bin/bash

  #用于获得目前分区大小
  get_partcount(){
    PART_COUNT=$(fdisk -l | egrep -o "${I}[0-9]" | wc -l)
  }

  #用于获得目前磁盘可用空间
  get_remain_sector(){
    let RMNSCT_COUNT=${SECTOR_COUNT}-${USED_SECTOR_COUNT}
  }

  #用于从用户输入分区大小
  get_part_size(){
    while true
    do
      read -p "input part size:": GET_PART_SIZE
      if [[ $GET_PART_SIZE =~ ^[[:digit:]]+[K|M|G]$ ]]
      then
        return
      else
        echo bad format
      fi
    done

  }

  #用于创建主分区
  crtpart(){
    echo -e "n\n\n\n\n+$1\nw" | fdisk ${I} &> /dev/null
  }

  #用于创建逻辑分区
  crtlgcpart(){
    echo -e "n\n\n+$1\nw" | fdisk ${I} &> /dev/null
  }

  #用于创建扩展分区
  crtexpart(){
    echo -e "n\n\n\n\nw" | fdisk ${I} &> /dev/null
  }

  #若用户输入分区大小合法，则创建主分区
  tstpart(){
    while true
    do
      get_part_size
      if ! echo -e "n\n\n\n\n+${GET_PART_SIZE}\nq" | fdisk ${I} &> /dev/null
      then
        echo "the partition size is too big!"
        continue
      else
        crtpart ${GET_PART_SIZE}
        return
      fi
    done
  }

  #若用户创建分区大小合法，则创建逻辑分区
  tstlgcpart(){
    while true
    do
      get_part_size
      if ! echo -e "n\n\n+${GET_PART_SIZE}\nq" | fdisk ${I} &> /dev/null
      then
        echo "the partition size is too big!"
        continue
      else
        crtlgcpart ${GET_PART_SIZE}
        return
      fi
    done
  }

  #用于创建ext4文件系统
  makeext4(){
    for K in $(fdisk -l ${I} | egrep -o "${I}[0-9]+")
    do
      mkfs.ext4 $K &> /dev/null
      echo "$K has been created as ext4"
    done
  }

  #用于挂载和更新/etc/fstab文件
  mountpart(){
    for K in $(fdisk -l ${I} | egrep -o "${I}[0-9]+")
    do
      DNAME=` echo $K | egrep -o "/[^/]+$" `
      if ls /mnt${DNAME} &> /dev/null
      then
        continue
      else
        mkdir /mnt${DNAME} &> /dev/null
        mount $K /mnt${DNAME}
        DUUID=` blkid | egrep $K | cut -d "\"" -f2 `
        echo -e "UUID=$DUUID/t\/mnt$DNAME/text4/tdefaults/t0/t0" >> /etc/fstab
      fi
    done
  }

  #用于分区
  part(){
    #当用户输入分区和目前分区之和小于15时，可以创建分区
    while true
    do
      read -p "you can create $[15-${1}] partitions:": GET_PART_COUNT
      if [[ ${GET_PART_COUNT} =~ [^[:digit:]] ]]
      then
        echo "wrong format"
        continue
      else
        if [ ${GET_PART_COUNT} -gt $[15-${1}] ]
        then
          echo "too big"
        else
          break
        fi
      fi
    done

    #若正在分区的分区号小于等于3，则创建主分区，若等于4，则创建扩展分区，否则创建逻辑分区
    for((j=1;j<=${GET_PART_COUNT};j++))
    do
      if [ $[${j}+${1}] -le 3 ]
      then
        #判断是否有剩余空间，若没有则停止分区
        get_remain_sector
        echo "remain sector is $RMNSCT_COUNT"
        if [ ${RMNSCT_COUNT} -le 2000 ]
        then
          echo "capacity has been used up"
          break
        fi
        #创建主分区，并更新剩余空间大小
        tstpart
        USED_SECTOR_COUNT=` fdisk -l ${I} | grep -v "Extended" | grep "^/dev" | cut -d "*" -f-5 --output-delimiter=" " | tr -s " "| cut -d " " -f3 | sort -n | tail -1 `
        echo "No.$[${j}+${1}]  primary has been created, it is $GET_PART_SIZE"
      elif [ $[${j}+${1}]  -eq 4 ]
      then
        #判断是否有剩余空间，若没有则停止分区
        if [ ${RMNSCT_COUNT} -le 2000 ]
        then
          echo "capacity has been used up"
          break
        fi
        #创建扩展分区
        crtexpart
        echo "No.4 extended partition has been created."
      else
        #更新剩余空间大小，若还有剩余空间，则继续分区，否则停止分区
        USED_SECTOR_COUNT=` fdisk -l ${I} | grep -v "Extended" | grep "^/dev" | cut -d "*" -f-5 --output-delimiter=" " | tr -s " "| cut -d " " -f3 | sort -n | tail -1 `
        get_remain_sector
        echo "remain sector is $RMNSCT_COUNT"
        if [ ${RMNSCT_COUNT} -le 2000 ]
        then
          echo "capacity has been used up"
          break
        fi
        #创建逻辑分区
        tstlgcpart
        echo "No.$[${j}+${1}]  logical has been created, it is $GET_PART_SIZE"
      fi
    done
  }

  #用于判断磁盘情况并进行分区和挂载
  partitions(){
    SECTOR_COUNT=$(fdisk -l ${I} | head -2 | tail -1 | awk '{print $7}')
    #若没有分区，则已用空间为0
    USED_SECTOR_COUNT=0
    get_partcount
    if [ ${PART_COUNT} -eq 0 ]
    then
      #进行分区和挂载
      part 0
      makeext4
      mountpart
      return
    fi
    #若没有剩余空间，则无法分区
    USED_SECTOR_COUNT=` fdisk -l ${I} | grep -v "Extended" | grep "^/dev" | cut -d "*" -f-5 --output-delimiter=" " | tr -s " "| cut -d " " -f3 | sort -n | tail -1 `
    get_remain_sector
    if [ ${RMNSCT_COUNT} -le 2000 ]
    then
      echo "no place to create new partition"
      return
    else
      #进行分区和挂载
      part ${PART_COUNT}
      makeext4
      mountpart
      return
    fi
  }

  select I in ` ls /dev/sd? ` quit
  do
    case ${I} in
      /dev/sda)
        echo "This disk had installed OS, select others please."
        continue
        ;;
      /dev/sd[b-z])
        partitions
        ;;
      quit)
        echo "see you next time"
        break
        ;;
      *)
        echo "bad choice"
        continue
        ;;
    esac
  done

  unset PART_COUNT I J K SECTOR_COUNT USED_SECTOR_COUNT DNAME PART_COUNT GET_PART_COUNT GET_PART_SIZE RMNSCT_COUNT