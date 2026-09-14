export async function collect<T extends { id: string } = { id: string }>(
  value: T,
  optional?: number,
  fallback: string = ["a", "b"].join(","),
  ...rest: readonly T[]
): Promise<T[]> { return [value, ...rest]; }
function destructured({ id }: { id: string }, [head, ...tail]: string[] = []): string { return id; }
function receiver(this: { value: string }, input: string): void {}
function untyped(value, fallback = { nested: [1, 2] }) {}
function predicate(value: unknown): value is string { return typeof value === "string"; }
function assertion(value: unknown): asserts value is string {}
function* sequence(start: number): Generator<number> { yield start; }
const arrow = <T,>(value: T, optional?: T): T => value;
const simple = value => value;
const wrapped = ((value: number): number => value);
const named = function inner(value: string): string { const local = value; return local; };
const generator = function* (value: number) { yield value; };
