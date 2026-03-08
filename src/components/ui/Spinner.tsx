export default function Spinner({ className = "py-20" }: { className?: string }) {
  return (
    <div className={"flex items-center justify-center " + className}>
      <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
    </div>
  );
}
