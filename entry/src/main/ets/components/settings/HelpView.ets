interface HelpTopic {
  id: string;
  title: string;
  summary: string;
  steps: string[];
  notes: string[];
}

@Component
export struct HelpView {
  @Prop activeTopicId: string = 'start';
  onSelectTopic: (id: string) => void = (_id: string) => {};
  onBack: () => void = () => {};

  private topics: HelpTopic[] = [
    {
      id: 'start', title: '开始记账', summary: '手动记账、编辑与记账周期',
      steps: [
        '在“账本”页点“手动记账”，填写金额、日期、收入或支出，以及商户和分类，确认后保存。',
        '点开已有账目可编辑；长按账目可查看可用操作，包括删除和调整记账类型。',
        '在“账本 → 设置”选择每月周期起始日。首页按该周期汇总，年统计仍按自然年。'
      ],
      notes: ['账目只保存在本机，卸载或更换设备前请先导出完整备份。']
    },
    {
      id: 'ocr', title: '导入账单截图', summary: '选择截图、逐笔复核与重复提醒',
      steps: [
        '在“账本”页点“识别账单截图”，从系统图片选择器选择账单截图；也可从其他应用分享图片给本应用。',
        '初始支持微信支付、支付宝和工商银行。来源无法确定时按提示手动选择；其他格式可先配置 OCR 识别规则。',
        '逐笔核对金额、日期、收支、商户和分类，取消勾选不需要的记录，再确认保存。'
      ],
      notes: [
        '识别结果只是草稿，不会直接入账。缺少可靠日期的记录不会生成可入账草稿；只有日期时不会补造时分。',
        '遇到相似重复提醒，请先对照已有账目。金额符号、余额和退款方向尤其需要核实。'
      ]
    },
    {
      id: 'notifications', title: '开启通知自动记账', summary: '授权来源、接收诊断与漏记排查',
      steps: [
        '进入“通知 → 设置 → 打开通知访问授权”，在系统页面允许访问，并选择需要接收的来源应用。返回后刷新授权状态。',
        '如需通过已配对设备转发通知，在“穿戴设备通知转发”中查找设备并订阅，按系统提示授予蓝牙访问权限。',
        '在“通知”页查看实际收到的通知。只有命中启用规则，且能识别有效金额、收支和时间的通知才会自动入账。',
        '如果漏记，先看通知历史里有没有原通知；没有时检查系统授权、来源选择和设备订阅。有原通知但未入账时，再检查识别规则或从通知详情创建规则。'
      ],
      notes: [
        '初始规则覆盖工商银行、中信银行、支付宝和微信支付，并非所有通知格式都能识别。',
        '修改规则只影响之后收到的通知，不会补记已有通知历史。重复交易按既有查重规则处理。'
      ]
    },
    {
      id: 'rules', title: '添加或调整识别规则', summary: '用样例生成规则，再在本机核对',
      steps: [
        'OCR：进入“账本 → 设置 → 管理 OCR 识别规则”，选择一张截图提取文字。通知：在通知详情点“用此通知创建规则”，自动带入来源、标题、正文和时间。',
        '检查原文，确认其中一笔交易的金额、日期和收支，可补充商户、分类。通知正文另有交易时间时，按正文修正。',
        '遮盖姓名、卡号等敏感信息，点“复制完整 AI 材料”，交给你使用的外部 AI。应用不会自动上传材料。',
        '把 AI 返回的完整内容粘贴回应用。检查字段对照，标红或未识别时调整规则再预览；通过后点“确认保存并优先启用”。',
        '新规则放在列表顶部。需要手动新增、编辑表达式或排序时，展开“高级设置”。通知标题固定时可开启标题限制；含金额或商户且每次变化时应保持关闭。'
      ],
      notes: [
        '截图预览使用真实坐标；修改原文后改用文字预览，无法验证截图列范围。单个样例通过不代表覆盖所有交易。',
        String.raw`JSON 正则字段支持直接使用 \d、\s、\.；已有合法 JSON 转义保持原意。词边界需要写为 \\b。高级设置的正则输入框直接填写正则即可。`
      ]
    },
    {
      id: 'credit', title: '信用卡消费与还款', summary: '区分记账类型，批量标记历史消费',
      steps: [
        '支出可设为普通、信用卡消费或信用卡还款，在编辑页面或长按账目后调整。收入使用普通类型。',
        '信用卡的 OCR 或通知规则可开启信用卡消费标记，让之后命中的支出按信用卡消费保存。还款请单独核对并设置记账类型。',
        '需要整理旧账时，在信用卡规则卡片点“标记历史账目”，检查候选并勾选后确认。没有通知原文的账目可用来源、日期和关键词手动筛选。',
        '批量标记有误时，可在设置或历史标记页撤销最近一次批量标记；已被编辑、删除或发生后续变化的记录可能跳过。'
      ],
      notes: ['批量标记只调整已有账目的记账类型，不新增或删除账目。']
    },
    {
      id: 'statistics', title: '看懂统计与现金结余', summary: '收支口径与信用卡的影响',
      steps: [
        '首页按当前记账周期展示收入、支出、其中信用卡消费和本期现金结余。可切换周期，进入统计详情查看趋势和排行。',
        '信用卡消费计入支出；信用卡还款单独统计，不重复计入支出趋势和排行。',
        '现金结余＝收入－支出＋信用卡消费－信用卡还款。它反映当前记录中的现金流，不是银行账户余额。'
      ],
      notes: ['统计异常时，先检查日期范围、记账周期，以及消费和还款的记账类型是否正确。']
    },
    {
      id: 'backup', title: '备份、恢复与数据隐私', summary: '完整 JSON 备份和 CSV 的区别',
      steps: [
        '在“账本 → 设置 → 数据备份”点“导出完整备份（JSON）”。完整备份包含账目及识别信息、OCR/通知规则和记账周期。',
        '点“从完整备份恢复”，选择文件并检查预览。账目按 ID 合并，冲突保留本机；规则和记账周期会在确认后整体替换。',
        'CSV 适合用表格工具查看或交换账目，导入接受本应用导出的格式。它不包含识别规则、记账周期和入账识别信息。',
        '卸载或更换设备前导出完整备份。恢复期间保持应用运行，完成后核对账目和设置。'
      ],
      notes: [
        '完整备份不包含通知归档、截图和历史批量标记的撤销记录。备份为明文文件，请妥善保管。',
        '账目、识别规则和通知归档保存在本机，不提供云同步。通知归档含完整标题和正文，可能包含个人或金融信息。'
      ]
    }
  ];

