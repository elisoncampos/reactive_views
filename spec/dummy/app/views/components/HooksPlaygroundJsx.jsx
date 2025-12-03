import { useCallback, useEffect, useLayoutEffect, useMemo, useReducer, useRef, useState } from 'react';

const reducer = (state, action) => {
  switch (action.type) {
    case 'add': {
      const nextId = state.length + 1;
      return [...state, { id: nextId, label: `item-${nextId}` }];
    }
    case 'reset':
      return [];
    default:
      return state;
  }
};

const HooksPlaygroundJsx = ({ initialCount, initialLabel, testId = 'hooks-playground-jsx' }) => {
  const [count, setCount] = useState(initialCount);
  const [text, setText] = useState(initialLabel);
  const [effectState, setEffectState] = useState('server');
  const [layoutState, setLayoutState] = useState('server');
  const [items, dispatch] = useReducer(reducer, []);
  const latestRef = useRef('none');

  const memoValue = useMemo(() => `${text}:${count}:${items.length}`, [text, count, items.length]);

  const addBurst = useCallback(() => {
    setCount((value) => value + 5);
  }, []);

  useEffect(() => {
    setEffectState('effect-jump');
    latestRef.current = `count-${count}`;
  }, [count]);

  useLayoutEffect(() => {
    setLayoutState('layout-finished');
  }, []);

  return (
    <section data-testid={testId}>
      <p data-testid={`${testId}-state`}>State: {count}</p>
      <p data-testid={`${testId}-text`}>Text: {text}</p>
      <p data-testid={`${testId}-effect`}>Effect: {effectState}</p>
      <p data-testid={`${testId}-layout`}>Layout: {layoutState}</p>
      <p data-testid={`${testId}-memo`}>Memo: {memoValue}</p>
      <p data-testid={`${testId}-ref`}>Ref: {latestRef.current}</p>

      <div>
        <button data-testid={`${testId}-increment`} onClick={() => setCount((value) => value + 1)}>
          Increment
        </button>
        <button data-testid={`${testId}-reset`} onClick={() => setCount(initialCount)}>
          Reset
        </button>
        <button data-testid={`${testId}-burst`} onClick={addBurst}>
          Callback +5
        </button>
      </div>

      <div>
        <button data-testid={`${testId}-text-append`} onClick={() => setText((value) => `${value}?`)}>
          Append ?
        </button>
        <button data-testid={`${testId}-items-add`} onClick={() => dispatch({ type: 'add' })}>
          Add Item
        </button>
        <button data-testid={`${testId}-items-reset`} onClick={() => dispatch({ type: 'reset' })}>
          Reset Items
        </button>
        <ul data-testid={`${testId}-items`}>
          {items.map((item) => (
            <li key={item.id}>{item.label}</li>
          ))}
        </ul>
      </div>
    </section>
  );
};

export default HooksPlaygroundJsx;










