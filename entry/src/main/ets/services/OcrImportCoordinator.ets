import type { DraftEntry, EntryDirection, EntrySource, ImportSource, LedgerEntry } from '../model/LedgerModels';
import { makeId, parseAmountFen, parseDateTime } from '../model/LedgerModels';
import type { DraftValidationError, OcrLine, OcrRecognizedPage, OcrImportResult, UnclassifiedOcrPage } from '../model/OcrModels';
import { IcbcParser } from './IcbcParser';
import { GenericOcrParser } from './GenericOcrParser';
import { OcrSourceDetector } from './OcrSourceDetector';
import { ReceiptParser } from './ReceiptParser';
import type { OcrRule } from './ocrRules/OcrRuleModels';

export interface OcrDraftConfirmationPlan {
  additions: LedgerEntry[];
  categoryUpdates: LedgerEntry[];
  validationErrors: DraftValidationError[];
  selectedCount: number;
  matchedCount: number;
  firstSelectedAt?: number;
}

function sourceLabel(rule: OcrRule): string {
  return rule.sourceName ?? rule.name;
}

function sameTimedAmount(entry: LedgerEntry, happenedAt: number, amountFen: number, hasTime: boolean,
  direction: EntryDirection): boolean {
  return hasTime && entry.hasTime && entry.happenedAt === happenedAt &&
    entry.amountFen === amountFen && entry.direction === direction;
}

function entryWithCategory(entry: LedgerEntry, category: string): LedgerEntry {
  return {
    id: entry.id,
    happenedAt: entry.happenedAt,
    hasTime: entry.hasTime,
    amountFen: entry.amountFen,
    direction: entry.direction,
    accountingType: entry.accountingType,
    source: entry.source,
    merchant: entry.merchant,
    category: category,
    note: entry.note
  };
}

export class OcrImportCoordinator {
  static parsePages(pages: OcrRecognizedPage[], existing: LedgerEntry[], rules: OcrRule[]): OcrImportResult {
    const drafts: DraftEntry[] = [];
    const rawPages: string[] = [];
    const unclassifiedPages: UnclassifiedOcrPage[] = [];
    pages.forEach((page: OcrRecognizedPage) => {
      const selectedRule = OcrSourceDetector.detect(page.rawText, rules);
      if (selectedRule === undefined) {
        if (page.rawText.indexOf('识别失败：') !== 0) {
          unclassifiedPages.push({
            pageNumber: page.pageNumber,
            lines: page.lines,
            captureTime: page.captureTime,
            imageWidth: page.imageWidth
          });
          rawPages.push('截图 ' + page.pageNumber + '（来源待确认）\n' + page.rawText);
        } else {
          rawPages.push('截图 ' + page.pageNumber + '\n' + page.rawText);
        }
        return;
      }
      const parsed = OcrImportCoordinator.parsePage(page.lines, selectedRule.source, existing, rules, drafts,
        page.captureTime, page.imageWidth);
      parsed.forEach((draft: DraftEntry) => {
        drafts.push(draft);
      });
      rawPages.push('截图 ' + page.pageNumber + '（识别来源：' + sourceLabel(selectedRule) + '）\n' + page.rawText);
    });
    return {
      drafts: drafts,
      rawText: rawPages.join('\n\n'),
      unclassifiedPages: unclassifiedPages
    };
  }

  static parsePage(
    lines: OcrLine[],
    source: ImportSource,
    existing: LedgerEntry[],
    rules: OcrRule[],
    priorDrafts: DraftEntry[] = [],
    captureTime?: number,
    imageWidth?: number
  ): DraftEntry[] {
    const candidates = rules.filter((rule: OcrRule) => rule.enabled && rule.source === source);
    for (const rule of candidates) {
      const drafts = rule.layoutStrategy === 'icbc-statement' ?
        IcbcParser.parse(lines, rule, existing, priorDrafts, captureTime) :
        rule.layoutStrategy === 'generic' ?
          GenericOcrParser.parse(lines, source as EntrySource, rule, existing, priorDrafts, captureTime, imageWidth) :
          ReceiptParser.parse(lines, source as EntrySource, rule, existing, priorDrafts, captureTime);
      if (drafts.length > 0) {
        drafts.forEach((draft: DraftEntry) => {
          draft.accountingType = rule.isCreditCard === true ? 'credit-card' : 'normal';
        });
        return drafts;
      }
    }
    return [];
  }

  static selectedCount(drafts: DraftEntry[]): number {
    return drafts.filter((draft: DraftEntry) => draft.checked).length;
  }

  static matchedCount(drafts: DraftEntry[], entries: LedgerEntry[]): number {
    return drafts.filter((draft: DraftEntry) => draft.checked &&
      OcrImportCoordinator.matchingEntries(draft, entries).length > 0).length;
  }

