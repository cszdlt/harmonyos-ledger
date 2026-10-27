import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type { LedgerEntry } from '../../model/LedgerModels';
import { formatDateOnly, formatDateTime, formatMoney } from '../../model/LedgerModels';
import type { NotificationArchiveCursor, NotificationArchiveEntry, NotificationArchivePage } from '../../model/NotificationArchiveModels';
import type { NotificationInput } from '../../services/notificationRules/NotificationRuleModels';
import { NotificationArchiveRepository } from '../../data/NotificationArchiveRepository';
import { CreditHistoryMatcher, parseCreditHistoryFilter } from '../../services/CreditHistory';
import type { CreditHistoryCandidate, CreditHistoryPreview, CreditHistoryRule } from '../../services/CreditHistory';
import { csvSourceLabel } from '../../services/CsvFormat';

@Component
export struct CreditHistoryPage {
  @Prop rule: CreditHistoryRule = { name: '', source: '' };
  @Prop entries: LedgerEntry[] = [];
  @Link saving: boolean;
  @Prop undoCount: number = 0;
  onUndo: () => Promise<number> = () => Promise.reject(new Error('账本尚未连接'));
  onBack: () => void = () => {};
  onListEntries: () => Promise<LedgerEntry[]> = () => Promise.reject(new Error('账本尚未连接'));
  onApply: (entries: LedgerEntry[]) => Promise<number> =
    (_entries: LedgerEntry[]) => Promise.reject(new Error('账本尚未连接'));

