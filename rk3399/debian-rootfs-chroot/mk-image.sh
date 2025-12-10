#!/bin/bash -e

#指定rootfs.img挂载点./binary，linaro-rootfs.img挂载点./rootfs，输出名称为linaro-rootfs.img
TARGET_ROOTFS_DIR=./binary
MOUNTPOINT=./rootfs
ROOTFSIMAGE=linaro-rootfs.img
OUT=../out

# 输出消息：正在创建文件系统
echo Making rootfs!

# 如果linaro-rootfs.img已存在，则删除它
if [ -e ${ROOTFSIMAGE} ]; then 
    rm ${ROOTFSIMAGE}
fi

# 如果挂载点./rootfs已存在，则删除它
if [ -e ${MOUNTPOINT} ]; then 
    rm -r ${MOUNTPOINT}
fi

# 创建挂载点目录
mkdir ${MOUNTPOINT}

# 使用 dd 命令创建一个指定大小的空白linaro-rootfs.img系统映像文件
dd if=/dev/zero of=${ROOTFSIMAGE} bs=1M count=0 seek=4000

# 定义一个函数：用于在出现错误时执行清理操作
finish() {
    sudo umount ${MOUNTPOINT} || true
    echo -e "\e[31m MAKE ROOTFS FAILED.\e[0m"
    exit -1
}

# 输出消息：正在将linaro-rootfs.img系统格式化为 ext4 格式
echo Format rootfs to ext4

# 使用 mkfs.ext4 命令将linaro-rootfs.img系统映像格式化为 ext4 文件系统
mkfs.ext4 ${ROOTFSIMAGE}

# 输出消息：正在将linaro-rootfs.img根文件系统映像挂载到指定挂载点
echo Mount rootfs to ${MOUNTPOINT}

# 使用 mount 命令将linaro-rootfs.img根文件系统映像挂载到指定挂载点
sudo mount  ${ROOTFSIMAGE} ${MOUNTPOINT}

# 设置错误处理器：如果出现错误，则执行 finish 函数
trap finish ERR

# 输出消息：正在将根文件系统复制到挂载点
echo Copy rootfs to ${MOUNTPOINT}

# 使用 cp 命令将rootfs.img根文件挂载目录复制到linaro-rootfs.img挂载点
sudo cp -rfp ${TARGET_ROOTFS_DIR}/*  ${MOUNTPOINT}

# 输出消息：正在卸载根文件系统
echo Umount rootfs

# 使用 umount 命令卸载inaro-rootfs.img根文件系统
sudo umount ${MOUNTPOINT}

# 输出inaro-rootfs.img根文件系统映像的名称
echo Rootfs Image: ${ROOTFSIMAGE}

# 使用 e2fsck 命令检查和修复 ext4 linaro-rootfs.img文件系统中的错误
e2fsck -p -f ${ROOTFSIMAGE}

# 使用 resize2fs 命令将 ext4 linaro-rootfs.img文件系统调整到最小可能的大小
resize2fs -M ${ROOTFSIMAGE}

# 如果输出目录不存在，则创建它
[ ! -d ${OUT} ] && mkdir ${OUT}

# 将根文件系统inaro-rootfs.img映像复制到输出目录
cp $ROOTFSIMAGE ${OUT}

