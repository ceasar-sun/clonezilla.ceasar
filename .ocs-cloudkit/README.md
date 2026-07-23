# Clonezilla OCS CloudKit 輔助工具

本專案提供了一些輔助工具與腳本，以便在 Clonezilla 整合與雲端環境中進行測試與開發。

---

## Git 同步與分支維護注意事項

> **說明：** 用於合併來自 `github.com/stevenshiau/clonezilla` 與 `master/dev` 分支的注意事項。

### 1. 確認並同步遠端 master 分支
**目標：** 確認遠端 `https://github.com/ceasar-sun/clonezilla.ceasar/tree/master` 已經同步。
- **分支：** `master`
- **操作：** 從遠端拉回，並直接以遠端為準。

```bash
git switch master
git pull
git reset --hard origin/master
```

### 2. 讓 master 覆蓋 dev 分支，但保留 `.ocs-cloudkit` 內容
- **分支：** `dev`
- **步驟：**
  1. 在 `dev` 分支強制將狀態重置為 `master`。
  2. 重新檢出（Refetch）並提交 `.ocs-cloudkit` 的內容。
  3. 強制推回（Force push）遠端。

> **注意：** 執行 `git checkout ORIG_HEAD -- .ocs-cloudkit` 時，需注意目前所在路徑是否在 `~clonezilla.ceasar.git/` 目錄下。

```bash
git switch dev
git reset --hard master
git checkout ORIG_HEAD -- .ocs-cloudkit
git commit -m "Refetch .ocs-cloud while syncing with master"
git push origin dev --force
```

---

## Clonezilla ISO 轉 QCOW2 工具 (`cnvt-ocsiso-qcow2`)

將 Clonezilla Live ISO 轉換為 QCOW2 虛擬磁碟格式。

### 1. 建立 ISO-type / VHD-type 的 QCOW2 Clonezilla Live

```bash
./cnvt-ocsiso-qcow2 -i iso/clonezilla-live-20260705-resolute-amd64.iso \
  --use-vhd-mode - \
  --use-iso-mode \
  -kb locales=en_US.UTF-8 keyboard-layouts=us ocs_daemonon="ssh" ocs_prerun01="dhclient -v" toram=live,syslinux,EFI,boot,.disk,utils \
  --prefix ocs-live-20260705-resolute
```

#### 1.1 在 BIOS 或 UEFI 模式下啟動 `iso-qcow2`

```bash
qemu-system-x86_64 -enable-kvm -cpu host -smp 2 -m 4G \
  # 若要使用 uEFI 模式，請取消下行註解：
  # -bios /usr/share/ovmf/OVMF.fd \
  -drive file=./clonezilla-live-iso.qcow2,if=virtio,format=qcow2,index=0,media=disk \
  -netdev user,id=net0,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
  -device virtio-net-pci,netdev=net0 -vga virtio \
  -display gtk,show-cursor=on -boot menu=on
```

#### 1.2 在 BIOS 或 UEFI 模式下啟動 `vhd-qcow2`

```bash
qemu-system-x86_64 -enable-kvm -cpu host -smp 2 -m 4G \
  # 若要使用 uEFI 模式，請取消下行註解：
  # -bios /usr/share/ovmf/OVMF.fd \
  -drive file=./clonezilla-live-vhd.qcow2,if=virtio,format=qcow2,index=0,media=disk \
  -netdev user,id=net0,net=10.0.2.0/24,dhcpstart=10.0.2.15 \
  -device virtio-net-pci,netdev=net0 -vga virtio \
  -display gtk,show-cursor=on -boot menu=on
```

### 2. 建立用於 Redirect-Boot 的 ISO-type / VHD-type QCOW2

```bash
./cnvt-ocsiso-qcow2 -i iso/clonezilla-live-20260705-resolute-amd64.iso \
  --redirect-boot-only \
  --use-vhd-mode - \
  --use-iso-mode \
  --prefix ocs-live-20260705
```

---

## QEMU 掛載與連接 QCOW2 映像檔 (`qemu-nbd`)

使用 `qemu-nbd` 掛載 QCOW2 虛擬磁碟檔案到本機系統。

### 1. 載入核心網路區塊裝置（NBD）模組

```bash
sudo modprobe nbd max_part=8
```

### 2. 將 QCOW2 映像檔對接至 `/dev/nbd0` 虛擬通道

```bash
sudo qemu-nbd --connect=/dev/nbd0 ./qcow2/redirect-bootdisk.qcow2
```

### 3. 掃描分割區並進行掛載
對接後，您可以使用 `lsblk` 檢視分割區（通常會看到 `/dev/nbd0p1`）：

```bash
lsblk /dev/nbd0
sudo mkdir -p /mnt/nbd0
sudo mount /dev/nbd0p1 /mnt/nbd0
```

### 4. 卸載並中斷 QCOW2 連接

```bash
sudo umount /mnt/nbd0
sudo qemu-nbd --disconnect /dev/nbd0
```

---

## QEMU 基本測試指令集

如何在 QEMU 中以 Legacy BIOS 或 UEFI 模式測試 ISO 或 QCOW2。

### 1. 使用 QEMU 啟動 ISO，並掛載 QEMU NAT 網路

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  # 若要使用 uEFI 模式，請取消下行註解：
  # -bios /usr/share/ovmf/OVMF.fd \
  -cdrom clonezilla-live-amd64-new.iso \
  -boot d \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  -vga virtio \
  -display gtk,show-cursor=on
```

### 2. 使用 QEMU 啟動 QCOW2，並掛載 QEMU NAT 網路

```bash
qemu-system-x86_64 \
  -m 2048 \
  # 若要使用 uEFI 模式，請取消下行註解：
  # -bios /usr/share/ovmf/OVMF.fd \
  -drive file=clonezilla-live-amd64.qcow2,format=qcow2 \
  -netdev user,id=net0,hostname=clonezilla-vm -device e1000,netdev=net0 \
  -vga virtio \
  -display gtk,show-cursor=on \
  -enable-kvm
```

### 3. 使用 QEMU 以 UEFI 模式啟動 QCOW2，並掛載 QEMU NAT 網路
*(需要安裝 OVMF 軟體包，例如：`sudo apt-get install ovmf`)*

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -bios /usr/share/ovmf/OVMF.fd \
  -drive file=clonezilla-live-amd64.qcow2,format=qcow2 \
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
  -vga virtio \
  -display gtk,show-cursor=on
```

### 4. 啟動 UEFI 模式：搭配 Clonezilla 與 OracleLinux-R10-U1 映像檔

```bash
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
```

### 5. 啟動 BIOS 模式：搭配 Clonezilla 與 OracleLinux-R10-U1 映像檔

```bash
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
```
