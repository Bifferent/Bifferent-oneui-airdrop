# 国行三星 OneUI 8.5 开启 AirDrop（Google mosey）

> 用**临时 KernelSU + 一个模块**，在**不解 BL** 的国行 Galaxy S24 Ultra 上把「与 Apple 设备分享」完整跑起来：**iPhone / Mac 双向发现、双向收发**，同时保留三星互传。

**English TL;DR** — Enable Apple AirDrop (Google *mosey*) on a China-market Samsung OneUI 8.5 device **without unlocking the bootloader**, via temporary KernelSU late-load + Magic Mount RS. The module restores the mosey userspace stack from the HK firmware, switches S互传 to the global build, removes the `cn.google.services` restriction and works around SELinux/permission blockers. Tested on SM-S9280 / S9280ZCS6DZH3: discovery in both directions and file transfer to/from iPhone & Mac. **Proprietary binaries are not included** — build them from your own firmware.

---

## 效果

| 状态 | S互传 | 与 Apple 设备 |
|---|---|---|
| 未 Root（原厂） | 正常，可发现同账号三星设备（Samsung D2D / 互传联盟） | ❌ 无入口 |
| 临时 Root + 本模块 | 正常 | ✅ 双向发现 + 收发文件 |

## 测试环境

| 项目 | 值 |
|---|---|
| 机型 | Galaxy S24 Ultra `SM-S9280` |
| 固件 | 国行 CHC `S9280ZCS6DZH3`（OneUI 8.5 / Android 16） |
| 对照固件 | 港版 OZS `S9280ZHS6DZH3` |
| Root | **不解 BL**，KernelSU `late-load` + Magic Mount RS |
| 内核 | `6.1.145-android14-11`，自带 `wonder.ko` |

---

## 背景：OneUI 8.5 的「与 Apple 设备分享」是什么

它不是三星自己写的 AirDrop，而是复用 Google 的 **mosey** 协议栈：

```
S互传 (ShareLive)
   └─ GMS Nearby Sharing
        └─ MoseyApp (com.google.android.mosey，Quick Share extension)
             └─ IMoseyService (AIDL HAL, /vendor/bin/mosey_server)
                  └─ libmosey_daemon_ffi.so
                       └─ wonder0 / wondertap0 (Wi-Fi 802.11 帧注入, ch149)
```

国行 CHC 固件把 userspace 部分整体裁掉，但内核驱动（`/vendor_dlkm/lib/modules/wonder.ko`）和 SELinux 策略都还在——这是本方案成立的前提。

---

## 根因链（踩坑记录）

### 1. 固件裁剪

CHC 相对 OZS 只少了 6 个 mosey 文件，SELinux type / service_contexts / seapp_contexts 全部保留：

| 文件 | 分区 |
|---|---|
| `mosey_server` | `/vendor/bin/` |
| `libmosey_daemon_ffi.so` | `/vendor/lib64/` |
| `mosey.rc` | `/vendor/etc/init/` |
| `manifest_mosey.xml` | `/vendor/etc/vintf/manifest/` |
| `MoseyApp.apk` | `/system_ext/priv-app/MoseyApp/` |
| privapp / default permissions | `/system_ext/etc/` |

### 2. S互传 编译分支写死

国行 S互传 是 `sepChinaPublic` 分支：

```java
// CapabilitySourceImpl.f()
"sepChinaPublic".startsWith("sepGlobal")  // 恒 false
```

`nearbyShareSupported` 永远不成立，「与 Apple 设备分享」入口和 ProtocolX 永远不会启用。必须换港版 `sepGlobal` 分支的 `ShareLive.apk`（同签名，可直接替换系统 APK）。

### 3. servicemanager 的 VINTF 校验

`mosey_server` 注册 binder 服务时校验 HAL 是否在 device manifest 中声明，而 manifest 有缓存（缓存键是 `/apex/apex-info-list.xml` 的 mtime）。挂载 manifest 后必须：

