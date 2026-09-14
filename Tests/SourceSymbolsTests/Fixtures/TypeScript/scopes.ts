import { external as imported } from "library";
export { imported as exported };
const { key: renamed, shorthand, nested: [head, ...tail], missing = 1, ...rest } = source;
let [first, , { value: second = 2 }] = source;
const object = {
  value: 1,
  shorthand,
  run(value: string) { const local = value; function inner() {} },
  constructor() {},
  get current() { return 1; },
  callback: (value: number) => { const result = value; return result; },
  "quoted-name": true,
  [computed]: false
};
const Factory = class Named {
  field = (() => { const seed = 1; return seed; })();
  method() { function nested() {} }
};
const Anonymous = class { method() { let local = 1; } };
function outer(input = () => { function inDefault() {} }) {
  const callback = () => { const local = 1; };
  { function duplicate() {} }
  { function duplicate() {} }
}
for (const entry of source) { let loopLocal = entry; }
for (existing of source) {}
type Shape = { child: { hidden: string }; method(value: { hidden: number }): void };
