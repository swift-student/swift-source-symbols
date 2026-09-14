/** external documentation */
export default async function fetchValue<T /* generic */ extends { id: string }>(
  value: T = (() => { const fallback = { id: "x" }; return fallback; })() as T
): Promise<T> /* before body */ { return value; } // trailing
export declare function ambient(value?: { text: string }): void;
declare namespace Ambient { function nested(): void; }
export type MapValue = { readonly key: string; };
const grouped = 1, callback = (value: string): string => { return value; };
export default class { method() {} }
class Symbols {
  static constructor() {}
  "quoted"(value: string): void {}
  42(): void {}
  #private(value: number): void {}
  [Symbol.iterator](): Iterator<string> { function nested() {} }
  static { const block = 1; }
}