```sh
touch /apex/apex-info-list.xml
```

否则 `addService` 返回 `UNKNOWN_ERROR`。

### 4. 国行 GMS 禁用 Nearby Sharing

```
NearbySharing: Nearby sharing service is disabled. Do not instantiate Nearby Share
NearbySharing: Sharing is disabled for reason UNSUPPORTED_DEVICE_TYPE_LATCHSKY.
```

GMS 因 `cn.google.services` 特性关闭 Nearby Sharing，MoseyApp 根本不会被拉起。按 [unlock-cn-gms](https://github.com/fei-ke/unlock-cn-gms) 的做法，去掉 `/product/etc/permissions/services.cn.google.xml` 里的：

```xml
<feature name="cn.google.services" />
<feature name="com.google.android.feature.services_updater" />
```

### 5. privapp 权限缺失 → MoseyApp 崩溃循环

`CONNECTIVITY_USE_RESTRICTED_NETWORKS` 必须由 privapp-permissions 白名单授予，否则：

```
java.lang.SecurityException: ConnectivityService: user 10346 has no permission to access restricted network.
```

表现为「Quick Share extension 屡次停止运行」。此外还需要 `pm grant` 运行时权限（BLUETOOTH_SCAN / ADVERTISE / CONNECT、NEARBY_WIFI_DEVICES、定位）。

### 6. vendor SELinux 拒绝 startMosey

```
mosey_daemon: Starting mosey0 at f6:f7:5b:d2:b8:95
mosey_daemon: Error starting mosey: Permission denied (os error 13)
mosey_server: Start mosey returned null
```

国行 vendor 策略缺精确规则，对 `mosey_server` 域加 `permissive mosey_server`（`ksud sepolicy apply` 可运行时生效）。

### 7. 可见性 10 分钟过期 + ProtocolX 挂起

「任何人（仅 10 分钟）」到期会自动收回；再切回「任何人」时可能卡在：

```
[NearbyShareSourceImpl] NS [ resumeProtocolX ] suspendGuard is null, cannot resume
```

结果设置显示「所有人」但双方都发现不了，直到 S互传 / MoseyApp 进程重启。

### 8. PMS 解析缓存导致 S互传 闪退（替换 APK 的副作用）

替换系统 APK 后，PMS 把解析结果缓存在 `/data/system/package_cache/ShareLive-*`。重启后 overlay 消失、磁盘回到国行 APK，但 PMS 复用港版 manifest 的资源 ID → `network-security-config` 被解析成 `PreferenceScreen` → 一开就崩。切换 APK 前后删除该缓存条目即可。

---

## 模块设计

### 文件

```
module/
├── module.prop
├── META-INF/com/google/android/...
├── mount.sh                     # overlayfs(userxattr) 挂载 + SELinux 标签
├── post-fs-data.sh              # 挂载 + touch apex-info + 清 ShareLive 解析缓存
├── service.sh                   # sepolicy + 启动 mosey_server + 授权 + 自动软重启
├── action.sh                    # 手动一键重启分享栈
├── watch_visibility.sh          # 可见性切回「任何人」时自动恢复
├── sepolicy.rule                # permissive mosey_server 等
└── nearby_components.txt        # GMS nearby 组件列表
```

> 二进制（`mosey_server`、`MoseyApp.apk`、`ShareLive.apk` 等）**不随仓库分发**，用 `scripts/` 从你自己的固件生成。

### 每次开机（late-load 后）

1. `post-fs-data`：在 init 挂载命名空间用 overlayfs 挂载 8 个目录并设标签；
2. `touch /apex/apex-info-list.xml`；
3. `ksud sepolicy apply`；
4. 启动 `/vendor/bin/mosey_server`（`runcon u:r:mosey_server:s0`）；
5. 回退 Galaxy Store 的国行 S互传 更新；
6. 授予 MoseyApp 运行时权限、启用 GMS nearby 组件；
7. 若 MoseyApp 未被 PMS 收录，自动 `ksud soft-reboot` 一次（boot_id 防循环）；
8. 拉起 `watch_visibility.sh`。

---

## 自动恢复

`watch_visibility.sh` 每 3 秒读一次：

```
/data/data/com.samsung.android.app.sharelive/shared_prefs/quick_share_nearby_setting_pref.xml
device_visibility_type: 1=您的设备 2=联系人 3=任何人
```

检测到切回 **3（任何人）** 后等 3 秒自动执行 `action.sh`（重启 HAL + MoseyApp + S互传），20 秒冷却。代价是 S互传 窗口会闪退一次，重新打开即可。

也可以在 KernelSU 管理器点模块的 **action** 按钮手动触发。

---

## 性能实测

mosey 走的是 userspace AWDL 实现，吞吐有明显上限。实测（SM-S9280 → iPhone，645MB MP4）：

| 指标 | 数值 |
|---|---|
| 文件 | `20261113_000642.mp4`，676,653,957 字节（645 MiB） |
| 耗时 | 246 秒 |
| 载荷平均速度 | **2.75 MB/s ≈ 22 Mbps** |
| `wonder0` tx 平均（含协议开销） | 3.0 MB/s ≈ 24 Mbps |
| 5 秒峰值 | 4.7 MB/s ≈ 39 Mbps |

发送与接收基本对称，瓶颈都在三星侧：

```
mosey_daemon: Transceiver task channel is full      # 内部收发队列持续打满
mosey_server  spin-sleep      67.8% CPU             # 软件 AWDL 时序
mosey_server  tokio-runtime-w 17.8% CPU
```

- `mosey_server` 已运行在性能核（亲和性 `fc`），worker nice -8；
- 传输时手机未连接 Wi-Fi AP，射频独占；
- `mosey_server` 是三星 2026-02-04 版闭源二进制，`wonder.ko` 只有 `physical_name` 一个参数，**没有队列/线程/带宽相关的可调项**。

结论：**20–30 Mbps 是该实现的正常水平**，模块层面无法优化；能改善的只有环境（清内存、保持亮屏、两台设备靠近、避免同时连 AP）。

### 复现测速

传输时在电脑上运行：

```sh
./scripts/measure_throughput.sh 300
```

脚本每 2 秒读取一次 `/sys/class/net/wonder0/statistics/{tx,rx}_bytes`，结束时给出平均与峰值。也可以手动采样：

```sh
adb shell 'cat /sys/class/net/wonder0/statistics/tx_bytes'
```

---

## 从自己的固件构建模块

> 需要一个港版/国际版 AP 包（`.tar.md5`），以及 `lz4`、`python3`、`erofs-utils`（`fsck.erofs`）。

```sh
# 1) 提取 mosey 相关文件到 out/payload
./scripts/extract_from_firmware.sh /path/to/AP_*.tar.md5 out

# 2) 组装模块并打包
./scripts/build_module.sh out/payload dist
# -> dist/mosey_airdrop_s9280.zip
```

手动提取步骤见文末附录。

---

## 安装与使用

1. KernelSU 管理器安装 `mosey_airdrop_s9280.zip`
   （目录名必须与 `module.prop` 的 `id` 一致，否则管理器无法启用）；
2. 重启手机，按原流程重新 late-load KernelSU（临时 root）；
3. S互传 → 设置 → 「谁可以与您分享」：
   - 临时测试选 **任何人（仅 10 分钟）**；
   - 长期使用建议选 **联系人**，并把对方 Apple ID 加进三星联系人（无 10 分钟过期）；
4. 打开 S互传 → 接收，或直接分享文件。

### 验证

```sh
service list | grep -i mosey          # HAL 是否注册
ls /sys/class/net | grep wonder       # wonder0 是否创建
logcat -b all -d | grep mosey_daemon  # daemon 日志
# 正常应看到:
#   mosey_daemon: Starting mosey0 at ...
#   Mosey.A: Sending back valid discover response
```

---

## 已知限制

- 临时 root 不持久，每次重启都要重新 late-load；
- `permissive mosey_server` 是安全折衷（域级 permissive，仅限该进程）；
- S互传 换成港版后，国行「互传联盟」入口可能变化；
- Galaxy Store 可能把 S互传 更新回国行版，模块会自动回退；
- 「任何人」10 分钟过期，且切换后必须重启一次分享栈（已由 watcher 自动处理）；
- 仅测试 SM-S9280 / OneUI 8.5，其它机型（尤其缺 `wonder.ko` 的国行固件）不要照搬；
- 大文件传输速度约 20–30 Mbps（见「性能实测」），瓶颈在 mosey userspace，无模块级优化空间；
- 临时 root 本身会影响 Play Integrity / KNOX，与本模块无关。

---

## 回退

1. KernelSU 管理器禁用/删除模块并重启；
2. 应用商店把 S互传 更新回国行版；
3. 删除模块后 overlay 随重启消失，系统回到原厂状态。

---

## 声明与许可

- 仅供研究与个人设备互操作，与 Samsung / Google / Apple 无关；
- 仓库内**不包含**任何 Samsung/Google 的二进制，请从你自己合法持有的固件中提取；
- 脚本与文档以 MIT 许可发布；固件提取物版权归各自权利人所有；
- 改机有风险，KNOX 熔断 / 保修失效 / 数据丢失请自行承担。

---

## 参考

- 酷安原帖：Wxxsfxyzm《可能是第一个在国行上用上 airdrop 的？》
- [thelok1s/mosey-extended](https://github.com/thelok1s/mosey-extended) —— mosey 栈逆向与 KSU 模块实现
- [fei-ke/unlock-cn-gms](https://github.com/fei-ke/unlock-cn-gms) —— 去除 `cn.google.services` 限制
- KernelSU / Magic Mount RS

---

## 附录：手动提取

```sh
tar -xf AP_*.tar.md5 super.img.lz4
lz4 -d super.img.lz4 super.img
# 若是 Android sparse，先转 raw
python3 scripts/sparse2img.py super.img super.raw.img
# 解析 LP metadata 并导出分区（vendor / system_ext / system）
python3 scripts/lpunpack.py super.raw.img extract vendor out/vendor.img
python3 scripts/lpunpack.py super.raw.img extract system_ext out/system_ext.img
python3 scripts/lpunpack.py super.raw.img extract system out/system.img
# 解 erofs
fsck.erofs --extract=out/vendor out/vendor.img
fsck.erofs --extract=out/system_ext out/system_ext.img
fsck.erofs --extract=out/system out/system.img
```

需要的文件：

```
out/vendor/bin/mosey_server
out/vendor/lib64/libmosey_daemon_ffi.so
out/vendor/etc/init/mosey.rc
out/vendor/etc/vintf/manifest/manifest_mosey.xml
out/system_ext/priv-app/MoseyApp/MoseyApp.apk
out/system_ext/etc/permissions/privapp-permissions-com.google.android.mosey.xml
out/system_ext/etc/default-permissions/default-permissions-com.google.android.mosey.xml
out/system/priv-app/ShareLive/ShareLive.apk        # 港版 sepGlobal
```

---

## FAQ

**Q: 模块在 KernelSU 里无法启用？**
A: 检查 `/data/adb/modules/<目录名>` 是否与 `module.prop` 的 `id` 一致——管理器用 id 找目录。

**Q: 重启后未 Root 状态 S互传 闪退？**
A: 这是替换系统 APK 后 PMS 解析缓存不一致导致的。模块会在切换 APK 前后删除 `ShareLive-*` 缓存；手动修复：`rm -f /data/system/package_cache/*/ShareLive-*` 后重启。

**Q: 切回「所有人」后突然发现不了？**
A: ProtocolX 挂起无法恢复，模块的 `watch_visibility.sh` 会自动重启分享栈；也可以点模块 action 按钮。
