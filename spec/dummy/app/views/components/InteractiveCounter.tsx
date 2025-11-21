import { useState } from 'react';

interface InteractiveCounterProps {
  initialCount: number;
}

export default function InteractiveCounter({ initialCount }: InteractiveCounterProps) {
  const [count, setCount] = useState(initialCount);

  return (
    <div className="card" style={{ background: '#f8f9fa', marginTop: '20px' }}>
      <h2>Interactive Counter</h2>
      <p>This component is hydrated and interactive on the client.</p>
      
      <div className="count-display" data-testid="count-display">
        Count: {count}
      </div>
      
      <div>
        <button 
          onClick={() => setCount(count + 1)}
          data-testid="increment-btn"
        >
          Increment (+)
        </button>
        <button 
          onClick={() => setCount(count - 1)}
          data-testid="decrement-btn"
        >
          Decrement (−)
        </button>
        <button 
          onClick={() => setCount(initialCount)}
          data-testid="reset-btn"
        >
          Reset
        </button>
      </div>
      
      <p style={{ marginTop: '20px', fontSize: '14px', color: '#666' }}>
        Initial count was: {initialCount}
      </p>
    </div>
  );
}


