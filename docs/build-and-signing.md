# 构建与签名

## 环境

- DevEco Studio 与 HarmonyOS SDK 26。
- 项目最低目标为 HarmonyOS 7 / API 26，使用 Stage 模型。
- 应用包名为 `com.gyg.harmonyledger`。

在 PowerShell 中将路径替换为本机 DevEco Studio 安装目录：

~~~powershell
$devEcoStudioRoot = 'C:\path\to\DevEco Studio'
$env:DEVECO_SDK_HOME = Join-Path $devEcoStudioRoot 'sdk'
$hvigor = Join-Path $devEcoStudioRoot 'tools\hvigor\bin\hvigorw.bat'
& $hvigor --mode module -p product=default assembleHap
~~~

HAP 自动使用 `entry/build-profile.json5` 中的 `artifactName`，当前名称为 `harmonyledger`，无需手动重命名。构建产物位于 `entry/build/default/outputs/default/`。

## 本机签名

仓库不保存签名材料。项目根目录的 `hvigorfile.ts` 在构建时读取本机 `signing.local.json`；文件缺失时会构建未签名 HAP。仓库提供 `signing.local.json.example` 作为格式示例，按本机 DevEco 签名材料填写后，将其保存为根目录下的 `signing.local.json`。证书、Profile、密钥库路径及 DevEco 加密口令放在该配置的 `material` 字段中。

`.gitignore` 已排除 `signing.local.json` 和常见签名文件。提交前检查 `git status` 与 `git diff`，确认签名配置、本机路径、证书、密钥和口令没有进入版本控制。

## 版本号

`hvigorfile.ts` 使用 `git rev-list --count HEAD` 获取仓库总提交数，并加上版本序列偏移量 `18`。`versionCode` 为偏移后的数量加 `1,000,000`；`versionName` 使用当前提交可达的最近版本 tag（去掉开头的 `v`）加偏移后的数量，例如 tag 为 `v1.0.2`、总提交数为 `66` 时，版本名为 `1.0.2.83`。该偏移用于主线历史压缩后继续递增已安装版本；再次整理提交历史时，应相应调整偏移，避免设备将新包识别为降级。HarmonyOS 的版本名格式不接受 `v` 前缀。构建需要可读取的完整 Git 历史和可达的 `v*` 版本 tag。

## GitHub Actions

`.github/workflows/build-unsigned-hap.yml` 仅在推送匹配 `v*` 的 Git tag 时触发。普通分支推送和手动触发不会运行该工作流。tag 构建成功后，工作流会创建 GitHub Release，并附上未签名 HAP 与 SHA-256 校验文件。