  @State private sourceFilter: string = '';
  @State private startDate: string = '';
  @State private endDate: string = '';
  @State private keyword: string = '';
  @State private loading: boolean = false;
  @State private hasPreview: boolean = false;
  @State private scannedCount: number = 0;
  @State private message: string = '';
  @State private previewData: CreditHistoryPreview = { candidates: [], ambiguousCount: 0 };
  @State private selectedIds: string[] = [];
  private requestId: number = 0;
  private archiveRepository: NotificationArchiveRepository = new NotificationArchiveRepository();

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
        Text('标记历史信用卡消费')
          .layoutWeight(1)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#172B4D');
      }
      .width('100%')
      .padding(18);
      Scroll() {
        Column({ space: 12 }) {
          Text('规则：' + this.rule.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#172B4D');
          if (this.undoCount > 0) {
            Button('撤销最近一次批量标记（' + this.undoCount + ' 笔）')
              .enabled(!this.loading && !this.saving)
              .width('100%')
              .backgroundColor('#E9F1FF')
              .fontColor('#2457C5')
              .onClick(() => { void this.confirmUndo(); });
          }
          Text('仅列出普通支出。通知唯一匹配的账目默认勾选；仅按来源筛出的记录请人工核对。已标记的信用卡消费和还款不参与本次操作。')
            .fontSize(12)
            .fontColor('#52606D');
          Column({ space: 10 }) {
            Text('来源')
              .fontSize(13)
              .fontColor('#52606D');
            Select(this.sourceChoices().map((source: string): SelectOption => {
              return { value: source.length === 0 ? '规则来源及通知匹配' : csvSourceLabel(source) };
            }))
              .selected(this.sourceChoices().indexOf(this.sourceFilter))
              .width('100%')
              .onSelect((index: number) => {
                this.sourceFilter = this.sourceChoices()[index];
                this.invalidatePreview();
              });
            Row({ space: 8 }) {
              Column() {
                this.filterField('开始日期（可留空）', this.startDate, 'start');
              }
              .layoutWeight(1);
              Column() {
                this.filterField('结束日期（可留空）', this.endDate, 'end');
              }
              .layoutWeight(1);
            }
            .width('100%');
            this.filterField('商户或备注关键词（可留空）', this.keyword, 'keyword');
            Button(this.loading ? '正在预览…' : '预览候选账目')
              .width('100%')
              .backgroundColor('#2857C5')
              .fontColor('#FFFFFF')
              .onClick(() => { void this.previewHistory(); });
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .enabled(!this.loading && !this.saving);
          if (this.loading) {
            Text('正在读取账目与本机通知归档，已扫描 ' + this.scannedCount + ' 条通知')
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
              Text('候选 ' + this.previewData.candidates.length + ' 笔')
                .layoutWeight(1)
                .fontSize(14)
                .fontWeight(FontWeight.Bold);
              Button(this.selectedIds.length === this.previewData.candidates.length ? '取消全选' : '全选当前候选')
                .enabled(!this.saving && this.previewData.candidates.length > 0)
                .fontSize(12)
                .onClick(() => {
                  this.selectedIds = this.selectedIds.length === this.previewData.candidates.length ? [] :
                    this.previewData.candidates.map((item: CreditHistoryCandidate) => item.entry.id);
                });
            }
            .width('100%');
            if (this.previewData.ambiguousCount > 0) {
              Text(this.previewData.ambiguousCount + ' 组通知匹配不唯一，未自动勾选')
                .fontSize(12)
                .fontColor('#8A4B08');
            }
            ForEach(this.previewData.candidates, (item: CreditHistoryCandidate) => {
              this.candidateCard(item);
            }, (item: CreditHistoryCandidate) => item.entry.id);
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, bottom: 18 });
      }
      .layoutWeight(1);
      Column({ space: 8 }) {
        Text('已选 ' + this.selectedEntries().length + ' 笔 · ' + formatMoney(this.selectedTotalFen()))
          .fontSize(14)
          .fontColor('#344563');
        Button(this.saving ? '正在保存…' : '确认标记为信用卡消费')
          .width('100%')
          .enabled(!this.saving && !this.loading && this.selectedIds.length > 0)
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
    .backgroundColor('#F6F7F9')
    .hitTestBehavior(HitTestMode.Default)
    .zIndex(2);
  }

  @Builder
  private filterField(label: string, value: string, field: string) {
    Column({ space: 5 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#52606D');
      TextInput({ text: value, placeholder: field === 'keyword' ? '例如：卡尾号、商户名' : 'YYYY-MM-DD' })
        .fontSize(14)
        .onChange((text: string) => {
          if (field === 'start') {
            this.startDate = text;
          } else if (field === 'end') {
            this.endDate = text;
          } else {
            this.keyword = text;
          }
          this.invalidatePreview();
        });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private candidateCard(item: CreditHistoryCandidate) {
    Row({ space: 8 }) {
      Checkbox({ name: item.entry.id })
        .select(this.selectedIds.includes(item.entry.id))
        .enabled(!this.saving)
        .onChange((selected: boolean) => {
          this.selectedIds = selected ? this.selectedIds.concat([item.entry.id]) :
            this.selectedIds.filter((id: string) => id !== item.entry.id);
        });
      Column({ space: 5 }) {
        Text(item.entry.merchant + ' · ' + formatMoney(item.entry.amountFen))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#172B4D');
        Text((item.entry.hasTime ? formatDateTime(item.entry.happenedAt) : formatDateOnly(item.entry.happenedAt)) +
          ' · ' + csvSourceLabel(item.entry.source))
          .fontSize(12)
          .fontColor('#7B8794');
        Text(item.matched ? '通知唯一匹配' : '来源候选，需人工核对')
          .fontSize(12)
          .fontColor(item.matched ? '#16845B' : '#8A4B08');
        if (item.entry.note.length > 0) {
          Text(item.entry.note)
            .fontSize(12)
            .fontColor('#52606D');
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12);
  }

  private sourceChoices(): string[] {
    const choices: string[] = ['', this.rule.source];
    this.entries.forEach((entry: LedgerEntry) => {
      if (!choices.includes(entry.source)) {
        choices.push(entry.source);
      }
    });
    return choices;
  }

  private invalidatePreview(): void {
    this.requestId++;
    this.loading = false;
    this.hasPreview = false;
    this.message = '';
    this.previewData = { candidates: [], ambiguousCount: 0 };
    this.selectedIds = [];
  }

  private async previewHistory(): Promise<void> {
    if (this.loading || this.saving) {
      return;
    }
    this.invalidatePreview();
    const request = this.requestId;
    this.loading = true;
    this.scannedCount = 0;
    try {
      const filter = parseCreditHistoryFilter(this.sourceFilter, this.startDate, this.endDate, this.keyword);
      const entries = await this.onListEntries();
      if (request !== this.requestId) {
        return;
      }
      let matcher = new CreditHistoryMatcher(entries, this.rule.source);
      let warning = '';
      const notificationRule = this.rule.notificationRule;
      if (notificationRule !== undefined) {
        try {
          await this.archiveRepository.open(this.getUIContext().getHostContext() as common.Context);
          let cursor: NotificationArchiveCursor | undefined = undefined;
          do {
            if (request !== this.requestId) {
              return;
            }
            const page: NotificationArchivePage = await this.archiveRepository.listPage({ bundleName: '', keyword: '' }, cursor);
            if (request !== this.requestId) {
              return;
            }
            matcher.scan(page.entries.map((item: NotificationArchiveEntry): NotificationInput => {
              return { appName: item.appName, bundleName: item.bundleName, title: item.title, body: item.body,
                deliveryTime: item.deliveryTime, receivedAt: item.receivedAt };
            }), notificationRule);
            this.scannedCount += page.entries.length;
            cursor = page.nextCursor;
          } while (cursor !== undefined);
        } catch (_error) {
          matcher = new CreditHistoryMatcher(entries, this.rule.source);
          warning = '通知归档读取失败，本次仅显示来源候选，请手动核对并勾选。';
        }
      }
      if (request !== this.requestId) {
        return;
      }
      this.previewData = matcher.preview(filter);
      this.selectedIds = this.previewData.candidates.filter((item: CreditHistoryCandidate) => item.matched)
        .map((item: CreditHistoryCandidate) => item.entry.id);
      this.hasPreview = true;
      this.message = warning.length > 0 ? warning : this.previewData.candidates.length === 0 ?
        '没有符合条件的普通支出，可调整来源、日期或关键词后重新预览。' : '';
    } catch (error) {
      const businessError = error as BusinessError;
      this.message = '预览失败：' + businessError.message;
    } finally {
      if (request === this.requestId) {
        this.loading = false;
      }
    }
  }

  private selectedEntries(): LedgerEntry[] {
    return this.previewData.candidates.filter((item: CreditHistoryCandidate) =>
      this.selectedIds.includes(item.entry.id)).map((item: CreditHistoryCandidate) => item.entry);
  }

  private async confirmUndo(): Promise<void> {
    if (this.saving || this.loading) { return; }
    this.saving = true;
    try {
      const response = await this.getUIContext().getPromptAction().showDialog({
        title: '撤销最近一次批量标记',
        message: '恢复为普通支出；后来已编辑、删除或改为还款的记录会跳过。',
        buttons: [{ text: '取消', color: '#52606D' }, { text: '撤销标记', color: '#2457C5' }]
      });
      if (response.index !== 1) { return; }
      const before = this.undoCount;
      const updated = await this.onUndo();
      this.invalidatePreview();
      this.message = '已撤销 ' + updated + ' 笔；跳过已变化的记录 ' + (before - updated) + ' 笔。';
    } catch (error) {
      this.message = '撤销失败：' + (error as BusinessError).message;
    } finally { this.saving = false; }
  }

  private selectedTotalFen(): number {
    return this.selectedEntries().reduce((total: number, entry: LedgerEntry) => total + entry.amountFen, 0);
  }

  private async applySelection(): Promise<void> {
    const selected = this.selectedEntries();
    if (this.saving || this.loading || selected.length === 0) {
      return;
    }
    this.saving = true;
    try {
      const updated = await this.onApply(selected);
      this.selectedIds = [];
      this.previewData = { candidates: [], ambiguousCount: 0 };
      this.hasPreview = false;
      this.message = '已标记 ' + updated + ' 笔信用卡消费；跳过已变化的记录 ' + (selected.length - updated) + ' 笔。';
    } catch (error) {
      const businessError = error as BusinessError;
      this.message = '保存失败：' + businessError.message + '，可重试。';
    } finally {
      this.saving = false;
    }
  }
}
