# 架构与数据流

## 模块职责

| 目录 | 职责 |
| --- | --- |
| pages/ | 页面状态、查询状态、编辑和导入流程 |
| components/ | 受控展示组件，以属性接收数据、以回调上报交互 |
| model/ | 账目、草稿、通知归档类型和主页签导航状态，以及金额和日期格式化 |
| data/ | ArkData relationalStore 读写和数据库初始化 |
| services/ | OCR、账单解析、通知解析与规则引擎、规则偏好存储和统计计算 |
| state/ | 分享导入等跨扩展入口的短期应用状态 |
| entryability/ | EntryAbility 启动、前后台切换与宿主能力 |
| extensionability/ | 图片分享导入、通知订阅等扩展入口 |

`Index.ets` 负责主页签和跨页面流程协调；`MainTabNavigation.ts` 保存纯导航状态。数据计算与数据库访问不应放进展示组件。

~~~mermaid
flowchart LR
  User[用户] --> Index[Index 页面协调]
  Index --> Nav{账本 / 通知}
  Nav --> LedgerTab[账本页签]
  Nav --> NotifyTab[通知页签]
  LedgerTab --> Picker[系统图片选择器或分享图片]
  Picker --> OCR[Core Vision 本地 OCR]
  OCR --> OcrCoordinator[来源检测与账单解析]
  OcrRules[OCR 规则设置] --> OcrPreferences[(Preferences: ocr_recognition_rules)]
  OcrPreferences --> OcrCoordinator
  OcrCoordinator --> Review[逐条复核]
  Review --> Ledger[LedgerRepository]
  Ledger --> LedgerDB[(harmony_ledger.db)]
  LedgerTab --> ImportPicker[系统文档选择器]
  ImportPicker --> CsvImport[CsvImporter]
  CsvImport --> CsvPreview[导入预览与确认]
  CsvPreview --> Ledger
  LedgerTab --> ExportPicker[系统保存选择器]
  ExportPicker --> CsvExport[CsvExporter]
  CsvExport --> CsvFile[CSV 文件]
  NotifyTab --> History[通知历史页]
  NotifyTab --> NotifySettings[通知设置与规则]
  NotifySettings --> NotifyRules[NotificationRuleStore]
  NotifyRules --> NotifyPreferences[(Preferences: notification_rules)]
  SystemNotify[系统通知订阅] --> Extension[NotificationProbeExtension]
  Extension --> Archive[NotificationArchiveRepository]
  Archive --> ArchiveDB[(notification_archive.db)]
  NotifyPreferences --> Extension
  Extension --> Parser[BankNotificationParser / NotificationRuleEngine]
  Parser --> Ledger
  LedgerTab --> Stats[LedgerStatistics]
~~~

## 本地数据库

### 账本

账本存放在 harmony_ledger.db 的 ledger_entries 表。金额使用 amount_fen 整数分保存，direction 区分收入和支出；happened_at 保存本地时间戳，has_time 表示是否识别到具体时分。只有日期的 OCR 账目以当天日期保存，但 has_time 为 false；显示和导出时不显示虚构的时分。

既有字段包括 id、happened_at、amount_fen、direction、source、merchant、category、note 和 has_time。新增 accounting_type 保存普通（normal）、信用卡消费（credit-card）或信用卡还款（credit-repayment），与消费分类独立。初始化时通过 PRAGMA 检查列并原地添加，旧账目默认 normal；保留已有字段、记录和数据库。

首页展示收入、支出、其中信用卡消费、本期现金结余四项。支出包含信用卡消费，排除信用卡还款；现金结余＝收入－支出＋信用卡消费－信用卡还款，表示该账期现金流净额。还款金额只在统计详情展示，不参与支出趋势或排行。还款记录仍保留在账本，可长按设置或撤销记账类型，也可在编辑页面修改；收入只能使用普通类型。

通知和 OCR 规则可设置 isCreditCard，仅把命中的支出记为信用卡消费，收入不受影响。旧规则未设置该字段时按普通规则处理，修改规则不批量改写历史账目。重复通知沿用既有查重，命中普通记录时允许补充信用卡消费标记，不覆盖已标记的还款；分类仍仅在原分类为“其他”时补充。

信用卡规则卡片提供“标记历史账目”入口。通知规则在本机分页重放已有归档，以同分钟、金额和支出方向匹配已有账目；仅匹配唯一且仍为普通支出的记录默认勾选。没有原文的账目可按来源、日期及商户或备注关键词筛选，并人工勾选；OCR 规则仅提供这种候选筛选。归档读取失败时仍可手动筛选，不把部分扫描结果当作完整预览。确认后通过事务仅更新记账类型，复核预览快照以跳过已编辑或已标为还款的记录，失败则整批回滚；不新增或删除账目，不保存额外通知原文，不需要数据库迁移。

