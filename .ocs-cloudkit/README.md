
### Note: git 合併 remote from github.com/stevenshiau/clonezilla and master/dev 注意事項
#
## 目標： 確認遠端 https://github.com/ceasar-sun/clonezilla.ceasar/tree/master 已經同步
# branch : master
## 從遠端拉回，並直接以遠端為準
git switch master
git pull ; git reset --hard origin/master

## 目標：讓 branch : master 覆蓋  branch : dev ，但保持 .ocs-cloudkit  內容
# branch : dev
### 步驟： 1) 在 dev 分支強制將狀態重置為 master、2)Refetch then commit  .ocs-cloud 、3) Force to push back remote
git switch dev
git reset --hard master
git checkout ORIG_HEAD -- .ocs-cloudkit
git commit -m "Refetch .ocs-cloud while syncing with master"
git push origin dev --force

### Note: cnvt-ocsiso-qcow2
# Convert Clonezilla ISO to QCOW2 format 
# Usage : 

# 1. create ISO-type / VHD-type qcow2 Clonezilla live 
./cnvt-ocsiso-qcow2 -i iso/clonezilla-live-20260705-resolute-amd64.iso \
--use-vhd-mode -\
--use-iso-mode \
-kb locales=en_US.UTF-8 keyboard-layouts=us ocs_daemonon="ssh" ocs_prerun01="dhclient -v" toram=live,syslinux,EFI,boot,.disk,utils \
--prefix ocs-live-20260705-resolute

# 1.1 Boot iso-qcow2 mode in BIOS/uEFI mode
qemu-system-x86_64 -enable-kvm -cpu host -smp 2 -m 4G \
##   use uEFI mode :
# -bios /usr/share/ovmf/OVMF.fd \
-drive file=./clonezilla-live-iso.qcow2,if=virtio,format=qcow2,index=0,media=disk \
-netdev user,id=net0,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
-device virtio-net-pci,netdev=net0   -vga virtio  \
-display gtk,show-cursor=on   -boot menu=on

# 1.2 Boot vhd-qcow2 mode in BIOS/uEFI mode
qemu-system-x86_64   -enable-kvm   -cpu host   -smp 2   -m 4G \
##   use uEFI mode :
# -bios /usr/share/ovmf/OVMF.fd \
-drive file=./clonezilla-live-vhd.qcow2,if=virtio,format=qcow2,index=0,media=disk
-netdev user,id=net0,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
-device virtio-net-pci,netdev=net0   -vga virtio  \
-display gtk,show-cursor=on   -boot menu=on

# 2. create ISO-type / VHD-type qcow2 for redirect-boot 
./cnvt-ocsiso-qcow2 -i iso/clonezilla-live-20260705-resolute-amd64.iso  \
--redirect-boot-only \
--use-vhd-mode -\
--use-iso-mode \
--prefix ocs-live-20260705 \


##### Note : for qemu-nbd / qcow2 
## 使用 qemu-nbd 連接掛載 qcow2 檔案
##### 1. 載入核心網路區塊裝置模組：
sudo modprobe nbd max_part=8

##### 2. 將 QCOW2 對接至 /dev/nbd0 虛擬通道：
sudo qemu-nbd --connect=/dev/nbd0 ./qcow2/redirect-bootdisk.qcow2

##### 3. 掃描分割區並進行掛載：
# 您會看見 /dev/nbd0p1 
lsblk /dev/nbd0
sudo mkdir -p /mnt/nbd0
sudo mount /dev/nbd0p1 /mnt/nbd0

##### 4. 卸載 qcow2 檔案
sudo umount /mnt/nbd0
sudo qemu-nbd --disconnect /dev/nbd0


##### Note : for qemu basic usage: 
### How to test iso/qcow2 under legacy/UEFI mode in QEMU
# use qemu 啟動 iso , 並掛載 qemu NAT 網路
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  ##   use uEFI mode :
  # -bios /usr/share/ovmf/OVMF.fd \
  -cdrom clonezilla-live-amd64-new.iso \
  -boot d \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  -vga virtio \
  -display gtk,show-cursor=on

# use qemu 啟動 qcow2 , 並掛載 qemu NAT 網路
qemu-system-x86_64 \
  -m 2048 \
  ##   use uEFI mode :
  # -bios /usr/share/ovmf/OVMF.fd \
  -drive file=clonezilla-live-amd64.qcow2,format=qcow2 \
  -netdev user,id=net0,hostname=clonezilla-vm -device e1000,netdev=net0 \
  -vga virtio \
  -display gtk,show-cursor=on \
  -enable-kvm

# use qemu 以 UEFI 模式啟動 qcow2 ，並掛載 qemu NAT 網路
## require: sudo apt-get install ovmf
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -bios /usr/share/ovmf/OVMF.fd \
  -drive file=clonezilla-live-amd64.qcow2,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -vga virtio \
  -display gtk,show-cursor=on

# uefi mode with clonezilla and OracleLinux-R10-U1 ISO
qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -smp 2 \
  -bios /usr/share/OVMF/OVMF_CODE.fd \
  -m 4G \
  -drive file=clonezilla-live-20260613-resolute-amd64.qcow2,if=virtio,format=qcow2,index=0,media=disk \
  -drive file=./OracleLinux-R10-U1-x86_64-boot.qcow2,if=virtio,format=qcow2,index=1,media=disk \
  -netdev user,id=net0,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
  -device virtio-net-pci,netdev=net0 \
  -vga virtio \
  -display gtk,show-cursor=on \
  -boot menu=on

# BIOS mode with clonezilla and OracleLinux-R10-U1 ISO
qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -smp 2 \
  -m 4G \
  -drive file=/home/ceasar/workspace/ocs-cloudkit/qcow2/clonezilla-live-20260613-resolute-amd64.qcow2,if=virtio,format=qcow2,index=0,media=disk \
  -drive file=./OracleLinux-R10-U1-x86_64-boot.qcow2,if=virtio,format=qcow2,index=1,media=disk \
  -netdev user,id=net0,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
  -device virtio-net-pci,netdev=net0 \
  -vga virtio \
  -display gtk,show-cursor=on \
  -boot menu=on



