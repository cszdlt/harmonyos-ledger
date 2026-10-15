function isValidGroupedInteger(value: string, separator: string): boolean {
  const groups = value.split(separator);
  if (groups.length === 1) {
    return /^\d+$/.test(value);
  }
  if (!/^[1-9]\d{0,2}$/.test(groups[0])) {
    return false;
  }
  return groups.slice(1).every((group: string) => /^\d{3}$/.test(group));
}

export function parseAmountFen(value: string): number | undefined {
  const raw = value.trim().replace(/[¥￥\s]|元/g, '');
  if (!/^\d+(?:[.,]\d+)*$/.test(raw)) {
    return undefined;
  }

  const hasDot = raw.indexOf('.') >= 0;
  const hasComma = raw.indexOf(',') >= 0;
  let yuanText = raw;
  let fraction = '';

  if (hasDot && hasComma) {
    const decimalSeparator = raw.lastIndexOf('.') > raw.lastIndexOf(',') ? '.' : ',';
    const decimalIndex = raw.lastIndexOf(decimalSeparator);
    const groupingSeparator = decimalSeparator === '.' ? ',' : '.';
    const groupedYuanText = raw.slice(0, decimalIndex);
    fraction = raw.slice(decimalIndex + 1);
    if (fraction.length > 2 || !isValidGroupedInteger(groupedYuanText, groupingSeparator)) {
      return undefined;
    }
    yuanText = groupedYuanText.split(groupingSeparator).join('');
  } else if (hasDot || hasComma) {
    const separator = hasDot ? '.' : ',';
    const groups = raw.split(separator);
    if (groups.length === 2) {
      if (groups[1].length <= 2) {
        yuanText = groups[0];
        fraction = groups[1];
      } else if (separator === ',' && groups[1].length === 3 &&
        isValidGroupedInteger(raw, separator)) {
        yuanText = groups.join('');
      } else {
        return undefined;
      }
    } else if (isValidGroupedInteger(raw, separator)) {
      yuanText = groups.join('');
    } else {
      return undefined;
    }
  }

  const yuan = Number(yuanText);
  const fen = Number((fraction + '00').slice(0, 2));
  if (!Number.isFinite(yuan) || yuan < 0) {
    return undefined;
  }
  const amountFen = yuan * 100 + fen;
  return Number.isSafeInteger(amountFen) ? amountFen : undefined;
}
