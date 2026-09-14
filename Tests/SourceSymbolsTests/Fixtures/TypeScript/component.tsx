export interface Props { title: string; }
export function View({ title }: Props): JSX.Element {
  const render = <T,>(value: T) => <span>{String(value)}</span>;
  return <section title={title}><Child render={() => { const nested = title; return <>{nested}</>; }} />{render(title)}</section>;
}
export const App = ({ title }: Props) => <View title={title} />;
const fragment = <>function fake() {}<div data-name="const absent = 1" /></>;
