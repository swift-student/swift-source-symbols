class Café {
  // Leading documentation is not part of the method.
  @first("😀") /* between decorators */
  @second
  method(value: string): void { const local = value; }
  @access get value(): string { return ""; }
  @access set value(input: string) {}
  @field public callback = (value: string): void => {};
  @decorate(() => { function inDecorator() {} }) decorated(): void {}
  @broken(@) damaged(value: string): void {}
  plain(): void {}
}
