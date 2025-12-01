import * as React from "react";

// Simplified shadcn-style demo that doesn't require external CSS dependencies
// Tests that CVA-style variant pattern works with SSR

type ButtonVariant = "default" | "destructive" | "outline" | "secondary" | "ghost";
type ButtonSize = "default" | "sm" | "lg";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
}

// Simple Button component demonstrating CVA-style variant pattern
const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ variant = "default", size = "default", className = "", ...props }, ref) => {
    // CVA-style class building
    const baseClasses = "inline-flex items-center justify-center rounded-md font-medium";
    const variantClasses: Record<ButtonVariant, string> = {
      default: "bg-blue-500 text-white",
      destructive: "bg-red-500 text-white",
      outline: "border border-gray-300 bg-white",
      secondary: "bg-gray-200 text-gray-800",
      ghost: "bg-transparent hover:bg-gray-100",
    };
    const sizeClasses: Record<ButtonSize, string> = {
      default: "h-9 px-4 py-2",
      sm: "h-8 px-3 text-xs",
      lg: "h-10 px-8",
    };
    
    const classes = `${baseClasses} ${variantClasses[variant]} ${sizeClasses[size]} ${className}`.trim();
    
    return (
      <button
        ref={ref}
        className={classes}
        data-variant={variant}
        data-testid="shadcn-button"
        {...props}
      />
    );
  }
);
Button.displayName = "Button";

// Simple Card component
const Card = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  ({ className = "", ...props }, ref) => (
    <div
      ref={ref}
      className={`rounded-xl border border-gray-200 shadow ${className}`.trim()}
      data-testid="shadcn-card"
      {...props}
    />
  )
);
Card.displayName = "Card";

const CardHeader = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  ({ className = "", ...props }, ref) => (
    <div ref={ref} className={`p-6 ${className}`.trim()} data-testid="shadcn-card-header" {...props} />
  )
);
CardHeader.displayName = "CardHeader";

const CardTitle = React.forwardRef<HTMLParagraphElement, React.HTMLAttributes<HTMLHeadingElement>>(
  ({ className = "", ...props }, ref) => (
    <h3 ref={ref} className={`font-semibold ${className}`.trim()} data-testid="shadcn-card-title" {...props} />
  )
);
CardTitle.displayName = "CardTitle";

const CardDescription = React.forwardRef<HTMLParagraphElement, React.HTMLAttributes<HTMLParagraphElement>>(
  ({ className = "", ...props }, ref) => (
    <p ref={ref} className={`text-sm text-gray-500 ${className}`.trim()} data-testid="shadcn-card-description" {...props} />
  )
);
CardDescription.displayName = "CardDescription";

const CardContent = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  ({ className = "", ...props }, ref) => (
    <div ref={ref} className={`p-6 pt-0 ${className}`.trim()} data-testid="shadcn-card-content" {...props} />
  )
);
CardContent.displayName = "CardContent";

const CardFooter = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  ({ className = "", ...props }, ref) => (
    <div ref={ref} className={`flex items-center p-6 pt-0 ${className}`.trim()} data-testid="shadcn-card-footer" {...props} />
  )
);
CardFooter.displayName = "CardFooter";

// Main ShadcnDemo component
interface ShadcnDemoProps {
  title?: string;
  description?: string;
}

export default function ShadcnDemo({ 
  title = "shadcn/ui Demo", 
  description = "Testing CVA-style variant patterns" 
}: ShadcnDemoProps) {
  const [clickCount, setClickCount] = React.useState(0);
  const [variant, setVariant] = React.useState<ButtonVariant>("default");

  const variants: ButtonVariant[] = ["default", "destructive", "outline", "secondary", "ghost"];

  const cycleVariant = () => {
    const currentIndex = variants.indexOf(variant);
    const nextIndex = (currentIndex + 1) % variants.length;
    setVariant(variants[nextIndex]);
  };

  return (
    <Card className="w-96">
      <CardHeader>
        <CardTitle data-testid="demo-title">{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          <p data-testid="click-count">Button clicked: {clickCount} times</p>
          <p data-testid="current-variant">Current variant: {variant}</p>
          <div className="flex gap-2">
            <Button 
              variant={variant}
              onClick={() => setClickCount(c => c + 1)}
              data-testid="increment-btn"
            >
              Click me
            </Button>
            <Button 
              variant="outline"
              onClick={cycleVariant}
              data-testid="cycle-variant-btn"
            >
              Change variant
            </Button>
          </div>
        </div>
      </CardContent>
      <CardFooter>
        <Button 
          variant="ghost" 
          size="sm"
          onClick={() => setClickCount(0)}
          data-testid="reset-btn"
        >
          Reset count
        </Button>
      </CardFooter>
    </Card>
  );
}
