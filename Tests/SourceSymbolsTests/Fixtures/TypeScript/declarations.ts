// Leading documentation is outside the exported declaration.
export namespace App.Tools {
  export interface Store<T> extends Readonly<T> {
    readonly size: number;
    read(key: string): T;
    read(key: number): T;
  }
  export type Item = { value: string; format(): string };
  export const enum State { Ready, Busy = "busy" }
  @sealed
  export abstract class Client<T extends Item> implements Store<T> {
    static count = 0;
    #secret = "";
    abstract size: number;
    constructor(public value: T) {}
    abstract read(key: string): T;
    read(key: number): T;
    read(key: string | number): T { const local = this.value; return local; }
    get current(): T { return this.value; }
    set current(value: T) { this.value = value; }
    async send(value: T, timeout?: number): Promise<T> { return value; }
  }
  export function choose(value: string): string;
  export function choose(value: number): number;
  export function choose(value: string | number): string | number { return value; }
  export const first = 1, second = 2;
}
declare module "remote" { export function load(): void; }
