import { useState } from 'react';

interface CounterProps {
  initialCount: number;
}

export default function Counter({ initialCount }: CounterProps) {
  const [count, setCount] = useState(initialCount);

  return (
    <div className="counter-component">
      <h2>Counter Component</h2>
      <p data-testid="count-display">Count: {count}</p>
      
      <div>
        <button 
          onClick={() => setCount(count + 1)}
          data-testid="increment-btn"
        >
          Increment
        </button>
        <button 
          onClick={() => setCount(count - 1)}
          data-testid="decrement-btn"
        >
          Decrement
        </button>
        <button 
          onClick={() => setCount(initialCount)}
          data-testid="reset-btn"
        >
          Reset
        </button>
      </div>
    </div>
  );
}


