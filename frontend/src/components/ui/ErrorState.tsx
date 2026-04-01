import { AlertTriangle } from "lucide-react";

interface Props {
  message?: string;
  onRetry?: () => void;
}

export default function ErrorState({ message = "Не удалось загрузить данные", onRetry }: Props) {
  return (
    <div className="text-center py-20">
      <AlertTriangle className="h-8 w-8 text-accent-red mx-auto mb-3 opacity-50" />
      <p className="text-text-tertiary text-sm">{message}</p>
      {onRetry && (
        <button
          onClick={onRetry}
          className="mt-3 px-4 py-2 rounded-lg border border-border-default text-sm text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors"
        >
          Попробовать снова
        </button>
      )}
    </div>
  );
}
