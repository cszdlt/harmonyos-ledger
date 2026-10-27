import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

// 在 Node 中执行页面的实际方法，ArkUI 展示和设备 API 由调用方提供边界替身。
export function loadPageMethods(url, methodNames, dependencies = {}) {
  const source = readFileSync(url, 'utf8').replace(/\r\n/g, '\n');
  const methods = methodNames.map((name) => {
    const match = new RegExp(`^  private (?:async )?${name}\\(`, 'm').exec(source);
    if (match === null) {
      throw new Error(`Missing page method: ${name}`);
    }
    const end = source.indexOf('\n  }', match.index);
    if (end < 0) {
      throw new Error(`Unclosed page method: ${name}`);
    }
    return source.slice(match.index, end + 4);
  });
  const code = stripTypeScriptTypes(`class PageHarness {\n${methods.join('\n')}\n}`, { mode: 'transform' });
  return new Function(...Object.keys(dependencies), `${code}\nreturn PageHarness;`)(...Object.values(dependencies));
}