  static duplicateMessage(draft: DraftEntry, entries: LedgerEntry[]): string {
    if (!draft.checked) {
      return '';
    }
    const matches = OcrImportCoordinator.matchingEntries(draft, entries);
    if (matches.length === 0) {
      return '';
    }
    const category = draft.category.trim();
    const shouldUpdateCategory = category.length > 0 && category !== '其他' &&
      matches.some((entry: LedgerEntry) => entry.category !== category);
    return '账本中已有相同方向、时间和金额的记录；确认后会跳过新增。' +
      (shouldUpdateCategory ? '原记录分类会更新为“' + category + '”。' : '');
  }

  static prepareConfirmation(drafts: DraftEntry[], entries: LedgerEntry[]): OcrDraftConfirmationPlan {
    const additions: LedgerEntry[] = [];
    const categoryUpdates: LedgerEntry[] = [];
    const validationErrors: DraftValidationError[] = [];
    let selectedCount = 0;
    let matchedCount = 0;
    let firstSelectedAt: number | undefined = undefined;

    for (const draft of drafts) {
      if (!draft.checked) {
        continue;
      }
      selectedCount++;
      const happenedAt = parseDateTime(draft.dateText);
      const amountFen = parseAmountFen(draft.amountText);
      if (happenedAt === undefined || amountFen === undefined || amountFen <= 0) {
        const messages: string[] = [];
        if (happenedAt === undefined) {
          messages.push('日期缺失或格式无效');
        }
        if (amountFen === undefined || amountFen <= 0) {
          messages.push('金额无效，需大于 0');
        }
        validationErrors.push({ id: draft.id, message: messages.join('；') });
        continue;
      }
      if (draft.direction === undefined || draft.merchant.trim().length === 0) {
        const messages: string[] = [];
        if (draft.direction === undefined) {
          messages.push('请选择收入或支出');
        }
        if (draft.merchant.trim().length === 0) {
          messages.push('请填写商户或摘要');
        }
        validationErrors.push({ id: draft.id, message: messages.join('；') });
        continue;
      }
      if (firstSelectedAt === undefined) {
        firstSelectedAt = happenedAt;
      }

      const category = draft.category.trim();
      const hasSpecificCategory = category.length > 0 && category !== '其他';
      const matchingEntries = OcrImportCoordinator.matchingEntries(
        draft, entries, happenedAt, amountFen, draft.direction);
      if (matchingEntries.length > 0) {
        matchedCount++;
        if (hasSpecificCategory) {
          matchingEntries.forEach((entry: LedgerEntry) => {
            const updateIndex = categoryUpdates.findIndex((item: LedgerEntry) => item.id === entry.id);
            const current = updateIndex >= 0 ? categoryUpdates[updateIndex] : entry;
            if (current.category !== category) {
              const updated = entryWithCategory(current, category);
              if (updateIndex >= 0) {
                categoryUpdates[updateIndex] = updated;
              } else {
                categoryUpdates.push(updated);
              }
            }
          });
        }
        continue;
      }

      const pendingIndex = additions.findIndex((entry: LedgerEntry) =>
        sameTimedAmount(entry, happenedAt, amountFen, draft.hasTime, draft.direction as EntryDirection));
      if (pendingIndex >= 0) {
        matchedCount++;
        if (hasSpecificCategory && additions[pendingIndex].category !== category) {
          additions[pendingIndex] = entryWithCategory(additions[pendingIndex], category);
        }
        continue;
      }

      additions.push({
        id: makeId('entry'),
        happenedAt: happenedAt,
        hasTime: draft.hasTime,
        amountFen: amountFen,
        direction: draft.direction,
        accountingType: draft.direction === 'expense' ? draft.accountingType : 'normal',
        source: draft.source,
        merchant: draft.merchant.trim(),
        category: category.length > 0 ? category : '其他',
        note: draft.isRefund ? '退款' : ''
      });
    }
    return {
      additions: additions,
      categoryUpdates: categoryUpdates,
      validationErrors: validationErrors,
      selectedCount: selectedCount,
      matchedCount: matchedCount,
      firstSelectedAt: firstSelectedAt
    };
  }

  private static matchingEntries(
    draft: DraftEntry,
    entries: LedgerEntry[],
    happenedAt?: number,
    amountFen?: number,
    direction?: EntryDirection
  ): LedgerEntry[] {
    const timestamp = happenedAt === undefined ? parseDateTime(draft.dateText) : happenedAt;
    const amount = amountFen === undefined ? parseAmountFen(draft.amountText) : amountFen;
    const entryDirection = direction === undefined ? draft.direction : direction;
    if (timestamp === undefined || amount === undefined || amount <= 0 || entryDirection === undefined) {
      return [];
    }
    return entries.filter((entry: LedgerEntry) =>
      sameTimedAmount(entry, timestamp, amount, draft.hasTime, entryDirection));
  }
}
