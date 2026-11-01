import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type { LedgerEntry } from '../../model/LedgerModels';
import { formatDateTime, formatMoney } from '../../model/LedgerModels';
import type { NotificationArchiveCursor, NotificationArchiveEntry, NotificationArchiveFilter,
  NotificationArchivePage } from '../../model/NotificationArchiveModels';
import type { NotificationRule } from '../../services/notificationRules/NotificationRuleModels';
import { NotificationArchiveRepository } from '../../data/NotificationArchiveRepository';
import { LedgerRepository } from '../../data/LedgerRepository';
import { NotificationHistoryRebookingMatcher } from '../../services/NotificationHistoryRebooking';
import type { NotificationRebookingCandidate } from '../../services/NotificationHistoryRebooking';

@Component
export struct NotificationRebookingPage {
  @Prop rule: NotificationRule = {
    id: '', name: '', enabled: true, sourceKeywords: [], bodyPattern: '', incomeText: '收入', expenseText: '支出',
    dateFormat: '', dateStrategy: 'delivery-time', defaultMerchant: '', defaultCategory: '其他',
    categoryMappings: [], merchantPrefixToStrip: '', noteTemplate: ''
  };
  onBack: () => void = () => {};

  @State private loading: boolean = false;
  @State private saving: boolean = false;
  @State private scannedCount: number = 0;
  @State private hasPreview: boolean = false;
  @State private candidates: NotificationRebookingCandidate[] = [];
  @State private selectedIds: string[] = [];
  @State private message: string = '';
  private requestId: number = 0;
  private archiveRepository: NotificationArchiveRepository = new NotificationArchiveRepository();
  private ledgerRepository: LedgerRepository = new LedgerRepository();

  aboutToDisappear(): void {
    this.requestId++;
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .enabled(!this.saving)
          .backgroundColor('#FFFFFF')
          .fontColor('#344563')
          .onClick(() => this.onBack());
        Text('补记历史通知')
          .layoutWeight(1)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172B4D');
      }
      .width('100%')
      .padding(18);

      List({ space: 10 }) {
        ListItem() {
          Column({ space: 12 }) {
            Text('规则：' + this.rule.name)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#172B4D');
            Text('扫描本机通知历史，只预览能被这条规则解析的通知。候选默认不勾选；已存在同一分钟、金额和收支方向的账目会标记为重复。')
              .fontSize(12)
              .fontColor('#52606D');
            Button(this.loading ? '正在扫描…' : this.hasPreview ? '重新扫描通知历史' : '预览匹配的历史通知')
              .width('100%')
              .enabled(!this.loading && !this.saving)
              .backgroundColor('#2857C5')
              .fontColor('#FFFFFF')
              .onClick(() => { void this.previewHistory(); });
            if (this.loading) {
              Text('已扫描 ' + this.scannedCount + ' 条通知')
                .fontSize(12)
                .fontColor('#52606D');
            }
            if (this.message.length > 0) {
              Text(this.message)
                .fontSize(13)
                .fontColor('#8A4B08');
            }
            if (this.hasPreview) {
              Row() {
                Text('匹配 ' + this.candidates.length + ' 条 · 可选 ' + this.availableCandidates().length + ' 条')
                  .layoutWeight(1)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#172B4D');
                Button(this.allAvailableSelected() ? '取消全选' : '全选可补记')
                  .fontSize(12)
                  .enabled(!this.saving && this.availableCandidates().length > 0)
                  .onClick(() => this.toggleAllAvailable());
              }
              .width('100%');
              if (this.candidates.length === 0) {
                Text('没有通知能被当前规则解析。')
                  .fontSize(13)
                  .fontColor('#52606D');
              }
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 18, right: 18, bottom: 18 });
        }
        if (this.hasPreview) {
          ForEach(this.candidates, (candidate: NotificationRebookingCandidate) => {
            ListItem() {
              this.candidateCard(candidate);
            }
          }, (candidate: NotificationRebookingCandidate) => candidate.archive.id.toString());
        }
      }
      .layoutWeight(1);

