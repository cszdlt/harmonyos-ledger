import type { EntrySource, LedgerEntry } from '../../model/LedgerModels';
import { buildLedgerHomeData, moveLedgerMonthCursor } from '../../services/LedgerHomeData';
import type { LedgerHomeData } from '../../services/LedgerHomeData';
import { LedgerHomeView } from './LedgerHomeView';
import { LedgerSettingsPage } from './LedgerSettingsPage';
import { StatisticsView } from '../statistics/StatisticsView';
import { OcrRuleSettingsView } from '../ocr/OcrRuleSettingsView';

export type LedgerScreen = 'ledger' | 'editor' | 'statistics' | 'import' | 'settings' | 'ocrRules';

@Component
export struct LedgerTabPage {
  @Link screen: LedgerScreen;
  @Watch('onHomeDataInputsChanged')
  @Link monthCursor: number;
  @Link pendingDeleteId: string;
  @Watch('onBackRequestChanged')
  @Prop backRequestRevision: number = 0;
  @Prop entries: LedgerEntry[] = [];
  @Watch('onHomeDataInputsChanged')
  @Prop entriesViewRevision: number = 0;
  @Watch('onHomeDataInputsChanged')
  @Prop cycleStartDay: number = 15;

  sourceLabel: (source: EntrySource) => string = (_source: EntrySource) => '';
  onOpenEditor: (entry: LedgerEntry | undefined, fromStatistics: boolean) => void =
    (_entry: LedgerEntry | undefined, _fromStatistics: boolean) => {};
  onStartImport: () => void = () => {};
  onCycleStartDayChange: (day: number) => void = (_day: number) => {};
  onListEntries: () => Promise<LedgerEntry[]> = () => Promise.resolve([]);
  onSaveCsvEntries: (entries: LedgerEntry[], duplicateCount: number, invalidCount: number) => Promise<void> =
    (_entries: LedgerEntry[], _duplicateCount: number, _invalidCount: number) => Promise.resolve();
  onToast: (message: string) => void = (_message: string) => {};

  @State private selectedRankValue: string = '';
  @State private ledgerScrollOffset: number = 0;
  @State private restoreLedgerScrollOnAppear: boolean = false;
  @State private homeData: LedgerHomeData = buildLedgerHomeData([], Date.now(), 15);

  aboutToAppear(): void {
    this.refreshHomeData();
  }

  private onHomeDataInputsChanged(): void {
    this.refreshHomeData();
  }

  private refreshHomeData(): void {
    this.homeData = buildLedgerHomeData(this.entries, this.monthCursor, this.cycleStartDay);
  }

  private onBackRequestChanged(): void {
    if (this.screen === 'statistics') {
      if (this.selectedRankValue.length > 0) {
        this.selectedRankValue = '';
      } else {
        this.screen = 'ledger';
      }
    } else if (this.screen === 'ocrRules') {
      this.screen = 'settings';
    } else if (this.screen === 'settings') {
      this.screen = 'ledger';
    }
  }

  build() {
    if (this.screen === 'settings') {
      LedgerSettingsPage({
        cycleStartDay: this.cycleStartDay,
        onBack: () => {
          this.screen = 'ledger';
        },
        onCycleStartDayChange: (day: number) => this.onCycleStartDayChange(day),
        onOpenOcrRules: () => {
          this.screen = 'ocrRules';
        },
        onListEntries: () => this.onListEntries(),
        onSaveCsvEntries: (entries: LedgerEntry[], duplicateCount: number, invalidCount: number) =>
          this.onSaveCsvEntries(entries, duplicateCount, invalidCount),
        onToast: (message: string) => this.onToast(message)
      });
    } else if (this.screen === 'ocrRules') {
      OcrRuleSettingsView({
        onBack: () => {
          this.screen = 'settings';
        }
      });
    } else if (this.screen === 'statistics') {
      StatisticsView({
        entries: this.entries,
        cycleStartDay: this.cycleStartDay,
        selectedRankValue: $selectedRankValue,
        onBack: () => {
          this.selectedRankValue = '';
          this.screen = 'ledger';
        },
        onEditEntry: (entry: LedgerEntry) => this.onOpenEditor(entry, true),
        onDeleteRequest: (entry: LedgerEntry) => {
          this.pendingDeleteId = entry.id;
        }
      });
    } else {
      this.ledgerHome();
    }
  }

  @Builder
  private ledgerHome() {
    LedgerHomeView({
      entriesViewRevision: this.entriesViewRevision,
      monthEntries: this.homeData.monthEntries,
      dayGroups: this.homeData.dayGroups,
      incomeTotalFen: this.homeData.incomeTotalFen,
      expenseTotalFen: this.homeData.expenseTotalFen,
      monthLabel: this.homeData.monthLabel,
      cycleStartDay: this.cycleStartDay,
      scrollOffset: this.ledgerScrollOffset,
      restoreScrollOnAppear: this.restoreLedgerScrollOnAppear,
      onSaveScroll: (offset: number) => {
        this.ledgerScrollOffset = Math.max(0, offset);
        this.restoreLedgerScrollOnAppear = true;
      },
      onRestoreScrollComplete: () => {
        this.restoreLedgerScrollOnAppear = false;
      },
      onPreviousMonth: () => this.moveMonth(-1),
      onNextMonth: () => this.moveMonth(1),
      onOpenStatistics: () => {
        this.selectedRankValue = '';
        this.screen = 'statistics';
      },
      onCycleStartDayChange: (day: number) => this.onCycleStartDayChange(day),
      onStartImport: () => this.onStartImport(),
      onOpenSettings: () => {
        this.screen = 'settings';
      },
      onAddEntry: () => this.onOpenEditor(undefined, false),
      onEditEntry: (entry: LedgerEntry) => this.onOpenEditor(entry, false),
      onDeleteRequest: (entry: LedgerEntry) => {
        this.pendingDeleteId = entry.id;
      },
      sourceLabel: (source: EntrySource) => this.sourceLabel(source)
    });
  }

  private moveMonth(offset: number): void {
    this.monthCursor = moveLedgerMonthCursor(this.monthCursor, offset);
  }
}