LedgerRepository 在新增、批量导入、编辑、删除和通知自动入账（含匹配账目的分类更新）后发出跨进程数据变更事件。Index 监听事件并重新读取账目；并发读取时只接受最后发起的查询结果，避免旧列表覆盖新数据。截图分享扩展、通知扩展或其他写入入口的变化因此能反映到当前页面，页面内保存流程也会主动重载。

### 通知归档

通知标题、正文和系统来源字段独立存放于 notification_archive.db 的 notification_events 表。归档与自动记账分别使用自己的异步队列和错误处理：归档失败不会阻止通知自动记账，自动记账失败也不会阻止保存通知历史。

该数据库会保存设备实际投递给本应用的通知内容；使用者应将它视作敏感个人数据。当前版本没有云端副本或账号同步。

### 可编辑识别规则

OCR 规则与通知规则不存入账本或通知归档数据库，而是分别以版本化 JSON 存在 ArkData Preferences：`ocr_recognition_rules` 和 `notification_rules`。OCR 导入流程读取当前规则并交给来源检测和通用/兼容解析器；通知扩展在处理新通知时读取通知规则，再调用通知解析引擎。旧 OCR 和通知规则分别迁移到版本 2，保留已有解析配置。规则编辑不会改写已有账目或通知归档。

规则导入使用独立的 `RuleImportEngine` 校验带版本号的精简 JSON。OCR 与通知适配器把描述编译成各自的运行时规则，并调用正式解析器本地预览样例。样例只在设置页面当前导入草稿中流转，不传给存储服务；只有用户确认后才追加运行时规则并写入 Preferences。提示词可复制到外部 AI，应用不发送网络请求。OCR 文字样例不包含图片坐标，不能验证列范围本身。

## 页面与服务流

- 底部“账本”和“通知”为同级页签。切换页签时回到账本首页或通知历史页；`MainTabNavigation.ts` 表示当前页签，以及通知页内的历史、设置和规则路由。
- 账本设置包含记账周期、OCR 识别规则和数据备份；数据备份位于设置页底部，并提供 CSV 导入/导出。通知设置管理通知授权、穿戴设备转发和诊断，通知识别规则在通知设置内单独编辑。
- `Index.ets` 协调统计、手动编辑、OCR 复核和页签路由。通知历史作为“通知”页签的主页面展示。
- LedgerStatistics.ets 对已加载的账目按本地日期和所选记账周期做纯计算；统计视图负责图表与排行展示。
- OcrRuleStore.ets 和 NotificationRuleStore.ets 分别读取及校验偏好设置中的规则；OCR 规则供截图导入流程使用，通知规则由通知扩展用于后续自动记账。
- RuleImportEngine.ets 校验 OCR/通知精简规则；对应导入适配器通过正式解析器本地试跑样例，设置页确认后只保存运行时规则。
- CsvExporter.ets 通过系统文档保存选择器写出 UTF-8 CSV，默认基础文件名为“通知记账”并提供 `csv` 后缀选项；CsvImporter.ets 读取用户选择的 CSV 并生成导入预览。文件只在导入流程内读取，不长期保留。
- ShareImportExtension 接收用户从其他应用明确分享过来的图片 URI；图片仍由 OCR 导入流程处理。
- NotificationProbeExtension 将通知归档和自动记账排入独立队列。`BankNotificationParser.ets` 负责把系统通知转换为通用输入并调用 `NotificationRuleEngine.ets`；具体来源和正文正则来自可编辑规则，解析器不再维护银行专用正文正则。

## CSV 导入与导出

导出的 CSV 在原七列末尾增加“记账类型”（普通、信用卡消费、信用卡还款）；导入同时接受新八列表头和旧七列表头，旧文件恢复为普通类型。导入支持 UTF-8 BOM、逗号分隔、双引号包裹、双引号重复转义和带引号字段中的换行；表头不匹配时拒绝文件。日期、金额、方向、来源或记账类型不合法的行会列入预览，不写入账本。

导入前按导出的日期精度、方向、金额、商户、分类、来源、备注和记账类型与现有账目比较。完全相同的现有记录会跳过并计数；导入文件内部重复的行保留。用户确认后才批量写入。CSV 每个字段以双引号包裹；可能被表格软件解释为公式的前导字符会转义。表格软件处理规则各不相同，重新保存文件可能改变转义行为。参见 [OWASP CSV Injection](https://owasp.org/www-community/attacks/CSV_Injection)。