      Column({ space: 8 }) {
        Text('已选 ' + this.selectedCandidates().length + ' 条 · ' + formatMoney(this.selectedTotalFen()))
          .fontSize(14)
          .fontColor('#344563');
        Button(this.saving ? '正在补记…' : '确认补记所选通知')
          .width('100%')
          .enabled(this.hasPreview && !this.loading && !this.saving && this.selectedIds.length > 0)
          .backgroundColor('#2857C5')
          .fontColor('#FFFFFF')
          .onClick(() => { void this.applySelection(); });
      }
      .width('100%')
      .padding(18)
      .backgroundColor('#FFFFFF');
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F7F9');
  }

  @Builder
  private candidateCard(candidate: NotificationRebookingCandidate) {
    Row({ space: 8 }) {
      Checkbox({ name: candidate.archive.id.toString() })
        .select(this.selectedIds.includes(candidate.archive.id.toString()))
        .enabled(!candidate.duplicate && !this.saving)
        .onChange((selected: boolean) => this.toggleCandidate(candidate, selected));
      Column({ space: 5 }) {
        Text(candidate.entry.merchant + ' · ' + formatMoney(candidate.entry.amountFen) + ' · ' +
          (candidate.entry.direction === 'expense' ? '支出' : '收入'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#172B4D');
        Text(formatDateTime(candidate.entry.happenedAt) + ' · ' + candidate.entry.category)
          .fontSize(12)
          .fontColor('#7B8794');
        Text(candidate.archive.appName.length > 0 ? candidate.archive.appName : candidate.archive.bundleName)
          .fontSize(12)
          .fontColor('#52606D');
        Text(candidate.archive.body)
          .fontSize(12)
          .fontColor('#52606D');
        Text(candidate.duplicate ? '重复通知：账本已有同分钟、同金额、同收支方向的记录' : '可补记')
          .fontSize(12)
          .fontColor(candidate.duplicate ? '#8A4B08' : '#16845B');
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12);
  }

  private async previewHistory(): Promise<void> {
    if (this.loading || this.saving) { return; }
    const request = ++this.requestId;
    this.loading = true;
    this.scannedCount = 0;
    this.hasPreview = false;
    this.candidates = [];
    this.selectedIds = [];
    this.message = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      await this.archiveRepository.open(context);
      await this.ledgerRepository.open(context);
      const ledgerEntries = await this.ledgerRepository.listEntries();
      if (request !== this.requestId) { return; }
      const matcher: NotificationHistoryRebookingMatcher =
        new NotificationHistoryRebookingMatcher(this.rule, ledgerEntries);
      const filter: NotificationArchiveFilter = { bundleName: '', keyword: '' };
      let cursor: NotificationArchiveCursor | undefined = undefined;
      do {
        if (request !== this.requestId) { return; }
        const page: NotificationArchivePage = await this.archiveRepository.listPage(filter, cursor);
        if (request !== this.requestId) { return; }
        matcher.scan(page.entries);
        this.scannedCount += page.entries.length;
        cursor = page.nextCursor;
      } while (cursor !== undefined);
      if (request !== this.requestId) { return; }
      this.candidates = matcher.preview();
      this.hasPreview = true;
      this.message = this.candidates.length === 0 ? '没有通知能被当前规则解析。' :
        this.availableCandidates().length === 0 ? '匹配通知都已存在于账本中。' : '';
    } catch (error) {
      if (request === this.requestId) {
        this.message = '读取历史通知失败：' + (error as BusinessError).message;
      }
    } finally {
      if (request === this.requestId) { this.loading = false; }
    }
  }

  private availableCandidates(): NotificationRebookingCandidate[] {
    return this.candidates.filter((candidate: NotificationRebookingCandidate) => !candidate.duplicate);
  }

  private allAvailableSelected(): boolean {
    const available = this.availableCandidates();
    return available.length > 0 && available.every((candidate: NotificationRebookingCandidate) =>
      this.selectedIds.includes(candidate.archive.id.toString()));
  }

  private toggleAllAvailable(): void {
    this.selectedIds = this.allAvailableSelected() ? [] :
      this.availableCandidates().map((candidate: NotificationRebookingCandidate) => candidate.archive.id.toString());
  }

  private toggleCandidate(candidate: NotificationRebookingCandidate, selected: boolean): void {
    if (candidate.duplicate || this.saving) { return; }
    const id = candidate.archive.id.toString();
    this.selectedIds = selected ? this.selectedIds.concat([id]) :
      this.selectedIds.filter((selectedId: string) => selectedId !== id);
  }

  private selectedCandidates(): NotificationRebookingCandidate[] {
    return this.candidates.filter((candidate: NotificationRebookingCandidate) =>
      !candidate.duplicate && this.selectedIds.includes(candidate.archive.id.toString()));
  }

  private selectedTotalFen(): number {
    return this.selectedCandidates().reduce((total: number, candidate: NotificationRebookingCandidate) =>
      total + candidate.entry.amountFen, 0);
  }

  private async applySelection(): Promise<void> {
    const selected = this.selectedCandidates();
    if (this.saving || this.loading || selected.length === 0) { return; }
    this.saving = true;
    try {
      const response = await this.getUIContext().getPromptAction().showDialog({
        title: '确认补记历史通知',
        message: '将所选 ' + selected.length + ' 条通知解析结果写入账本，共 ' +
          formatMoney(this.selectedTotalFen()) + '。已有账目仍会按同分钟、金额和收支方向自动去重。',
        buttons: [{ text: '取消', color: '#52606D' }, { text: '确认补记', color: '#2457C5' }]
      });
      if (response.index !== 1) { return; }
      for (const candidate of selected) {
        await this.ledgerRepository.addNotificationEntry(candidate.entry);
      }
      this.selectedIds = [];
      this.candidates = [];
      this.hasPreview = false;
      this.message = '已处理 ' + selected.length + ' 条所选通知。账本已按现有规则查重；可再次预览核对结果。';
    } catch (error) {
      this.message = '补记失败：' + (error as BusinessError).message + '。已成功处理的通知可安全重试，重复项会由账本自动跳过。';
    } finally {
      this.saving = false;
    }
  }
}
