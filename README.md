# Aria2 超·懒人包使用指南

## 介绍

Aria2 超·懒人包，一键配置Aria2。注册Aria2后台进程为系统服务，让Aria2以Windows系统服务的方式自动运行。没有cmd窗口，方便进程管理，开机后无需用户登录即可自启动。

<img width="666" height="593" alt="image" src="https://github.com/user-attachments/assets/9bc3095a-81cc-46af-9193-b6fade6a7151" />


## 使用方法

### 安装

1. 从 [**GitHub Releases**](https://github.com/Nahuimi/Aria2-SuperLazyPackage/releases) 下载最新的 ZIP 压缩包，解压后将文件夹 `Aria2` 复制到想要安装的位置。
2. 右键以管理员模式运行 `install.bat`，等待脚本执行完毕，`Aria2Service` 服务即安装成功。
3. 在任务管理器的“详细信息”中，查看“服务”部分，可以看到 `Aria2Service` 服务正在运行。

### 使用

`Aria2` 管理界面建议直接使用浏览器插件 [**Aria2 Explorer**](https://aria2e.com/) ，也可以使用本地网页文件 [**AriaNg**](https://github.com/mayswind/AriaNg)，压缩包内已附带。

### 卸载

1. 右键以管理员模式运行 `uninstall.bat`，等待脚本执行完毕，`Aria2Service` 服务即卸载成功。
2. 然后手动删除文件夹 `Aria2` 即可。

## 程序修改

### aria2 主程序更新

1. 本懒人包采用持续维护的 [**aria2-next**](https://github.com/AnInsomniacy/aria2-next) Windows x86_64 版本。仓库不保存可执行文件，GitHub Releases 中的懒人包会在构建时自动下载并校验最新版。
2. 在任务管理器的“详细信息”中，选中 `Aria2Service` 服务，右键停止。
3. 下载相应版本的 `aria2c.exe` 文件，覆盖 `Aria2` 目录下的文件即可。
4. 在任务管理器的“详细信息”中，选中 `Aria2Service` 服务，右键开始。

### AriaNg 界面更新

1. 下载地址见 [**AriaNg**](https://github.com/mayswind/AriaNg)。GitHub Releases 中的懒人包会自动包含其最新稳定版。
2. 下载相应版本的`AllInOne.zip` 压缩包，解压后用浏览器打开 `index.html` 文件即可。
3. 若使用浏览器插件[**Aria2 Explorer**](https://aria2e.com/) 来管理 `Aria2`，则不需要更新它。

### 编辑 Aria2 配置

1. 若有需求，打开并修改 `Aria2` 目录下的 `aria2.conf` 文件即可，具体参数文档可见 [**Aria2 中文文档 — aria2 1.37.0 documentation**](https://aria2.document.top/zh/) 、 
 [**关于aria2最完整的一篇**](http://ivo-wang.github.io/2019/04/18/%E5%85%B3%E4%BA%8Earia2%E6%9C%80%E5%AE%8C%E6%95%B4%E7%9A%84%E4%B8%80%E7%AF%87/)。
2. 在任务管理器的“详细信息”中，选中 `Aria2Service` 服务，右键重新启动。

### 编辑 shawl 命令

`Shawl` 不采用配置文件的方式，而是直接执行含参命令即可创建服务。如果需要修改命令，直接在`install.bat`中添加参数即可，具体参数可见 [**Shawl-Windows service wrapper for arbitrary commands**](https://github.com/mtkennerly/shawl/blob/master/docs/cli.md)。

### trackers 更新

1. `trackers` 服务器地址来自 [**ngosang/trackerslist**](https://github.com/ngosang/trackerslist)。
2. 手动更新：打开并修改 `Aria2` 目录下的 `aria2.conf` 文件，在 `bt-tracker=` 后添加 `trackers` 服务器地址，使用逗号分隔。
   自动更新：选中 `Aria2` 目录下的 `RenewTrackers.ps1` 文件，右键使用 `PowerShell` 运行。
3. 在任务管理器的“详细信息”中，选中 `Aria2Service` 服务，右键重新启动。

## 下载功能

1. 可配合 [**Aria2 Explorer**](https://aria2e.com/) 浏览器插件，自动拦截接管 HTTP 下载。
2. 可配合 [**网盘直链下载助手**](https://www.youxiaohou.com/zh-cn/) 中的脚本，直链下载网盘文件。
3. 可添加磁链或种子，进行 BT 下载。


## 一些说明

因为 [**FrostSigh大佬的超懒人包**](https://meta.appinn.net/t/aria2-2018-11-19/7434) 太久没有更新，于是我在其基础上进行了修改和更新。

具体内容如下：

1. 构建时下载 [**aria2-next**](https://github.com/AnInsomniacy/aria2-next) 的最新稳定版，并校验上游提供的 SHA-256。
2. 自动打包最新稳定版 `AriaNg`，不过更推荐采用浏览器插件进行管理。
3. 修改 `aria2.conf` 配置文件，增加下载线程、添加详细注释等。
4. 添加最新 `trackers` 服务器，并添加 `trackers` 自动更新脚本。
5. 改为使用`shawl`来创建系统服务。
6. 添加 `dht.dat` 和 `dht6.dat` 文件，方便找到 `dht` 网络。

## 自动发布

GitHub Actions 每天检查一次 `aria2-next` 和 `AriaNg` 的最新稳定版。任一项目发布新版本后，工作流会自动生成新的 GitHub Release；发布说明及压缩包文件名均会标明两个上游版本。