  build() {
    Column() {
      Row() {
        Button('返回').backgroundColor('#FFFFFF').fontColor('#344563').onClick(() => this.onBack());
        Blank();
        Text('使用帮助').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#172B4D');
        Blank();
        Blank().width(48);
      }
      .width('100%').padding(18);

      Scroll() {
        Column({ space: 14 }) {
          Text('点击主题查看操作步骤。这些说明可离线阅读。')
            .fontSize(13).fontColor('#52606D').width('100%');
          ForEach(this.topics, (topic: HelpTopic) => {
            Column({ space: 12 }) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 10 }) {
                  Column({ space: 5 }) {
                    Text(topic.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#172B4D');
                    Text(topic.summary).fontSize(12).fontColor('#52606D');
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1);
                  Text(this.activeTopicId === topic.id ? '收起' : '展开').fontSize(13).fontColor('#2457C5');
                }.width('100%');
              }
              .width('100%').padding(4).backgroundColor('#FFFFFF').borderRadius(8)
              .onClick(() => this.onSelectTopic(this.activeTopicId === topic.id ? '' : topic.id));
              if (this.activeTopicId === topic.id) {
                ForEach(topic.steps, (step: string, index: number) => {
                  Text((index + 1) + '. ' + step).fontSize(14).lineHeight(23).fontColor('#344563')
                    .width('100%').copyOption(CopyOptions.LocalDevice);
                }, (_step: string, index: number) => topic.id + '-step-' + index);
                ForEach(topic.notes, (note: string, index: number) => {
                  Text(note).fontSize(13).lineHeight(22).fontColor('#8A4B08')
                    .width('100%').copyOption(CopyOptions.LocalDevice);
                }, (_note: string, index: number) => topic.id + '-note-' + index);
              }
            }
            .width('100%').alignItems(HorizontalAlign.Start).padding(16)
            .backgroundColor('#FFFFFF').borderRadius(14);
          }, (topic: HelpTopic) => topic.id);
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, bottom: 24 });
      }.width('100%').layoutWeight(1);
    }
    .width('100%').height('100%').backgroundColor('#F6F7F9');
  }
}
