export = class Service { run(value: string): void {} };
export = function factory(value: number) { const local = value; return local; };
export = (() => { class Nested { run() {} } return Nested; })();
export = existing;
export { existing as renamed };
export * from "remote";
