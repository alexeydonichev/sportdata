import { useState, useEffect, useCallback, useRef } from "react";

interface UseApiQueryResult<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  refresh: () => void;
  refreshing: boolean;
}

export function useApiQuery<T>(
  fetcher: () => Promise<T>,
  deps: React.DependencyList = []
): UseApiQueryResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => { mountedRef.current = false; };
  }, []);

  const load = useCallback(async (isRefresh = false) => {
    if (isRefresh) setRefreshing(true);
    else setLoading(true);
    setError(null);
    try {
      const result = await fetcher();
      if (mountedRef.current) setData(result);
    } catch (e: unknown) {
      if (mountedRef.current) setError(e instanceof Error ? e.message : "Unknown error");
    } finally {
      if (mountedRef.current) { setLoading(false); setRefreshing(false); }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => { load(); }, [load]);

  const refresh = useCallback(() => { load(true); }, [load]);

  return { data, loading, error, refresh, refreshing };
}
