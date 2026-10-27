import type { RuleImportKind } from './RuleImportModels';

interface JsonContainer {
  path: string[];
  isArray: boolean;
  key: string;
}

function valuePath(containers: JsonContainer[]): string[] {
  if (containers.length === 0) { return []; }
  const parent = containers[containers.length - 1];
  return parent.path.concat(parent.isArray ? '[]' : parent.key);
}

function isRegexField(path: string[], kind: RuleImportKind): boolean {
  if (path[0] !== 'rule') { return false; }
  if (kind === 'notification') {
    return path.length === 2 && path[1] === 'bodyPattern';
  }
  if (path.length === 3) {
    return (path[1] === 'fields' && ['amount', 'date', 'time', 'direction', 'merchant', 'category'].includes(path[2])) ||
      (path[1] === 'record' && path[2] === 'anchor') ||
      (['failurePatterns', 'refundPatterns', 'summaryPatterns'].includes(path[1]) && path[2] === '[]');
  }
  return path.length === 4 && ((path[1] === 'source' && path[2] === 'patterns' && path[3] === '[]') ||
    (path[1] === 'categoryMappings' && path[2] === '[]' && path[3] === 'pattern'));
}

function stringEnd(text: string, start: number): number {
  for (let index = start + 1; index < text.length; index++) {
    if (text[index] === '\\') { index++; }
    else if (text[index] === '"') { return index + 1; }
  }
  return text.length;
}

function escapeRegexString(token: string): string {
  const parts: string[] = [];
  for (let index = 0; index < token.length; index++) {
    const character = token[index];
    parts.push(character);
    if (character !== '\\' || index + 1 >= token.length) { continue; }
    const next = token[index + 1];
    const validEscape = ['"', '\\', '/', 'b', 'f', 'n', 'r', 't'].includes(next) ||
      (next === 'u' && /^[0-9a-fA-F]{4}$/.test(token.slice(index + 2, index + 6)));
    // 只补齐 JSON 不接受的正则转义；合法的反斜杠、换行和 Unicode 转义原样保留。
    if (!validEscape) { parts.push('\\'); }
    parts.push(next);
    index++;
  }
  return parts.join('');
}

function normalizeRegexEscapes(text: string, kind: RuleImportKind): string {
  const containers: JsonContainer[] = [];
  const parts: string[] = [];
  let index = 0;
  while (index < text.length) {
    const character = text[index];
    if (character === '"') {
      const end = stringEnd(text, index);
      const token = text.slice(index, end);
      let next = end;
      while (next < text.length && /\s/.test(text[next])) { next++; }
      const parent = containers.length === 0 ? undefined : containers[containers.length - 1];
      if (parent !== undefined && !parent.isArray && text[next] === ':') {
        parent.key = JSON.parse(token) as string;
        parts.push(token);
      } else {
        parts.push(isRegexField(valuePath(containers), kind) ? escapeRegexString(token) : token);
      }
      index = end;
      continue;
    }
    if (character === '{' || character === '[') {
      containers.push({ path: valuePath(containers), isArray: character === '[', key: '' });
    } else if (character === '}' || character === ']') {
      containers.pop();
    }
    parts.push(character);
    index++;
  }
  return parts.join('');
}

export function parseRuleImportJson(text: string, kind: RuleImportKind): Object {
  try {
    return JSON.parse(text) as Object;
  } catch (_error) {
    // 标准 JSON 优先；兼容输入仍必须重新通过 JSON 语法与后续规则校验。
    return JSON.parse(normalizeRegexEscapes(text, kind)) as Object;
  }
}
